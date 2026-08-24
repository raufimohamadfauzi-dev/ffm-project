import '../../../../core/database/app_database.dart';
import '../../../transaction/domain/usecases/transaction_crud_usecases.dart';
import '../entities/goal_entity.dart';
import 'goal_crud_usecases.dart';

/// Menjaga currentAmount target berdasarkan transaksi yang tertaut ke target.
///
/// Transaksi lama dengan source `goal_contribution` tetap dihitung sebagai
/// setoran. Source `goal_usage` dihitung sebagai pemakaian dana target.
class SyncGoalBalance {
  const SyncGoalBalance(this.database);

  final AppDatabase database;

  Future<void> call({
    required String householdId,
    required TransactionEntity? previous,
    required String? nextGoalId,
    required int nextAmount,
    required String? nextSource,
  }) async {
    final oldGoalId = previous?.goalId;
    final oldDelta = _goalDelta(previous);
    final newDelta = _nextDelta(
      goalId: nextGoalId,
      amount: nextAmount,
      source: nextSource,
    );

    if (oldGoalId == nextGoalId) {
      await _applyGoalDelta(householdId, oldGoalId, newDelta - oldDelta);
      return;
    }
    await _applyGoalDelta(householdId, oldGoalId, -oldDelta);
    await _applyGoalDelta(householdId, nextGoalId, newDelta);
  }

  int _goalDelta(TransactionEntity? transaction) {
    if (transaction == null ||
        transaction.goalId == null ||
        transaction.amount >= 0) {
      return 0;
    }
    final amount = transaction.amount.abs();
    return transaction.source == 'goal_usage' ? -amount : amount;
  }

  int _nextDelta({
    required String? goalId,
    required int amount,
    required String? source,
  }) {
    if (goalId == null || amount >= 0) return 0;
    final absoluteAmount = amount.abs();
    return source == 'goal_usage' ? -absoluteAmount : absoluteAmount;
  }

  Future<void> _applyGoalDelta(
    String householdId,
    String? goalId,
    int delta,
  ) async {
    if (goalId == null || delta == 0) return;
    final goal = await GetGoal(database)(householdId, goalId);
    if (goal == null) return;
    await SaveGoal(database)(
      GoalEntity(
        id: goal.id,
        householdId: goal.householdId,
        name: goal.name,
        targetAmount: goal.targetAmount,
        currentAmount: (goal.currentAmount + delta).clamp(0, 1 << 62).toInt(),
        targetDate: goal.targetDate,
        categoryId: goal.categoryId,
        isActive: goal.isActive,
        createdAt: goal.createdAt,
      ),
    );
  }
}
