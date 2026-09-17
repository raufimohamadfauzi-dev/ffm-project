import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_capability_adapters.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_reminder_mutation_service.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_plan.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_planner.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_capability_executor.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_draft_validator.dart';
import 'package:ffm_manager/features/reminder/data/repositories/reminder_repository.dart';
import 'package:ffm_manager/features/reminder/data/services/reminder_notification_service.dart';
import 'package:ffm_manager/features/reminder/domain/entities/reminder_entity.dart';
import 'package:ffm_manager/features/reminder/domain/usecases/reminder_usecases.dart';

class _FakeReminderGateway implements ReminderNotificationGateway {
  @override
  Future<void> Function(String action, Map<String, dynamic> payload)? onAction;

  @override
  Future<void> cancel(int notificationId) async {}

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
  late FfmAssistantCapabilityAdapterRegistry adapterRegistry;
  late FfmAssistantActionPlanController planController;
  late FfmAssistantCapabilityExecutor capabilityExecutor;
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

    // Seed Data Utama: Account & Category
    await db.into(db.accounts).insert(
      AccountsCompanion.insert(
        id: 'acc-bca',
        householdId: AppContext.householdId,
        name: 'BCA',
        type: 'bank',
        createdAt: fixedClock,
      ),
    );
    await db.into(db.categories).insert(
      CategoriesCompanion.insert(
        id: 'cat-makanan',
        householdId: AppContext.householdId,
        name: 'Makanan',
        type: 'expense',
        createdAt: fixedClock,
      ),
    );
    // Seed existing tag
    await db.into(db.tags).insert(
      TagsCompanion.insert(
        id: 'tag-makan',
        householdId: AppContext.householdId,
        name: 'makan',
        createdAt: fixedClock,
      ),
    );

