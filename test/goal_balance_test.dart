import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/goal/domain/entities/goal_entity.dart';
import 'package:ffm_manager/features/goal/domain/usecases/goal_balance_usecases.dart';
import 'package:ffm_manager/features/goal/domain/usecases/goal_crud_usecases.dart';
import 'package:ffm_manager/features/transaction/domain/usecases/transaction_crud_usecases.dart';

void main() {
  test('setor target menambah saldo target satu kali', () async {
    final database = createInMemoryDatabaseForTests();
    addTearDown(database.close);
    final now = DateTime(2026, 8, 20, 9, 0);

    await SaveGoal(database)(
      GoalEntity(
        id: 'goal-darurat',
        householdId: AppContext.householdId,
        name: 'Dana darurat',
        targetAmount: 5000000,
        currentAmount: 0,
        targetDate: DateTime(2026, 12, 31),
        categoryId: 'expense-darurat',
        createdAt: now,
      ),
    );

    final contribution = TransactionEntity(
      id: 'goal-contribution-1',
      householdId: AppContext.householdId,
      date: now,
      amount: -200000,
      owner: 'Keluarga',
      categoryId: null,
      source: 'goal_contribution',
      accountId: 'account-seabank',
      goalId: 'goal-darurat',
      recordedAt: now,
    );
    await SyncGoalBalance(database)(
      householdId: AppContext.householdId,
      previous: null,
      nextGoalId: contribution.goalId,
      nextAmount: contribution.amount,
      nextSource: contribution.source,
    );

    final goal = await GetGoal(database)(
      AppContext.householdId,
      'goal-darurat',
    );
    expect(goal!.currentAmount, 200000);
  });

  test(
    'pemakaian target mengurangi saldo dan edit tidak menggandakan delta',
    () async {
      final database = createInMemoryDatabaseForTests();
      addTearDown(database.close);
      final now = DateTime(2026, 8, 20, 9, 0);

      await SaveGoal(database)(
        GoalEntity(
          id: 'goal-darurat',
          householdId: AppContext.householdId,
          name: 'Dana darurat',
          targetAmount: 5000000,
          currentAmount: 200000,
          targetDate: DateTime(2026, 12, 31),
          createdAt: now,
        ),
      );

      final previous = TransactionEntity(
        id: 'goal-contribution-1',
        householdId: AppContext.householdId,
        date: now,
        amount: -200000,
        owner: 'Keluarga',
        categoryId: null,
        source: 'goal_contribution',
        accountId: 'account-seabank',
        goalId: 'goal-darurat',
        recordedAt: now,
      );
      final usage = TransactionEntity(
        id: previous.id,
        householdId: previous.householdId,
        date: previous.date,
        amount: -50000,
        owner: previous.owner,
        categoryId: 'expense-darurat',
        source: 'goal_usage',
        accountId: previous.accountId,
        goalId: previous.goalId,
        recordedAt: previous.recordedAt,
      );

      await SyncGoalBalance(database)(
        householdId: AppContext.householdId,
        previous: null,
        nextGoalId: usage.goalId,
        nextAmount: usage.amount,
        nextSource: usage.source,
      );

      var goal = await GetGoal(database)(
        AppContext.householdId,
        'goal-darurat',
      );
      expect(goal!.currentAmount, 150000);

      await SyncGoalBalance(database)(
        householdId: AppContext.householdId,
        previous: usage,
        nextGoalId: usage.goalId,
        nextAmount: -100000,
        nextSource: usage.source,
      );
      goal = await GetGoal(database)(AppContext.householdId, 'goal-darurat');
      expect(goal!.currentAmount, 100000);

      final editedUsage = TransactionEntity(
        id: usage.id,
        householdId: usage.householdId,
        date: usage.date,
        amount: -100000,
        owner: usage.owner,
        categoryId: usage.categoryId,
        source: usage.source,
        accountId: usage.accountId,
        goalId: usage.goalId,
        recordedAt: usage.recordedAt,
      );
      await SyncGoalBalance(database)(
        householdId: AppContext.householdId,
        previous: editedUsage,
        nextGoalId: null,
        nextAmount: 0,
        nextSource: null,
      );

      goal = await GetGoal(database)(AppContext.householdId, 'goal-darurat');
      expect(goal!.currentAmount, 200000);
    },
  );

  test('pemakaian target tidak membuat saldo target negatif', () async {
    final database = createInMemoryDatabaseForTests();
    addTearDown(database.close);
    await SaveGoal(database)(
      GoalEntity(
        id: 'goal-kecil',
        householdId: AppContext.householdId,
        name: 'Target kecil',
        targetAmount: 100000,
        currentAmount: 25000,
        targetDate: DateTime(2026, 9, 1),
      ),
    );

    await SyncGoalBalance(database)(
      householdId: AppContext.householdId,
      previous: null,
      nextGoalId: 'goal-kecil',
      nextAmount: -50000,
      nextSource: 'goal_usage',
    );

    final goal = await GetGoal(database)(AppContext.householdId, 'goal-kecil');
    expect(goal!.currentAmount, 0);
  });
}
