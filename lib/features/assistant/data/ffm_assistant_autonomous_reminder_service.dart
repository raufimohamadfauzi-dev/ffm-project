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
    final sourceType =
        ReminderSourceTypeX.fromStorage(payload['sourceType']?.toString()) ??
        ReminderSourceType.assistantLog;
    final rawSourceId = payload['sourceId']?.toString().trim();
    final sourceId = (rawSourceId != null && rawSourceId.isNotEmpty)
        ? rawSourceId
        : insight.id;
    final rawTitle = payload['title']?.toString().trim();
    final title = (rawTitle != null && rawTitle.isNotEmpty)
        ? rawTitle
        : insight.title.trim();
    final scheduledAt =
        DateTime.tryParse(payload['scheduledAt']?.toString() ?? '') ??
        insight.expiresAt?.subtract(const Duration(days: 7)) ??
        DateTime.now().add(const Duration(hours: 1));

    if (title.isEmpty) {
      return null;
    }

    final existing = await _reminders.getReminders(insight.householdId);
    if (existing.any(
      (item) =>
          item.isActive &&
          ((item.sourceType == sourceType && item.sourceId == sourceId) ||
              (item.title.toLowerCase() == title.toLowerCase() &&
                  item.origin == ReminderOrigin.autonomous)),
    )) {
      return null;
    }

    final modeRaw =
        payload['reminderMode']?.toString() ?? payload['mode']?.toString();
    final mode = ReminderModeX.fromStorage(modeRaw);

    final id = const Uuid().v4();
    final reminder = ReminderEntity(
      id: id,
      householdId: insight.householdId,
      title: title,
      note: payload['note']?.toString() ?? insight.summary,
      scheduledAt: scheduledAt,
      recurrenceType: ReminderRecurrenceType.once,
      weekdays: const [],
      notificationId: stableReminderNotificationId(id, 'initial'),
      sourceType: sourceType,
      sourceId: sourceId,
      origin: ReminderOrigin.autonomous,
      mode: mode,
    );
    await _reminders.saveReminder(reminder);
    await _scheduleReplenisher?.replenish(householdId: insight.householdId);
    return reminder;
  }
}
