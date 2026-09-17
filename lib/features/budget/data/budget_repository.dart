import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/audit_logger.dart';

/// Snapshot nilai Anggaran yang dipakai preview, guard, audit, dan readback.
///
/// Tidak menghitung atau menciptakan transaksi/transfer baru. Nilai [remaining]
/// selalu mengikuti kontrak: allocated + rollover + transfer masuk - transfer
/// keluar - pengeluaran yang cocok dalam periode.
class BudgetMutationSnapshot {
  const BudgetMutationSnapshot({
    required this.budget,
    required this.categoryIds,
    required this.spent,
    required this.transferredIn,
    required this.transferredOut,
  });

  final EnvelopeBudget budget;
  final Set<String> categoryIds;
  final int spent;
  final int transferredIn;
  final int transferredOut;

  int get limit => budget.allocated + budget.rollover + transferredIn;

  int get available => limit - transferredOut;

  int get remaining => available - spent;

  double get progress =>
      available <= 0 ? (spent > 0 ? 1 : 0) : spent / available;

  int remainingFor(int allocated) =>
      allocated + budget.rollover + transferredIn - transferredOut - spent;
}

/// Posisi Anggaran read-only untuk capability asisten dan digest cloud.
class BudgetReadSnapshot {
  const BudgetReadSnapshot({
    required this.mutation,
    required this.status,
    required this.elapsedFraction,
    required this.asOf,
  });

  final BudgetMutationSnapshot mutation;
  final String status;
  final double elapsedFraction;
  final DateTime asOf;

  EnvelopeBudget get budget => mutation.budget;
  Set<String> get categoryIds => mutation.categoryIds;
  int get allocated => budget.allocated;
  int get rollover => budget.rollover;
  int get transferredIn => mutation.transferredIn;
  int get transferredOut => mutation.transferredOut;
  int get spent => mutation.spent;
  int get available => mutation.available;
  int get remaining => mutation.remaining;
  double get progress => mutation.progress;
}

/// Jalur persistence resmi untuk mutasi Anggaran yang sangat dibatasi Agent.
///
/// Agent hanya dapat mengubah `allocated` pada satu pos yang memenuhi seluruh
/// syarat kelayakan, atau melakukan arsip lunak bila tidak ada jejak transaksi
/// maupun transfer alokasi. Kategori, periode, rollover, ambang peringatan,
/// nama, dan identitas selalu dipertahankan.
class BudgetRepository {
  BudgetRepository(
    this._database,
    this._auditLogger, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const _recurringPeriodTypes = <String>{
    'weekly',
    'biweekly',
    'monthly',
    'bimonthly',
    'fourmonthly',
    'fivemonthly',
  };

  final AppDatabase _database;
  final AuditLogger _auditLogger;
  final DateTime Function() _clock;

  Future<List<EnvelopeBudget>> readActive(String householdId) =>
      (_database.select(_database.envelopeBudgets)
            ..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isActive.equals(true),
            )
            ..orderBy([(row) => OrderingTerm.asc(row.name)]))
          .get();

  Future<EnvelopeBudget?> get(String householdId, String id) =>
      (_database.select(_database.envelopeBudgets)..where(
            (row) => row.householdId.equals(householdId) & row.id.equals(id),
          ))
          .getSingleOrNull();

  Future<BudgetMutationSnapshot?> snapshot({
    required String householdId,
    required String id,
  }) async {
    final budget = await get(householdId, id);
    if (budget == null) return null;
    return _snapshotFor(householdId, budget);
  }

