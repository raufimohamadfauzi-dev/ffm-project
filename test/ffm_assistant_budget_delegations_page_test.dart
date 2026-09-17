import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/database/audit_logger.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_budget_autonomy_repository.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_budget_autonomy_service.dart';
import 'package:ffm_manager/features/assistant/presentation/pages/ffm_assistant_budget_delegations_page.dart';
import 'package:ffm_manager/features/budget/data/budget_repository.dart';

void main() {
  const householdId = 'household-a';
  final now = DateTime(2026, 9, 17, 9);

  Future<
    (
      AppDatabase,
      FfmAssistantBudgetAutonomyRepository,
      FfmAssistantBudgetAutonomyService,
    )
  >
  createFixture() async {
    final database = createInMemoryDatabaseForTests();
    final repository = FfmAssistantBudgetAutonomyRepository(database);
    final service = FfmAssistantBudgetAutonomyService(
      database,
      BudgetRepository(database, AuditLogger(database), clock: () => now),
      repository,
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
    await service.saveDelegation(
      FfmAssistantBudgetDelegation(
        id: 'delegation-food',
        householdId: householdId,
        budgetId: 'budget-food',
        status: FfmAssistantBudgetDelegationStatus.active,
        maxAdjustmentAmount: 30000,
        maxAllocatedAmount: 150000,
        maxExecutions: 2,
        createdAt: now,
        updatedAt: now,
      ),
    );
    return (database, repository, service);
  }

  testWidgets('menampilkan delegasi aktif dan ledger eksekusi immutable', (
    tester,
  ) async {
    final (database, repository, service) = await createFixture();
    addTearDown(database.close);
    await service.adjustAllocated(
      householdId: householdId,
      budgetId: 'budget-food',
      allocated: 120000,
      idempotencyKey: 'adjust-food',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: FfmAssistantBudgetDelegationsPage(
          database: database,
          repository: repository,
          service: service,
          householdId: householdId,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Delegasi Anggaran Asisten'), findsOneWidget);
    expect(find.text('Delegasi aktif'), findsOneWidget);
    expect(find.text('Riwayat eksekusi'), findsOneWidget);
    expect(find.text('Makan'), findsNWidgets(2));
    expect(find.textContaining('append-only'), findsOneWidget);
    await tester.tap(find.text('Makan').last);
    await tester.pumpAndSettle();
    expect(find.text('Batalkan dengan aman'), findsOneWidget);
  });

  testWidgets(
    'membatalkan eksekusi setelah konfirmasi dan menambah ledger undo',
    (tester) async {
      final (database, repository, service) = await createFixture();
      addTearDown(database.close);
      await service.adjustAllocated(
        householdId: householdId,
        budgetId: 'budget-food',
        allocated: 120000,
        idempotencyKey: 'adjust-food',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: FfmAssistantBudgetDelegationsPage(
            database: database,
            repository: repository,
            service: service,
            householdId: householdId,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Makan').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Batalkan dengan aman'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Batalkan dengan aman'));
      await tester.pumpAndSettle();

      expect(find.text('Batalkan eksekusi ini?'), findsOneWidget);
      await tester.tap(find.text('Batalkan eksekusi'));
      await tester.pumpAndSettle();

      expect(
        find.text('Eksekusi dibatalkan dan dicatat sebagai riwayat baru.'),
        findsOneWidget,
      );
      expect(
        await database.select(database.budgetAutonomyExecutionLedgers).get(),
        hasLength(2),
      );
    },
  );

  testWidgets('menjeda delegasi aktif dari halaman monitor', (tester) async {
    final (database, repository, service) = await createFixture();
    addTearDown(database.close);

    await tester.pumpWidget(
      MaterialApp(
        home: FfmAssistantBudgetDelegationsPage(
          database: database,
          repository: repository,
          service: service,
          householdId: householdId,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Jeda'));
    await tester.pumpAndSettle();

    expect(
      find.text('Delegasi dijeda. Asisten tidak dapat menyesuaikan pos ini.'),
      findsOneWidget,
    );
    expect(
      await repository.activeDelegations(householdId: householdId),
      isEmpty,
    );
  });
}
