import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/audit_logger.dart';
import '../domain/entities/routine_entity.dart';

/// Penyimpanan Rutinitas lokal yang terpisah dari Tugas, Catatan Harian,
/// Aktivitas bertimer, dan Jadwal. Repository ini tidak menyediakan hapus
/// permanen Rutinitas; pembatalan hanya dapat menghapus satu tanda harian.
class RoutineRepository {
  RoutineRepository(
    this._database,
    this._auditLogger, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const maxTitleLength = 160;
  static const maxNoteLength = 2000;

  final AppDatabase _database;
  final AuditLogger _auditLogger;
  final DateTime Function() _clock;

  Future<List<RoutineEntity>> readActive(String householdId) async {
    final rows =
        await (_database.select(_database.dailyRoutines)
              ..where(
                (row) =>
                    row.householdId.equals(householdId) &
                    row.isArchived.equals(false),
              )
              ..orderBy([
                (row) => OrderingTerm.desc(row.isActive),
                (row) => OrderingTerm.asc(row.title),
              ]))
            .get();
    return rows.map(_fromRoutineRow).toList(growable: false);
  }

  Future<RoutineEntity?> get(String householdId, String id) async {
    final row =
        await (_database.select(_database.dailyRoutines)..where(
              (row) => row.householdId.equals(householdId) & row.id.equals(id),
            ))
            .getSingleOrNull();
    return row == null ? null : _fromRoutineRow(row);
  }

  Future<RoutineEntity> create({
    required String householdId,
    required String title,
    String? note,
    List<int> weekdays = const [],
    String? id,
  }) async {
    final normalizedTitle = _requiredTitle(title);
    final normalizedNote = _optionalNote(note);
    final normalizedWeekdays = _weekdays(weekdays);
    final now = _clock();
    final resolvedId = id?.trim().isNotEmpty == true
        ? id!.trim()
        : 'routine-${now.microsecondsSinceEpoch}';
    final existing = await get(householdId, resolvedId);
    if (existing != null) {
      if (existing.title == normalizedTitle &&
          existing.note == normalizedNote &&
          _sameWeekdays(existing.weekdays, normalizedWeekdays) &&
          !existing.isArchived) {
        return existing;
      }
      throw ArgumentError.value(
        resolvedId,
        'id',
        'Kunci penyimpanan Rutinitas sudah dipakai untuk isi berbeda.',
      );
    }
    final entity = RoutineEntity(
      id: resolvedId,
      householdId: householdId,
      title: normalizedTitle,
      note: normalizedNote,
      weekdays: normalizedWeekdays,
      isActive: true,
      isArchived: false,
      createdAt: now,
    );
    await _database
        .into(_database.dailyRoutines)
        .insert(
          DailyRoutinesCompanion.insert(
            id: entity.id,
            householdId: entity.householdId,
            title: entity.title,
            note: Value(entity.note),
            weekdaysJson: Value(jsonEncode(entity.weekdays)),
            createdAt: entity.createdAt,
          ),
        );
    await _auditLogger.record(
      action: 'create',
      entity: 'daily_routine',
      householdId: householdId,
      newValue: _routineAuditValue(entity),
    );
    return entity;
  }

  Future<RoutineEntity?> update({
    required String householdId,
    required String id,
    required String title,
    String? note,
    List<int> weekdays = const [],
  }) async {
    final before = await get(householdId, id);
    if (before == null || before.isArchived) return null;
    final now = _clock();
    final normalizedWeekdays = _weekdays(weekdays);
    await (_database.update(_database.dailyRoutines)..where(
          (row) => row.householdId.equals(householdId) & row.id.equals(id),
        ))
        .write(
          DailyRoutinesCompanion(
            title: Value(_requiredTitle(title)),
            note: Value(_optionalNote(note)),
            weekdaysJson: Value(jsonEncode(normalizedWeekdays)),
            updatedAt: Value(now),
          ),
        );
    final updated = await get(householdId, id);
    await _auditLogger.record(
      action: 'update',
      entity: 'daily_routine',
      householdId: householdId,
      oldValue: _routineAuditValue(before),
      newValue: updated == null ? null : _routineAuditValue(updated),
    );
    return updated;
  }

  Future<RoutineEntity?> setActive({
    required String householdId,
    required String id,
    required bool isActive,
  }) async {
    final before = await get(householdId, id);
    if (before == null || before.isArchived || before.isActive == isActive) {
      return before;
    }
    final now = _clock();
    await (_database.update(_database.dailyRoutines)..where(
          (row) => row.householdId.equals(householdId) & row.id.equals(id),
        ))
        .write(
          DailyRoutinesCompanion(
            isActive: Value(isActive),
            updatedAt: Value(now),
          ),
        );
    final updated = await get(householdId, id);
    await _auditLogger.record(
      action: isActive ? 'activate' : 'deactivate',
      entity: 'daily_routine',
      householdId: householdId,
      oldValue: _routineAuditValue(before),
      newValue: updated == null ? null : _routineAuditValue(updated),
    );
    return updated;
  }

  Future<RoutineEntity?> archive({
    required String householdId,
    required String id,
  }) async {
    final before = await get(householdId, id);
    if (before == null || before.isArchived) return null;
    final now = _clock();
    await (_database.update(_database.dailyRoutines)..where(
          (row) => row.householdId.equals(householdId) & row.id.equals(id),
        ))
        .write(
          DailyRoutinesCompanion(
            isArchived: const Value(true),
            updatedAt: Value(now),
          ),
        );
    final archived = await get(householdId, id);
    await _auditLogger.record(
      action: 'archive',
      entity: 'daily_routine',
      householdId: householdId,
      oldValue: _routineAuditValue(before),
      newValue: archived == null ? null : _routineAuditValue(archived),
    );
    return archived;
  }

  Future<RoutineCompletionEntity?> completionForDay({
    required String householdId,
    required String routineId,
    required DateTime day,
  }) async {
    final normalizedDay = _day(day);
    final row =
        await (_database.select(_database.dailyRoutineCompletions)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.routineId.equals(routineId) &
                  row.routineDate.equals(normalizedDay),
            ))
            .getSingleOrNull();
    return row == null ? null : _fromCompletionRow(row);
  }

