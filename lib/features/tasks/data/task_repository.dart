import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/audit_logger.dart';
import '../domain/entities/task_entity.dart';

/// Penyimpanan Tugas lokal yang terpisah dari aktivitas bertimer, Catatan
/// Harian, Rutinitas, dan Jadwal. Tidak ada penghapusan permanen di repository.
class TaskRepository {
  TaskRepository(
    this._database,
    this._auditLogger, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const maxTitleLength = 160;
  static const maxNoteLength = 2000;

  final AppDatabase _database;
  final AuditLogger _auditLogger;
  final DateTime Function() _clock;

  Future<List<TaskEntity>> readActive(String householdId) async {
    final rows =
        await (_database.select(_database.tasks)
              ..where(
                (row) =>
                    row.householdId.equals(householdId) &
                    row.isArchived.equals(false),
              )
              ..orderBy([
                (row) => OrderingTerm.asc(row.status),
                (row) => OrderingTerm.asc(row.dueDate),
                (row) => OrderingTerm.desc(row.createdAt),
              ]))
            .get();
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<TaskEntity?> get(String householdId, String id) async {
    final row =
        await (_database.select(_database.tasks)..where(
              (row) => row.householdId.equals(householdId) & row.id.equals(id),
            ))
            .getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  Future<TaskEntity> create({
    required String householdId,
    required String title,
    String? note,
    DateTime? dueDate,
    String? id,
  }) async {
    final normalizedTitle = _requiredTitle(title);
    final normalizedNote = _optionalNote(note);
    final normalizedDueDate = dueDate == null ? null : _day(dueDate);
    final now = _clock();
    final resolvedId = id?.trim().isNotEmpty == true
        ? id!.trim()
        : 'task-${now.microsecondsSinceEpoch}';
    final existing = await get(householdId, resolvedId);
    if (existing != null) {
      if (existing.title == normalizedTitle &&
          existing.note == normalizedNote &&
          existing.dueDate == normalizedDueDate &&
          !existing.isArchived) {
        return existing;
      }
      throw ArgumentError.value(
        resolvedId,
        'id',
        'Kunci penyimpanan Tugas sudah dipakai untuk isi berbeda.',
      );
    }
    final entity = TaskEntity(
      id: resolvedId,
      householdId: householdId,
      title: normalizedTitle,
      note: normalizedNote,
      dueDate: normalizedDueDate,
      status: TaskStatus.open,
      isArchived: false,
      createdAt: now,
    );
    await _database
        .into(_database.tasks)
        .insert(
          TasksCompanion.insert(
            id: entity.id,
            householdId: entity.householdId,
            title: entity.title,
            note: Value(entity.note),
            dueDate: Value(entity.dueDate),
            createdAt: entity.createdAt,
          ),
        );
    await _auditLogger.record(
      action: 'create',
      entity: 'task',
      householdId: householdId,
      newValue: _auditValue(entity),
    );
    return entity;
  }

  Future<TaskEntity?> update({
    required String householdId,
    required String id,
    required String title,
    String? note,
    DateTime? dueDate,
  }) async {
    final before = await get(householdId, id);
    if (before == null || before.isArchived) return null;
    final now = _clock();
    await (_database.update(_database.tasks)..where(
          (row) => row.householdId.equals(householdId) & row.id.equals(id),
        ))
        .write(
          TasksCompanion(
            title: Value(_requiredTitle(title)),
            note: Value(_optionalNote(note)),
            dueDate: Value(dueDate == null ? null : _day(dueDate)),
            updatedAt: Value(now),
          ),
        );
    final updated = await get(householdId, id);
    await _auditLogger.record(
      action: 'update',
      entity: 'task',
      householdId: householdId,
      oldValue: _auditValue(before),
      newValue: updated == null ? null : _auditValue(updated),
    );
    return updated;
  }

  Future<TaskEntity?> complete({
    required String householdId,
    required String id,
  }) => _setCompletion(householdId: householdId, id: id, completed: true);

  Future<TaskEntity?> reopen({
    required String householdId,
    required String id,
  }) => _setCompletion(householdId: householdId, id: id, completed: false);

  Future<TaskEntity?> _setCompletion({
    required String householdId,
    required String id,
    required bool completed,
  }) async {
    final before = await get(householdId, id);
    if (before == null || before.isArchived) return null;
    if (before.isCompleted == completed) return before;
    final now = _clock();
    await (_database.update(_database.tasks)..where(
          (row) => row.householdId.equals(householdId) & row.id.equals(id),
        ))
        .write(
          TasksCompanion(
            status: Value(completed ? 'completed' : 'open'),
            completedAt: Value(completed ? now : null),
            updatedAt: Value(now),
          ),
        );
    final updated = await get(householdId, id);
    await _auditLogger.record(
      action: completed ? 'complete' : 'reopen',
      entity: 'task',
      householdId: householdId,
      oldValue: _auditValue(before),
      newValue: updated == null ? null : _auditValue(updated),
    );
    return updated;
  }

  Future<TaskEntity?> archive({
    required String householdId,
    required String id,
  }) async {
    final before = await get(householdId, id);
    if (before == null || before.isArchived) return null;
    final now = _clock();
    await (_database.update(_database.tasks)..where(
          (row) => row.householdId.equals(householdId) & row.id.equals(id),
        ))
        .write(
          TasksCompanion(isArchived: const Value(true), updatedAt: Value(now)),
        );
    final archived = await get(householdId, id);
    await _auditLogger.record(
      action: 'archive',
      entity: 'task',
      householdId: householdId,
      oldValue: _auditValue(before),
      newValue: archived == null ? null : _auditValue(archived),
    );
    return archived;
  }

  TaskEntity _fromRow(Task row) => TaskEntity(
    id: row.id,
    householdId: row.householdId,
    title: row.title,
    note: row.note,
    dueDate: row.dueDate == null ? null : _day(row.dueDate!),
    status: row.status == 'completed' ? TaskStatus.completed : TaskStatus.open,
    completedAt: row.completedAt,
    isArchived: row.isArchived,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );

  DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);

  String _requiredTitle(String value) {
    final normalized = _sanitize(value);
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, 'title', 'Judul tugas wajib diisi.');
    }
    if (normalized.length > maxTitleLength) {
      throw ArgumentError.value(value, 'title', 'Judul tugas terlalu panjang.');
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
        'Catatan tugas terlalu panjang.',
      );
    }
    return normalized;
  }

  String _sanitize(String value) => value
      .replaceAll(RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F]'), '')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();

  Map<String, Object?> _auditValue(TaskEntity task) => {
    'id': task.id,
    'title': task.title,
    'dueDate': task.dueDate?.toIso8601String(),
    'status': task.status.name,
    'isArchived': task.isArchived,
  };
}
