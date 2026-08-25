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

  int get remaining => limit - transferredOut - spent;

  int remainingFor(int allocated) =>
      allocated + budget.rollover + transferredIn - transferredOut - spent;
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
    if (before.remainingFor(allocated) < 0) {
      throw StateError(
        'Batas baru membuat sisa Anggaran negatif; pengeluaran dan transfer yang sudah tercatat tidak diubah.',
      );
    }
    if (before.budget.allocated == allocated) return before;
    await (_database.update(_database.envelopeBudgets)..where(
          (row) => row.householdId.equals(householdId) & row.id.equals(id),
        ))
        .write(
          EnvelopeBudgetsCompanion(
            allocated: Value(allocated),
            updatedAt: Value(_clock()),
          ),
        );
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
