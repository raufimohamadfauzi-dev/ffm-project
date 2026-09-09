import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../assistant/data/ffm_assistant_autonomy_trigger_service.dart';
import '../../data/repositories/reminder_repository.dart';
import '../../data/services/reminder_notification_service.dart';
import '../../domain/entities/reminder_entity.dart';
import '../../domain/usecases/reminder_usecases.dart';

sealed class ReminderEvent {
  const ReminderEvent();
}

final class ReminderLoadRequested extends ReminderEvent {
  const ReminderLoadRequested();
}

final class ReminderSaved extends ReminderEvent {
  const ReminderSaved(this.reminder);

  final ReminderEntity reminder;
}

final class ReminderActiveChanged extends ReminderEvent {
  const ReminderActiveChanged(this.reminder, this.isActive);

  final ReminderEntity reminder;
  final bool isActive;
}

final class ReminderDeleted extends ReminderEvent {
  const ReminderDeleted(this.reminder);

  final ReminderEntity reminder;
}

final class ReminderHistoryStatusChanged extends ReminderEvent {
  const ReminderHistoryStatusChanged({
    required this.history,
    required this.status,
    this.snoozedUntil,
  });

  final ReminderHistoryEntity history;
  final ReminderHistoryStatus status;
  final DateTime? snoozedUntil;
}

final class ReminderHistoryDeleted extends ReminderEvent {
  const ReminderHistoryDeleted(this.history);

  final ReminderHistoryEntity history;
}

final class ReminderNotificationActionReceived extends ReminderEvent {
  const ReminderNotificationActionReceived({
    required this.actionId,
    required this.payload,
  });

  final String actionId;
  final Map<String, dynamic> payload;
}

class ReminderState {
  const ReminderState({
    this.reminders = const [],
    this.history = const [],
    this.isLoading = false,
    this.errorMessage,
    this.permissionState,
  });

  final List<ReminderEntity> reminders;
  final List<ReminderHistoryView> history;
  final bool isLoading;
  final String? errorMessage;

  /// Current device permission state for showing a banner in the UI.
  /// Null until the first load completes.
  final ReminderPermissionState? permissionState;

  ReminderState copyWith({
    List<ReminderEntity>? reminders,
    List<ReminderHistoryView>? history,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
    ReminderPermissionState? permissionState,
    bool clearPermissionState = false,
  }) => ReminderState(
    reminders: reminders ?? this.reminders,
    history: history ?? this.history,
    isLoading: isLoading ?? this.isLoading,
    errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    permissionState: clearPermissionState
        ? null
        : permissionState ?? this.permissionState,
  );
}

class ReminderBloc extends Bloc<ReminderEvent, ReminderState> {
  ReminderBloc({
    required this._repository,
    required this._notificationService,
    required this._occurrenceCalculator,
    required this._householdId,
    this._autonomyTrigger,
  }) : super(const ReminderState()) {
    on<ReminderLoadRequested>(_load);
    on<ReminderSaved>(_save);
    on<ReminderActiveChanged>(_changeActive);
    on<ReminderDeleted>(_delete);
    on<ReminderHistoryStatusChanged>(_changeHistoryStatus);
    on<ReminderHistoryDeleted>(_deleteHistory);
    on<ReminderNotificationActionReceived>(_handleNotificationAction);
    _notificationService.onAction = (action, payload) async {
      if (!isClosed) {
        await _applyNotificationAction(action, payload);
        if (!isClosed) add(const ReminderLoadRequested());
      }
    };
  }

  final ReminderRepository _repository;
  final ReminderNotificationGateway _notificationService;
  final ReminderOccurrenceCalculator _occurrenceCalculator;
  final String _householdId;
  final FfmAssistantAutonomyTriggerService? _autonomyTrigger;

  Future<void> recover() async {
    final pendingActions = await _notificationService.consumePendingActions();
    for (final action in pendingActions) {
      await _applyNotificationAction(action.actionId, action.payload);
      await _acknowledgeNotificationAction(action.id);
    }
    await _reconcileTriggeredHistories();
    final reminders = await _repository.getReminders(_householdId);
    await _reschedule(reminders);
  }

