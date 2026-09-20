import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_capability_adapters.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_financial_snapshot_service.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_query_tools.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_reminder_mutation_service.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_plan.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_planner.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_capability_executor.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/reminder/data/repositories/reminder_repository.dart';
import 'package:ffm_manager/features/reminder/data/services/reminder_notification_service.dart';
import 'package:ffm_manager/features/reminder/domain/entities/reminder_entity.dart';
import 'package:ffm_manager/features/reminder/domain/usecases/reminder_usecases.dart';

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

void main() {
  late AppDatabase db;
  late _FakeReminderGateway gateway;
  late ReminderRepository reminderRepo;
  late ReminderOccurrenceCalculator calculator;
  late FfmAssistantReminderMutationService mutationService;
  late FfmAssistantInterpreter interpreter;
  final fixedClock = DateTime(2026, 9, 17, 10, 0);

  setUp(() async {
    db = createInMemoryDatabaseForTests();
    gateway = _FakeReminderGateway();
    reminderRepo = ReminderRepository(db);
    calculator = const ReminderOccurrenceCalculator();
    mutationService = FfmAssistantReminderMutationService(
      repository: reminderRepo,
      notificationGateway: gateway,
      occurrenceCalculator: calculator,
      clock: () => fixedClock,
    );
    interpreter = FfmAssistantInterpreter(db, clock: () => fixedClock);

    // Seed test accounts and categories
    await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            id: 'acc-bca',
            householdId: AppContext.householdId,
            name: 'BCA',
            type: 'bank',
            createdAt: fixedClock,
          ),
        );
    await db
        .into(db.categories)
        .insert(
          CategoriesCompanion.insert(
            id: 'cat-util',
            householdId: AppContext.householdId,
            name: 'Tagihan & Utilitas',
            type: 'expense',
            createdAt: fixedClock,
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  group('Pilar 1 (Poin 3): Query & Ringkasan Pengingat via Assistant Query Tool & Digest', () {
    test(
      'UpcomingRemindersQueryTool filters reminders by timeframe correctly',
      () async {
        await reminderRepo.saveReminder(
          ReminderEntity(
            id: 'rem-today',
            householdId: AppContext.householdId,
            title: 'Bayar Listrik PLN Hari Ini',
            scheduledAt: DateTime(2026, 9, 17, 14, 0),
            recurrenceType: ReminderRecurrenceType.once,
            weekdays: const [],
            notificationId: 101,
            isActive: true,
            createdAt: fixedClock,
            updatedAt: fixedClock,
          ),
        );
        await reminderRepo.saveReminder(
          ReminderEntity(
            id: 'rem-tomorrow',
            householdId: AppContext.householdId,
            title: 'Beli Token Air Besok',
            scheduledAt: DateTime(2026, 9, 18, 9, 0),
            recurrenceType: ReminderRecurrenceType.once,
            weekdays: const [],
            notificationId: 102,
            isActive: true,
            createdAt: fixedClock,
            updatedAt: fixedClock,
          ),
        );

        final snapshotService = FfmAssistantFinancialSnapshotService(db);
        final digest = await snapshotService.buildRemindersDigest(
          householdId: AppContext.householdId,
        );

        expect(digest, contains('Bayar Listrik PLN Hari Ini'));
        expect(digest, contains('Beli Token Air Besok'));

        final queryRegistry = FfmAssistantQueryRegistry(
          db,
          clock: () => fixedClock,
        );
        final todayAnswer = await queryRegistry.tryAnswer(
          'ada pengingat apa hari ini',
          householdId: AppContext.householdId,
        );

        expect(todayAnswer, isNotNull);
        expect(todayAnswer!.message, contains('Bayar Listrik PLN Hari Ini'));
        expect(todayAnswer.message.contains('Beli Token Air Besok'), isFalse);
      },
    );
  });

  group('Pilar 2 (Poin 4): Selesaikan Pengingat Lewat Bahasa Santai', () {
    test('Interprets and executes reminder completion flow', () async {
      await reminderRepo.saveReminder(
        ReminderEntity(
          id: 'rem-wifi',
          householdId: AppContext.householdId,
          title: 'Bayar WiFi Indihome',
          scheduledAt: DateTime(2026, 9, 20, 10, 0),
          recurrenceType: ReminderRecurrenceType.once,
          weekdays: const [],
          notificationId: 103,
          isActive: true,
          createdAt: fixedClock,
          updatedAt: fixedClock,
        ),
      );

      final intent = await interpreter.interpret(
        'selesaikan pengingat wifi indihome',
      );
      expect(intent.type, FfmAssistantIntentType.completeReminder);
      expect(intent.draft, isNotNull);
      expect(intent.draft!.kind, FfmAssistantDraftKind.reminderComplete);
      expect(intent.draft!.formValues['targetId'], 'rem-wifi');
      expect(intent.draft!.formValues['operation'], 'complete');

      final planner = FfmAssistantActionPlanner(now: () => fixedClock);
      final plan = planner.planFor(intent);
      expect(plan, isNotNull);
      expect(
        plan!.steps.any((s) => s.capabilityId == 'mutate.complete'),
        isTrue,
      );

      final adapters = FfmAssistantCapabilityAdapterRegistry(
        database: db,
        householdId: AppContext.householdId,
        reminderMutations: mutationService,
        clock: () => fixedClock,
      );

      final controller = FfmAssistantActionPlanController(now: () => fixedClock)
        ..register(plan)
        ..markAwaitingConfirmation(plan.id)
        ..confirm(plan.id);

      final executedPlan = await FfmAssistantCapabilityExecutor(
        controller: controller,
        handlers: adapters.handlers,
      ).execute(plan.id);

      expect(executedPlan?.status, FfmAssistantActionPlanStatus.completed);
      final updatedReminder = await reminderRepo.getReminder(
        AppContext.householdId,
        'rem-wifi',
      );
      expect(updatedReminder!.isActive, isFalse);
    });
  });

  group('Pilar 3 (Poin 5): Pengingat Ambang Batas Finansial', () {
    test('Interprets condition-based budget monitoring trigger', () async {
      final intent = await interpreter.interpret(
        'ingatkan kalau budget jajan < 50rb',
      );
      expect(intent.type, FfmAssistantIntentType.createMonitoringJob);
      expect(intent.draft, isNotNull);
      expect(intent.draft!.kind, FfmAssistantDraftKind.monitoringJob);
      expect(intent.draft!.formValues['preset'], 'budgetMonitor');
      expect(intent.draft!.formValues['categoryFilter'], 'jajan');
    });
  });

  group('Pilar 4 (Poin 2): Smart Auto-Dismiss Pengingat saat Transaksi Dicatat Lebih Awal', () {
    test(
      'Automatically resolves matching active reminder when expense is logged',
      () async {
        await reminderRepo.saveReminder(
          ReminderEntity(
            id: 'rem-pdam',
            householdId: AppContext.householdId,
            title: 'Bayar Tagihan PDAM Air',
            scheduledAt: DateTime(2026, 9, 22, 10, 0),
            recurrenceType: ReminderRecurrenceType.once,
            weekdays: const [],
            notificationId: 104,
            isActive: true,
            createdAt: fixedClock,
            updatedAt: fixedClock,
          ),
        );

        final adapters = FfmAssistantCapabilityAdapterRegistry(
          database: db,
          householdId: AppContext.householdId,
          reminderMutations: mutationService,
          clock: () => fixedClock,
        );

        final saveDraftHandler = adapters.handlers['mutate.save_draft'];
        expect(saveDraftHandler, isNotNull);

        final saveResult = await saveDraftHandler!(
          FfmAssistantActionStep(
            id: 'save-tx-1',
            capabilityId: 'mutate.save_draft',
            parameters: {
              'kind': 'expense',
              '_idempotencyKey': 'test-idem-tx-pdam',
              'amount': 75000,
              'fromAccount': 'BCA',
              'category': 'Tagihan & Utilitas',
              'note': 'Bayar PDAM bulan September',
              'date': fixedClock.toIso8601String(),
            },
          ),
        );

        expect(saveResult.isSuccess, isTrue);
        expect(
          saveResult.message,
          contains(
            'Pengingat “Bayar Tagihan PDAM Air” otomatis ditandai selesai.',
          ),
        );

        final updatedReminder = await reminderRepo.getReminder(
          AppContext.householdId,
          'rem-pdam',
        );
        expect(updatedReminder!.isActive, isFalse);
      },
    );
  });
}
