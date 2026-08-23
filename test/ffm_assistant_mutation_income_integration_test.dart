import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_capability_adapters.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_plan.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_planner.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_capability_executor.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';

void main() {
  late AppDatabase database;
  final now = DateTime(2026, 8, 23, 10);

  setUp(() async {
    database = createInMemoryDatabaseForTests();
    await database.batch((batch) {
      batch.insert(
        database.accounts,
        AccountsCompanion.insert(
          id: 'cash-1',
          householdId: 'local-household',
          name: 'Kas Utama',
          type: 'cash',
          createdAt: now,
        ),
      );
      batch.insert(
        database.accounts,
        AccountsCompanion.insert(
          id: 'cash-2',
          householdId: 'local-household',
          name: 'Dompet',
          type: 'cash',
          createdAt: now,
        ),
      );
    });
  });

  tearDown(() async {
    await database.close();
  });

  FfmAssistantCapabilityExecutor executorFor(FfmAssistantActionPlan plan) {
    final controller = FfmAssistantActionPlanController(now: () => now);
    controller.register(plan);
    controller.markAwaitingConfirmation(plan.id);
    controller.confirm(plan.id);
    final adapters = FfmAssistantCapabilityAdapterRegistry(
      database: database,
      householdId: 'local-household',
      clock: () => now,
    );
    return FfmAssistantCapabilityExecutor(
      controller: controller,
      handlers: adapters.handlers,
    );
  }

  test(
    'income melewati preview, confirmation, execute sekali, dan verify',
    () async {
      final intent = FfmAssistantIntent(
        rawText: 'catat gaji 1000000 ke Kas Utama',
        normalizedText: 'catat gaji 1000000 ke kas utama',
        type: FfmAssistantIntentType.createIncome,
        destination: FfmAssistantDestination.transactions,
        draft: FfmAssistantDraft(
          kind: FfmAssistantDraftKind.income,
          amount: 1000000,
          toAccountName: 'Kas Utama',
          categoryName: 'Gaji',
          date: now,
          createdAt: now,
        ),
      );
      final plan = FfmAssistantActionPlanner(now: () => now).planFor(intent)!;
      final completed = await executorFor(plan).execute(plan.id);

      expect(completed?.status, FfmAssistantActionPlanStatus.completed);
      expect(
        completed?.steps.where(
          (step) => step.status == FfmAssistantActionStepStatus.completed,
        ),
        hasLength(3),
      );
      final rows = await (database.select(
        database.transactions,
      )..where((row) => row.householdId.equals('local-household'))).get();
      expect(rows, hasLength(1));
      expect(rows.single.amount, 1000000);
      expect(rows.single.accountId, 'cash-1');
    },
  );

  test('expense menggunakan rekening sumber dan tidak diduplikasi', () async {
    final intent = FfmAssistantIntent(
      rawText: 'catat makan 50000 dari Kas Utama',
      normalizedText: 'catat makan 50000 dari kas utama',
      type: FfmAssistantIntentType.createExpense,
      destination: FfmAssistantDestination.transactions,
      draft: FfmAssistantDraft(
        kind: FfmAssistantDraftKind.expense,
        amount: 50000,
        fromAccountName: 'Kas Utama',
        date: now,
        createdAt: now,
      ),
    );
    final plan = FfmAssistantActionPlanner(now: () => now).planFor(intent)!;
    final executor = executorFor(plan);
    final result = await executor.execute(plan.id);

    expect(result?.status, FfmAssistantActionPlanStatus.completed);
    final rows = await (database.select(
      database.transactions,
    )..where((row) => row.householdId.equals('local-household'))).get();
    expect(rows, hasLength(1));
    expect(rows.single.amount, -50000);
    expect(rows.single.accountId, 'cash-1');
    expect(await executor.execute(plan.id), result);
  });

  test('transfer memvalidasi rekening berbeda dan diverifikasi', () async {
    final intent = FfmAssistantIntent(
      rawText: 'transfer 75000 dari Kas Utama ke Dompet',
      normalizedText: 'transfer 75000 dari kas utama ke dompet',
      type: FfmAssistantIntentType.createTransfer,
      destination: FfmAssistantDestination.transactions,
      draft: FfmAssistantDraft(
        kind: FfmAssistantDraftKind.transfer,
        amount: 75000,
        fromAccountName: 'Kas Utama',
        toAccountName: 'Dompet',
        date: now,
        createdAt: now,
      ),
    );
    final plan = FfmAssistantActionPlanner(now: () => now).planFor(intent)!;
    final result = await executorFor(plan).execute(plan.id);

    expect(result?.status, FfmAssistantActionPlanStatus.completed);
    final transfers = await (database.select(
      database.transfers,
    )..where((row) => row.householdId.equals('local-household'))).get();
    expect(transfers, hasLength(1));
    expect(transfers.single.amount, 75000);
    expect(transfers.single.fromAccountId, 'cash-1');
    expect(transfers.single.toAccountId, 'cash-2');
  });
}