  Future<RoutineCompletionEntity?> markCompletedForDay({
    required String householdId,
    required String routineId,
    required DateTime day,
    String? note,
  }) async {
    final routine = await get(householdId, routineId);
    if (routine == null || routine.isArchived || !routine.isActive) return null;
    final normalizedDay = _day(day);
    final existing = await completionForDay(
      householdId: householdId,
      routineId: routineId,
      day: normalizedDay,
    );
    if (existing != null) return existing;
    final now = _clock();
    final entity = RoutineCompletionEntity(
      id: _completionId(routineId, normalizedDay),
      routineId: routineId,
      householdId: householdId,
      routineDate: normalizedDay,
      completedAt: now,
      note: _optionalNote(note),
      createdAt: now,
    );
    await _database
        .into(_database.dailyRoutineCompletions)
        .insert(
          DailyRoutineCompletionsCompanion.insert(
            id: entity.id,
            routineId: entity.routineId,
            householdId: entity.householdId,
            routineDate: entity.routineDate,
            completedAt: entity.completedAt,
            note: Value(entity.note),
            createdAt: entity.createdAt,
          ),
          mode: InsertMode.insertOrIgnore,
        );
    final stored = await completionForDay(
      householdId: householdId,
      routineId: routineId,
      day: normalizedDay,
    );
    if (stored != null && stored.id == entity.id) {
      await _auditLogger.record(
        action: 'mark_complete',
        entity: 'daily_routine_completion',
        householdId: householdId,
        newValue: _completionAuditValue(stored),
      );
    }
    return stored;
  }

  /// Pembatalan eksplisit hanya menghapus tanda pada [day], bukan definisi
  /// Rutinitas, arsip, maupun riwayat tanggal lain.
  Future<RoutineCompletionEntity?> unmarkCompletedForDay({
    required String householdId,
    required String routineId,
    required DateTime day,
  }) async {
    final existing = await completionForDay(
      householdId: householdId,
      routineId: routineId,
      day: day,
    );
    if (existing == null) return null;
    await (_database.delete(_database.dailyRoutineCompletions)..where(
          (row) =>
              row.householdId.equals(householdId) & row.id.equals(existing.id),
        ))
        .go();
    await _auditLogger.record(
      action: 'unmark_complete',
      entity: 'daily_routine_completion',
      householdId: householdId,
      oldValue: _completionAuditValue(existing),
    );
    return existing;
  }

  RoutineEntity _fromRoutineRow(DailyRoutine row) => RoutineEntity(
    id: row.id,
    householdId: row.householdId,
    title: row.title,
    note: row.note,
    weekdays: _decodeWeekdays(row.weekdaysJson),
    isActive: row.isActive,
    isArchived: row.isArchived,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );

  RoutineCompletionEntity _fromCompletionRow(DailyRoutineCompletion row) =>
      RoutineCompletionEntity(
        id: row.id,
        routineId: row.routineId,
        householdId: row.householdId,
        routineDate: _day(row.routineDate),
        completedAt: row.completedAt,
        note: row.note,
        createdAt: row.createdAt,
      );

  List<int> _decodeWeekdays(String value) {
    try {
      final raw = jsonDecode(value);
      if (raw is! List) return const [];
      return _weekdays(
        raw.whereType<num>().map((item) => item.toInt()).toList(),
      );
    } on FormatException {
      return const [];
    }
  }

  List<int> _weekdays(List<int> values) {
    final normalized = values.toSet().toList()..sort();
    if (normalized.any(
      (weekday) => weekday < DateTime.monday || weekday > DateTime.sunday,
    )) {
      throw ArgumentError.value(
        values,
        'weekdays',
        'Hari Rutinitas harus bernilai 1 sampai 7.',
      );
    }
    return List.unmodifiable(normalized);
  }

  bool _sameWeekdays(List<int> first, List<int> second) =>
      first.length == second.length &&
      List.generate(
        first.length,
        (index) => first[index] == second[index],
      ).every((same) => same);

  String _completionId(String routineId, DateTime day) =>
      'routine-completion-$routineId-${day.year.toString().padLeft(4, '0')}${day.month.toString().padLeft(2, '0')}${day.day.toString().padLeft(2, '0')}';

  DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);

  String _requiredTitle(String value) {
    final normalized = _sanitize(value);
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, 'title', 'Judul Rutinitas wajib diisi.');
    }
    if (normalized.length > maxTitleLength) {
      throw ArgumentError.value(
        value,
        'title',
        'Judul Rutinitas terlalu panjang.',
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
        'Catatan Rutinitas terlalu panjang.',
      );
    }
    return normalized;
  }

  String _sanitize(String value) => value
      .replaceAll(RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F]'), '')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();

  Map<String, Object?> _routineAuditValue(RoutineEntity routine) => {
    'id': routine.id,
    'title': routine.title,
    'weekdays': routine.weekdays,
    'isActive': routine.isActive,
    'isArchived': routine.isArchived,
  };

  Map<String, Object?> _completionAuditValue(
    RoutineCompletionEntity completion,
  ) => {
    'id': completion.id,
    'routineId': completion.routineId,
    'routineDate': completion.routineDate.toIso8601String(),
    'completedAt': completion.completedAt.toIso8601String(),
  };
}
