import '../repositories/reminder_repository.dart';
import 'reminder_notification_service.dart';
import '../../domain/usecases/reminder_usecases.dart';

/// Menjaga antrean alarm one-shot tetap terisi tanpa bergantung pada aplikasi
/// dibuka atau pengguna menekan notifikasi.
class ReminderScheduleReplenisher {
  const ReminderScheduleReplenisher(
    this._repository,
    this._notifications,
    this._calculator,
  );

  final ReminderRepository _repository;
  final ReminderNotificationGateway _notifications;
  final ReminderOccurrenceCalculator _calculator;

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
    return scheduled;
  }
}
