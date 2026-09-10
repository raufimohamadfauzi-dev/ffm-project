import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_autonomy_repository.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_insight_repository.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_reminder_due_insight_service.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_insight.dart';
import 'package:ffm_manager/features/reminder/data/repositories/reminder_repository.dart';
import 'package:ffm_manager/features/reminder/domain/entities/reminder_entity.dart';

void main() {
  const householdId = 'local-household';

  test(
    'pengingat hutang jatuh tempo membuat satu insight tanpa transaksi',
    () async {
      final database = createInMemoryDatabaseForTests();
      addTearDown(database.close);
      final reminders = ReminderRepository(database);
      final insights = FfmAssistantInsightRepository(database);
      final now = DateTime(2026, 9, 10, 9);
      await database
          .into(database.liabilities)
          .insert(
            LiabilitiesCompanion.insert(
              id: 'liability-1',
              householdId: householdId,
              name: 'Cicilan motor',
              originalAmount: 12000000,
              remainingBalance: 8000000,
              startDate: now.subtract(const Duration(days: 30)),
              dueDate: drift.Value(now),
              createdAt: now.subtract(const Duration(days: 30)),
            ),
          );
      final reminder = ReminderEntity(
        id: 'reminder-1',
        householdId: householdId,
        title: 'Bayar cicilan motor',
        scheduledAt: now.subtract(const Duration(minutes: 5)),
        recurrenceType: ReminderRecurrenceType.once,
        weekdays: const [],
        notificationId: 101,
        sourceType: ReminderSourceType.liability,
        sourceId: 'liability-1',
      );
      await reminders.saveReminder(reminder);
      final history = await reminders.ensureHistory(
        reminder: reminder,
        occurrence: ReminderOccurrence(
          key: '20260910-0855',
          scheduledAt: reminder.scheduledAt,
          notificationId: 101,
        ),
      );
      final service = FfmAssistantReminderDueInsightService(
        database,
        reminders,
        insights,
        clock: () => now,
      );
      final event = FfmAssistantAutonomyEvent(
        id: 'reminder-due-${history.id}',
        type: 'reminder.due',
        occurredAt: now,
        householdId: householdId,
        payload: {'reminderId': reminder.id, 'historyId': history.id},
      );

      await service.createFor(event);
      await service.createFor(event);

      final active = await insights.getActiveInsights(householdId: householdId);
      final transactions = await database.select(database.transactions).get();
      expect(active, hasLength(1));
      expect(active.single.type, FfmAssistantInsightType.reminderDue);
      expect(active.single.title, contains('Cicilan motor'));
      expect(active.single.dedupeKey, 'reminder-due:${history.id}');
      expect(transactions, isEmpty);
    },
  );
}
