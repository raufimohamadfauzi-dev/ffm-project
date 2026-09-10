import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_autonomous_reminder_service.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_insight.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/reminder/data/repositories/reminder_repository.dart';
import 'package:ffm_manager/features/reminder/domain/entities/reminder_entity.dart';

void main() {
  test('membuat pengingat otonom tanpa membuat transaksi', () async {
    final database = createInMemoryDatabaseForTests();
    addTearDown(database.close);
    final scheduledAt = DateTime(2026, 9, 13, 9);
    final insight = FfmAssistantInsight(
      id: 'suggestion-1',
      householdId: 'local-household',
      type: FfmAssistantInsightType.reminderSuggestion,
      severity: FfmAssistantInsightSeverity.info,
      priority: 82,
      confidence: 1,
      title: 'Buat pengingat untuk hutang',
      summary: 'Cicilan motor belum memiliki pengingat.',
      evidence: const {},
      suggestedAction: 'Tinjau draft pengingat',
      destination: FfmAssistantDestination.reminders,
      actionPayload: {
        'type': 'reminder_suggestion',
        'title': 'Bayar hutang: Cicilan motor',
        'note': 'Terkait hutang Cicilan motor.',
        'scheduledAt': scheduledAt.toIso8601String(),
        'sourceType': 'liability',
        'sourceId': 'liability-1',
      },
      createdAt: DateTime(2026, 9, 10),
      dedupeKey: 'reminder-suggestion:liability:liability-1:2026-9',
    );
    final service = FfmAssistantAutonomousReminderService(
      ReminderRepository(database),
    );

    final reminder = await service.createFrom(insight);

    expect(reminder, isNotNull);
    expect(reminder!.origin, ReminderOrigin.autonomous);
    expect(reminder.sourceType, ReminderSourceType.liability);
    expect(reminder.sourceId, 'liability-1');
    expect(reminder.soundUri, isNull);
    expect(await database.select(database.transactions).get(), isEmpty);
    expect(
      await service.createFrom(insight),
      isNull,
      reason: 'sumber yang sudah tertaut tidak boleh dibuat ulang',
    );
  });
}
