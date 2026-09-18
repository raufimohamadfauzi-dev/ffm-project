import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_reminder_mutation_service.dart';
import 'package:ffm_manager/features/reminder/data/repositories/reminder_repository.dart';
import 'package:ffm_manager/features/reminder/data/services/reminder_notification_service.dart';
import 'package:ffm_manager/features/reminder/domain/entities/reminder_entity.dart';
import 'package:ffm_manager/features/reminder/domain/usecases/reminder_usecases.dart';

void main() {
  const householdId = 'local-household';
  final now = DateTime(2026, 8, 25, 9);
  late AppDatabase database;
  late ReminderRepository repository;
  late _Gateway gateway;
  late FfmAssistantReminderMutationService service;
  late ReminderEntity previous;

  setUp(() async {
    database = createInMemoryDatabaseForTests();
    repository = ReminderRepository(database);
    gateway = _Gateway();
    service = FfmAssistantReminderMutationService(
      repository: repository,
      notificationGateway: gateway,
      occurrenceCalculator: const ReminderOccurrenceCalculator(),
      clock: () => now,
    );
    previous = ReminderEntity(
      id: 'internet',
      householdId: householdId,
      title: 'Bayar internet',
      note: 'paket rumah',
      scheduledAt: DateTime(2026, 8, 30, 8),
      recurrenceType: ReminderRecurrenceType.weekly,
      weekdays: const [1, 5],
      soundUri: 'content://ringtone/custom',
      soundName: 'Nada keluarga',
      defaultSnoozeMinutes: 15,
      notificationId: 331,
      createdAt: now,
    );
    await repository.saveReminder(previous);
  });

  tearDown(() => database.close());

  test('update judul dan waktu mempertahankan recurrence, suara, snooze, serta notificationId', () async {
    final next = await service.updateTitleAndScheduledAt(
      previous: previous,
      title: 'Bayar internet rumah',
      note: 'bayar sebelum malam',
      scheduledAt: DateTime(2026, 8, 30, 10),
    );

    expect(next.title, 'Bayar internet rumah');
    expect(next.scheduledAt, DateTime(2026, 8, 30, 10));
    expect(next.recurrenceType, previous.recurrenceType);
    expect(next.weekdays, previous.weekdays);
    expect(next.soundUri, previous.soundUri);
    expect(next.soundName, previous.soundName);
    expect(next.defaultSnoozeMinutes, previous.defaultSnoozeMinutes);
    expect(next.notificationId, previous.notificationId);
    expect(gateway.cancelled, contains(previous.notificationId));
    expect(gateway.scheduled.length, greaterThan(1));
    expect(
      gateway.scheduled.every((item) => item.reminder.id == previous.id),
      isTrue,
    );

    final stored = await repository.getReminder(householdId, previous.id);
    expect(stored?.title, next.title);
    expect(stored?.scheduledAt, next.scheduledAt);
    expect(stored?.notificationId, previous.notificationId);
  });

  test('edit reminder menyimpan nada dering baru dan menjadwalkan ulang dengan nada tersebut', () async {
    final next = await service.updateTitleAndScheduledAt(
      previous: previous,
      title: previous.title,
      scheduledAt: previous.scheduledAt.add(const Duration(hours: 1)),
      soundUri: 'content://ringtone/new',
      soundName: 'Nada baru',
    );

    expect(next.soundUri, 'content://ringtone/new');
    expect(next.soundName, 'Nada baru');

    final stored = await repository.getReminder(householdId, previous.id);
    expect(stored?.soundUri, 'content://ringtone/new');
    expect(stored?.soundName, 'Nada baru');
    expect(gateway.scheduled.last.reminder.soundUri, 'content://ringtone/new');
    expect(gateway.scheduled.last.reminder.soundName, 'Nada baru');
  });

  test(
    'izin gagal tidak membatalkan alarm atau menulis perubahan Pengingat',
    () async {
      gateway.permission = const ReminderPermissionState(
        notificationsEnabled: false,
        exactAlarmEnabled: false,
      );

      await expectLater(
        service.updateTitleAndScheduledAt(
          previous: previous,
          title: 'Bayar internet rumah',
          scheduledAt: DateTime(2026, 8, 30, 10),
        ),
        throwsStateError,
      );

      final stored = await repository.getReminder(householdId, previous.id);
      expect(stored?.title, previous.title);
      expect(stored?.scheduledAt, previous.scheduledAt);
      expect(gateway.cancelled, isEmpty);
      expect(gateway.scheduled, isEmpty);
    },
  );

  test(
    'write di-rollback bila scheduling gagal setelah database write',
    () async {
      gateway.failScheduling = true;
      final created = ReminderEntity(
        id: 'rollback-reminder',
        householdId: householdId,
        title: 'Tes rollback',
        note: 'catatan',
        scheduledAt: DateTime(2026, 8, 30, 8),
        recurrenceType: ReminderRecurrenceType.weekly,
        weekdays: const [1, 3],
        soundUri: 'content://ringtone/custom',
        soundName: 'Nada keluarga',
        sourceType: ReminderSourceType.budgetSetup,
        sourceId: 'budget-1',
        notificationId: 999,
        createdAt: now,
      );

      await expectLater(service.save(created), throwsStateError);
      expect(await repository.getReminder(householdId, created.id), isNull);
    },
  );
}

class _Gateway implements ReminderNotificationGateway {
  ReminderPermissionState permission = const ReminderPermissionState(
    notificationsEnabled: true,
    exactAlarmEnabled: true,
  );
  final cancelled = <int>[];
  final scheduled =
      <({ReminderEntity reminder, ReminderOccurrence occurrence})>[];
  bool failScheduling = false;

  @override
  Future<void> Function(String action, Map<String, dynamic> payload)? onAction;

  @override
  Future<void> cancel(int notificationId) async {
    cancelled.add(notificationId);
  }

  @override
  Future<void> cancelAll() async {}

  @override
  Future<List<ReminderNotificationAction>> consumePendingActions() async =>
      const [];

  @override
  Future<ReminderPermissionState> permissionState() async => permission;

  @override
  Future<ReminderPermissionState> requestPermissions() async => permission;

  @override
  Future<void> schedule({
    required ReminderEntity reminder,
    required ReminderOccurrence occurrence,
    String? historyId,
  }) async {
    if (failScheduling) throw StateError('schedule failed');
    scheduled.add((reminder: reminder, occurrence: occurrence));
  }
}
