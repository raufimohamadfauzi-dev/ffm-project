import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/audit_logger.dart';
import '../domain/entities/schedule_entry_entity.dart';

/// Penyimpanan agenda Jadwal lokal. Tidak menjadwalkan notifikasi, tidak
/// membuat Aktivitas, dan tidak menyediakan penghapusan permanen.
class ScheduleRepository {
  ScheduleRepository(
    this._database,
    this._auditLogger, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const maxTitleLength = 160;
  static const maxNoteLength = 2000;
  static const minutesPerDay = 24 * 60;

  final AppDatabase _database;
  final AuditLogger _auditLogger;
  final DateTime Function() _clock;

  Future<List<ScheduleEntryEntity>> readActive(String householdId) async {
    final rows =
        await (_database.select(_database.scheduleEntries)
              ..where(
                (row) =>
                    row.householdId.equals(householdId) &
                    row.isArchived.equals(false),
              )
              ..orderBy([
                (row) => OrderingTerm.asc(row.scheduledDate),
                (row) => OrderingTerm.desc(row.isAllDay),
                (row) => OrderingTerm.asc(row.startMinutes),
                (row) => OrderingTerm.asc(row.title),
              ]))
            .get();
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<List<ScheduleEntryEntity>> readForDay(
    String householdId,
    DateTime day,
  ) async {
    final normalizedDay = _day(day);
    final rows =
        await (_database.select(_database.scheduleEntries)
              ..where(
                (row) =>
                    row.householdId.equals(householdId) &
                    row.isArchived.equals(false) &
                    row.scheduledDate.equals(normalizedDay),
              )
              ..orderBy([
                (row) => OrderingTerm.desc(row.isAllDay),
                (row) => OrderingTerm.asc(row.startMinutes),
                (row) => OrderingTerm.asc(row.title),
              ]))
            .get();
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<ScheduleEntryEntity?> get(String householdId, String id) async {
    final row =
        await (_database.select(_database.scheduleEntries)..where(
              (row) => row.householdId.equals(householdId) & row.id.equals(id),
            ))
            .getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  Future<ScheduleEntryEntity> create({
    required String householdId,
    required String title,
    required DateTime scheduledDate,
    String? note,
    bool isAllDay = true,
    int? startMinutes,
    int? endMinutes,
    String? id,
  }) async {
    final normalized = _normalizedFields(
      title: title,
      note: note,
      scheduledDate: scheduledDate,
      isAllDay: isAllDay,
      startMinutes: startMinutes,
      endMinutes: endMinutes,
    );
    final now = _clock();
    final resolvedId = id?.trim().isNotEmpty == true
        ? id!.trim()
        : 'schedule-${now.microsecondsSinceEpoch}';
    final existing = await get(householdId, resolvedId);
    if (existing != null) {
      if (_sameContent(existing, normalized) && !existing.isArchived) {
        return existing;
      }
      throw ArgumentError.value(
        resolvedId,
        'id',
        'Kunci penyimpanan Jadwal sudah dipakai untuk isi berbeda.',
      );
    }
    final entity = ScheduleEntryEntity(
      id: resolvedId,
      householdId: householdId,
      title: normalized.title,
      note: normalized.note,
      scheduledDate: normalized.scheduledDate,
      isAllDay: normalized.isAllDay,
      startMinutes: normalized.startMinutes,
      endMinutes: normalized.endMinutes,
      isArchived: false,
      createdAt: now,
    );
    await _database
        .into(_database.scheduleEntries)
        .insert(
          ScheduleEntriesCompanion.insert(
            id: entity.id,
            householdId: entity.householdId,
            title: entity.title,
            note: Value(entity.note),
            scheduledDate: entity.scheduledDate,
            isAllDay: Value(entity.isAllDay),
            startMinutes: Value(entity.startMinutes),
            endMinutes: Value(entity.endMinutes),
            createdAt: entity.createdAt,
          ),
        );
    await _auditLogger.record(
      action: 'create',
      entity: 'schedule_entry',
      householdId: householdId,
      newValue: _auditValue(entity),
    );
    return entity;
  }

  Future<ScheduleEntryEntity?> update({
    required String householdId,
    required String id,
    required String title,
    required DateTime scheduledDate,
    String? note,
    bool isAllDay = true,
    int? startMinutes,
    int? endMinutes,
  }) async {
    final before = await get(householdId, id);
    if (before == null || before.isArchived) return null;
    final normalized = _normalizedFields(
      title: title,
      note: note,
      scheduledDate: scheduledDate,
      isAllDay: isAllDay,
      startMinutes: startMinutes,
      endMinutes: endMinutes,
    );
    final now = _clock();
    await (_database.update(_database.scheduleEntries)..where(
          (row) => row.householdId.equals(householdId) & row.id.equals(id),
        ))
        .write(
          ScheduleEntriesCompanion(
            title: Value(normalized.title),
            note: Value(normalized.note),
            scheduledDate: Value(normalized.scheduledDate),
            isAllDay: Value(normalized.isAllDay),
            startMinutes: Value(normalized.startMinutes),
            endMinutes: Value(normalized.endMinutes),
            updatedAt: Value(now),
          ),
        );
    final updated = await get(householdId, id);
    await _auditLogger.record(
      action: 'update',
      entity: 'schedule_entry',
      householdId: householdId,
      oldValue: _auditValue(before),
      newValue: updated == null ? null : _auditValue(updated),
    );
    return updated;
  }

  Future<ScheduleEntryEntity?> archive({
    required String householdId,
    required String id,
  }) async {
    final before = await get(householdId, id);
    if (before == null || before.isArchived) return null;
    final now = _clock();
    await (_database.update(_database.scheduleEntries)..where(
          (row) => row.householdId.equals(householdId) & row.id.equals(id),
        ))
        .write(
          ScheduleEntriesCompanion(
            isArchived: const Value(true),
            updatedAt: Value(now),
          ),
        );
    final archived = await get(householdId, id);
    await _auditLogger.record(
      action: 'archive',
      entity: 'schedule_entry',
      householdId: householdId,
      oldValue: _auditValue(before),
      newValue: archived == null ? null : _auditValue(archived),
    );
    return archived;
  }

  ScheduleEntryEntity _fromRow(ScheduleEntry row) => ScheduleEntryEntity(
    id: row.id,
    householdId: row.householdId,
    title: row.title,
    note: row.note,
    scheduledDate: _day(row.scheduledDate),
    isAllDay: row.isAllDay,
    startMinutes: row.startMinutes,
    endMinutes: row.endMinutes,
    isArchived: row.isArchived,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );

  _ScheduleFields _normalizedFields({
    required String title,
    required String? note,
    required DateTime scheduledDate,
    required bool isAllDay,
    required int? startMinutes,
    required int? endMinutes,
  }) {
    final normalizedStart = isAllDay
        ? null
        : _minute(startMinutes, 'waktu mulai');
    final normalizedEnd = isAllDay
        ? null
        : endMinutes == null
        ? null
        : _minute(endMinutes, 'waktu selesai');
    if (!isAllDay && normalizedStart == null) {
      throw ArgumentError.value(
        startMinutes,
        'startMinutes',
        'Jadwal dengan waktu harus memiliki waktu mulai.',
      );
    }
    if (normalizedStart != null &&
        normalizedEnd != null &&
        normalizedEnd < normalizedStart) {
      throw ArgumentError.value(
        endMinutes,
        'endMinutes',
        'Waktu selesai tidak boleh lebih awal dari waktu mulai.',
      );
    }
    return _ScheduleFields(
      title: _requiredTitle(title),
      note: _optionalNote(note),
      scheduledDate: _day(scheduledDate),
      isAllDay: isAllDay,
      startMinutes: normalizedStart,
      endMinutes: normalizedEnd,
    );
  }

  int? _minute(int? value, String label) {
    if (value == null) return null;
    if (value < 0 || value >= minutesPerDay) {
      throw ArgumentError.value(
        value,
        label,
        '$label harus antara 00:00 dan 23:59.',
      );
    }
    return value;
  }

  bool _sameContent(ScheduleEntryEntity value, _ScheduleFields fields) =>
      value.title == fields.title &&
      value.note == fields.note &&
      value.scheduledDate == fields.scheduledDate &&
      value.isAllDay == fields.isAllDay &&
      value.startMinutes == fields.startMinutes &&
      value.endMinutes == fields.endMinutes;

  DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);

  String _requiredTitle(String value) {
    final normalized = _sanitize(value);
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, 'title', 'Judul Jadwal wajib diisi.');
    }
    if (normalized.length > maxTitleLength) {
      throw ArgumentError.value(
        value,
        'title',
        'Judul Jadwal terlalu panjang.',
      );
    }
    return normalized;
  }

  String? _optionalNote(String? value) {
    final normalized = _sanitize(value ?? '');
    if (normalized.isEmpty) return null;
    if (normalized.length > maxNoteLength) {
      throw ArgumentError.value(
        value,
        'note',
        'Catatan Jadwal terlalu panjang.',
      );
    }
    return normalized;
  }

  String _sanitize(String value) => value
      .replaceAll(RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F]'), '')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();

  Map<String, Object?> _auditValue(ScheduleEntryEntity entry) => {
    'id': entry.id,
    'title': entry.title,
    'scheduledDate': entry.scheduledDate.toIso8601String(),
    'isAllDay': entry.isAllDay,
    'startMinutes': entry.startMinutes,
    'endMinutes': entry.endMinutes,
    'isArchived': entry.isArchived,
  };
}

class _ScheduleFields {
  const _ScheduleFields({
    required this.title,
    required this.note,
    required this.scheduledDate,
    required this.isAllDay,
    required this.startMinutes,
    required this.endMinutes,
  });

  final String title;
  final String? note;
  final DateTime scheduledDate;
  final bool isAllDay;
  final int? startMinutes;
  final int? endMinutes;
}
