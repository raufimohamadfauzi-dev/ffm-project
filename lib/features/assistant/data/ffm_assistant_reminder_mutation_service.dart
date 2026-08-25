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

  /// Memperbarui hanya teks dan waktu Pengingat yang sudah ada. Seluruh
  /// konfigurasi recurrence, suara, snooze, dan identitas notifikasi diwariskan
  /// dari data resmi, sehingga Agent tidak dapat mengubahnya secara implisit.
  Future<ReminderEntity> updateTitleAndScheduledAt({
    required ReminderEntity previous,
    required String title,
    required DateTime scheduledAt,
    String? note,
  }) async {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      throw ArgumentError.value(title, 'title', 'Judul pengingat wajib diisi.');
    }
    final next = ReminderEntity(
      id: previous.id,
      householdId: previous.householdId,
      title: normalizedTitle,
      note: note?.trim().isEmpty == true ? null : note?.trim(),
      scheduledAt: scheduledAt,
      recurrenceType: previous.recurrenceType,
      weekdays: previous.weekdays,
      isActive: previous.isActive,
      soundUri: previous.soundUri,
      soundName: previous.soundName,
      defaultSnoozeMinutes: previous.defaultSnoozeMinutes,
      notificationId: previous.notificationId,
      createdAt: previous.createdAt,
      updatedAt: _clock(),
    );
    if (_sameEditableFields(previous, next)) return previous;

    final permission = await _notificationGateway.requestPermissions();
    if (!permission.canSchedule) {
      throw StateError(
        'Izin notifikasi dan alarm presisi wajib diaktifkan agar pengingat bisa diperbarui.',
      );
    }
    await _cancelScheduled(previous);
    try {
      await _repository.saveReminder(next);
      if (next.isActive) await _scheduleNext(next);
      return next;
    } on Object {
      // Mengembalikan data serta alarm lama sebagai pemulihan terbaik bila
      // penjadwalan ulang gagal setelah pembatalan alarm sebelumnya.
      await _repository.saveReminder(previous);
      if (previous.isActive) await _scheduleNext(previous);
      rethrow;
    }
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

  bool _sameEditableFields(ReminderEntity left, ReminderEntity right) =>
      left.title == right.title &&
      left.note == right.note &&
      left.scheduledAt == right.scheduledAt;
}
