import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/audit_logger.dart';
import '../../domain/entities/activity_entity.dart';

class ActivityRepository {
  const ActivityRepository(this.database, this.auditLogger);

  final AppDatabase database;
  final AuditLogger auditLogger;

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
    await database
        .into(database.activitySessions)
        .insertOnConflictUpdate(
          ActivitySessionsCompanion.insert(
            id: entity.id,
            householdId: entity.householdId,
            title: entity.title,
            parentSessionId: Value(entity.parentSessionId),
            category: Value(entity.category),
            startedAt: entity.startedAt,
            endedAt: Value<DateTime?>(entity.endedAt),
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
      },
    );
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
  }

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

  ActivitySessionEntity _sessionFromRow(ActivitySession row) =>
      ActivitySessionEntity(
        id: row.id,
        householdId: row.householdId,
        title: row.title,
        category: row.category,
        parentSessionId: row.parentSessionId,
        startedAt: row.startedAt,
        endedAt: row.endedAt,
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
