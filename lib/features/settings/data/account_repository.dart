import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/audit_logger.dart';

/// Jalur persistence resmi Rekening Data Utama.
///
/// Agent hanya menerima [updateName] dan [archive]. Saldo awal, tipe, serta
/// seluruh referensi keuangan tidak pernah diubah oleh jalur Agent.
class AccountRepository {
  AccountRepository(
    this._database,
    this._auditLogger, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const maxNameLength = 160;

  final AppDatabase _database;
  final AuditLogger _auditLogger;
  final DateTime Function() _clock;

  Future<List<Account>> readActive(String householdId) =>
      (_database.select(_database.accounts)
            ..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isActive.equals(true) &
                  row.isArchived.equals(false),
            )
            ..orderBy([(row) => OrderingTerm.asc(row.name)]))
          .get();

  Future<List<Account>> readAvailable(String householdId) =>
      (_database.select(_database.accounts)
            ..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isArchived.equals(false),
            )
            ..orderBy([(row) => OrderingTerm.asc(row.name)]))
          .get();

  Future<Account?> get(String householdId, String id) =>
      (_database.select(_database.accounts)..where(
            (row) => row.householdId.equals(householdId) & row.id.equals(id),
          ))
          .getSingleOrNull();

  /// Dipakai UI Data Utama; tidak diekspos sebagai capability Agent.
  Future<Account> create({
    required String id,
    required String householdId,
    required String name,
    required String type,
    required int openingBalance,
  }) async {
    final normalizedName = _name(name);
    await _ensureUniqueName(householdId, normalizedName);
    final now = _clock();
    await _database
        .into(_database.accounts)
        .insert(
          AccountsCompanion.insert(
            id: id,
            householdId: householdId,
            name: normalizedName,
            type: type,
            openingBalance: Value(openingBalance),
            createdAt: now,
          ),
        );
    final created = (await get(householdId, id))!;
    await _auditLogger.record(
      action: 'create',
      entity: 'account',
      householdId: householdId,
      newValue: _auditValue(created),
    );
    return created;
  }

  /// Dipakai UI Data Utama; tidak diekspos sebagai capability Agent.
  Future<Account?> updateFromUser({
    required String householdId,
    required String id,
    required String name,
    required String type,
    required int openingBalance,
  }) async {
    final before = await get(householdId, id);
    if (before == null || before.isArchived) return null;
    final normalizedName = _name(name);
    await _ensureUniqueName(householdId, normalizedName, excludeId: id);
    await (_database.update(_database.accounts)..where(
          (row) => row.householdId.equals(householdId) & row.id.equals(id),
        ))
        .write(
          AccountsCompanion(
            name: Value(normalizedName),
            type: Value(type),
            openingBalance: Value(openingBalance),
          ),
        );
    final updated = (await get(householdId, id))!;
    await _auditLogger.record(
      action: 'update',
      entity: 'account',
      householdId: householdId,
      oldValue: _auditValue(before),
      newValue: _auditValue(updated),
    );
    return updated;
  }

  /// Satu-satunya update yang dapat dipakai Agent.
  Future<Account?> updateName({
    required String householdId,
    required String id,
    required String name,
  }) async {
    final before = await get(householdId, id);
    if (before == null || before.isArchived) return null;
    final normalizedName = _name(name);
    await _ensureUniqueName(householdId, normalizedName, excludeId: id);
    if (before.name == normalizedName) return before;
    await (_database.update(_database.accounts)..where(
          (row) => row.householdId.equals(householdId) & row.id.equals(id),
        ))
        .write(AccountsCompanion(name: Value(normalizedName)));
    final updated = (await get(householdId, id))!;
    await _auditLogger.record(
      action: 'update',
      entity: 'account',
      householdId: householdId,
      oldValue: _auditValue(before),
      newValue: _auditValue(updated),
    );
    return updated;
  }

  /// Mengembalikan alasan penolakan jika Rekening pernah dirujuk data lain.
  Future<String?> archiveBlockReason({
    required String householdId,
    required String id,
  }) async {
    final transaction =
        await (_database.select(_database.transactions)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.accountId.equals(id),
            ))
            .getSingleOrNull();
    if (transaction != null) {
      return 'Rekening pernah dipakai transaksi “${transaction.id}”.';
    }
    final transfer =
        await (_database.select(_database.transfers)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  (row.fromAccountId.equals(id) | row.toAccountId.equals(id)),
            ))
            .getSingleOrNull();
    if (transfer != null) {
      return 'Rekening pernah dipakai transfer “${transfer.id}”.';
    }
    final recurring =
        await (_database.select(_database.recurringTransactions)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.accountId.equals(id),
            ))
            .getSingleOrNull();
    if (recurring != null) {
      return 'Rekening pernah dipakai transaksi berkala “${recurring.name}”.';
    }
    final reconciliation =
        await (_database.select(_database.accountReconciliationLogs)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.accountId.equals(id),
            ))
            .getSingleOrNull();
    if (reconciliation != null) {
      return 'Rekening memiliki log rekonsiliasi “${reconciliation.id}”.';
    }
    return null;
  }

  Future<Account?> archive({
    required String householdId,
    required String id,
  }) async {
    final before = await get(householdId, id);
    if (before == null || before.isArchived) return null;
    final block = await archiveBlockReason(householdId: householdId, id: id);
    if (block != null) throw StateError(block);
    await (_database.update(_database.accounts)..where(
          (row) => row.householdId.equals(householdId) & row.id.equals(id),
        ))
        .write(const AccountsCompanion(isArchived: Value(true)));
    final archived = await get(householdId, id);
    await _auditLogger.record(
      action: 'archive',
      entity: 'account',
      householdId: householdId,
      oldValue: _auditValue(before),
      newValue: archived == null ? null : _auditValue(archived),
    );
    return archived;
  }

  Future<void> _ensureUniqueName(
    String householdId,
    String name, {
    String? excludeId,
  }) async {
    final rows = await readAvailable(householdId);
    final duplicate = rows.any(
      (row) =>
          row.id != excludeId && row.name.toLowerCase() == name.toLowerCase(),
    );
    if (duplicate) {
      throw ArgumentError.value(
        name,
        'name',
        'Nama Rekening aktif sudah dipakai.',
      );
    }
  }

  String _name(String value) {
    final normalized = value
        .replaceAll(RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, 'name', 'Nama Rekening wajib diisi.');
    }
    if (normalized.length > maxNameLength) {
      throw ArgumentError.value(
        value,
        'name',
        'Nama Rekening terlalu panjang.',
      );
    }
    return normalized;
  }

  Map<String, Object?> _auditValue(Account account) => {
    'id': account.id,
    'name': account.name,
    'type': account.type,
    'openingBalance': account.openingBalance,
    'isActive': account.isActive,
    'isArchived': account.isArchived,
  };
}
