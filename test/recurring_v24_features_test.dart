import 'package:drift/drift.dart' hide Column, isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/database/database_seed.dart';
import 'package:ffm_manager/features/recurring_transaction/domain/usecases/recurring_transaction_crud_usecases.dart';

void main() {
  test('seed menyediakan kategori biaya admin untuk Data Utama', () async {
    final database = createInMemoryDatabaseForTests();
    addTearDown(database.close);
    await DatabaseSeed.ensure(database);

    final category =
        await (database.select(database.categories)..where(
              (row) =>
                  row.householdId.equals(AppContext.householdId) &
                  row.name.equals('Biaya admin') &
                  row.type.equals('expense') &
                  row.isActive.equals(true),
            ))
            .getSingleOrNull();

    expect(category, isNotNull);
  });

  test('jadwal dua mingguan membuat occurrence setiap 14 hari', () async {
    final database = createInMemoryDatabaseForTests();
    addTearDown(database.close);
    await DatabaseSeed.ensure(database);
    final start = DateTime(2026, 8, 1);
    await database
        .into(database.accounts)
        .insert(
          AccountsCompanion.insert(
            id: 'account-biweekly',
            householdId: AppContext.householdId,
            name: 'Rekening dua mingguan',
            type: 'bank',
            openingBalance: const Value(100000),
            createdAt: start,
          ),
        );

    final ruleId = await CreateRecurringTransaction(database)(
      householdId: AppContext.householdId,
      name: 'Setoran dua mingguan',
      type: 'expense',
      amount: 10000,
      startDate: start,
      periodType: 'biweekly',
      accountId: 'account-biweekly',
    );

    final created = await ProcessRecurringTransactions(database)(
      AppContext.householdId,
      now: DateTime(2026, 8, 15, 23),
    );
    final transactions =
        await (database.select(database.transactions)
              ..where((row) => row.recurringTransactionId.equals(ruleId))
              ..orderBy([(row) => OrderingTerm.asc(row.date)]))
            .get();

    expect(created, 2);
    expect(transactions.map((row) => row.date.day), [1, 15]);
    expect(transactions.map((row) => row.amount), [-10000, -10000]);
  });

  test('mode persentase menghitung bunga dari saldo buku', () async {
    final database = createInMemoryDatabaseForTests();
    addTearDown(database.close);
    await DatabaseSeed.ensure(database);
    final start = DateTime(2026, 8, 18);
    await database
        .into(database.accounts)
        .insert(
          AccountsCompanion.insert(
            id: 'account-percent',
            householdId: AppContext.householdId,
            name: 'SeaBank Persen',
            type: 'bank',
            openingBalance: const Value(100000),
            createdAt: start,
          ),
        );

    final ruleId = await CreateRecurringTransaction(database)(
      householdId: AppContext.householdId,
      name: 'Bunga 1,5 persen',
      type: 'income',
      amount: 0,
      ratePercent: 1.5,
      calcMode: 'percent',
      startDate: start,
      periodType: 'daily',
      accountId: 'account-percent',
    );
    final created = await ProcessRecurringTransactions(database)(
      AppContext.householdId,
      now: DateTime(2026, 8, 18, 23),
    );

    final transaction = await (database.select(
      database.transactions,
    )..where((row) => row.recurringTransactionId.equals(ruleId))).getSingle();
    expect(created, 1);
    expect(transaction.amount, 1500);
    expect(transaction.type, 'income');
    expect(transaction.source, 'recurring');
  });

  test(
    'mode persentase melewati jadwal bila saldo buku nol atau minus',
    () async {
      final database = createInMemoryDatabaseForTests();
      addTearDown(database.close);
      await DatabaseSeed.ensure(database);
      final start = DateTime(2026, 8, 18);
      await database
          .into(database.accounts)
          .insert(
            AccountsCompanion.insert(
              id: 'account-empty',
              householdId: AppContext.householdId,
              name: 'Rekening kosong',
              type: 'bank',
              createdAt: start,
            ),
          );
      final ruleId = await CreateRecurringTransaction(database)(
        householdId: AppContext.householdId,
        name: 'Bunga rekening kosong',
        type: 'income',
        amount: 0,
        ratePercent: 2,
        calcMode: 'percent',
        startDate: start,
        periodType: 'daily',
        accountId: 'account-empty',
      );

      final created = await ProcessRecurringTransactions(database)(
        AppContext.householdId,
        now: DateTime(2026, 8, 18, 23),
      );
      final transactions = await (database.select(
        database.transactions,
      )..where((row) => row.recurringTransactionId.equals(ruleId))).get();
      final runs = await (database.select(
        database.recurringTransactionRuns,
      )..where((row) => row.recurringTransactionId.equals(ruleId))).get();
      expect(created, 0);
      expect(transactions, isEmpty);
      expect(runs, hasLength(1));
    },
  );

  test('biaya admin berkala menjadi pengeluaran terpisah dari bunga', () async {
    final database = createInMemoryDatabaseForTests();
    addTearDown(database.close);
    await DatabaseSeed.ensure(database);
    final start = DateTime(2026, 8, 18);
    await database
        .into(database.accounts)
        .insert(
          AccountsCompanion.insert(
            id: 'account-fee',
            householdId: AppContext.householdId,
            name: 'Bank biaya',
            type: 'bank',
            openingBalance: const Value(100000),
            createdAt: start,
          ),
        );
    final feeId = await CreateRecurringTransaction(database)(
      householdId: AppContext.householdId,
      name: 'Admin bulanan',
      type: 'expense',
      amount: 25000,
      startDate: start,
      periodType: 'monthly',
      accountId: 'account-fee',
    );
    final interestId = await CreateRecurringTransaction(database)(
      householdId: AppContext.householdId,
      name: 'Bunga bulanan',
      type: 'income',
      amount: 5000,
      startDate: start,
      periodType: 'monthly',
      accountId: 'account-fee',
    );

    final created = await ProcessRecurringTransactions(database)(
      AppContext.householdId,
      now: DateTime(2026, 8, 18, 23),
    );
    final fee = await (database.select(
      database.transactions,
    )..where((row) => row.recurringTransactionId.equals(feeId))).getSingle();
    final interest =
        await (database.select(database.transactions)
              ..where((row) => row.recurringTransactionId.equals(interestId)))
            .getSingle();
    expect(created, 2);
    expect(fee.type, 'expense');
    expect(fee.amount, -25000);
    expect(interest.type, 'income');
    expect(interest.amount, 5000);
    expect(fee.id, isNot(interest.id));
  });

  test('warning muncul bila biaya berkala melebihi saldo buku', () async {
    final database = createInMemoryDatabaseForTests();
    addTearDown(database.close);
    await DatabaseSeed.ensure(database);
    final start = DateTime(2020, 1, 1);
    await database
        .into(database.accounts)
        .insert(
          AccountsCompanion.insert(
            id: 'account-warning',
            householdId: AppContext.householdId,
            name: 'Saldo tipis',
            type: 'bank',
            openingBalance: const Value(10000),
            createdAt: start,
          ),
        );
    await CreateRecurringTransaction(database)(
      householdId: AppContext.householdId,
      name: 'Admin lebih besar dari saldo',
      type: 'expense',
      amount: 15000,
      startDate: start,
      periodType: 'monthly',
      accountId: 'account-warning',
    );

    final warnings = await GetRecurringBalanceWarnings(database)(
      AppContext.householdId,
    );
    expect(warnings, hasLength(1));
    expect(warnings.single.bookBalance, 10000);
    expect(warnings.single.estimatedAmount, 15000);
    expect(warnings.single.willSkip, isFalse);
  });

  test(
    'log rekonsiliasi menyimpan selisih dan transaksi penyesuaian',
    () async {
      final database = createInMemoryDatabaseForTests();
      addTearDown(database.close);
      await DatabaseSeed.ensure(database);
      final checkedAt = DateTime(2026, 8, 19, 10, 11, 12);
      await database
          .into(database.accounts)
          .insert(
            AccountsCompanion.insert(
              id: 'account-reconcile',
              householdId: AppContext.householdId,
              name: 'Tunai',
              type: 'cash',
              openingBalance: const Value(100000),
              createdAt: checkedAt,
            ),
          );

      final log = await CreateReconciliationLog(database)(
        householdId: AppContext.householdId,
        accountId: 'account-reconcile',
        actualBalance: 125000,
        checkedAt: checkedAt,
        note: 'Cek kas sore',
      );
      expect(log.bookBalance, 100000);
      expect(log.actualBalance, 125000);
      expect(log.difference, 25000);
      expect(log.adjustmentTransactionId, isNotNull);

      final adjustment = await (database.select(
        database.transactions,
      )..where((row) => row.source.equals('balance_adjustment'))).getSingle();
      expect(adjustment.amount, 25000);
      expect(adjustment.accountId, 'account-reconcile');
      expect(
        await GetAccountBookBalance(database)(
          AppContext.householdId,
          'account-reconcile',
          asOf: checkedAt.add(const Duration(seconds: 1)),
        ),
        125000,
      );

      final sameBalanceLog = await CreateReconciliationLog(database)(
        householdId: AppContext.householdId,
        accountId: 'account-reconcile',
        actualBalance: 125000,
        checkedAt: checkedAt.add(const Duration(hours: 1)),
      );
      expect(sameBalanceLog.difference, 0);
      expect(sameBalanceLog.adjustmentTransactionId, isNull);
      expect(
        await GetReconciliationHistory(database)(
          householdId: AppContext.householdId,
          accountId: 'account-reconcile',
        ),
        hasLength(2),
      );
    },
  );
}
