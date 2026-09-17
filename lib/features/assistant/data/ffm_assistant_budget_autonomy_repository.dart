import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';

/// Durable storage for explicit, per-budget autonomous allocation delegation.
class FfmAssistantBudgetAutonomyRepository {
  FfmAssistantBudgetAutonomyRepository(this._database);

  final AppDatabase _database;

  Future<BudgetAutonomyDelegation?> delegationForBudget({
    required String householdId,
    required String budgetId,
  }) =>
      (_database.select(_database.budgetAutonomyDelegations)..where(
            (row) =>
                row.householdId.equals(householdId) &
                row.budgetId.equals(budgetId),
          ))
          .getSingleOrNull();

  Future<List<BudgetAutonomyDelegation>> activeDelegations({
    required String householdId,
  }) =>
      (_database.select(_database.budgetAutonomyDelegations)..where(
            (row) =>
                row.householdId.equals(householdId) &
                row.status.equals('active'),
          ))
          .get();

  Future<void> saveDelegation({
    required String id,
    required String householdId,
    required String budgetId,
    required String status,
    required int maxAdjustmentAmount,
    required int maxAllocatedAmount,
    required int maxExecutions,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) async {
    if (maxAdjustmentAmount <= 0 ||
        maxAllocatedAmount <= 0 ||
        maxExecutions <= 0) {
      throw ArgumentError('Batas delegasi harus lebih dari nol.');
    }
    await _database
        .into(_database.budgetAutonomyDelegations)
        .insertOnConflictUpdate(
          BudgetAutonomyDelegationsCompanion.insert(
            id: id,
            householdId: householdId,
            budgetId: budgetId,
            status: Value(status),
            maxAdjustmentAmount: maxAdjustmentAmount,
            maxAllocatedAmount: maxAllocatedAmount,
            maxExecutions: maxExecutions,
            createdAt: createdAt,
            updatedAt: updatedAt,
          ),
        );
  }

  Future<bool> setStatus({
    required String householdId,
    required String budgetId,
    required String status,
    required DateTime updatedAt,
  }) async {
    final changed =
        await (_database.update(_database.budgetAutonomyDelegations)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.budgetId.equals(budgetId),
            ))
            .write(
              BudgetAutonomyDelegationsCompanion(
                status: Value(status),
                updatedAt: Value(updatedAt),
              ),
            );
    return changed == 1;
  }

  Future<BudgetAutonomyExecutionLedger?> ledgerByIdempotencyKey({
    required String householdId,
    required String idempotencyKey,
  }) =>
      (_database.select(_database.budgetAutonomyExecutionLedgers)..where(
            (row) =>
                row.householdId.equals(householdId) &
                row.idempotencyKey.equals(idempotencyKey),
          ))
          .getSingleOrNull();

  Future<BudgetAutonomyExecutionLedger?> ledgerById(String id) =>
      (_database.select(
        _database.budgetAutonomyExecutionLedgers,
      )..where((row) => row.id.equals(id))).getSingleOrNull();

  Future<int> executionCount(String delegationId) async {
    final count = _database.budgetAutonomyExecutionLedgers.id.count();
    final row =
        await (_database.selectOnly(_database.budgetAutonomyExecutionLedgers)
              ..addColumns([count])
              ..where(
                _database.budgetAutonomyExecutionLedgers.delegationId.equals(
                      delegationId,
                    ) &
                    _database.budgetAutonomyExecutionLedgers.operation.equals(
                      'adjustment',
                    ),
              ))
            .getSingle();
    return row.read(count) ?? 0;
  }

  Future<void> appendLedger({
    required String id,
    required String householdId,
    required String delegationId,
    required String budgetId,
    required String idempotencyKey,
    required String operation,
    required int previousAllocated,
    required int appliedAllocated,
    required int previousRevision,
    required int appliedRevision,
    required int delta,
    required DateTime executedAt,
    String? reversesLedgerId,
  }) => _database
      .into(_database.budgetAutonomyExecutionLedgers)
      .insert(
        BudgetAutonomyExecutionLedgersCompanion.insert(
          id: id,
          householdId: householdId,
          delegationId: delegationId,
          budgetId: budgetId,
          idempotencyKey: idempotencyKey,
          operation: operation,
          reversesLedgerId: Value(reversesLedgerId),
          previousAllocated: previousAllocated,
          appliedAllocated: appliedAllocated,
          previousRevision: previousRevision,
          appliedRevision: appliedRevision,
          delta: delta,
          executedAt: executedAt,
        ),
      );
}
