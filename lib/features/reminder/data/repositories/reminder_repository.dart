import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/audit_logger.dart';
import '../../domain/entities/reminder_entity.dart';

class ReminderHistoryFilter {
  const ReminderHistoryFilter({this.status});

  final ReminderHistoryStatus? status;
}

class ReminderHistoryView {
  const ReminderHistoryView({required this.history, required this.reminder});

  final ReminderHistoryEntity history;
  final ReminderEntity? reminder;
}

class ReminderRepository {
  const ReminderRepository(this.database);

  final AppDatabase database;

  Future<List<ReminderEntity>> getReminders(String householdId) async {
    final rows =
        await (database.select(database.reminders)
              ..where((row) => row.householdId.equals(householdId))
              ..orderBy([(row) => OrderingTerm.asc(row.scheduledAt)]))
            .get();
    return rows.map(_toReminder).toList(growable: false);
  }

  Future<ReminderEntity?> getReminder(
    String householdId,
    String reminderId,
  ) async {
    final row =
        await (database.select(database.reminders)..where(
              (item) =>
                  item.householdId.equals(householdId) &
                  item.id.equals(reminderId),
            ))
            .getSingleOrNull();
    return row == null ? null : _toReminder(row);
  }

  Future<void> saveReminder(ReminderEntity entity) async {
    final now = DateTime.now();
    await database
        .into(database.reminders)
        .insertOnConflictUpdate(
          RemindersCompanion.insert(
            id: entity.id,
            householdId: entity.householdId,
            title: entity.title,
            note: Value(entity.note),
            scheduledAt: entity.scheduledAt,
            recurrenceType: Value(entity.recurrenceType.storageValue),
            weekdaysJson: Value(jsonEncode(entity.weekdays)),
            isActive: Value(entity.isActive),
            soundUri: Value(entity.soundUri),
            soundName: Value(entity.soundName),
            defaultSnoozeMinutes: Value(entity.defaultSnoozeMinutes),
            notificationId: entity.notificationId,
            createdAt: entity.createdAt ?? now,
            updatedAt: Value(now),
          ),
        );
    await AuditLogger(database).record(
      action: 'simpan pengingat',
      entity: 'reminder',
      householdId: entity.householdId,
      newValue: {
        'id': entity.id,
        'title': entity.title,
        'recurrence': entity.recurrenceType.storageValue,
        'isActive': entity.isActive,
      },
    );
  }

  Future<void> setActive({
    required String householdId,
    required String reminderId,
    required bool isActive,
  }) async {
    await (database.update(database.reminders)..where(
          (row) =>
              row.householdId.equals(householdId) & row.id.equals(reminderId),
        ))
        .write(RemindersCompanion(isActive: Value(isActive)));
    await AuditLogger(database).record(
      action: isActive ? 'aktifkan pengingat' : 'nonaktifkan pengingat',
      entity: 'reminder',
      householdId: householdId,
      newValue: {'id': reminderId, 'isActive': isActive},
    );
  }

  Future<void> deleteReminder({
    required String householdId,
    required String reminderId,
  }) async {
    await (database.delete(database.reminders)..where(
          (row) =>
              row.householdId.equals(householdId) & row.id.equals(reminderId),
        ))
        .go();
    await AuditLogger(database).record(
      action: 'hapus pengingat',
      entity: 'reminder',
      householdId: householdId,
      newValue: {'id': reminderId},
    );
  }

  Future<ReminderHistoryEntity?> getHistoryById({
    required String householdId,
    required String historyId,
  }) async {
    final row =
        await (database.select(database.reminderHistories)..where(
              (item) =>
                  item.householdId.equals(householdId) &
                  item.id.equals(historyId),
            ))
            .getSingleOrNull();
    return row == null ? null : _toHistory(row);
  }

  Future<ReminderHistoryEntity?> getHistoryByOccurrence({
    required String householdId,
    required String reminderId,
    required String occurrenceKey,
  }) async {
    final row =
        await (database.select(database.reminderHistories)..where(
              (item) =>
                  item.householdId.equals(householdId) &
                  item.reminderId.equals(reminderId) &
                  item.occurrenceKey.equals(occurrenceKey),
            ))
            .getSingleOrNull();
    return row == null ? null : _toHistory(row);
  }

