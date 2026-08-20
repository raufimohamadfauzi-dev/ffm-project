import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/reminder/data/repositories/reminder_repository.dart';
import 'package:ffm_manager/features/reminder/data/services/reminder_notification_service.dart';
import 'package:ffm_manager/features/reminder/domain/entities/reminder_entity.dart';
import 'package:ffm_manager/features/reminder/domain/usecases/reminder_usecases.dart';
import 'package:ffm_manager/features/reminder/presentation/bloc/reminder_bloc.dart';

void main() {
  const calculator = ReminderOccurrenceCalculator();
  const householdId = 'local-household';

  ReminderEntity reminder({
    ReminderRecurrenceType recurrence = ReminderRecurrenceType.once,
    required DateTime scheduledAt,
    List<int> weekdays = const [],
  }) => ReminderEntity(
    id: 'reminder-test',
    householdId: householdId,
    title: 'Cek pengingat',
    scheduledAt: scheduledAt,
    recurrenceType: recurrence,
    weekdays: weekdays,
    notificationId: 1001,
  );

  group('ReminderOccurrenceCalculator', () {
    test('once hanya menghasilkan satu occurrence sebelum waktu lewat', () {
      final scheduledAt = DateTime(2026, 8, 20, 9);
      final item = reminder(scheduledAt: scheduledAt);

      expect(
        calculator
            .nextOccurrence(item, now: DateTime(2026, 8, 20, 8))
            ?.scheduledAt,
        scheduledAt,
      );
      expect(
        calculator.nextOccurrence(item, now: DateTime(2026, 8, 20, 9)),
        isNull,
      );
      expect(
        calculator.nextOccurrence(item, now: DateTime(2026, 8, 21)),
        isNull,
      );
    });

    test('daily menghitung occurrence berikutnya pada hari berikutnya', () {
      final item = reminder(
        recurrence: ReminderRecurrenceType.daily,
        scheduledAt: DateTime(2026, 8, 20, 8, 30),
      );

      final occurrence = calculator.nextOccurrence(
        item,
        now: DateTime(2026, 8, 20, 9),
      );

      expect(occurrence?.scheduledAt, DateTime(2026, 8, 21, 8, 30));
    });

    test('weekly memilih hari yang dikonfigurasi berikutnya', () {
      final item = reminder(
        recurrence: ReminderRecurrenceType.weekly,
        scheduledAt: DateTime(2026, 8, 17, 8),
        weekdays: const [5],
      );

      final occurrence = calculator.nextOccurrence(
        item,
        now: DateTime(2026, 8, 18, 9),
      );

      expect(occurrence?.scheduledAt, DateTime(2026, 8, 21, 8));
    });
  });

  group('ReminderRepository', () {
    late AppDatabase database;
    late ReminderRepository repository;

    setUp(() {
      database = createInMemoryDatabaseForTests();
      repository = ReminderRepository(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('ensureHistory idempotent untuk occurrence yang sama', () async {
      final item = reminder(scheduledAt: DateTime(2026, 8, 25, 7));
      final occurrence = calculator.nextOccurrence(
        item,
        now: DateTime(2026, 8, 24),
      )!;
      await repository.saveReminder(item);

      final first = await repository.ensureHistory(
        reminder: item,
        occurrence: occurrence,
      );
      final second = await repository.ensureHistory(
        reminder: item,
        occurrence: occurrence,
      );
      final rows = await repository.getHistoryViews(householdId);

      expect(second.id, first.id);
      expect(rows, hasLength(1));
      expect(rows.single.history.occurrenceKey, occurrence.key);
    });
  });

  group('ReminderBloc scheduling', () {
    late AppDatabase database;
    late ReminderRepository repository;
    late FakeReminderNotificationGateway gateway;
    late ReminderBloc bloc;

    setUp(() {
      database = createInMemoryDatabaseForTests();
      repository = ReminderRepository(database);
      gateway = FakeReminderNotificationGateway();
      bloc = ReminderBloc(
        repository: repository,
        notificationService: gateway,
        occurrenceCalculator: calculator,
        householdId: householdId,
      );
    });

    tearDown(() async {
      await bloc.close();
      await database.close();
    });

    test('recover menjadwalkan ulang reminder aktif setelah restart', () async {
      final item = reminder(
        recurrence: ReminderRecurrenceType.daily,
        scheduledAt: DateTime.now().add(const Duration(hours: 2)),
      );
      await repository.saveReminder(item);

      await bloc.recover();

      expect(gateway.scheduled, hasLength(1));
      expect(gateway.scheduled.single.reminder.id, item.id);
      expect(
        await repository.getHistoryByOccurrence(
          householdId: householdId,
          reminderId: item.id,
          occurrenceKey: gateway.scheduled.single.occurrence.key,
        ),
        isNotNull,
      );
    });

    test(
      'snooze mengubah status dan menjadwalkan ulang sepuluh menit',
      () async {
        final item = reminder(
          scheduledAt: DateTime.now().subtract(const Duration(minutes: 1)),
        );
        await repository.saveReminder(item);
        final occurrence = ReminderOccurrence(
          key: '20260820-1200',
          scheduledAt: item.scheduledAt,
          notificationId: 2002,
        );

        final history = await repository.ensureHistory(
          reminder: item,
          occurrence: occurrence,
        );
        final until = DateTime.now().add(const Duration(minutes: 10));

        final stateFuture = bloc.stream.firstWhere(
          (state) => state.history.any(
            (view) =>
                view.history.id == history.id &&
                view.history.status == ReminderHistoryStatus.snoozed,
          ),
        );
        bloc.add(
          ReminderHistoryStatusChanged(
            history: history,
            status: ReminderHistoryStatus.snoozed,
            snoozedUntil: until,
          ),
        );
        await stateFuture;

        final stored = await repository.getHistoryById(
          householdId: householdId,
          historyId: history.id,
        );
        expect(stored?.status, ReminderHistoryStatus.snoozed);
        expect(
          stored?.snoozedUntil?.difference(until).abs(),
          lessThan(const Duration(seconds: 1)),
        );
        expect(gateway.scheduled, hasLength(1));
        expect(gateway.scheduled.single.occurrence.scheduledAt, until);
        expect(gateway.cancelled, contains(history.notificationId));
      },
    );
  });
}

class ScheduledReminder {
  const ScheduledReminder({
    required this.reminder,
    required this.occurrence,
    required this.historyId,
  });

  final ReminderEntity reminder;
  final ReminderOccurrence occurrence;
  final String? historyId;
}

class FakeReminderNotificationGateway implements ReminderNotificationGateway {
  final List<ScheduledReminder> scheduled = [];
  final List<int> cancelled = [];
  final List<ReminderNotificationAction> pendingActions = [];

  @override
  Future<void> Function(String action, Map<String, dynamic> payload)? onAction;

  @override
  Future<ReminderPermissionState> permissionState() async =>
      const ReminderPermissionState(
        notificationsEnabled: true,
        exactAlarmEnabled: true,
      );

  @override
  Future<ReminderPermissionState> requestPermissions() => permissionState();

  @override
  Future<List<ReminderNotificationAction>> consumePendingActions() async {
    final result = List<ReminderNotificationAction>.of(pendingActions);
    pendingActions.clear();
    return result;
  }

  @override
  Future<void> schedule({
    required ReminderEntity reminder,
    required ReminderOccurrence occurrence,
    String? historyId,
  }) async {
    scheduled.add(
      ScheduledReminder(
        reminder: reminder,
        occurrence: occurrence,
        historyId: historyId,
      ),
    );
  }

  @override
  Future<void> cancel(int notificationId) async {
    cancelled.add(notificationId);
  }

  @override
  Future<void> cancelAll() async {
    cancelled.add(-1);
  }
}
