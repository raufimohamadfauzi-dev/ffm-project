import '../repositories/reminder_repository.dart';
import '../../../assistant/data/ffm_assistant_autonomy_trigger_service.dart';
import 'reminder_notification_service.dart';
import '../../domain/usecases/reminder_usecases.dart';

/// Menjaga antrean alarm one-shot tetap terisi tanpa bergantung pada aplikasi
/// dibuka atau pengguna menekan notifikasi.
class ReminderScheduleReplenisher {
  const ReminderScheduleReplenisher(
    this._repository,
    this._notifications,
    this._calculator, [
    this._autonomyTrigger,
  ]);

  final ReminderRepository _repository;
  final ReminderNotificationGateway _notifications;
  final ReminderOccurrenceCalculator _calculator;
  final FfmAssistantAutonomyTriggerService? _autonomyTrigger;

  Future<int> replenish({required String householdId, DateTime? now}) async {
    final permission = await _notifications.permissionState();
    if (!permission.canSchedule) return 0;

    final current = now ?? DateTime.now();
    final reminders = await _repository.getReminders(householdId);
    var scheduled = 0;
    for (final reminder in reminders.where((item) => item.isActive)) {
      final occurrences = _calculator.upcomingOccurrences(
        reminder,
        now: current,
      );
      for (final occurrence in occurrences) {
        final history = await _repository.ensureHistory(
          reminder: reminder,
          occurrence: occurrence,
        );
        await _notifications.schedule(
          reminder: reminder,
          occurrence: occurrence,
          historyId: history.id,
        );
        scheduled++;
      }
    }
    final due = await _repository.getDueUntriggeredHistories(
      householdId,
      current,
    );
    for (final history in due) {
      await _autonomyTrigger?.emitSafely(
        triggerId: history.id,
        type: 'reminder.due',
        householdId: householdId,
        occurredAt: history.scheduledAt,
        entityId: history.reminderId,
        payload: {
          'reminderId': history.reminderId,
          'historyId': history.id,
          'occurrenceKey': history.occurrenceKey,
        },
      );
    }
    return scheduled;
  }
}
