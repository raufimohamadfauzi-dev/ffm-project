import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/repositories/reminder_repository.dart';
import '../../../assistant/presentation/widgets/ffm_agent_status_indicator.dart';
import '../../data/services/reminder_notification_service.dart';
import '../../domain/entities/reminder_entity.dart';
import '../../domain/usecases/reminder_usecases.dart'
    hide stableReminderNotificationId;

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
  });

  final List<ReminderEntity> reminders;
  final List<ReminderHistoryView> history;
  final bool isLoading;
  final String? errorMessage;

  ReminderState copyWith({
    List<ReminderEntity>? reminders,
    List<ReminderHistoryView>? history,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) => ReminderState(
    reminders: reminders ?? this.reminders,
    history: history ?? this.history,
    isLoading: isLoading ?? this.isLoading,
    errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
  );
}

class ReminderBloc extends Bloc<ReminderEvent, ReminderState> {
  ReminderBloc({
    required ReminderRepository repository,
    required ReminderNotificationGateway notificationService,
    required ReminderOccurrenceCalculator occurrenceCalculator,
    required String householdId,
    FfmAgentStatusController? status,
  }) : _repository = repository,
       _notificationService = notificationService,
       _occurrenceCalculator = occurrenceCalculator,
       _householdId = householdId,
       _status = status,
       super(const ReminderState()) {
    on<ReminderLoadRequested>(_load);
    on<ReminderSaved>(_save);
    on<ReminderActiveChanged>(_changeActive);
    on<ReminderDeleted>(_delete);
    on<ReminderHistoryStatusChanged>(_changeHistoryStatus);
    on<ReminderHistoryDeleted>(_deleteHistory);
    on<ReminderNotificationActionReceived>(_handleNotificationAction);
    _notificationService.onAction = (action, payload) async {
      if (!isClosed) {
        add(
          ReminderNotificationActionReceived(
            actionId: action,
            payload: payload,
          ),
        );
      }
    };
  }

  final ReminderRepository _repository;
  final ReminderNotificationGateway _notificationService;
  final ReminderOccurrenceCalculator _occurrenceCalculator;
  final String _householdId;
  final FfmAgentStatusController? _status;

  Future<void> recover() async {
    final pendingActions = await _notificationService.consumePendingActions();
    for (final action in pendingActions) {
      await _applyNotificationAction(action.actionId, action.payload);
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
      }
      await _reconcileTriggeredHistories();
      final reminders = await _repository.getReminders(_householdId);
      final history = await _repository.getHistoryViews(_householdId);
      await _reschedule(reminders);
      emit(
        state.copyWith(
          reminders: _visibleReminders(reminders),
          history: history,
          isLoading: false,
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
    _status?.working('Menyimpan pengingat dan memperbarui konteks asisten...');
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
        final previousOccurrence = _occurrenceCalculator.nextOccurrence(
          previous,
          now: DateTime.now().subtract(const Duration(seconds: 1)),
        );
        if (previousOccurrence != null) {
          await _notificationService.cancel(previousOccurrence.notificationId);
        }
        await _notificationService.cancel(previous.notificationId);
      }
      await _repository.saveReminder(event.reminder);
      await _reschedule([event.reminder]);
      _status?.done('Pengingat tersimpan; konteks asisten diperbarui.');
      add(const ReminderLoadRequested());
    } catch (error) {
      _status?.failed('Pengingat belum berhasil disimpan.');
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
        final occurrence = _occurrenceCalculator.nextOccurrence(
          event.reminder,
          now: DateTime.now().subtract(const Duration(seconds: 1)),
        );
        if (occurrence != null) {
          await _notificationService.cancel(occurrence.notificationId);
        }
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
    _status?.working('Menghapus pengingat dan memperbarui konteks asisten...');
    try {
      final occurrence = _occurrenceCalculator.nextOccurrence(
        event.reminder,
        now: DateTime.now().subtract(const Duration(seconds: 1)),
      );
      if (occurrence != null) {
        await _notificationService.cancel(occurrence.notificationId);
      }
      await _notificationService.cancel(event.reminder.notificationId);
      await _repository.deleteReminder(
        householdId: _householdId,
        reminderId: event.reminder.id,
      );
      _status?.done('Pengingat dihapus; konteks asisten diperbarui.');
      add(const ReminderLoadRequested());
    } catch (error) {
      _status?.failed('Pengingat belum berhasil dihapus.');
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
      await _notificationService.cancel(event.history.notificationId);
      if (event.status == ReminderHistoryStatus.snoozed &&
          event.snoozedUntil != null) {
        final reminder = await _repository.getReminder(
          _householdId,
          event.history.reminderId,
        );
        if (reminder != null && reminder.isActive) {
          final occurrenceKey =
              '${event.history.occurrenceKey}:snooze:${event.snoozedUntil!.microsecondsSinceEpoch}';
          await _notificationService.schedule(
            reminder: reminder,
            occurrence: ReminderOccurrence(
              key: occurrenceKey,
              scheduledAt: event.snoozedUntil!,
              notificationId: stableReminderNotificationId(
                reminder.id,
                occurrenceKey,
              ),
            ),
            historyId: event.history.id,
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
    final householdId = '${payload['householdId'] ?? _householdId}';
    if (householdId != _householdId) return;
    final historyId = '${payload['historyId'] ?? ''}';
    final reminderId = '${payload['reminderId'] ?? ''}';
    if (historyId.isEmpty || reminderId.isEmpty) return;
    var history = await _repository.getHistoryById(
      householdId: _householdId,
      historyId: historyId,
    );
    if (history == null) {
      final reminder = await _repository.getReminder(_householdId, reminderId);
      final occurrenceKey = '${payload['occurrenceKey'] ?? ''}';
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
      return;
    }
    if (actionId == 'snooze_10') {
      await _repository.markHistoryTriggered(
        householdId: _householdId,
        historyId: history.id,
      );
      final until = DateTime.now().add(const Duration(minutes: 10));
      await _repository.updateHistoryStatus(
        householdId: _householdId,
        historyId: history.id,
        status: ReminderHistoryStatus.snoozed,
        snoozedUntil: until,
      );
      final reminder = await _repository.getReminder(_householdId, reminderId);
      if (reminder != null && reminder.isActive) {
        final occurrence = ReminderOccurrence(
          key:
              '${history.occurrenceKey}:snooze:${until.microsecondsSinceEpoch}',
          scheduledAt: until,
          notificationId: stableReminderNotificationId(
            reminder.id,
            '${history.occurrenceKey}:snooze:${until.microsecondsSinceEpoch}',
          ),
        );
        await _notificationService.schedule(
          reminder: reminder,
          occurrence: occurrence,
          historyId: history.id,
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

  Future<void> _reschedule(List<ReminderEntity> reminders) async {
    final permission = await _notificationService.permissionState();
    if (!permission.canSchedule) return;
    for (final reminder in reminders.where((item) => item.isActive)) {
      final occurrence = _occurrenceCalculator.nextOccurrence(
        reminder,
        now: DateTime.now().subtract(const Duration(seconds: 1)),
      );
      if (occurrence == null) continue;
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
