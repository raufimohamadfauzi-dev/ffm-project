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
    expect(gateway.scheduled.single.reminder.id, previous.id);

    final stored = await repository.getReminder(householdId, previous.id);
    expect(stored?.title, next.title);
    expect(stored?.scheduledAt, next.scheduledAt);
    expect(stored?.notificationId, previous.notificationId);
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
}

class _Gateway implements ReminderNotificationGateway {
  ReminderPermissionState permission = const ReminderPermissionState(
    notificationsEnabled: true,
    exactAlarmEnabled: true,
  );
  final cancelled = <int>[];
  final scheduled =
      <({ReminderEntity reminder, ReminderOccurrence occurrence})>[];

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
    scheduled.add((reminder: reminder, occurrence: occurrence));
  }
}
