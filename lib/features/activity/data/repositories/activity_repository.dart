import 'dart:async';

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/audit_logger.dart';
import '../../../assistant/data/ffm_activity_habit_learner.dart';
import '../../../assistant/data/ffm_assistant_autonomy_trigger_service.dart';
import '../../domain/entities/activity_entity.dart';

class ActivityRepository {
  const ActivityRepository(
    this.database,
    this.auditLogger, {
    this.habitLearner,
    this.autonomyTrigger,
  });

  final AppDatabase database;
  final AuditLogger auditLogger;

  /// Pengamat kebiasaan opsional: merekam pola aktivitas sebagai memori
  /// `habit` agar asisten memahami rutinitas pengguna.
  final FfmActivityHabitLearner? habitLearner;
  final FfmAssistantAutonomyTriggerService? autonomyTrigger;

  Future<List<ActivitySessionEntity>> getSessions(String householdId) async {
    final rows =
        await (database.select(database.activitySessions)
              ..where(
                (row) =>
                    row.householdId.equals(householdId) &
                    row.isArchived.equals(false),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.startedAt)]))
            .get();
    return rows.map(_sessionFromRow).toList();
  }

  Future<ActivitySessionEntity?> getSession(
    String householdId,
    String id,
  ) async {
    final row =
        await (database.select(database.activitySessions)..where(
              (item) =>
                  item.householdId.equals(householdId) & item.id.equals(id),
            ))
            .getSingleOrNull();
    return row == null ? null : _sessionFromRow(row);
  }

  Future<List<ActivitySessionEntity>> getActiveSessions(
    String householdId,
  ) async {
    final rows =
        await (database.select(database.activitySessions)
              ..where(
                (item) =>
                    item.householdId.equals(householdId) &
                    item.status.equals(ActivitySessionStatus.active.value) &
                    item.isArchived.equals(false),
              )
              ..orderBy([(item) => OrderingTerm.asc(item.startedAt)]))
            .get();
    return rows.map(_sessionFromRow).toList();
  }

  Future<ActivitySessionEntity?> getActiveSession(String householdId) async {
    final active = await getActiveSessions(householdId);
    return active.firstOrNull;
  }

  /// Mengembalikan semua sesi aktif apa adanya setelah aplikasi dibuka ulang.
  ///
  /// Parent yang force close tidak boleh otomatis menghentikan child. Jika
  /// parent tidak ditemukan karena data lama atau penghapusan yang tidak
  /// lengkap, child tetap dipertahankan dan dicatat sebagai recovery.
  Future<List<ActivitySessionEntity>> recoverActiveSessions(
    String householdId,
  ) async {
    final active = await getActiveSessions(householdId);
    final activeIds = active.map((session) => session.id).toSet();
    final orphaned = active
        .where(
          (session) =>
              session.parentSessionId != null &&
              !activeIds.contains(session.parentSessionId),
        )
        .toList(growable: false);
    if (orphaned.isNotEmpty) {
      await auditLogger.record(
        action: 'recover_active_sessions',
        entity: 'activity_session',
        householdId: householdId,
        newValue: {
          'orphanedActiveSessionIds': orphaned.map((item) => item.id).toList(),
          'reason': 'parent tidak aktif atau tidak ditemukan setelah aplikasi dibuka ulang',
        },
      );
    }
    return active;
  }

  Future<List<ActivityCheckpointEntity>> getCheckpoints(
    String sessionId,
  ) async {
    final rows =
        await (database.select(database.activityCheckpoints)
              ..where((row) => row.sessionId.equals(sessionId))
              ..orderBy([(row) => OrderingTerm.asc(row.sequence)]))
            .get();
    return rows.map(_checkpointFromRow).toList();
  }

  Future<int> getActivityLinkedCost(String sessionId) async {
    final rows = await (database.select(
      database.transactions,
    )..where((row) => row.linkedActivityId.equals(sessionId))).get();
    return rows.fold<int>(0, (sum, row) => sum + row.amount.abs());
  }

  Future<List<ActivityJournalEntryEntity>> getEntries(
    String householdId,
  ) async {
    final rows =
        await (database.select(database.activityEntries)
              ..where(
                (row) =>
                    row.householdId.equals(householdId) &
                    row.isArchived.equals(false),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.startedAt)]))
            .get();
    return rows.map(_entryFromRow).toList();
  }

  Future<void> saveSession(ActivitySessionEntity entity) async {
    final category = await _resolveActivityCategory(entity);
    await database
        .into(database.activitySessions)
        .insertOnConflictUpdate(
          ActivitySessionsCompanion.insert(
            id: entity.id,
            householdId: entity.householdId,
            title: entity.title,
            parentSessionId: Value(entity.parentSessionId),
            categoryId: Value(category?.id ?? entity.categoryId),
            category: Value(category?.name ?? entity.category),
            kind: Value(entity.kind.value),
            mode: Value(entity.effectiveMode.value),
            // Activity Intelligence Upgrade fields
            activityGroupId: Value(entity.activityGroupId),
            subjectType: Value(entity.subjectType),
            subjectId: Value(entity.subjectId),
            startedAt: entity.startedAt,
            endedAt: Value<DateTime?>(entity.endedAt),
            scheduledAt: Value<DateTime?>(entity.scheduledAt),
            dueDate: Value<DateTime?>(entity.dueDate),
            isAllDay: Value(entity.isAllDay),
            isCompleted: Value(entity.isCompleted),
            priority: Value(entity.priority),
            status: Value(entity.status.value),
            notes: Value(entity.notes),
            isArchived: Value(entity.isArchived),
            createdAt: entity.createdAt,
            updatedAt: Value<DateTime?>(entity.updatedAt),
          ),
        );
    await auditLogger.record(
      action: 'save',
      entity: 'activity_session',
      householdId: entity.householdId,
      newValue: {
        'id': entity.id,
        'title': entity.title,
        'status': entity.status.value,
        'effectiveMode': entity.effectiveMode.name,
        'activityGroupId': entity.activityGroupId,
        'subjectType': entity.subjectType,
        'subjectId': entity.subjectId,
      },
    );
    await autonomyTrigger?.emitSafely(
      triggerId:
          'activity-session:${entity.id}:${entity.updatedAt?.microsecondsSinceEpoch ?? entity.createdAt.microsecondsSinceEpoch}',
      type: 'database.changed',
      householdId: entity.householdId,
      occurredAt: entity.updatedAt ?? entity.createdAt,
      entityId: entity.id,
      activityId: entity.id,
      payload: const {'entityType': 'activity_session', 'operation': 'save'},
    );
    habitLearner
        ?.recordActivityObservation(
          title: entity.title,
          occurredAt: entity.startedAt,
          // Activity Intelligence Upgrade - pass structured context
          category: entity.category,
          activityGroupId: entity.activityGroupId,
          subjectType: entity.subjectType,
          subjectId: entity.subjectId,
        )
        .ignore();
  }

  Future<void> saveCheckpoint(ActivityCheckpointEntity entity) async {
    await database
        .into(database.activityCheckpoints)
        .insertOnConflictUpdate(
          ActivityCheckpointsCompanion.insert(
            id: entity.id,
            sessionId: entity.sessionId,
            label: entity.label,
            place: Value(entity.place),
            occurredAt: entity.occurredAt,
            sequence: entity.sequence,
            note: Value(entity.note),
            createdAt: entity.createdAt,
          ),
        );
    await auditLogger.record(
      action: 'save',
      entity: 'activity_checkpoint',
      newValue: {
        'id': entity.id,
        'sessionId': entity.sessionId,
        'label': entity.label,
        'occurredAt': entity.occurredAt.toIso8601String(),
      },
    );
  }

  Future<void> saveEntry(ActivityJournalEntryEntity entity) async {
    await database
        .into(database.activityEntries)
        .insertOnConflictUpdate(
          ActivityEntriesCompanion.insert(
            id: entity.id,
            sessionId: Value(entity.sessionId),
            householdId: entity.householdId,
            activityType: Value(entity.activityType),
            title: entity.title,
            participants: Value(entity.participants),
            topic: Value(entity.topic),
            place: Value(entity.place),
            startedAt: entity.startedAt,
            endedAt: Value<DateTime?>(entity.endedAt),
            notes: Value(entity.notes),
            followUp: Value(entity.followUp),
            isArchived: Value(entity.isArchived),
            createdAt: entity.createdAt,
            updatedAt: Value<DateTime?>(entity.updatedAt),
          ),
        );
    await auditLogger.record(
      action: 'save',
      entity: 'activity_journal',
      householdId: entity.householdId,
      newValue: {
        'id': entity.id,
        'title': entity.title,
        'activityType': entity.activityType,
      },
    );
    await autonomyTrigger?.emitSafely(
      triggerId:
          'activity-journal:${entity.id}:${entity.updatedAt?.microsecondsSinceEpoch ?? entity.createdAt.microsecondsSinceEpoch}',
      type: 'database.changed',
      householdId: entity.householdId,
      occurredAt: entity.updatedAt ?? entity.createdAt,
      entityId: entity.id,
      activityId: entity.sessionId,
      payload: const {'entityType': 'activity_journal', 'operation': 'save'},
    );
    habitLearner
        ?.recordActivityObservation(
          title: entity.title,
          occurredAt: entity.startedAt,
        )
        .ignore();
  }

  Future<void> recordVoiceCommand({
    required String householdId,
    required String rawTranscript,
    required String normalizedText,
    required String intent,
    required String status,
    String? targetSessionId,
    double? confidence,
    String? resultMessage,
  }) => auditLogger.record(
    action: 'voice_command_$status',
    entity: 'activity_voice_command',
    householdId: householdId,
    newValue: {
      'rawTranscript': rawTranscript,
      'normalizedText': normalizedText,
      'intent': intent,
      'status': status,
      'targetSessionId': targetSessionId,
      'confidence': confidence,
      'resultMessage': resultMessage,
    },
  );

  Future<void> deleteSessionPermanently(String householdId, String id) async {
    final session = await getSession(householdId, id);
    if (session == null) return;

    var deletedSessionIds = <String>[];
    var checkpointCount = 0;
    var linkedEntryCount = 0;
    await database.transaction(() async {
      final allSessions = await (database.select(
        database.activitySessions,
      )..where((row) => row.householdId.equals(householdId))).get();
      final childrenByParent = <String, List<String>>{};
      for (final row in allSessions) {
        final parentId = row.parentSessionId;
        if (parentId != null) {
          childrenByParent.putIfAbsent(parentId, () => []).add(row.id);
        }
      }
      final pending = <String>[id];
      final descendants = <String>{id};
      while (pending.isNotEmpty) {
        final parentId = pending.removeLast();
        for (final childId in childrenByParent[parentId] ?? const <String>[]) {
          if (descendants.add(childId)) pending.add(childId);
        }
      }
      deletedSessionIds = descendants.toList(growable: false);

      checkpointCount =
          await (database.select(database.activityCheckpoints)
                ..where((row) => row.sessionId.isIn(deletedSessionIds)))
              .get()
              .then((rows) => rows.length);
      linkedEntryCount =
          await (database.select(database.activityEntries)..where(
                (row) =>
                    row.householdId.equals(householdId) &
                    row.sessionId.isIn(deletedSessionIds),
              ))
              .get()
              .then((rows) => rows.length);

      await (database.delete(
        database.activityCheckpoints,
      )..where((row) => row.sessionId.isIn(deletedSessionIds))).go();
      await (database.delete(database.activityEntries)..where(
            (row) =>
                row.householdId.equals(householdId) &
                row.sessionId.isIn(deletedSessionIds),
          ))
          .go();
      await (database.delete(database.activitySessions)..where(
            (row) =>
                row.householdId.equals(householdId) &
                row.id.isIn(deletedSessionIds),
          ))
          .go();
    });

    final remainingSessions = await (database.select(
      database.activitySessions,
    )..where((row) => row.id.isIn(deletedSessionIds))).get();
    final remainingCheckpoints = await (database.select(
      database.activityCheckpoints,
    )..where((row) => row.sessionId.isIn(deletedSessionIds))).get();
    final remainingEntries = await (database.select(
      database.activityEntries,
    )..where((row) => row.sessionId.isIn(deletedSessionIds))).get();
    if (remainingSessions.isNotEmpty ||
        remainingCheckpoints.isNotEmpty ||
        remainingEntries.isNotEmpty) {
      throw StateError('Aktivitas belum terhapus bersih dari perangkat.');
    }

    await auditLogger.record(
      action: 'delete_permanently',
      entity: 'activity_session',
      householdId: householdId,
      oldValue: {
        'id': session.id,
        'title': session.title,
        'status': session.status.value,
        'deletedSessionCount': deletedSessionIds.length,
        'checkpointCount': checkpointCount,
        'linkedEntryCount': linkedEntryCount,
      },
    );
  }

  Future<void> archiveSession(String householdId, String id) async {
    await (database.update(database.activitySessions)..where(
          (row) => row.householdId.equals(householdId) & row.id.equals(id),
        ))
        .write(
          ActivitySessionsCompanion(
            isArchived: const Value(true),
            updatedAt: Value(DateTime.now()),
          ),
        );
    await auditLogger.record(
      action: 'archive',
      entity: 'activity_session',
      householdId: householdId,
      newValue: {'id': id},
    );
  }

  Future<void> _ensureNotesTable() async {
    await database.customStatement(
      'CREATE TABLE IF NOT EXISTS activity_notes ('
      'id TEXT PRIMARY KEY, '
      'household_id TEXT NOT NULL, '
      'text TEXT NOT NULL, '
      'category TEXT NOT NULL, '
      'numeric_value REAL, '
      'unit TEXT, '
      'latitude REAL, '
      'longitude REAL, '
      'created_at INTEGER NOT NULL, '
      'linked_session_id TEXT, '
      'source TEXT NOT NULL, '
      'is_archived INTEGER NOT NULL DEFAULT 0, '
      'updated_at INTEGER)',
    );
  }

  Future<List<ActivityNoteEntity>> getNotes(
    String householdId, {
    String? linkedSessionId,
    String? category,
  }) async {
    await _ensureNotesTable();
    var sql =
        'SELECT * FROM activity_notes WHERE household_id = ? AND is_archived = 0';
    final params = <Object?>[householdId];
    if (linkedSessionId != null) {
      sql += ' AND linked_session_id = ?';
      params.add(linkedSessionId);
    }
    if (category != null) {
      sql += ' AND category = ?';
      params.add(category);
    }
    sql += ' ORDER BY created_at DESC';

    final rows = await database
        .customSelect(sql, variables: params.map((p) => Variable(p)).toList())
        .get();
    return rows
        .map((row) {
          final data = row.data;
          final createdAtMillis = data['created_at'] as int;
          final updatedAtMillis = data['updated_at'] as int?;
          return ActivityNoteEntity(
            id: data['id'] as String,
            householdId: data['household_id'] as String,
            text: data['text'] as String,
            category: data['category'] as String,
            numericValue: (data['numeric_value'] as num?)?.toDouble(),
            unit: data['unit'] as String?,
            latitude: (data['latitude'] as num?)?.toDouble(),
            longitude: (data['longitude'] as num?)?.toDouble(),
            createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMillis),
            linkedSessionId: data['linked_session_id'] as String?,
            source: ActivityEntrySource.fromValue(data['source'] as String?),
            isArchived: (data['is_archived'] as int? ?? 0) == 1,
            updatedAt: updatedAtMillis != null
                ? DateTime.fromMillisecondsSinceEpoch(updatedAtMillis)
                : null,
          );
        })
        .toList(growable: false);
  }

  Future<void> saveNote(ActivityNoteEntity entity) async {
    await _ensureNotesTable();
    await database.customStatement(
      'INSERT OR REPLACE INTO activity_notes '
      '(id, household_id, text, category, numeric_value, unit, latitude, longitude, created_at, linked_session_id, source, is_archived, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        entity.id,
        entity.householdId,
        entity.text,
        entity.category,
        entity.numericValue,
        entity.unit,
        entity.latitude,
        entity.longitude,
        entity.createdAt.millisecondsSinceEpoch,
        entity.linkedSessionId,
        entity.source.value,
        entity.isArchived ? 1 : 0,
        entity.updatedAt?.millisecondsSinceEpoch,
      ],
    );
    await auditLogger.record(
      action: 'save',
      entity: 'activity_note',
      householdId: entity.householdId,
      newValue: {
        'id': entity.id,
        'category': entity.category,
        'numericValue': entity.numericValue,
        'unit': entity.unit,
        'linkedSessionId': entity.linkedSessionId,
      },
    );
    await autonomyTrigger?.emitSafely(
      triggerId:
          'activity-note:${entity.id}:${entity.updatedAt?.microsecondsSinceEpoch ?? entity.createdAt.microsecondsSinceEpoch}',
      type: 'database.changed',
      householdId: entity.householdId,
      occurredAt: entity.updatedAt ?? entity.createdAt,
      entityId: entity.id,
      activityId: entity.linkedSessionId,
      payload: const {'entityType': 'activity_note', 'operation': 'save'},
    );
  }

  Future<void> archiveNote(String householdId, String id) async {
    await _ensureNotesTable();
    await database.customStatement(
      'UPDATE activity_notes SET is_archived = 1, updated_at = ? WHERE household_id = ? AND id = ?',
      [DateTime.now().millisecondsSinceEpoch, householdId, id],
    );
    await auditLogger.record(
      action: 'archive',
      entity: 'activity_note',
      householdId: householdId,
      newValue: {'id': id},
    );
  }

  Future<void> archiveEntry(String householdId, String id) async {
    await (database.update(database.activityEntries)..where(
          (row) => row.householdId.equals(householdId) & row.id.equals(id),
        ))
        .write(
          ActivityEntriesCompanion(
            isArchived: const Value(true),
            updatedAt: Value(DateTime.now()),
          ),
        );
    await auditLogger.record(
      action: 'archive',
      entity: 'activity_journal',
      householdId: householdId,
      newValue: {'id': id},
    );
  }

  Future<void> migrateOldData(String householdId) async {
    final prefKey = 'migration_v2_done';
    final alreadyDone =
        await (database.select(database.userPreferences)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.preferenceKey.equals(prefKey),
            ))
            .getSingleOrNull();

    if (alreadyDone != null && alreadyDone.preferenceValue == 'true') return;

    await database.transaction(() async {
      // ... (migration logic stays same)
      // 1. Migrate Tasks
      final tasks = await (database.select(
        database.tasks,
      )..where((row) => row.householdId.equals(householdId))).get();
      for (final task in tasks) {
        await saveSession(
          ActivitySessionEntity(
            id: task.id,
            householdId: householdId,
            title: task.title,
            category: 'tugas',
            kind: ActivityKind.task,
            startedAt: task.createdAt,
            endedAt: task.completedAt,
            dueDate: task.dueDate,
            isCompleted: task.status == 'completed',
            status: task.status == 'completed'
                ? ActivitySessionStatus.completed
                : ActivitySessionStatus.active,
            notes: task.note,
            isArchived: task.isArchived,
            createdAt: task.createdAt,
            updatedAt: task.updatedAt,
          ),
        );
      }

      // 2. Migrate Daily Notes
      final notes = await (database.select(
        database.dailyNotes,
      )..where((row) => row.householdId.equals(householdId))).get();
      for (final note in notes) {
        await saveSession(
          ActivitySessionEntity(
            id: note.id,
            householdId: householdId,
            title: note.title ?? 'Catatan',
            category: 'catatan',
            kind: ActivityKind.note,
            startedAt: note.noteDate,
            endedAt: note.noteDate,
            isCompleted: true,
            status: ActivitySessionStatus.completed,
            notes: note.body,
            isArchived: note.isArchived,
            createdAt: note.createdAt,
            updatedAt: note.updatedAt,
          ),
        );
      }

      // 3. Migrate Schedule Entries
      final schedules = await (database.select(
        database.scheduleEntries,
      )..where((row) => row.householdId.equals(householdId))).get();
      for (final schedule in schedules) {
        await saveSession(
          ActivitySessionEntity(
            id: schedule.id,
            householdId: householdId,
            title: schedule.title,
            category: 'jadwal',
            kind: ActivityKind.event,
            startedAt: schedule.scheduledDate,
            scheduledAt: schedule.scheduledDate,
            isAllDay: schedule.isAllDay,
            isCompleted: schedule.scheduledDate.isBefore(DateTime.now()),
            status: schedule.scheduledDate.isBefore(DateTime.now())
                ? ActivitySessionStatus.completed
                : ActivitySessionStatus.active,
            notes: schedule.note,
            isArchived: schedule.isArchived,
            createdAt: schedule.createdAt,
            updatedAt: schedule.updatedAt,
          ),
        );
      }

      // Mark as done
      await database
          .into(database.userPreferences)
          .insertOnConflictUpdate(
            UserPreferencesCompanion.insert(
              id: 'pref-mig-$householdId',
              householdId: householdId,
              preferenceKey: prefKey,
              preferenceValue: 'true',
              updatedAt: DateTime.now(),
            ),
          );
    });
  }

  Future<Category?> _resolveActivityCategory(
    ActivitySessionEntity entity,
  ) async {
    if (entity.categoryId != null) {
      final byId =
          await (database.select(database.categories)..where(
                (row) =>
                    row.householdId.equals(entity.householdId) &
                    row.id.equals(entity.categoryId!) &
                    row.type.equals('activity') &
                    row.isActive.equals(true),
              ))
              .getSingleOrNull();
      if (byId != null) return byId;
    }
    final normalized = entity.category.trim();
    if (normalized.isEmpty) return null;
    final rows =
        await (database.select(database.categories)..where(
              (row) =>
                  row.householdId.equals(entity.householdId) &
                  row.type.equals('activity') &
                  row.isActive.equals(true) &
                  row.name.equals(normalized),
            ))
            .get();
    return rows.length == 1 ? rows.single : null;
  }

  ActivitySessionEntity _sessionFromRow(ActivitySession row) =>
      ActivitySessionEntity(
        id: row.id,
        householdId: row.householdId,
        title: row.title,
        category: row.category,
        categoryId: row.categoryId,
        kind: ActivityKind.fromValue(row.kind),
        parentSessionId: row.parentSessionId,
        // Activity Intelligence Upgrade fields
        activityGroupId: row.activityGroupId,
        subjectType: row.subjectType,
        subjectId: row.subjectId,
        startedAt: row.startedAt,
        endedAt: row.endedAt,
        scheduledAt: row.scheduledAt,
        dueDate: row.dueDate,
        isAllDay: row.isAllDay,
        isCompleted: row.isCompleted,
        priority: row.priority,
        status: ActivitySessionStatus.fromValue(row.status),
        notes: row.notes,
        isArchived: row.isArchived,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
      );

  ActivityCheckpointEntity _checkpointFromRow(ActivityCheckpoint row) =>
      ActivityCheckpointEntity(
        id: row.id,
        sessionId: row.sessionId,
        label: row.label,
        place: row.place,
        occurredAt: row.occurredAt,
        sequence: row.sequence,
        note: row.note,
        createdAt: row.createdAt,
      );

  ActivityJournalEntryEntity _entryFromRow(ActivityEntry row) =>
      ActivityJournalEntryEntity(
        id: row.id,
        sessionId: row.sessionId,
        householdId: row.householdId,
        activityType: row.activityType,
        title: row.title,
        participants: row.participants,
        topic: row.topic,
        place: row.place,
        startedAt: row.startedAt,
        endedAt: row.endedAt,
        notes: row.notes,
        followUp: row.followUp,
        isArchived: row.isArchived,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
      );
}
