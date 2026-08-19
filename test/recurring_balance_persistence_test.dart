import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/database/database_seed.dart';
import 'package:ffm_manager/features/recurring_transaction/domain/usecases/recurring_transaction_crud_usecases.dart';

void main() {
  test(
    'pemasukan berkala membuat occurrence sekali dan memperbarui saldo',
    () async {
      final database = createInMemoryDatabaseForTests();
      addTearDown(database.close);
      await DatabaseSeed.ensure(database);

      final start = DateTime(2026, 8, 18);
      await database
          .into(database.accounts)
          .insert(
            AccountsCompanion.insert(
              id: 'account-seabank',
              householdId: AppContext.householdId,
              name: 'SeaBank',
              type: 'bank',
              createdAt: start,
            ),
          );

      final ruleId = await CreateRecurringTransaction(database)(
        householdId: AppContext.householdId,
        name: 'Bunga SeaBank',
        type: 'income',
        amount: 3500,
        startDate: start,
        periodType: 'daily',
        accountId: 'account-seabank',
        note: 'Bunga harian dari mutasi bank',
      );

      final processor = ProcessRecurringTransactions(database);
      final firstRun = await processor(
        AppContext.householdId,
        now: DateTime(2026, 8, 20, 12),
      );
      final secondRun = await processor(
        AppContext.householdId,
        now: DateTime(2026, 8, 20, 18),
      );

      expect(firstRun, 3);
      expect(secondRun, 0);

      final transactions = await (database.select(
        database.transactions,
      )..where((row) => row.recurringTransactionId.equals(ruleId))).get();
      final occurrences = await (database.select(
        database.recurringTransactionRuns,
      )..where((row) => row.recurringTransactionId.equals(ruleId))).get();

      expect(transactions, hasLength(3));
      expect(occurrences, hasLength(3));
      expect(transactions.every((row) => row.amount == 3500), isTrue);
      expect(transactions.every((row) => row.source == 'recurring'), isTrue);
      expect(transactions.map((row) => row.date.day).toList(), [18, 19, 20]);

      final balance = await GetAccountBookBalance(database)(
        AppContext.householdId,
        'account-seabank',
        asOf: DateTime(2026, 8, 20, 23),
      );
      expect(balance, 10500);
    },
  );

  test(
    'rekonsiliasi saldo disimpan sebagai transaksi nyata dan ikut dihitung',
    () async {
      final database = createInMemoryDatabaseForTests();
      addTearDown(database.close);
      await DatabaseSeed.ensure(database);

      final now = DateTime(2026, 8, 20, 10);
      await database
          .into(database.accounts)
          .insert(
            AccountsCompanion.insert(
              id: 'account-cash',
              householdId: AppContext.householdId,
              name: 'Tunai',
              type: 'cash',
              openingBalance: const Value(100000),
              createdAt: now,
            ),
          );

      await database
          .into(database.transactions)
          .insert(
            TransactionsCompanion.insert(
              id: 'adjustment-plus',
              householdId: AppContext.householdId,
              type: 'income',
              amount: 25000,
              accountId: const Value('account-cash'),
              date: now,
              recordedAt: now,
              source: const Value('balance_adjustment'),
              note: const Value('Penyesuaian saldo nyata'),
              owner: const Value('Keluarga'),
              createdAt: now,
            ),
          );

      final adjustment = await (database.select(
        database.transactions,
      )..where((row) => row.source.equals('balance_adjustment'))).getSingle();
      final balance = await GetAccountBookBalance(database)(
        AppContext.householdId,
        'account-cash',
        asOf: now.add(const Duration(minutes: 1)),
      );

      expect(adjustment.amount, 25000);
      expect(adjustment.accountId, 'account-cash');
      expect(balance, 125000);
    },
  );
}