    adapterRegistry = FfmAssistantCapabilityAdapterRegistry(
      database: db,
      householdId: AppContext.householdId,
      clock: () => fixedClock,
      reminderMutations: mutationService,
    );
    planController = FfmAssistantActionPlanController();
    capabilityExecutor = FfmAssistantCapabilityExecutor(
      controller: planController,
      handlers: adapterRegistry.handlers,
      readTransaction: <T>(action) => db.transaction(action),
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('Direct in-place expense draft execution saves transaction & auto-registers new tag', () async {
    final draft = FfmAssistantDraft(
      kind: FfmAssistantDraftKind.expense,
      amount: 45000,
      categoryName: 'Makanan',
      fromAccountName: 'BCA',
      note: 'Makan siang dan ngopi',
      tags: 'makan, ngopi',
      newTags: 'ngopi', // Tag baru yang belum ada di Data Utama
      date: fixedClock,
      createdAt: fixedClock,
    );

    final intent = FfmAssistantIntent(
      rawText: 'catat makan 45000',
      normalizedText: 'catat makan 45000',
      type: FfmAssistantIntentType.createExpense,
      destination: FfmAssistantDestination.transactions,
      draft: draft,
    );

    final plan = const FfmAssistantActionPlanner().planFor(intent);
    expect(plan, isNotNull);
    expect(plan!.hasMutation, isTrue);

    final registered = planController.register(plan);
    planController.markAwaitingConfirmation(registered.id);
    final confirmed = planController.confirm(registered.id);
    expect(confirmed, isNotNull);

    final executedPlan = await capabilityExecutor.execute(confirmed!.id);
    expect(executedPlan, isNotNull);
    expect(executedPlan!.status, FfmAssistantActionPlanStatus.completed);

    // Verifikasi transaksi tersimpan di database
    final txRows = await db.select(db.transactions).get();
    expect(txRows.length, 1);
    expect(txRows.first.amount, -45000);
    expect(txRows.first.note, 'Makan siang dan ngopi');
    expect(txRows.first.accountId, 'acc-bca');
    expect(txRows.first.categoryId, 'cat-makanan');

    // Verifikasi bahwa tag baru 'ngopi' otomatis didaftarkan ke tabel tags Data Utama
    final tagRows = await db.select(db.tags).get();
    final tagNames = tagRows.map((t) => t.name).toList();
    expect(tagNames, contains('makan'));
    expect(tagNames, contains('ngopi'));

    // Verifikasi relasi transactionTags
    final txTags = await db.select(db.transactionTags).get();
    expect(txTags.length, 2);
  });

  test('Direct in-place income draft execution saves transaction', () async {
    final draft = FfmAssistantDraft(
      kind: FfmAssistantDraftKind.income,
      amount: 5000000,
      categoryName: 'Gaji',
      toAccountName: 'BCA',
      note: 'Gaji bulanan',
      date: fixedClock,
      createdAt: fixedClock,
    );

    final intent = FfmAssistantIntent(
      rawText: 'catat pemasukan 5000000',
      normalizedText: 'catat pemasukan 5000000',
      type: FfmAssistantIntentType.createIncome,
      destination: FfmAssistantDestination.transactions,
      draft: draft,
    );

    final plan = const FfmAssistantActionPlanner().planFor(intent);
    expect(plan, isNotNull);

    final registered = planController.register(plan!);
    planController.markAwaitingConfirmation(registered.id);
    final confirmed = planController.confirm(registered.id);
    final executedPlan = await capabilityExecutor.execute(confirmed!.id);

    expect(executedPlan!.status, FfmAssistantActionPlanStatus.completed);

    final txRows = await db.select(db.transactions).get();
    expect(txRows.length, 1);
    expect(txRows.first.amount, 5000000);
    expect(txRows.first.accountId, 'acc-bca');
  });

  test('Direct in-place reminder draft execution saves reminder with alarm mode', () async {
    final draft = FfmAssistantDraft(
      kind: FfmAssistantDraftKind.reminder,
      title: 'Bayar Wifi Indihome',
      note: 'Jangan sampai telat',
      date: fixedClock.add(const Duration(days: 3)),
      reminderMode: ReminderMode.alarm,
      createdAt: fixedClock,
    );

    final intent = FfmAssistantIntent(
      rawText: 'ingatkan bayar wifi 3 hari lagi',
      normalizedText: 'ingatkan bayar wifi 3 hari lagi',
      type: FfmAssistantIntentType.createReminder,
      destination: FfmAssistantDestination.reminders,
      draft: draft,
    );

    final plan = const FfmAssistantActionPlanner().planFor(intent);
    expect(plan, isNotNull);

    final registered = planController.register(plan!);
    planController.markAwaitingConfirmation(registered.id);
    final confirmed = planController.confirm(registered.id);
    final executedPlan = await capabilityExecutor.execute(confirmed!.id);

    expect(executedPlan!.status, FfmAssistantActionPlanStatus.completed);

    final reminders = await (db.select(db.reminders)).get();
    expect(reminders.length, 1);
    expect(reminders.first.title, 'Bayar Wifi Indihome');
    expect(reminders.first.mode, 'alarm');
  });

  test('Direct in-place activity draft execution saves activity session', () async {
    await db.into(db.categories).insert(
      CategoriesCompanion.insert(
        id: 'cat-olahraga',
        householdId: AppContext.householdId,
        name: 'Olahraga',
        type: 'activity',
        createdAt: fixedClock,
      ),
    );

    final draft = FfmAssistantDraft(
      kind: FfmAssistantDraftKind.activity,
      title: 'Lari Pagi',
      categoryName: 'Olahraga',
      note: 'Keliling komplek',
      date: fixedClock,
      createdAt: fixedClock,
      formValues: const {
        'entity': 'activity_session',
        'activityMode': 'timeTracking',
      },
    );

    final intent = FfmAssistantIntent(
      rawText: 'catat aktivitas lari pagi',
      normalizedText: 'catat aktivitas lari pagi',
      type: FfmAssistantIntentType.createActivity,
      destination: FfmAssistantDestination.activity,
      draft: draft,
    );

    final plan = const FfmAssistantActionPlanner().planFor(intent);
    expect(plan, isNotNull);

    final registered = planController.register(plan!);
    planController.markAwaitingConfirmation(registered.id);
    final confirmed = planController.confirm(registered.id);
    final executedPlan = await capabilityExecutor.execute(confirmed!.id);

    expect(executedPlan!.status, FfmAssistantActionPlanStatus.completed);

    final sessions = await (db.select(db.activitySessions)).get();
    expect(sessions.length, 1);
    expect(sessions.first.title, 'Lari Pagi');
  });

  test('Direct in-place daily note draft execution saves daily note to database', () async {
    final draft = FfmAssistantDraft(
      kind: FfmAssistantDraftKind.dailyNote,
      note: 'Hari ini produktif dan menyenangkan',
      date: fixedClock,
      createdAt: fixedClock,
    );

    final intent = FfmAssistantIntent(
      rawText: 'catat jurnal hari ini produktif',
      normalizedText: 'catat jurnal hari ini produktif',
      type: FfmAssistantIntentType.createDailyNote,
      destination: FfmAssistantDestination.activityLog,
      draft: draft,
    );

    final plan = const FfmAssistantActionPlanner().planFor(intent);
    expect(plan, isNotNull);

    final registered = planController.register(plan!);
    planController.markAwaitingConfirmation(registered.id);
    final confirmed = planController.confirm(registered.id);
    final executedPlan = await capabilityExecutor.execute(confirmed!.id);

    expect(executedPlan!.status, FfmAssistantActionPlanStatus.completed);

    final notes = await (db.select(db.dailyNotes)).get();
    expect(notes.length, 1);
    expect(notes.first.body, 'Hari ini produktif dan menyenangkan');
  });

  test('Direct in-place goal draft execution saves goal to database', () async {
    final draft = FfmAssistantDraft(
      kind: FfmAssistantDraftKind.goal,
      title: 'Beli Laptop Baru',
      amount: 15000000,
      createdAt: fixedClock,
    );

    final intent = FfmAssistantIntent(
      rawText: 'buat target beli laptop 15jt',
      normalizedText: 'buat target beli laptop 15jt',
      type: FfmAssistantIntentType.createGoal,
      destination: FfmAssistantDestination.goals,
      draft: draft,
    );

    final plan = const FfmAssistantActionPlanner().planFor(intent);
    expect(plan, isNotNull);

    final registered = planController.register(plan!);
    planController.markAwaitingConfirmation(registered.id);
    final confirmed = planController.confirm(registered.id);
    final executedPlan = await capabilityExecutor.execute(confirmed!.id);

    expect(executedPlan!.status, FfmAssistantActionPlanStatus.completed);

    final goals = await (db.select(db.goals)).get();
    expect(goals.length, 1);
    expect(goals.first.name, 'Beli Laptop Baru');
    expect(goals.first.targetAmount, 15000000);
  });

  test('Incomplete draft is caught by validator and cannot be confirmed until complete', () {
    // Expense draft missing required amount
    final incompleteDraft = FfmAssistantDraft(
      kind: FfmAssistantDraftKind.expense,
      title: 'Makan',
      fromAccountName: 'BCA',
      createdAt: fixedClock,
    );

    // Validator check
    final issues = FfmAssistantDraftValidator.validate(incompleteDraft);
    expect(
      issues.any(
        (i) =>
            i.field == 'nominal' &&
            i.severity == FfmAssistantDraftIssueSeverity.required,
      ),
      isTrue,
    );

    final review = FfmAssistantDraftReview(
      draft: incompleteDraft,
      version: 1,
      issues: issues,
    );
    expect(review.canContinue, isFalse);
  });
}
