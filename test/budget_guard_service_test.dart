import 'package:drift/drift.dart' hide Column;
import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/advisor/domain/usecases/budget_guard_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late BudgetGuardService service;

  setUp(() {
    database = createInMemoryDatabaseForTests();
    service = BudgetGuardService(database);
  });

  tearDown(() => database.close());

  test(
    'mendeteksi anggaran jebol, arus kas minus, dan hutang jatuh tempo',
    () async {
      final now = DateTime(2026, 6, 10, 9);
      await _insertExpenseCategory(database, 'cat-belanja', 'Belanja pasar');
      await database
          .into(database.envelopeBudgets)
          .insert(
            EnvelopeBudgetsCompanion.insert(
              id: 'overall-monthly-2026-06',
              householdId: AppContext.householdId,
              name: 'Total belanja Juni',
              categoryIdsJson: const Value('[]'),
              allocated: const Value(100000),
              periodType: const Value('monthly'),
              startDate: DateTime(2026, 6, 1),
              endDate: DateTime(2026, 6, 30, 23, 59, 59),
              alertPercent: const Value(80),
              createdAt: now,
            ),
          );
      await _insertTransaction(
        database,
        id: 'expense-juni',
        amount: -120000,
        date: now,
        categoryId: 'cat-belanja',
      );
      await _insertTransaction(
        database,
        id: 'income-juni',
        amount: 20000,
        date: now,
      );
      await database
          .into(database.liabilities)
          .insert(
            LiabilitiesCompanion.insert(
              id: 'hutang-jatuh-tempo',
              householdId: AppContext.householdId,
              name: 'Cicilan motor',
              originalAmount: 500000,
              remainingBalance: 300000,
              monthlyInstallment: const Value(50000),
              startDate: DateTime(2026, 1, 1),
              dueDate: Value(DateTime(2026, 6, 15)),
              createdAt: now,
            ),
          );

      final suggestions = await service.check(AppContext.householdId, at: now);

      expect(
        suggestions.map((item) => item.kind),
        contains(FinancialGuardKind.budgetExceeded),
      );
      expect(
        suggestions.map((item) => item.kind),
        contains(FinancialGuardKind.monthlyCashDeficit),
      );
      expect(
        suggestions.map((item) => item.kind),
        contains(FinancialGuardKind.liabilityDue),
      );
      expect(
        suggestions
            .firstWhere(
              (item) => item.kind == FinancialGuardKind.budgetExceeded,
            )
            .message,
        contains('Rp20.000'),
      );
      expect(
        suggestions
            .firstWhere(
              (item) => item.kind == FinancialGuardKind.monthlyCashDeficit,
            )
            .trace,
        contains('transfer antar rekening tidak dihitung'),
      );
    },
  );

  test('tidak menghitung transaksi sumber transfer sebagai arus kas', () async {
    final now = DateTime(2026, 7, 8, 12);
    await _insertTransaction(
      database,
      id: 'income-juli',
      amount: 100000,
      date: now,
    );
    await _insertTransaction(
      database,
      id: 'expense-juli',
      amount: -25000,
      date: now,
    );
    await _insertTransaction(
      database,
      id: 'pindah-rekening',
      amount: -500000,
      date: now,
      source: 'transfer',
    );

    final suggestions = await service.check(AppContext.householdId, at: now);

    expect(
      suggestions.where(
        (item) => item.kind == FinancialGuardKind.monthlyCashDeficit,
      ),
      isEmpty,
    );
  });
}

Future<void> _insertExpenseCategory(
  AppDatabase database,
  String id,
  String name,
) => database
    .into(database.categories)
    .insert(
      CategoriesCompanion.insert(
        id: id,
        householdId: AppContext.householdId,
        name: name,
        type: 'expense',
        createdAt: DateTime(2026, 1, 1),
      ),
    );

Future<void> _insertTransaction(
  AppDatabase database, {
  required String id,
  required int amount,
  required DateTime date,
  String? categoryId,
  String source = 'manual',
}) => database
    .into(database.transactions)
    .insert(
      TransactionsCompanion.insert(
        id: id,
        householdId: AppContext.householdId,
        type: amount >= 0 ? 'income' : 'expense',
        amount: amount,
        categoryId: Value(categoryId),
        source: Value(source),
        date: date,
        recordedAt: date,
        createdAt: date,
      ),
    );