  Future<void> _load(
    ReminderLoadRequested event,
    Emitter<ReminderState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      final pendingActions = await _notificationService.consumePendingActions();
      for (final action in pendingActions) {
        await _applyNotificationAction(action.actionId, action.payload);
        await _acknowledgeNotificationAction(action.id);
      }
      await _reconcileTriggeredHistories();
      final reminders = await _repository.getReminders(_householdId);
      final history = await _repository.getHistoryViews(_householdId);
      final permission = await _notificationService.permissionState();
      await _reschedule(reminders);
      emit(
        state.copyWith(
          reminders: _visibleReminders(reminders),
          history: history,
          isLoading: false,
          permissionState: permission,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          isLoading: false,
          errorMessage: 'Pengingat belum bisa dimuat: $error',
        ),
      );
    }
  }

  Future<void> _save(ReminderSaved event, Emitter<ReminderState> emit) async {
    try {
      final permission = await _notificationService.requestPermissions();
      if (!permission.canSchedule) {
        throw StateError(
          'Izin notifikasi dan alarm presisi wajib diaktifkan agar pengingat bisa berbunyi.',
        );
      }
      final previous = await _repository.getReminder(
        _householdId,
        event.reminder.id,
      );
      if (previous != null) {
        await _cancelReminderNotifications(previous);
      }
      var dbSaved = false;
      try {
        await _repository.saveReminder(event.reminder);
        dbSaved = true;
        await _reschedule([event.reminder]);
        add(const ReminderLoadRequested());
      } catch (error) {
        if (dbSaved) {
          add(const ReminderLoadRequested());
          emit(
            state.copyWith(
              errorMessage:
                  'Pengingat tersimpan, tetapi gagal dijadwalkan ke notifikasi: $error',
            ),
          );
        } else {
          rethrow;
        }
      }
    } catch (error) {
      emit(state.copyWith(errorMessage: 'Pengingat belum tersimpan: $error'));
    }
  }

  Future<void> _changeActive(
    ReminderActiveChanged event,
    Emitter<ReminderState> emit,
  ) async {
    try {
      if (event.isActive) {
        final permission = await _notificationService.requestPermissions();
        if (!permission.canSchedule) {
          throw StateError(
            'Izin notifikasi dan alarm presisi wajib diaktifkan terlebih dahulu.',
          );
        }
      }
      await _repository.setActive(
        householdId: _householdId,
        reminderId: event.reminder.id,
        isActive: event.isActive,
      );
      if (!event.isActive) {
        await _cancelReminderNotifications(event.reminder);
      } else {
        await _reschedule([event.reminder]);
      }
      add(const ReminderLoadRequested());
    } catch (error) {
      emit(
        state.copyWith(errorMessage: 'Status pengingat belum berubah: $error'),
      );
    }
  }

  Future<void> _delete(
    ReminderDeleted event,
    Emitter<ReminderState> emit,
  ) async {
    try {
      await _cancelReminderNotifications(event.reminder);
      await _repository.deleteReminder(
        householdId: _householdId,
        reminderId: event.reminder.id,
      );
      add(const ReminderLoadRequested());
    } catch (error) {
      emit(state.copyWith(errorMessage: 'Pengingat belum terhapus: $error'));
    }
  }

  Future<void> _changeHistoryStatus(
    ReminderHistoryStatusChanged event,
    Emitter<ReminderState> emit,
  ) async {
    try {
      await _repository.updateHistoryStatus(
        householdId: _householdId,
        historyId: event.history.id,
        status: event.status,
        snoozedUntil: event.snoozedUntil,
      );
      await _cancelHistoryNotification(event.history);
      if (event.status == ReminderHistoryStatus.snoozed &&
          event.snoozedUntil != null) {
        final reminder = await _repository.getReminder(
          _householdId,
          event.history.reminderId,
        );
        if (reminder != null && reminder.isActive) {
          await _scheduleSnooze(
            reminder: reminder,
            history: event.history,
            scheduledAt: event.snoozedUntil!,
          );
        }
      }
      add(const ReminderLoadRequested());
    } catch (error) {
      emit(
        state.copyWith(errorMessage: 'Riwayat pengingat belum berubah: $error'),
      );
    }
  }

  Future<void> _deleteHistory(
    ReminderHistoryDeleted event,
    Emitter<ReminderState> emit,
  ) async {
    try {
      await _cancelHistoryNotification(event.history);
      await _repository.deleteHistory(
        householdId: _householdId,
        historyId: event.history.id,
      );
      add(const ReminderLoadRequested());
    } catch (error) {
      emit(state.copyWith(errorMessage: 'Riwayat belum terhapus: $error'));
    }
  }

  Future<void> _handleNotificationAction(
    ReminderNotificationActionReceived event,
    Emitter<ReminderState> emit,
  ) async {
    try {
      await _applyNotificationAction(event.actionId, event.payload);
      add(const ReminderLoadRequested());
    } catch (error) {
      emit(
        state.copyWith(errorMessage: 'Aksi pengingat belum diproses: $error'),
      );
    }
  }

  Future<void> _applyNotificationAction(
    String actionId,
    Map<String, dynamic> payload,
  ) async {
    if (!const {'open', 'complete', 'snooze_10'}.contains(actionId)) return;
    final householdId = '${payload['householdId'] ?? ''}';
    if (householdId != _householdId) return;
    final historyId = '${payload['historyId'] ?? ''}';
    final reminderId = '${payload['reminderId'] ?? ''}';
    if (historyId.isEmpty || reminderId.isEmpty) return;
    var history = await _repository.getHistoryById(
      householdId: _householdId,
      historyId: historyId,
    );
    if (history != null &&
        (history.reminderId != reminderId ||
            ('${payload['rootOccurrenceKey'] ?? payload['occurrenceKey'] ?? ''}'
                    .isNotEmpty &&
                history.occurrenceKey !=
                    '${payload['rootOccurrenceKey'] ?? payload['occurrenceKey']}'))) {
      return;
    }
    if (history == null) {
      final reminder = await _repository.getReminder(_householdId, reminderId);
      final occurrenceKey =
          '${payload['rootOccurrenceKey'] ?? payload['occurrenceKey'] ?? ''}';
      if (reminder == null || occurrenceKey.isEmpty) return;
      history = await _repository.ensureHistory(
        reminder: reminder,
        occurrence: ReminderOccurrence(
          key: occurrenceKey,
          scheduledAt:
              DateTime.tryParse('${payload['scheduledAt'] ?? ''}') ??
              DateTime.now(),
          notificationId:
              int.tryParse('${payload['notificationId'] ?? ''}') ??
              reminder.notificationId,
        ),
      );
    }

    // Queue the reminder event separately; a trigger failure must not break
    // the user's complete, snooze, or open action.
    try {
      await _autonomyTrigger?.emit(
        triggerId: history.id,
        type: 'reminder.due',
        householdId: _householdId,
        occurredAt: history.scheduledAt,
        entityId: reminderId,
        payload: <String, Object?>{
          'reminderId': reminderId,
          'historyId': history.id,
          'occurrenceKey': history.occurrenceKey,
          'actionId': actionId,
        },
      );
    } on Object {
      // Reminder UX remains authoritative when autonomy persistence is down.
    }

    if (actionId == 'complete') {
      await _repository.markHistoryTriggered(
        householdId: _householdId,
        historyId: history.id,
      );
      await _repository.updateHistoryStatus(
        householdId: _householdId,
        historyId: history.id,
        status: ReminderHistoryStatus.completed,
      );
      await _cancelHistoryNotification(history);
      return;
    }
    if (actionId == 'snooze_10') {
      await _repository.markHistoryTriggered(
        householdId: _householdId,
        historyId: history.id,
      );
      final reminder = await _repository.getReminder(_householdId, reminderId);
      if (reminder == null || !reminder.isActive) return;
      final requestedUntil = DateTime.tryParse(
        '${payload['snoozedUntil'] ?? ''}',
      );
      final until =
          requestedUntil ??
          DateTime.now().add(
            Duration(minutes: reminder.defaultSnoozeMinutes.clamp(1, 1440)),
          );
      await _repository.updateHistoryStatus(
        householdId: _householdId,
        historyId: history.id,
        status: ReminderHistoryStatus.snoozed,
        snoozedUntil: until,
      );
      if (payload['snoozeScheduled'] != true && until.isAfter(DateTime.now())) {
        await _scheduleSnooze(
          reminder: reminder,
          history: history,
          scheduledAt: until,
        );
      }
      return;
    }

    // Ketuk biasa (action `open`) berarti notification sudah diterima.
    // Occurrence dipindahkan ke history sebagai pending sampai user memilih
    // Selesai atau Tunda.
    await _repository.markHistoryTriggered(
      householdId: _householdId,
      historyId: history.id,
    );
  }

  Future<void> _reconcileTriggeredHistories() async {
    final now = DateTime.now();
    final due = await _repository.getDueUntriggeredHistories(_householdId, now);
    for (final history in due) {
      await _repository.markHistoryTriggered(
        householdId: _householdId,
        historyId: history.id,
        triggeredAt: history.scheduledAt,
      );
    }
    final dueSnoozed = await _repository.getDueSnoozedHistories(
      _householdId,
      now,
    );
    for (final history in dueSnoozed) {
      await _repository.markHistoryTriggered(
        householdId: _householdId,
        historyId: history.id,
        triggeredAt: history.snoozedUntil ?? now,
      );
    }
  }

  List<ReminderEntity> _visibleReminders(List<ReminderEntity> reminders) =>
      reminders
          .where((reminder) {
            if (!reminder.isActive ||
                reminder.recurrenceType != ReminderRecurrenceType.once) {
              return true;
            }
            return _occurrenceCalculator.nextOccurrence(
                  reminder,
                  now: DateTime.now(),
                ) !=
                null;
          })
          .toList(growable: false);

  Future<void> _acknowledgeNotificationAction(String id) async {
    final service = _notificationService;
    if (service is ReminderNotificationLifecycleGateway) {
      await (service as ReminderNotificationLifecycleGateway).acknowledgeAction(
        id,
      );
    }
  }

  Future<void> _cancelReminderNotifications(ReminderEntity reminder) async {
    final service = _notificationService;
    if (service is ReminderNotificationLifecycleGateway) {
      await (service as ReminderNotificationLifecycleGateway).cancelReminder(
        reminder.id,
      );
      return;
    }
    final occurrences = _occurrenceCalculator.upcomingOccurrences(
      reminder,
      now: DateTime.now().subtract(const Duration(seconds: 1)),
    );
    for (final occurrence in occurrences) {
      await service.cancel(occurrence.notificationId);
    }
    await service.cancel(reminder.notificationId);
  }

  Future<void> _cancelHistoryNotification(ReminderHistoryEntity history) async {
    final service = _notificationService;
    if (service is ReminderNotificationLifecycleGateway) {
      await (service as ReminderNotificationLifecycleGateway).cancelHistory(
        history.id,
      );
      return;
    }
    await service.cancel(history.notificationId);
    await service.cancel(
      stableSnoozeNotificationId(history.reminderId, history.occurrenceKey),
    );
  }

  Future<void> _scheduleSnooze({
    required ReminderEntity reminder,
    required ReminderHistoryEntity history,
    required DateTime scheduledAt,
  }) async {
    final service = _notificationService;
    if (service is ReminderNotificationLifecycleGateway) {
      await (service as ReminderNotificationLifecycleGateway).scheduleSnooze(
        reminder: reminder,
        history: history,
        scheduledAt: scheduledAt,
      );
      return;
    }
    await service.schedule(
      reminder: reminder,
      occurrence: ReminderOccurrence(
        key: '${history.occurrenceKey}:snooze',
        scheduledAt: scheduledAt,
        notificationId: stableSnoozeNotificationId(
          reminder.id,
          history.occurrenceKey,
        ),
      ),
      historyId: history.id,
    );
  }

  Future<void> _reschedule(List<ReminderEntity> reminders) async {
    final permission = await _notificationService.permissionState();
    if (!permission.canSchedule) return;
    final now = DateTime.now();
    for (final reminder in reminders.where((item) => item.isActive)) {
      final occurrences = _occurrenceCalculator.upcomingOccurrences(
        reminder,
        now: now.subtract(const Duration(seconds: 1)),
      );
      for (final occurrence in occurrences) {
        final history = await _repository.ensureHistory(
          reminder: reminder,
          occurrence: occurrence,
        );
        await _notificationService.schedule(
          reminder: reminder,
          occurrence: occurrence,
          historyId: history.id,
        );
      }
    }
  }
}
