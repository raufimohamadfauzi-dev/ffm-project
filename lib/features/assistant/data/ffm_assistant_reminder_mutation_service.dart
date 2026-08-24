import '../../reminder/data/repositories/reminder_repository.dart';
import '../../reminder/data/services/reminder_notification_service.dart';
import '../../reminder/domain/entities/reminder_entity.dart';
import '../../reminder/domain/usecases/reminder_usecases.dart';

/// Menjaga mutasi pengingat dari Agent tetap memakai kontrak notifikasi domain.
/// Layanan ini tidak menafsirkan teks dan tidak melewati konfirmasi Action Plan.
class FfmAssistantReminderMutationService {
  FfmAssistantReminderMutationService({
    required ReminderRepository repository,
    required ReminderNotificationGateway notificationGateway,
    required ReminderOccurrenceCalculator occurrenceCalculator,
    DateTime Function()? clock,
  }) : _repository = repository,
       _notificationGateway = notificationGateway,
       _occurrenceCalculator = occurrenceCalculator,
       _clock = clock ?? DateTime.now;

  final ReminderRepository _repository;
  final ReminderNotificationGateway _notificationGateway;
  final ReminderOccurrenceCalculator _occurrenceCalculator;
  final DateTime Function() _clock;

  Future<void> save(ReminderEntity next) async {
    final permission = await _notificationGateway.requestPermissions();
    if (!permission.canSchedule) {
      throw StateError(
        'Izin notifikasi dan alarm presisi wajib diaktifkan agar pengingat bisa dijadwalkan.',
      );
    }
    final previous = await _repository.getReminder(next.householdId, next.id);
    if (previous != null) await _cancelScheduled(previous);
    await _repository.saveReminder(next);
    if (next.isActive) await _scheduleNext(next);
  }

  Future<void> archive(ReminderEntity reminder) async {
    await _cancelScheduled(reminder);
    await _repository.setActive(
      householdId: reminder.householdId,
      reminderId: reminder.id,
      isActive: false,
    );
  }

  Future<void> _cancelScheduled(ReminderEntity reminder) async {
    final occurrence = _occurrenceCalculator.nextOccurrence(
      reminder,
      now: _clock().subtract(const Duration(seconds: 1)),
    );
    if (occurrence != null) {
      await _notificationGateway.cancel(occurrence.notificationId);
    }
    await _notificationGateway.cancel(reminder.notificationId);
  }

  Future<void> _scheduleNext(ReminderEntity reminder) async {
    final occurrence = _occurrenceCalculator.nextOccurrence(
      reminder,
      now: _clock().subtract(const Duration(seconds: 1)),
    );
    if (occurrence == null) return;
    final history = await _repository.ensureHistory(
      reminder: reminder,
      occurrence: occurrence,
    );
    await _notificationGateway.schedule(
      reminder: reminder,
      occurrence: occurrence,
      historyId: history.id,
    );
  }
}
