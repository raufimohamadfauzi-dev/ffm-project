import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/audit_logger.dart';

/// Jalur persistence resmi untuk Tag Data Utama.
///
/// Repository ini tidak pernah menulis tabel `transaction_tags`; mengubah nama
/// Tag hanya mengubah metadata penanda dan arsip hanya mencegah pemilihan baru.
class TagRepository {
  TagRepository(this._database, this._auditLogger, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  static const maxNameLength = 100;

  final AppDatabase _database;
  final AuditLogger _auditLogger;
  final DateTime Function() _clock;

  Future<List<Tag>> readActive(String householdId) =>
      (_database.select(_database.tags)
            ..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isArchived.equals(false),
            )
            ..orderBy([(row) => OrderingTerm.asc(row.name)]))
          .get();

  Future<Tag?> get(String householdId, String id) =>
      (_database.select(_database.tags)..where(
            (row) => row.householdId.equals(householdId) & row.id.equals(id),
          ))
          .getSingleOrNull();

  Future<Tag> create({
    required String id,
    required String householdId,
    required String name,
  }) async {
    final normalizedName = _name(name);
    await _ensureUniqueName(householdId, normalizedName);
    final now = _clock();
    await _database
        .into(_database.tags)
        .insert(
          TagsCompanion.insert(
            id: id,
            householdId: householdId,
            name: normalizedName,
            createdAt: now,
          ),
        );
    final created = (await get(householdId, id))!;
    await _auditLogger.record(
      action: 'create',
      entity: 'tag',
      householdId: householdId,
      newValue: _auditValue(created),
    );
    return created;
  }

  Future<Tag?> update({
    required String householdId,
    required String id,
    required String name,
  }) async {
    final before = await get(householdId, id);
    if (before == null || before.isArchived) return null;
    final normalizedName = _name(name);
    await _ensureUniqueName(householdId, normalizedName, excludeId: id);
    if (before.name == normalizedName) return before;
    await (_database.update(_database.tags)..where(
          (row) => row.householdId.equals(householdId) & row.id.equals(id),
        ))
        .write(TagsCompanion(name: Value(normalizedName)));
    final updated = (await get(householdId, id))!;
    await _auditLogger.record(
      action: 'update',
      entity: 'tag',
      householdId: householdId,
      oldValue: _auditValue(before),
      newValue: _auditValue(updated),
    );
    return updated;
  }

  Future<Tag?> archive({
    required String householdId,
    required String id,
  }) async {
    final before = await get(householdId, id);
    if (before == null || before.isArchived) return null;
    await (_database.update(_database.tags)..where(
          (row) => row.householdId.equals(householdId) & row.id.equals(id),
        ))
        .write(const TagsCompanion(isArchived: Value(true)));
    final archived = await get(householdId, id);
    await _auditLogger.record(
      action: 'archive',
      entity: 'tag',
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
      throw ArgumentError.value(name, 'name', 'Nama Tag sudah dipakai.');
    }
  }

  String _name(String value) {
    final normalized = value
        .replaceAll(RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, 'name', 'Nama Tag wajib diisi.');
    }
    if (normalized.length > maxNameLength) {
      throw ArgumentError.value(value, 'name', 'Nama Tag terlalu panjang.');
    }
    return normalized;
  }

  Map<String, Object?> _auditValue(Tag tag) => {
    'id': tag.id,
    'name': tag.name,
    'isArchived': tag.isArchived,
  };
}
