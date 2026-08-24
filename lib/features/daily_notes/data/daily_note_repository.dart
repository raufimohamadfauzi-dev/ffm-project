import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/audit_logger.dart';
import '../domain/entities/daily_note_entity.dart';

/// Penyimpanan Catatan Harian lokal. Domain ini sengaja terpisah dari tabel
/// `activity_*` agar aktivitas bertimer dan jurnal aktivitas tetap utuh.
class DailyNoteRepository {
  DailyNoteRepository(
    this._database,
    this._auditLogger, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const maxTitleLength = 160;
  static const maxBodyLength = 4000;

  final AppDatabase _database;
  final AuditLogger _auditLogger;
  final DateTime Function() _clock;

  Future<List<DailyNoteEntity>> readActive(String householdId) async {
    final rows =
        await (_database.select(_database.dailyNotes)
              ..where(
                (row) =>
                    row.householdId.equals(householdId) &
                    row.isArchived.equals(false),
              )
              ..orderBy([
                (row) => OrderingTerm.desc(row.noteDate),
                (row) => OrderingTerm.desc(row.createdAt),
              ]))
            .get();
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<DailyNoteEntity?> get(String householdId, String id) async {
    final row =
        await (_database.select(_database.dailyNotes)..where(
              (row) => row.householdId.equals(householdId) & row.id.equals(id),
            ))
            .getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  Future<DailyNoteEntity> create({
    required String householdId,
    required DateTime noteDate,
    required String body,
    String? title,
    String? id,
  }) async {
    final content = _requiredBody(body);
    final normalizedTitle = _optionalTitle(title);
    final now = _clock();
    final resolvedId = id?.trim().isNotEmpty == true
        ? id!.trim()
        : 'daily-note-${now.microsecondsSinceEpoch}';
    final existing = await get(householdId, resolvedId);
    if (existing != null) {
      if (existing.noteDate == _day(noteDate) &&
          existing.title == normalizedTitle &&
          existing.body == content) {
        return existing;
      }
      throw ArgumentError.value(
        resolvedId,
        'id',
        'Kunci penyimpanan Catatan Harian sudah dipakai untuk isi berbeda.',
      );
    }
    final entity = DailyNoteEntity(
      id: resolvedId,
      householdId: householdId,
      noteDate: _day(noteDate),
      title: normalizedTitle,
      body: content,
      isArchived: false,
      createdAt: now,
    );
    await _database
        .into(_database.dailyNotes)
        .insert(
          DailyNotesCompanion.insert(
            id: entity.id,
            householdId: entity.householdId,
            noteDate: entity.noteDate,
            title: Value(entity.title),
            body: entity.body,
            createdAt: entity.createdAt,
          ),
        );
    await _auditLogger.record(
      action: 'create',
      entity: 'daily_note',
      householdId: householdId,
      newValue: _auditValue(entity),
    );
    return entity;
  }

  Future<DailyNoteEntity?> update({
    required String householdId,
    required String id,
    required DateTime noteDate,
    required String body,
    String? title,
  }) async {
    final before = await get(householdId, id);
    if (before == null || before.isArchived) return null;
    final now = _clock();
    final updated = DailyNoteEntity(
      id: id,
      householdId: householdId,
      noteDate: _day(noteDate),
      title: _optionalTitle(title),
      body: _requiredBody(body),
      isArchived: false,
      createdAt: before.createdAt,
      updatedAt: now,
    );
    await (_database.update(_database.dailyNotes)..where(
          (row) => row.id.equals(id) & row.householdId.equals(householdId),
        ))
        .write(
          DailyNotesCompanion(
            noteDate: Value(updated.noteDate),
            title: Value(updated.title),
            body: Value(updated.body),
            updatedAt: Value(now),
          ),
        );
    await _auditLogger.record(
      action: 'update',
      entity: 'daily_note',
      householdId: householdId,
      oldValue: _auditValue(before),
      newValue: _auditValue(updated),
    );
    return get(householdId, id);
  }

  Future<DailyNoteEntity?> archive({
    required String householdId,
    required String id,
  }) async {
    final before = await get(householdId, id);
    if (before == null || before.isArchived) return null;
    final now = _clock();
    await (_database.update(_database.dailyNotes)..where(
          (row) => row.id.equals(id) & row.householdId.equals(householdId),
        ))
        .write(
          DailyNotesCompanion(
            isArchived: const Value(true),
            updatedAt: Value(now),
          ),
        );
    final archived = await get(householdId, id);
    await _auditLogger.record(
      action: 'archive',
      entity: 'daily_note',
      householdId: householdId,
      oldValue: _auditValue(before),
      newValue: archived == null ? null : _auditValue(archived),
    );
    return archived;
  }

  DailyNoteEntity _fromRow(DailyNote row) => DailyNoteEntity(
    id: row.id,
    householdId: row.householdId,
    noteDate: _day(row.noteDate),
    title: row.title,
    body: row.body,
    isArchived: row.isArchived,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );

  DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);

  String _requiredBody(String value) {
    final normalized = _sanitize(value);
    if (normalized.isEmpty)
      throw ArgumentError.value(value, 'body', 'Isi catatan wajib diisi.');
    if (normalized.length > maxBodyLength) {
      throw ArgumentError.value(value, 'body', 'Isi catatan terlalu panjang.');
    }
    return normalized;
  }

  String? _optionalTitle(String? value) {
    final normalized = _sanitize(value ?? '');
    if (normalized.isEmpty) return null;
    if (normalized.length > maxTitleLength) {
      throw ArgumentError.value(
        value,
        'title',
        'Judul catatan terlalu panjang.',
      );
    }
    return normalized;
  }

  String _sanitize(String value) => value
      .replaceAll(RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F]'), '')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();

  Map<String, Object?> _auditValue(DailyNoteEntity note) => {
    'id': note.id,
    'noteDate': note.noteDate.toIso8601String(),
    'title': note.title,
    'isArchived': note.isArchived,
  };
}
