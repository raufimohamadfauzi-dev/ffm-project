import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_capability_adapters.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_reminder_mutation_service.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_plan.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_planner.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_capability_executor.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/reminder/data/repositories/reminder_repository.dart';
import 'package:ffm_manager/features/reminder/data/services/reminder_notification_service.dart';
import 'package:ffm_manager/features/reminder/domain/entities/reminder_entity.dart';
import 'package:ffm_manager/features/reminder/domain/usecases/reminder_usecases.dart';

void main() {
  final now = DateTime(2026, 8, 24, 9);
  late AppDatabase database;
  late ReminderRepository repository;
  late FfmAssistantInterpreter interpreter;
  late _FakeReminderGateway gateway;

  setUp(() async {
    database = createInMemoryDatabaseForTests();
    repository = ReminderRepository(database);
    interpreter = FfmAssistantInterpreter(database, clock: () => now);
    gateway = _FakeReminderGateway();
    await repository.saveReminder(
      ReminderEntity(
        id: 'electricity',
        householdId: AppContext.householdId,
        title: 'Bayar listrik',
        scheduledAt: DateTime(2026, 8, 30, 8),
        recurrenceType: ReminderRecurrenceType.once,
        weekdays: const [],
        notificationId: 91,
        createdAt: now,
      ),
    );
  });

  tearDown(() async {
    await database.close();
  });

  Future<FfmAssistantActionPlan?> executeConfirmed(
    FfmAssistantActionPlan plan,
  ) async {
    final controller = FfmAssistantActionPlanController(now: () => now)
      ..register(plan)
      ..markAwaitingConfirmation(plan.id)
      ..confirm(plan.id);
    final adapters = FfmAssistantCapabilityAdapterRegistry(
      database: database,
      householdId: AppContext.householdId,
      clock: () => now,
      reminderMutations: FfmAssistantReminderMutationService(
        repository: repository,
        notificationGateway: gateway,
        occurrenceCalculator: const ReminderOccurrenceCalculator(),
        clock: () => now,
      ),
    );
    return FfmAssistantCapabilityExecutor(
      controller: controller,
      handlers: adapters.handlers,
    ).execute(plan.id);
  }

  test(
    'arsip pengingat membuat draft tanpa mengubah data sebelum konfirmasi',
    () async {
      final intent = await interpreter.interpret(
        'arsip pengingat bayar listrik',
      );

      expect(intent.type, FfmAssistantIntentType.archiveReminder);
      expect(intent.destination, FfmAssistantDestination.reminders);
      expect(intent.draft?.kind, FfmAssistantDraftKind.reminderArchive);
      expect(intent.draft?.formValues['targetId'], 'electricity');
      expect(intent.needsConfirmation, isTrue);
      expect(
        (await repository.getReminder(
          AppContext.householdId,
          'electricity',
        ))?.isActive,
        isTrue,
      );
    },
  );

  test('arsip pengingat yang ambigu tidak memilih target diam-diam', () async {
    await repository.saveReminder(
      ReminderEntity(
        id: 'electricity-home',
        householdId: AppContext.householdId,
        title: 'Bayar listrik rumah',
        scheduledAt: DateTime(2026, 8, 31, 8),
        recurrenceType: ReminderRecurrenceType.once,
        weekdays: const [],
        notificationId: 92,
        createdAt: now,
      ),
    );

    final intent = await interpreter.interpret('arsip pengingat bayar listrik');

    expect(intent.type, FfmAssistantIntentType.archiveReminder);
    expect(intent.draft, isNull);
    expect(intent.clarification, contains('menemukan 2 pengingat'));
  });

  test(
    'arsip pengingat membatalkan alarm, menonaktifkan, dan readback',
    () async {
      final intent = await interpreter.interpret(
        'arsip pengingat bayar listrik',
      );
      final plan = FfmAssistantActionPlanner(now: () => now).planFor(intent)!;

      final completed = await executeConfirmed(plan);

      expect(completed?.status, FfmAssistantActionPlanStatus.completed);
      expect(
        completed?.steps.map((step) => step.capabilityId),
        equals([
          'navigate.reminders',
          'draft.reminder_archive',
          'mutate.archive',
          'verify.reminder_mutation',
        ]),
      );
      expect(
        (await repository.getReminder(
          AppContext.householdId,
          'electricity',
        ))?.isActive,
        isFalse,
      );
      expect(gateway.cancelledNotificationIds, contains(91));
    },
  );
}

class _FakeReminderGateway implements ReminderNotificationGateway {
  final cancelledNotificationIds = <int>[];

  @override
  Future<void> Function(String action, Map<String, dynamic> payload)? onAction;

  @override
  Future<void> cancel(int notificationId) async {
    cancelledNotificationIds.add(notificationId);
  }

  @override
  Future<void> cancelAll() async {}

  @override
  Future<List<ReminderNotificationAction>> consumePendingActions() async =>
      const [];

  @override
  Future<ReminderPermissionState> permissionState() async =>
      const ReminderPermissionState(
        notificationsEnabled: true,
        exactAlarmEnabled: true,
      );

  @override
  Future<ReminderPermissionState> requestPermissions() async =>
      const ReminderPermissionState(
        notificationsEnabled: true,
        exactAlarmEnabled: true,
      );

  @override
  Future<void> schedule({
    required ReminderEntity reminder,
    required ReminderOccurrence occurrence,
    String? historyId,
  }) async {}
}
