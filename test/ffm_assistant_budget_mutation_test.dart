import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/database/audit_logger.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_capability_adapters.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_plan.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_planner.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_capability_executor.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/budget/data/budget_repository.dart';

void main() {
  final now = DateTime(2026, 8, 25, 9);
  late AppDatabase database;
  late BudgetRepository budgets;
  late FfmAssistantInterpreter interpreter;

  setUp(() async {
    database = createInMemoryDatabaseForTests();
    budgets = BudgetRepository(
      database,
      AuditLogger(database),
      clock: () => now,
    );
    interpreter = FfmAssistantInterpreter(database, clock: () => now);
    await database
        .into(database.categories)
        .insert(
          CategoriesCompanion.insert(
            id: 'category-food',
            householdId: AppContext.householdId,
            name: 'Makan',
            type: 'expense',
            createdAt: now,
          ),
        );
    await database
        .into(database.envelopeBudgets)
        .insert(
          EnvelopeBudgetsCompanion.insert(
            id: 'budget-food',
            householdId: AppContext.householdId,
            categoryId: const Value('category-food'),
            categoryIdsJson: const Value('["category-food"]'),
            name: 'Makan',
            month: const Value('2026-08'),
            allocated: const Value(1000000),
            periodType: const Value('monthly'),
            startDate: DateTime(2026, 8, 1),
            endDate: DateTime(2026, 8, 31),
            rollover: const Value(100000),
            createdAt: now,
            updatedAt: Value(now),
          ),
        );
  });

  tearDown(() => database.close());

  Future<void> addBudget({
    String id = 'budget-food',
    String name = 'Makan',
    String categoryId = 'category-food',
    String categoryIdsJson = '["category-food"]',
    int allocated = 1000000,
    String periodType = 'monthly',
  }) => database
      .into(database.envelopeBudgets)
      .insert(
        EnvelopeBudgetsCompanion.insert(
          id: id,
          householdId: AppContext.householdId,
          categoryId: Value(categoryId),
          categoryIdsJson: Value(categoryIdsJson),
          name: name,
          month: const Value('2026-08'),
          allocated: Value(allocated),
          periodType: Value(periodType),
          startDate: DateTime(2026, 8, 1),
          endDate: DateTime(2026, 8, 31),
          rollover: const Value(100000),
          createdAt: now,
          updatedAt: Value(now),
        ),
      );

  Future<FfmAssistantActionPlan?> execute(FfmAssistantActionPlan plan) async {
    final controller = FfmAssistantActionPlanController(now: () => now)
      ..register(plan)
      ..markAwaitingConfirmation(plan.id)
      ..confirm(plan.id);
    return FfmAssistantCapabilityExecutor(
      controller: controller,
      handlers: FfmAssistantCapabilityAdapterRegistry(
        database: database,
        householdId: AppContext.householdId,
        clock: () => now,
      ).handlers,
    ).execute(plan.id);
  }

  Future<EnvelopeBudget> budget(String id) async =>
      (await budgets.get(AppContext.householdId, id))!;

  Future<void> addExpense({
    String id = 'expense-food',
    String categoryId = 'category-food',
    int amount = -300000,
    bool archived = false,
  }) => database
      .into(database.transactions)
      .insert(
        TransactionsCompanion.insert(
          id: id,
          householdId: AppContext.householdId,
          type: 'expense',
          amount: amount,
          date: now,
          recordedAt: now,
          categoryId: Value(categoryId),
          isArchived: Value(archived),
          createdAt: now,
        ),
      );

  Future<void> addTransfer({
    required String id,
    required String from,
    required String to,
  }) => database
      .into(database.envelopeTransfers)
      .insert(
        EnvelopeTransfersCompanion.insert(
          id: id,
          householdId: AppContext.householdId,
          fromEnvelopeId: from,
          toEnvelopeId: to,
          amount: 100000,
          createdAt: now,
        ),
      );

  test('draft Anggaran hanya membuat preview dan plan allowlisted', () async {
    final before = await budget('budget-food');
    final intent = await interpreter.interpret(
      'ubah batas anggaran makan jadi 800 ribu',
    );

    expect(intent.type, FfmAssistantIntentType.updateBudget);
    expect(intent.draft?.kind, FfmAssistantDraftKind.budgetUpdate);
    expect((await budget('budget-food')).allocated, before.allocated);
    final plan = FfmAssistantActionPlanner(now: () => now).planFor(intent)!;
    expect(
      plan.steps.map((step) => step.capabilityId),
      containsAll(<String>[
        'draft.budget_update',
        'mutate.update',
        'verify.budget_mutation',
      ]),
    );
  });

  test('update batas menjaga field terlindungi dan menghitung sisa', () async {
    await addExpense();
    final before = await budget('budget-food');
    final intent = await interpreter.interpret(
      'ubah batas anggaran makan jadi 800 ribu',
    );
    expect(
      (await execute(
        FfmAssistantActionPlanner(now: () => now).planFor(intent)!,
      ))?.status,
      FfmAssistantActionPlanStatus.completed,
    );
    final after = await budget('budget-food');
    final snapshot = await budgets.snapshot(
      householdId: AppContext.householdId,
      id: after.id,
    );
    expect(after.allocated, 800000);
    expect(after.id, before.id);
    expect(after.name, before.name);
    expect(after.categoryId, before.categoryId);
    expect(after.categoryIdsJson, before.categoryIdsJson);
    expect(after.periodType, before.periodType);
    expect(after.startDate, before.startDate);
    expect(after.endDate, before.endDate);
    expect(after.rollover, before.rollover);
    expect(after.alertPercent, before.alertPercent);
    expect(after.isActive, isTrue);
    expect(snapshot?.remaining, 600000);
  });

  test('update batas ditolak bila sisa pascaubah menjadi negatif', () async {
    await addExpense(amount: -950000);
    final intent = await interpreter.interpret(
      'ubah batas anggaran makan jadi 800 ribu',
    );
    final plan = FfmAssistantActionPlanner(now: () => now).planFor(intent)!;
    expect((await execute(plan))?.status, FfmAssistantActionPlanStatus.failed);
    expect((await budget('budget-food')).allocated, 1000000);
  });

  test(
    'target Anggaran ambigu atau terlalu pendek tidak memilih pos',
    () async {
      await addBudget(id: 'budget-food-extra', name: 'Makan Rumah');
      final ambiguous = await interpreter.interpret('arsipkan anggaran makan');
      final short = await interpreter.interpret('arsipkan anggaran ma');
      expect(ambiguous.clarification, isNotNull);
      expect(short.clarification, isNotNull);
      expect((await budget('budget-food')).isActive, isTrue);
    },
  );

  test(
    'arsip Anggaran ditolak untuk transfer dan transaksi historis',
    () async {
      await addTransfer(id: 'transfer-out', from: 'budget-food', to: 'other');
      expect(
        await budgets.archiveBlockReason(
          householdId: AppContext.householdId,
          id: 'budget-food',
        ),
        contains('transfer'),
      );
      var intent = await interpreter.interpret('arsipkan anggaran makan');
      expect(
        (await execute(
          FfmAssistantActionPlanner(now: () => now).planFor(intent)!,
        ))?.status,
        FfmAssistantActionPlanStatus.failed,
      );

      await database.delete(database.envelopeTransfers).go();
      await addExpense(archived: true);
      intent = await interpreter.interpret('arsipkan anggaran makan');
      expect(
        (await execute(
          FfmAssistantActionPlanner(now: () => now).planFor(intent)!,
        ))?.status,
        FfmAssistantActionPlanStatus.failed,
      );
      expect((await budget('budget-food')).isActive, isTrue);
    },
  );

  test('arsip Anggaran tanpa jejak bersifat lunak, diaudit, dan tanpa catatan baru', () async {
    final transactionsBefore = await database
        .select(database.transactions)
        .get();
    final transfersBefore = await database
        .select(database.envelopeTransfers)
        .get();
    final intent = await interpreter.interpret('arsipkan anggaran makan');
    expect(
      (await execute(
        FfmAssistantActionPlanner(now: () => now).planFor(intent)!,
      ))?.status,
      FfmAssistantActionPlanStatus.completed,
    );
    final archived = await budget('budget-food');
    expect(archived.isActive, isFalse);
    expect(archived.allocated, 1000000);
    expect(archived.rollover, 100000);
    expect(
      (await database.select(database.transactions).get()).length,
      transactionsBefore.length,
    );
    expect(
      (await database.select(database.envelopeTransfers).get()).length,
      transfersBefore.length,
    );
    final audits = await database
        .customSelect(
          'SELECT action FROM audit_logs WHERE entity = ?',
          variables: [Variable<String>('budget')],
        )
        .get();
    expect(
      audits.map((row) => row.read<String>('action')),
      contains('archive'),
    );
  });
}