  /// Membaca posisi pos aktif pada periode berjalan dengan satu formula bersama.
  ///
  /// [categoryId] juga mencocokkan pos induk ketika kategori yang diminta adalah
  /// anaknya. Pos total sistem tidak dikembalikan agar tidak terjadi hitung ganda.
  Future<List<BudgetReadSnapshot>> readSnapshots({
    required String householdId,
    required DateTime now,
    String? periodType,
    String? categoryId,
    String? budgetId,
    int limit = 8,
  }) async {
    if (limit <= 0) return const [];
    final date = _dateOnly(now);
    final budgets = await readActive(householdId);
    final categories = await (_database.select(
      _database.categories,
    )..where((row) => row.householdId.equals(householdId))).get();
    final transactions = await (_database.select(
      _database.transactions,
    )..where((row) => row.householdId.equals(householdId))).get();
    final transfers = await (_database.select(
      _database.envelopeTransfers,
    )..where((row) => row.householdId.equals(householdId))).get();
    final snapshots = <BudgetReadSnapshot>[];
    for (final budget in budgets) {
      final categoryIds = _categoryIds(budget);
      if (budget.id.startsWith('overall-') ||
          (budgetId != null && budget.id != budgetId) ||
          (periodType != null && budget.periodType != periodType) ||
          (categoryId != null &&
              !_categoryMatches(categoryId, categoryIds, categories)) ||
          date.isBefore(_dateOnly(budget.startDate)) ||
          date.isAfter(_dateOnly(budget.endDate))) {
        continue;
      }
      final mutation = _snapshotForData(
        budget: budget,
        categoryIds: categoryIds,
        categories: categories,
        transactions: transactions,
        transfers: transfers,
      );
      final elapsed = _elapsedFraction(budget, date);
      snapshots.add(
        BudgetReadSnapshot(
          mutation: mutation,
          elapsedFraction: elapsed,
          status: _statusFor(mutation, elapsed),
          asOf: date,
        ),
      );
      if (snapshots.length == limit) break;
    }
    return snapshots;
  }

