import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/domain/detectors/reminder_suggestion_detector.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_insight.dart';
import 'package:ffm_manager/features/reminder/data/repositories/reminder_repository.dart';
import 'package:ffm_manager/features/reminder/domain/entities/reminder_entity.dart';

void main() {
  const householdId = 'local-household';
  final now = DateTime(2026, 9, 10, 9);

  test('mengusulkan draft hutang tanpa membuat pengingat otomatis', () async {
    final database = createInMemoryDatabaseForTests();
    addTearDown(database.close);
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
            dueDate: drift.Value(now.add(const Duration(days: 3))),
            createdAt: now.subtract(const Duration(days: 30)),
          ),
        );
    final detector = ReminderSuggestionDetector(database);

    final insight = await detector.detect(householdId: householdId, now: now);

    expect(insight, isNotNull);
    expect(insight!.type, FfmAssistantInsightType.reminderSuggestion);
    expect(insight.actionPayload!['type'], 'reminder_suggestion');
    expect(insight.actionPayload!['sourceType'], 'liability');
    expect(insight.actionPayload!['sourceId'], 'liability-1');
    expect(await database.select(database.reminders).get(), isEmpty);
    expect(await database.select(database.transactions).get(), isEmpty);
  });

  test(
    'tidak mengusulkan ulang sumber yang sudah tertaut ke pengingat',
    () async {
      final database = createInMemoryDatabaseForTests();
      addTearDown(database.close);
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
              dueDate: drift.Value(now.add(const Duration(days: 3))),
              createdAt: now.subtract(const Duration(days: 30)),
            ),
          );
      await ReminderRepository(database).saveReminder(
        ReminderEntity(
          id: 'reminder-1',
          householdId: householdId,
          title: 'Bayar cicilan motor',
          scheduledAt: now.add(const Duration(days: 3)),
          recurrenceType: ReminderRecurrenceType.once,
          weekdays: const [],
          notificationId: 101,
          sourceType: ReminderSourceType.liability,
          sourceId: 'liability-1',
        ),
      );

      final insight = await ReminderSuggestionDetector(database)
          .detect(householdId: householdId, now: now);

      expect(insight, isNull);
    },
  );

  test(
    'menormalisasi waktu tengah malam ke 08:00 pada pengingat otonom',
    () async {
      final database = createInMemoryDatabaseForTests();
      addTearDown(database.close);
      // dueDate tanpa komponen jam (date-only dari date picker) → 00:00:00
      final dueDateOnly = DateTime(2026, 9, 13); // jam 00:00:00
      await database
          .into(database.liabilities)
          .insert(
            LiabilitiesCompanion.insert(
              id: 'liability-midnight',
              householdId: householdId,
              name: 'Cicilan motor',
              originalAmount: 12000000,
              remainingBalance: 8000000,
              startDate: now.subtract(const Duration(days: 30)),
              dueDate: drift.Value(dueDateOnly),
              createdAt: now.subtract(const Duration(days: 30)),
            ),
          );
      final detector = ReminderSuggestionDetector(database);

      final insight = await detector.detect(householdId: householdId, now: now);

      expect(insight, isNotNull);
      final scheduledAt = DateTime.parse(
        insight!.actionPayload!['scheduledAt'] as String,
      );
      // Harus dinormalisasi ke 08:00, bukan 00:00
      expect(scheduledAt.hour, 8);
      expect(scheduledAt.minute, 0);
      expect(scheduledAt.day, 13);
    },
  );

  test(
    'mempertahankan waktu spesifik jika dueDate memiliki komponen jam',
    () async {
      final database = createInMemoryDatabaseForTests();
      addTearDown(database.close);
      final dueDateTime = DateTime(2026, 9, 13, 14, 30); // jam 14:30
      await database
          .into(database.liabilities)
          .insert(
            LiabilitiesCompanion.insert(
              id: 'liability-with-time',
              householdId: householdId,
              name: 'Cicilan motor',
              originalAmount: 12000000,
              remainingBalance: 8000000,
              startDate: now.subtract(const Duration(days: 30)),
              dueDate: drift.Value(dueDateTime),
              createdAt: now.subtract(const Duration(days: 30)),
            ),
          );
      final detector = ReminderSuggestionDetector(database);

      final insight = await detector.detect(householdId: householdId, now: now);

      expect(insight, isNotNull);
      final scheduledAt = DateTime.parse(
        insight!.actionPayload!['scheduledAt'] as String,
      );
      // Waktu asli 14:30 harus dipertahankan
      expect(scheduledAt.hour, 14);
      expect(scheduledAt.minute, 30);
    },
  );
}
