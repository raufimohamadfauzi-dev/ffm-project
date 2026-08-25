import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/audit_logger.dart';

/// Jalur persistence resmi untuk Toko/Tempat. Riwayat transaksi hanya
/// menyimpan referensi id merchant sehingga pembaruan metadata dan arsip lunak
/// tidak pernah menulis transaksi historis.
class MerchantRepository {
  MerchantRepository(
    this._database,
    this._auditLogger, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const maxNameLength = 160;
  static const maxDetailsLength = 1000;

  final AppDatabase _database;
  final AuditLogger _auditLogger;
  final DateTime Function() _clock;

  Future<List<Merchant>> readActive(String householdId) =>
      (_database.select(_database.merchants)
            ..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isActive.equals(true),
            )
            ..orderBy([(row) => OrderingTerm.asc(row.name)]))
          .get();

  Future<Merchant?> get(String householdId, String id) =>
      (_database.select(_database.merchants)..where(
            (row) => row.householdId.equals(householdId) & row.id.equals(id),
          ))
          .getSingleOrNull();

  Future<Merchant> create({
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
        .into(_database.merchants)
        .insert(
          MerchantsCompanion.insert(
            id: id,
            householdId: householdId,
            name: normalizedName,
            details: Value(normalizedDetails),
            createdAt: now,
          ),
        );
    final created = (await get(householdId, id))!;
    await _auditLogger.record(
      action: 'create',
      entity: 'merchant',
      householdId: householdId,
      newValue: _auditValue(created),
    );
    return created;
  }

  Future<Merchant?> update({
    required String householdId,
    required String id,
    required String name,
    String? details,
  }) async {
    final before = await get(householdId, id);
    if (before == null || !before.isActive) return null;
    final normalizedName = _name(name);
    final normalizedDetails = _details(details);
    await _ensureUniqueName(householdId, normalizedName, excludeId: id);
    if (before.name == normalizedName && before.details == normalizedDetails) {
      return before;
    }
    await (_database.update(_database.merchants)..where(
          (row) => row.householdId.equals(householdId) & row.id.equals(id),
        ))
        .write(
          MerchantsCompanion(
            name: Value(normalizedName),
            details: Value(normalizedDetails),
          ),
        );
    final updated = (await get(householdId, id))!;
    await _auditLogger.record(
      action: 'update',
      entity: 'merchant',
      householdId: householdId,
      oldValue: _auditValue(before),
      newValue: _auditValue(updated),
    );
    return updated;
  }

  Future<Merchant?> archive({
    required String householdId,
    required String id,
  }) async {
    final before = await get(householdId, id);
    if (before == null || !before.isActive) return null;
    await (_database.update(_database.merchants)..where(
          (row) => row.householdId.equals(householdId) & row.id.equals(id),
        ))
        .write(const MerchantsCompanion(isActive: Value(false)));
    final archived = await get(householdId, id);
    await _auditLogger.record(
      action: 'archive',
      entity: 'merchant',
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
        'Nama Toko/Tempat sudah dipakai.',
      );
    }
  }

  String _name(String value) {
    final normalized = _clean(value);
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, 'name', 'Nama Toko/Tempat wajib diisi.');
    }
    if (normalized.length > maxNameLength) {
      throw ArgumentError.value(
        value,
        'name',
        'Nama Toko/Tempat terlalu panjang.',
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
        'Keterangan Toko/Tempat terlalu panjang.',
      );
    }
    return normalized;
  }

  String _clean(String value) => value
      .replaceAll(RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  Map<String, Object?> _auditValue(Merchant merchant) => {
    'id': merchant.id,
    'name': merchant.name,
    'details': merchant.details,
    'isActive': merchant.isActive,
  };
}