  /// Menjelaskan mengapa pos tidak boleh ditargetkan Agent, tanpa write.
  Future<String?> mutationEligibilityReason({
    required String householdId,
    required String id,
  }) async {
    final budget = await get(householdId, id);
    if (budget == null) return 'Pos Anggaran tidak ditemukan.';
    if (!budget.isActive) return 'Pos Anggaran sudah tidak aktif.';
    if (budget.id.startsWith('overall-')) {
      return 'Pos total sistem tidak dapat diubah atau diarsipkan Agent.';
    }
    final categoryIds = _categoryIds(budget);
    if (categoryIds.length != 1) {
      return 'Pos Anggaran dengan kategori gabungan tidak dapat diubah atau diarsipkan Agent.';
    }
    final category =
        await (_database.select(_database.categories)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.id.equals(categoryIds.single) &
                  row.isActive.equals(true) &
                  row.type.equals('expense'),
            ))
            .getSingleOrNull();
    if (category == null) {
      return 'Pos Anggaran harus memakai tepat satu kategori pengeluaran aktif.';
    }
    if (!_recurringPeriodTypes.contains(budget.periodType)) {
      return 'Pos Anggaran tidak rutin tidak dapat diubah atau diarsipkan Agent pada milestone ini.';
    }
    final now = _dateOnly(_clock());
    if (now.isBefore(_dateOnly(budget.startDate)) ||
        now.isAfter(_dateOnly(budget.endDate))) {
      return 'Hanya pos Anggaran pada periode yang sedang berjalan dapat ditargetkan Agent.';
    }
    return null;
  }

  Future<String?> archiveBlockReason({
    required String householdId,
    required String id,
  }) async {
    final eligibility = await mutationEligibilityReason(
      householdId: householdId,
      id: id,
    );
    if (eligibility != null) return eligibility;
    final budget = await get(householdId, id);
    if (budget == null) return 'Pos Anggaran tidak ditemukan.';
    final outgoing =
        await (_database.select(_database.envelopeTransfers)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.fromEnvelopeId.equals(id),
            ))
            .getSingleOrNull();
    if (outgoing != null) {
      return 'Pos Anggaran pernah menjadi asal transfer alokasi.';
    }
    final incoming =
        await (_database.select(_database.envelopeTransfers)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.toEnvelopeId.equals(id),
            ))
            .getSingleOrNull();
    if (incoming != null) {
      return 'Pos Anggaran pernah menjadi tujuan transfer alokasi.';
    }
    final categories = await (_database.select(
      _database.categories,
    )..where((row) => row.householdId.equals(householdId))).get();
    final categoryIds = _categoryIds(budget);
    final transactions = await (_database.select(
      _database.transactions,
    )..where((row) => row.householdId.equals(householdId))).get();
    final referencedTransaction = transactions.firstWhereOrNull(
      (transaction) =>
          transaction.amount < 0 &&
          transaction.source != 'transfer' &&
          _isInPeriod(transaction.date, budget) &&
          _categoryMatches(transaction.categoryId, categoryIds, categories),
    );
    if (referencedTransaction != null) {
      return 'Pos Anggaran sudah memiliki jejak transaksi pengeluaran dalam periodenya.';
    }
    return null;
  }

  /// Satu-satunya update alokasi yang dapat dipakai Agent.
  Future<BudgetMutationSnapshot?> updateAllocated({
    required String householdId,
    required String id,
    required int allocated,
  }) async {
    final before = await snapshot(householdId: householdId, id: id);
    if (before == null) return null;
    return updateAllocatedIfCurrent(
      householdId: householdId,
      id: id,
      allocated: allocated,
      expectedAllocated: before.budget.allocated,
      expectedRevision: before.budget.revision,
    );
  }

  /// Updates allocation only while the exact allocation/revision snapshot holds.
  ///
  /// This is used by delegated automation and undo to prevent overwriting a
  /// concurrent manual or agent change.
  Future<BudgetMutationSnapshot?> updateAllocatedIfCurrent({
    required String householdId,
    required String id,
    required int allocated,
    required int expectedAllocated,
    required int expectedRevision,
  }) async {
    if (allocated <= 0) {
      throw ArgumentError.value(
        allocated,
        'allocated',
        'Batas Anggaran harus lebih dari nol.',
      );
    }
    final eligibility = await mutationEligibilityReason(
      householdId: householdId,
      id: id,
    );
    if (eligibility != null) throw StateError(eligibility);
    final before = await snapshot(householdId: householdId, id: id);
    if (before == null) return null;
    if (before.budget.allocated != expectedAllocated ||
        before.budget.revision != expectedRevision) {
      throw StateError(
        'Pos Anggaran telah berubah; perubahan tidak diterapkan.',
      );
    }
    if (before.remainingFor(allocated) < 0) {
      throw StateError(
        'Batas baru membuat sisa Anggaran negatif; pengeluaran dan transfer yang sudah tercatat tidak diubah.',
      );
    }
    if (before.budget.allocated == allocated) return before;
    final changed = await _database.customUpdate(
      'UPDATE envelope_budgets '
      'SET allocated = ?, revision = revision + 1, updated_at = ? '
      'WHERE household_id = ? AND id = ? AND allocated = ? AND revision = ?',
      variables: [
        Variable.withInt(allocated),
        Variable.withDateTime(_clock()),
        Variable.withString(householdId),
        Variable.withString(id),
        Variable.withInt(expectedAllocated),
        Variable.withInt(expectedRevision),
      ],
      updates: {_database.envelopeBudgets},
    );
    if (changed != 1) {
      throw StateError(
        'Pos Anggaran telah berubah; perubahan tidak diterapkan.',
      );
    }
    final updated = (await snapshot(householdId: householdId, id: id))!;
    await _auditLogger.record(
      action: 'update',
      entity: 'budget',
      householdId: householdId,
      oldValue: _auditValue(before),
      newValue: _auditValue(updated),
    );
    return updated;
  }

  /// Arsip lunak setelah guard referensi diperiksa kembali tepat sebelum write.
  Future<BudgetMutationSnapshot?> archive({
    required String householdId,
    required String id,
  }) async {
    final before = await snapshot(householdId: householdId, id: id);
    if (before == null || !before.budget.isActive) return null;
    final block = await archiveBlockReason(householdId: householdId, id: id);
    if (block != null) throw StateError(block);
    await (_database.update(_database.envelopeBudgets)..where(
          (row) => row.householdId.equals(householdId) & row.id.equals(id),
        ))
        .write(
          EnvelopeBudgetsCompanion(
            isActive: const Value(false),
            updatedAt: Value(_clock()),
          ),
        );
    final archived = (await snapshot(householdId: householdId, id: id))!;
    await _auditLogger.record(
      action: 'archive',
      entity: 'budget',
      householdId: householdId,
      oldValue: _auditValue(before),
      newValue: _auditValue(archived),
    );
    return archived;
  }

  Future<BudgetMutationSnapshot> _snapshotFor(
    String householdId,
    EnvelopeBudget budget,
  ) async {
    final categoryIds = _categoryIds(budget);
    final categories = await (_database.select(
      _database.categories,
    )..where((row) => row.householdId.equals(householdId))).get();
    final transactions = await (_database.select(
      _database.transactions,
    )..where((row) => row.householdId.equals(householdId))).get();
    final transfers = await (_database.select(
      _database.envelopeTransfers,
    )..where((row) => row.householdId.equals(householdId))).get();
    return _snapshotForData(
      budget: budget,
      categoryIds: categoryIds,
      categories: categories,
      transactions: transactions,
      transfers: transfers,
    );
  }

  BudgetMutationSnapshot _snapshotForData({
    required EnvelopeBudget budget,
    required Set<String> categoryIds,
    required List<Category> categories,
    required List<Transaction> transactions,
    required List<EnvelopeTransfer> transfers,
  }) {
    final spent = transactions
        .where(
          (transaction) =>
              !transaction.isArchived &&
              !transaction.isDeleted &&
              transaction.amount < 0 &&
              transaction.source != 'transfer' &&
              _isInPeriod(transaction.date, budget) &&
              _categoryMatches(transaction.categoryId, categoryIds, categories),
        )
        .fold<int>(0, (total, transaction) => total + transaction.amount.abs());
    final transferredIn = transfers
        .where((transfer) => transfer.toEnvelopeId == budget.id)
        .fold<int>(0, (total, transfer) => total + transfer.amount);
    final transferredOut = transfers
        .where((transfer) => transfer.fromEnvelopeId == budget.id)
        .fold<int>(0, (total, transfer) => total + transfer.amount);
    return BudgetMutationSnapshot(
      budget: budget,
      categoryIds: categoryIds,
      spent: spent,
      transferredIn: transferredIn,
      transferredOut: transferredOut,
    );
  }

  double _elapsedFraction(EnvelopeBudget budget, DateTime now) {
    final start = _dateOnly(budget.startDate);
    final endExclusive = _dateOnly(budget.endDate).add(const Duration(days: 1));
    if (now.isBefore(start)) return 0;
    if (!now.isBefore(endExclusive)) return 1;
    return now.difference(start).inSeconds /
        endExclusive.difference(start).inSeconds;
  }

  String _statusFor(BudgetMutationSnapshot snapshot, double elapsedFraction) {
    final budget = snapshot.budget;
    if (budget.allocated <= 0) return 'Tanpa target';
    if (snapshot.progress >= 1) return 'Melewati batas';
    if (snapshot.progress * 100 >= budget.alertPercent) {
      return 'Mendekati batas';
    }
    if (budget.periodType != 'nonrecurring' &&
        snapshot.progress > elapsedFraction + .15) {
      return 'Pemakaian cepat';
    }
    return 'Aman';
  }

  Set<String> _categoryIds(EnvelopeBudget budget) {
    try {
      final decoded = jsonDecode(budget.categoryIdsJson);
      if (decoded is! List) return const <String>{};
      return decoded.whereType<String>().toSet();
    } on FormatException {
      return const <String>{};
    }
  }

  bool _categoryMatches(
    String? categoryId,
    Set<String> categoryIds,
    List<Category> categories,
  ) {
    if (categoryId == null) return false;
    if (categoryIds.contains(categoryId)) return true;
    final byId = {for (final category in categories) category.id: category};
    var parentId = byId[categoryId]?.parentId;
    while (parentId != null) {
      if (categoryIds.contains(parentId)) return true;
      parentId = byId[parentId]?.parentId;
    }
    return false;
  }

  bool _isInPeriod(DateTime date, EnvelopeBudget budget) {
    final value = _dateOnly(date);
    return !value.isBefore(_dateOnly(budget.startDate)) &&
        !value.isAfter(_dateOnly(budget.endDate));
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  Map<String, Object?> _auditValue(BudgetMutationSnapshot snapshot) => {
    'id': snapshot.budget.id,
    'householdId': snapshot.budget.householdId,
    'name': snapshot.budget.name,
    'categoryId': snapshot.budget.categoryId,
    'categoryIdsJson': snapshot.budget.categoryIdsJson,
    'month': snapshot.budget.month,
    'allocated': snapshot.budget.allocated,
    'periodType': snapshot.budget.periodType,
    'startDate': snapshot.budget.startDate.toIso8601String(),
    'endDate': snapshot.budget.endDate.toIso8601String(),
    'alertPercent': snapshot.budget.alertPercent,
    'rollover': snapshot.budget.rollover,
    'isActive': snapshot.budget.isActive,
    'createdAt': snapshot.budget.createdAt.toIso8601String(),
    'spent': snapshot.spent,
    'transferredIn': snapshot.transferredIn,
    'transferredOut': snapshot.transferredOut,
    'remaining': snapshot.remaining,
  };
}

extension _FirstWhereOrNull<E> on Iterable<E> {
  E? firstWhereOrNull(bool Function(E value) test) {
    for (final value in this) {
      if (test(value)) return value;
    }
    return null;
  }
}
