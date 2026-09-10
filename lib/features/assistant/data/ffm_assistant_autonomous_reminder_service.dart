import 'package:uuid/uuid.dart';

import '../../reminder/data/repositories/reminder_repository.dart';
import '../../reminder/data/services/reminder_schedule_replenisher.dart';
import '../../reminder/domain/entities/reminder_entity.dart';
import '../domain/ffm_assistant_insight.dart';

/// Persists and schedules a bounded, deterministic reminder proposal.
/// This service deliberately cannot create financial transactions.
class FfmAssistantAutonomousReminderService {
  const FfmAssistantAutonomousReminderService(
    this._reminders, [
    this._scheduleReplenisher,
  ]);

  final ReminderRepository _reminders;
  final ReminderScheduleReplenisher? _scheduleReplenisher;

  Future<ReminderEntity?> createFrom(FfmAssistantInsight insight) async {
    final payload = insight.actionPayload;
    if (insight.type != FfmAssistantInsightType.reminderSuggestion ||
        payload == null ||
        payload['type'] != 'reminder_suggestion') {
      return null;
    }
    final sourceType = ReminderSourceTypeX.fromStorage(
      payload['sourceType']?.toString(),
    );
    final sourceId = payload['sourceId']?.toString().trim();
    final title = payload['title']?.toString().trim();
    final scheduledAt = DateTime.tryParse(
      payload['scheduledAt']?.toString() ?? '',
    );
    if (sourceType == null ||
        sourceId == null ||
        sourceId.isEmpty ||
        title == null ||
        title.isEmpty ||
        scheduledAt == null) {
      return null;
    }

    final existing = await _reminders.getReminders(insight.householdId);
    if (existing.any(
      (item) => item.sourceType == sourceType && item.sourceId == sourceId,
    )) {
      return null;
    }

    final id = const Uuid().v4();
    final reminder = ReminderEntity(
      id: id,
      householdId: insight.householdId,
      title: title,
      note: payload['note']?.toString(),
      scheduledAt: scheduledAt,
      recurrenceType: ReminderRecurrenceType.once,
      weekdays: const [],
      notificationId: stableReminderNotificationId(id, 'initial'),
      sourceType: sourceType,
      sourceId: sourceId,
      origin: ReminderOrigin.autonomous,
    );
    await _reminders.saveReminder(reminder);
    await _scheduleReplenisher?.replenish(householdId: insight.householdId);
    return reminder;
  }
}
