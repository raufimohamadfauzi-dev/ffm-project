import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/audit_logger.dart';

/// Jalur persistence resmi untuk Sumber Pemasukan Data Utama.
///
/// Repository ini membatasi data pada `kind = income_source` dan tidak pernah
/// menulis `transactions.sourceId`; perubahan hanya metadata sumber.
class IncomeSourceRepository {
  IncomeSourceRepository(
    this._database,
    this._auditLogger, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const kind = 'income_source';
  static const role = 'Sumber pemasukan';
  static const maxNameLength = 160;
  static const maxDetailsLength = 1000;

  final AppDatabase _database;
  final AuditLogger _auditLogger;
  final DateTime Function() _clock;

  Future<List<TransactionParty>> readActive(String householdId) =>
      (_database.select(_database.transactionParties)
            ..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.kind.equals(kind) &
                  row.isArchived.equals(false),
            )
            ..orderBy([(row) => OrderingTerm.asc(row.name)]))
          .get();

  Future<TransactionParty?> get(String householdId, String id) =>
      (_database.select(_database.transactionParties)..where(
            (row) =>
                row.householdId.equals(householdId) &
                row.id.equals(id) &
                row.kind.equals(kind),
          ))
          .getSingleOrNull();

  Future<TransactionParty> create({
    required String id,
    required String householdId,
    required String name,
    String? details,
  }) async {
    final normalizedName = _name(name);
    final normalizedDetails = _details(details);
    await _ensureUniqueName(householdId, normalizedName);
    final now = _clock();
    await _database
        .into(_database.transactionParties)
        .insert(
          TransactionPartiesCompanion.insert(
            id: id,
            householdId: householdId,
            name: normalizedName,
            role: const Value(role),
            kind: const Value(kind),
            details: Value(normalizedDetails),
            createdAt: now,
          ),
        );
    final created = (await get(householdId, id))!;
    await _auditLogger.record(
      action: 'create',
      entity: 'income_source',
      householdId: householdId,
      newValue: _auditValue(created),
    );
    return created;
  }

  Future<TransactionParty?> update({
    required String householdId,
    required String id,
    required String name,
    String? details,
  }) async {
    final before = await get(householdId, id);
    if (before == null || before.isArchived) return null;
    final normalizedName = _name(name);
    final normalizedDetails = _details(details);
    await _ensureUniqueName(householdId, normalizedName, excludeId: id);
    if (before.name == normalizedName && before.details == normalizedDetails) {
      return before;
    }
    await (_database.update(_database.transactionParties)..where(
          (row) =>
              row.householdId.equals(householdId) &
              row.id.equals(id) &
              row.kind.equals(kind),
        ))
        .write(
          TransactionPartiesCompanion(
            name: Value(normalizedName),
            details: Value(normalizedDetails),
          ),
        );
    final updated = (await get(householdId, id))!;
    await _auditLogger.record(
      action: 'update',
      entity: 'income_source',
      householdId: householdId,
      oldValue: _auditValue(before),
      newValue: _auditValue(updated),
    );
    return updated;
  }

  Future<TransactionParty?> archive({
    required String householdId,
    required String id,
  }) async {
    final before = await get(householdId, id);
    if (before == null || before.isArchived) return null;
    await (_database.update(_database.transactionParties)..where(
          (row) =>
              row.householdId.equals(householdId) &
              row.id.equals(id) &
              row.kind.equals(kind),
        ))
        .write(const TransactionPartiesCompanion(isArchived: Value(true)));
    final archived = await get(householdId, id);
    await _auditLogger.record(
      action: 'archive',
      entity: 'income_source',
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
    final rows = await readActive(householdId);
    final duplicate = rows.any(
      (row) =>
          row.id != excludeId && row.name.toLowerCase() == name.toLowerCase(),
    );
    if (duplicate) {
      throw ArgumentError.value(
        name,
        'name',
        'Nama Sumber Pemasukan sudah dipakai.',
      );
    }
  }

  String _name(String value) {
    final normalized = _clean(value);
    if (normalized.isEmpty) {
      throw ArgumentError.value(
        value,
        'name',
        'Nama Sumber Pemasukan wajib diisi.',
      );
    }
    if (normalized.length > maxNameLength) {
      throw ArgumentError.value(
        value,
        'name',
        'Nama Sumber Pemasukan terlalu panjang.',
      );
    }
    return normalized;
  }

  String? _details(String? value) {
    final normalized = _clean(value ?? '');
    if (normalized.isEmpty) return null;
    if (normalized.length > maxDetailsLength) {
      throw ArgumentError.value(
        value,
        'details',
        'Keterangan Sumber Pemasukan terlalu panjang.',
      );
    }
    return normalized;
  }

  String _clean(String value) => value
      .replaceAll(RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  Map<String, Object?> _auditValue(TransactionParty source) => {
    'id': source.id,
    'name': source.name,
    'details': source.details,
    'role': source.role,
    'kind': source.kind,
    'isArchived': source.isArchived,
  };
}
