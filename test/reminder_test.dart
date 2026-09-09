import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_autonomy_repository.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_autonomy_trigger_service.dart';
import 'package:ffm_manager/features/reminder/data/repositories/reminder_repository.dart';
import 'package:ffm_manager/features/reminder/data/services/reminder_notification_service.dart';
import 'package:ffm_manager/features/reminder/data/services/reminder_schedule_replenisher.dart';
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

    test('upcomingOccurrences mengisi horizon harian dengan ID unik', () {
      final item = reminder(
        recurrence: ReminderRecurrenceType.daily,
        scheduledAt: DateTime(2026, 9, 10, 8),
      );

      final occurrences = calculator.upcomingOccurrences(
        item,
        now: DateTime(2026, 9, 10, 7),
      );

      expect(occurrences, hasLength(14));
      expect(occurrences.first.scheduledAt, DateTime(2026, 9, 10, 8));
      expect(occurrences.last.scheduledAt, DateTime(2026, 9, 23, 8));
      expect(
        occurrences.map((item) => item.notificationId).toSet(),
        hasLength(occurrences.length),
      );
    });

    test('upcomingOccurrences tidak melewati tanggal mulai masa depan', () {
      final item = reminder(
        recurrence: ReminderRecurrenceType.weekly,
        scheduledAt: DateTime(2026, 10, 2, 8),
        weekdays: const [1, 5],
      );

      final occurrences = calculator.upcomingOccurrences(
        item,
        now: DateTime(2026, 9, 10, 7),
      );

      expect(occurrences, hasLength(1));
      expect(occurrences.single.scheduledAt, DateTime(2026, 10, 2, 8));
    });
  });

  group('Reminder replication shared helpers', () {
    test('nextDailyOccurrenceAt memilih hari ini bila belum lewat', () {
      final next = nextDailyOccurrenceAt(
        DateTime(2026, 9, 9, 8, 30),
        DateTime(2026, 9, 9, 7, 0),
      );
      expect(next, DateTime(2026, 9, 9, 8, 30));
    });

    test('nextDailyOccurrenceAt maju ke besok bila waktu sudah lewat', () {
      final next = nextDailyOccurrenceAt(
        DateTime(2026, 9, 9, 8, 30),
        DateTime(2026, 9, 9, 9, 0),
      );
      expect(next, DateTime(2026, 9, 10, 8, 30));
    });

    test('nextWeeklyOccurrenceAt memilih hari konfigurasi berikutnya', () {
      final next = nextWeeklyOccurrenceAt(
        DateTime(2026, 9, 9, 8, 30),
        DateTime(2026, 9, 16, 10, 0),
        const [2, 5], // Selasa & Jumat
      );
      // 16 Sep 2026 adalah Rabu -> Jumat terdekat adalah 18 Sep.
      expect(next, DateTime(2026, 9, 18, 8, 30));
    });

    test('stableSnoozeNotificationId konsisten lintas jalur', () {
      final canonical = stableSnoozeNotificationId('rem-1', '20260909-0830');
      final expected = stableReminderNotificationId(
        'rem-1',
        'snooze:20260909-0830',
      );
      expect(canonical, expected);
      // ID unik per occurrence, bukan hanya per reminder.
      final other = stableSnoozeNotificationId('rem-1', '20260910-0830');
      expect(other, isNot(canonical));
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
      final rowsBeforeTrigger = await repository.getHistoryViews(householdId);
      await repository.markHistoryTriggered(
        householdId: householdId,
        historyId: first.id,
        triggeredAt: occurrence.scheduledAt,
      );
      final rowsAfterTrigger = await repository.getHistoryViews(householdId);

      expect(second.id, first.id);
      expect(rowsBeforeTrigger, isEmpty);
      expect(rowsAfterTrigger, hasLength(1));
      expect(rowsAfterTrigger.single.history.occurrenceKey, occurrence.key);
    });
  });

  group('ReminderScheduleReplenisher', () {
    late AppDatabase database;
    late ReminderRepository repository;
    late FakeReminderNotificationGateway gateway;

    setUp(() {
      database = createInMemoryDatabaseForTests();
      repository = ReminderRepository(database);
      gateway = FakeReminderNotificationGateway();
    });

    tearDown(() => database.close());

    test(
      'replenishment berulang tetap memakai occurrence dan history yang sama',
      () async {
        final item = reminder(
          recurrence: ReminderRecurrenceType.daily,
          scheduledAt: DateTime(2026, 9, 10, 8),
        );
        await repository.saveReminder(item);
        final replenisher = ReminderScheduleReplenisher(
          repository,
          gateway,
          calculator,
        );

        final firstCount = await replenisher.replenish(
          householdId: householdId,
          now: DateTime(2026, 9, 10, 7),
        );
        final first = List<ScheduledReminder>.of(gateway.scheduled);
        final secondCount = await replenisher.replenish(
          householdId: householdId,
          now: DateTime(2026, 9, 10, 7),
        );
        final second = gateway.scheduled.skip(first.length).toList();

        expect(firstCount, 14);
        expect(secondCount, firstCount);
        expect(
          second.map((item) => item.occurrence.notificationId),
          first.map((item) => item.occurrence.notificationId),
        );
        expect(
          second.map((item) => item.historyId),
          first.map((item) => item.historyId),
        );
      },
    );
  });

  group('ReminderBloc scheduling', () {
    late AppDatabase database;
    late ReminderRepository repository;
    late FakeReminderNotificationGateway gateway;
    late FfmAssistantAutonomyRepository autonomyRepository;
    late FfmAssistantAutonomyTriggerService autonomyTrigger;
    late ReminderBloc bloc;

    setUp(() {
      database = createInMemoryDatabaseForTests();
      repository = ReminderRepository(database);
      gateway = FakeReminderNotificationGateway();
      autonomyRepository = FfmAssistantAutonomyRepository(database);
      autonomyTrigger = FfmAssistantAutonomyTriggerService(autonomyRepository);
      bloc = ReminderBloc(
        repository: repository,
        notificationService: gateway,
        occurrenceCalculator: calculator,
        householdId: householdId,
        autonomyTrigger: autonomyTrigger,
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

      expect(gateway.scheduled.length, greaterThan(1));
      expect(gateway.scheduled.first.reminder.id, item.id);
      expect(
        await repository.getHistoryByOccurrence(
          householdId: householdId,
          reminderId: item.id,
          occurrenceKey: gateway.scheduled.first.occurrence.key,
        ),
        isNotNull,
      );
    });

    test(
      'notification tap memindahkan occurrence sekali ke history pending',
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

        final stateFuture = bloc.stream.firstWhere(
          (state) => state.history.any(
            (view) =>
                view.history.id == history.id &&
                view.history.status == ReminderHistoryStatus.pending,
          ),
        );
        bloc.add(
          ReminderNotificationActionReceived(
            actionId: 'open',
            payload: {
              'householdId': householdId,
              'reminderId': item.id,
              'historyId': history.id,
              'occurrenceKey': occurrence.key,
            },
          ),
        );
        final state = await stateFuture;

        expect(state.reminders, isEmpty);
        expect(state.history, hasLength(1));
        expect(state.history.single.history.triggeredAt, isNotNull);
        expect(
          state.history.single.history.status,
          ReminderHistoryStatus.pending,
        );
        final events = await autonomyRepository.pendingEvents();
        expect(events, hasLength(1));
        expect(events.single.type, 'reminder.due');
      },
    );

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

    test(
      'snooze dari aksi notifikasi memakai ID canonical dan meneruskan series',
      () async {
        final item = reminder(
          recurrence: ReminderRecurrenceType.daily,
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

        bloc.add(
          ReminderNotificationActionReceived(
            actionId: 'snooze_10',
            payload: {
              'householdId': householdId,
              'reminderId': item.id,
              'historyId': history.id,
              'occurrenceKey': occurrence.key,
            },
          ),
        );
        await bloc.stream.firstWhere(
          (state) => state.history.any(
            (view) =>
                view.history.id == history.id &&
                view.history.status == ReminderHistoryStatus.snoozed,
          ),
        );

        // Alarm snooze memakai ID canonical (bukan id acak).
        final snooze = gateway.scheduled.firstWhere(
          (s) =>
              s.occurrence.notificationId ==
              stableSnoozeNotificationId(item.id, occurrence.key),
        );
        expect(
          snooze.occurrence.notificationId,
          stableSnoozeNotificationId(item.id, occurrence.key),
        );
        // Series harian tetap meneruskan occurrence berikutnya.
        final next = gateway.scheduled.firstWhere(
          (s) => s.occurrence.key != snooze.occurrence.key,
          orElse: () => throw StateError(
            'occurrence harian berikutnya belum dijadwalkan',
          ),
        );
        expect(
          next.occurrence.scheduledAt.difference(DateTime.now()),
          lessThan(const Duration(hours: 26)),
        );
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
