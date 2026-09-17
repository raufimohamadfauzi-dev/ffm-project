import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/database/audit_logger.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_budget_autonomy_repository.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_budget_autonomy_service.dart';
import 'package:ffm_manager/features/budget/data/budget_repository.dart';

void main() {
  const householdId = 'household-a';
  final now = DateTime(2026, 9, 17, 9);
  late AppDatabase database;
  late FfmAssistantBudgetAutonomyRepository autonomyRepository;
  late FfmAssistantBudgetAutonomyService service;

  setUp(() async {
    database = createInMemoryDatabaseForTests();
    final budgets = BudgetRepository(
      database,
      AuditLogger(database),
      clock: () => now,
    );
    autonomyRepository = FfmAssistantBudgetAutonomyRepository(database);
    service = FfmAssistantBudgetAutonomyService(
      database,
      budgets,
      autonomyRepository,
      clock: () => now,
    );
    await database
        .into(database.categories)
        .insert(
          CategoriesCompanion.insert(
            id: 'food',
            householdId: householdId,
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
            householdId: householdId,
            categoryId: const Value('food'),
            categoryIdsJson: const Value('["food"]'),
            name: 'Makan',
            allocated: const Value(100000),
            periodType: const Value('monthly'),
            startDate: DateTime(2026, 9, 1),
            endDate: DateTime(2026, 9, 30),
            createdAt: now,
          ),
        );
  });

  tearDown(() => database.close());

  Future<void> delegate({
    FfmAssistantBudgetDelegationStatus status =
        FfmAssistantBudgetDelegationStatus.active,
    int maxExecutions = 2,
  }) => service.saveDelegation(
    FfmAssistantBudgetDelegation(
      id: 'delegation-food',
      householdId: householdId,
      budgetId: 'budget-food',
      status: status,
      maxAdjustmentAmount: 30000,
      maxAllocatedAmount: 150000,
      maxExecutions: maxExecutions,
      createdAt: now,
      updatedAt: now,
    ),
  );

  test(
    'active delegation adjusts allocated once and persists immutable ledger',
    () async {
      await delegate();

      final applied = await service.adjustAllocated(
        householdId: householdId,
        budgetId: 'budget-food',
        allocated: 120000,
        idempotencyKey: 'increase-food-1',
      );
      final duplicate = await service.adjustAllocated(
        householdId: householdId,
        budgetId: 'budget-food',
        allocated: 120000,
        idempotencyKey: 'increase-food-1',
      );
      final budget = await (database.select(
        database.envelopeBudgets,
      )..where((row) => row.id.equals('budget-food'))).getSingle();
      final ledger = await database
          .select(database.budgetAutonomyExecutionLedgers)
          .get();

      expect(applied.idempotent, isFalse);
      expect(duplicate.idempotent, isTrue);
      expect(budget.allocated, 120000);
      expect(budget.revision, 1);
      expect(ledger, hasLength(1));
      expect(ledger.single.previousAllocated, 100000);
      expect(ledger.single.appliedRevision, 1);
      await expectLater(
        database.customUpdate(
          'DELETE FROM budget_autonomy_execution_ledgers WHERE id = ?',
          variables: [Variable.withString(ledger.single.id)],
        ),
        throwsA(isA<Exception>()),
      );
    },
  );

  test('paused delegation and strict limits reject writes', () async {
    await delegate(status: FfmAssistantBudgetDelegationStatus.paused);
    await expectLater(
      service.adjustAllocated(
        householdId: householdId,
        budgetId: 'budget-food',
        allocated: 120000,
        idempotencyKey: 'paused',
      ),
      throwsStateError,
    );
    await service.setDelegationStatus(
      householdId: householdId,
      budgetId: 'budget-food',
      status: FfmAssistantBudgetDelegationStatus.active,
    );
    await expectLater(
      service.adjustAllocated(
        householdId: householdId,
        budgetId: 'budget-food',
        allocated: 140000,
        idempotencyKey: 'too-large',
      ),
      throwsStateError,
    );
  });

  test(
    'undo is compare-and-swap safe and appends a separate ledger row',
    () async {
      await delegate();
      final applied = await service.adjustAllocated(
        householdId: householdId,
        budgetId: 'budget-food',
        allocated: 120000,
        idempotencyKey: 'increase-food-1',
      );
      final undone = await service.undo(
        householdId: householdId,
        ledgerId: applied.ledger.id,
        idempotencyKey: 'undo-food-1',
      );

      expect(undone.ledger.operation, 'undo');
      expect(undone.ledger.reversesLedgerId, applied.ledger.id);
      expect(
        (await (database.select(
          database.envelopeBudgets,
        )..where((row) => row.id.equals('budget-food'))).getSingle()).allocated,
        100000,
      );

      await expectLater(
        service.undo(
          householdId: householdId,
          ledgerId: applied.ledger.id,
          idempotencyKey: 'undo-food-stale',
        ),
        throwsStateError,
      );
      expect(
        await database.select(database.budgetAutonomyExecutionLedgers).get(),
        hasLength(2),
      );
    },
  );
}