  Future<ReminderHistoryEntity> ensureHistory({
    required ReminderEntity reminder,
    required ReminderOccurrence occurrence,
  }) async {
    final existing = await getHistoryByOccurrence(
      householdId: reminder.householdId,
      reminderId: reminder.id,
      occurrenceKey: occurrence.key,
    );
    if (existing != null) return existing;

    final now = DateTime.now();
    final entity = ReminderHistoryEntity(
      id: '${reminder.id}-${occurrence.key}',
      reminderId: reminder.id,
      householdId: reminder.householdId,
      title: reminder.title,
      occurrenceKey: occurrence.key,
      scheduledAt: occurrence.scheduledAt,
      status: ReminderHistoryStatus.pending,
      notificationId: occurrence.notificationId,
      createdAt: now,
    );
    await database
        .into(database.reminderHistories)
        .insertOnConflictUpdate(
          ReminderHistoriesCompanion.insert(
            id: entity.id,
            reminderId: entity.reminderId,
            householdId: entity.householdId,
            title: entity.title,
            occurrenceKey: entity.occurrenceKey,
            scheduledAt: entity.scheduledAt,
            triggeredAt: Value(entity.triggeredAt),
            status: Value(entity.status.storageValue),
            notificationId: entity.notificationId,
            createdAt: entity.createdAt,
          ),
        );
    return entity;
  }

  Future<void> updateHistoryStatus({
    required String householdId,
    required String historyId,
    required ReminderHistoryStatus status,
    DateTime? snoozedUntil,
  }) async {
    final now = DateTime.now();
    final existing =
        await (database.select(database.reminderHistories)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.id.equals(historyId),
            ))
            .getSingleOrNull();
    await (database.update(database.reminderHistories)..where(
          (row) =>
              row.householdId.equals(householdId) & row.id.equals(historyId),
        ))
        .write(
          ReminderHistoriesCompanion(
            status: Value(status.storageValue),
            triggeredAt: Value(
              existing?.triggeredAt ??
                  (status == ReminderHistoryStatus.pending ? null : now),
            ),
            completedAt: Value(
              status == ReminderHistoryStatus.completed ? now : null,
            ),
            snoozedUntil: Value(snoozedUntil),
            updatedAt: Value(now),
          ),
        );
    await AuditLogger(database).record(
      action: 'ubah status pengingat',
      entity: 'reminder_history',
      householdId: householdId,
      newValue: {
        'id': historyId,
        'status': status.storageValue,
        if (snoozedUntil != null)
          'snoozedUntil': snoozedUntil.toIso8601String(),
      },
    );
  }

  Future<List<ReminderHistoryView>> getHistoryViews(
    String householdId, {
    ReminderHistoryFilter filter = const ReminderHistoryFilter(),
  }) async {
    final historyRows =
        await (database.select(database.reminderHistories)
              ..where((row) {
                final household = row.householdId.equals(householdId);
                final status = filter.status == null
                    ? const Constant(true)
                    : row.status.equals(filter.status!.storageValue);
                return household & status;
              })
              ..orderBy([(row) => OrderingTerm.desc(row.scheduledAt)]))
            .get();
    final reminders = await getReminders(householdId);
    final byId = {for (final reminder in reminders) reminder.id: reminder};
    return historyRows
        .map(
          (row) => ReminderHistoryView(
            history: _toHistory(row),
            reminder: byId[row.reminderId],
          ),
        )
        .toList(growable: false);
  }

  Future<void> deleteHistory({
    required String householdId,
    required String historyId,
  }) async {
    await (database.delete(database.reminderHistories)..where(
          (row) =>
              row.householdId.equals(householdId) & row.id.equals(historyId),
        ))
        .go();
  }

  Future<void> deleteHistories({
    required String householdId,
    required Iterable<String> historyIds,
  }) async {
    final ids = historyIds.toSet();
    if (ids.isEmpty) return;
    await (database.delete(database.reminderHistories)..where(
          (row) => row.householdId.equals(householdId) & row.id.isIn(ids),
        ))
        .go();
  }

  Future<void> deleteAllHistory(String householdId) async {
    await (database.delete(
      database.reminderHistories,
    )..where((row) => row.householdId.equals(householdId))).go();
  }

  ReminderEntity _toReminder(Reminder row) => ReminderEntity(
    id: row.id,
    householdId: row.householdId,
    title: row.title,
    note: row.note,
    scheduledAt: row.scheduledAt,
    recurrenceType: ReminderRecurrenceTypeX.fromStorage(row.recurrenceType),
    weekdays: _decodeWeekdays(row.weekdaysJson),
    isActive: row.isActive,
    soundUri: row.soundUri,
    soundName: row.soundName,
    defaultSnoozeMinutes: row.defaultSnoozeMinutes,
    notificationId: row.notificationId,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );

  ReminderHistoryEntity _toHistory(ReminderHistory row) =>
      ReminderHistoryEntity(
        id: row.id,
        reminderId: row.reminderId,
        householdId: row.householdId,
        title: row.title,
        occurrenceKey: row.occurrenceKey,
        scheduledAt: row.scheduledAt,
        triggeredAt: row.triggeredAt,
        status: ReminderHistoryStatusX.fromStorage(row.status),
        completedAt: row.completedAt,
        snoozedUntil: row.snoozedUntil,
        notificationId: row.notificationId,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
      );

  List<int> _decodeWeekdays(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is! List) return const [];
      return decoded.whereType<num>().map((item) => item.toInt()).toList();
    } on Object {
      return const [];
    }
  }
}
