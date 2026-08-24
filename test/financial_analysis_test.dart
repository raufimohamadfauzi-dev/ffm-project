import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/database_factory.dart';
import 'package:ffm_manager/features/advisor/domain/usecases/financial_analysis.dart';
import 'package:ffm_manager/features/advisor/presentation/pages/summary_page.dart';
import 'package:ffm_manager/features/transaction/domain/usecases/transaction_crud_usecases.dart';

void main() {
  test(
    'forecast kosong tanpa transaksi dan sebelum tiga bulan data nyata',
    () async {
      final database = createInMemoryDatabaseForTests();
      addTearDown(database.close);
      final fromMonth = DateTime(2026, 8, 21);

      expect(
        FinancialAnalysis.forecast(const [], fromMonth: fromMonth),
        isEmpty,
      );

      final saveTransaction = SaveTransaction(database);
      for (final date in [DateTime(2026, 7, 10), DateTime(2026, 8, 10)]) {
        await saveTransaction(
          TransactionEntity(
            id: 'tx-${date.month}',
            householdId: AppContext.householdId,
            date: date,
            amount: 300000,
            owner: 'Keluarga',
            categoryId: 'income-category',
            recordedAt: date,
          ),
        );
      }

      final transactions = await GetTransactions(database)(
        AppContext.householdId,
      );
      expect(
        FinancialAnalysis.forecast(transactions, fromMonth: fromMonth),
        isEmpty,
      );
    },
  );

  test('forecast memakai rata-rata tiga bulan transaksi nyata dan mengabaikan masa depan', () async {
    final database = createInMemoryDatabaseForTests();
    addTearDown(database.close);
    final fromMonth = DateTime(2026, 8, 21);
    final saveTransaction = SaveTransaction(database);
    final records = [
      (DateTime(2026, 6, 10), 200000),
      (DateTime(2026, 7, 10), 300000),
      (DateTime(2026, 8, 10), 400000),
      (DateTime(2026, 9, 10), 900000),
    ];
    for (final record in records) {
      await saveTransaction(
        TransactionEntity(
          id: 'tx-${record.$1.month}',
          householdId: AppContext.householdId,
          date: record.$1,
          amount: record.$2,
          owner: 'Keluarga',
          categoryId: 'income-category',
          recordedAt: record.$1,
        ),
      );
    }

    final transactions = await GetTransactions(database)(
      AppContext.householdId,
    );
    final forecast = FinancialAnalysis.forecast(
      transactions,
      fromMonth: fromMonth,
    );

    expect(forecast, hasLength(1));
    expect(forecast.single.month, DateTime(2026, 9));
    expect(forecast.single.balance, 300000);
  });

  test(
    'ringkasan mingguan hanya menghitung transaksi pada rentang minggu aktif',
    () async {
      final database = createInMemoryDatabaseForTests();
      addTearDown(database.close);
      final saveTransaction = SaveTransaction(database);
      final monday = DateTime(2026, 8, 17, 8);
      final currentWeek = [
        (monday, -250000),
        (monday.add(const Duration(days: 2)), -750000),
        (monday.add(const Duration(days: 5)), 500000),
        (monday.add(const Duration(days: 7)), -1000000),
      ];
      for (var index = 0; index < currentWeek.length; index++) {
        final record = currentWeek[index];
        await saveTransaction(
          TransactionEntity(
            id: 'weekly-$index',
            householdId: AppContext.householdId,
            date: record.$1,
            amount: record.$2,
            owner: 'Keluarga',
            categoryId: 'category',
            recordedAt: record.$1,
          ),
        );
      }

      final transactions = await GetTransactions(database)(
        AppContext.householdId,
      );
      final digest = FinancialAnalysis.weeklyDigest(
        transactions,
        weekContaining: monday.add(const Duration(days: 3)),
      );

      expect(digest.start, DateTime(2026, 8, 17));
      expect(digest.endExclusive, DateTime(2026, 8, 24));
      expect(digest.transactionCount, 3);
      expect(digest.expense, 1000000);
      expect(digest.income, 500000);
    },
  );

  test('label batang grafik memakai nominal Rupiah yang mudah dibaca', () {
    expect(formatCompactRupiah(0), 'Rp0');
    expect(formatCompactRupiah(25000), 'Rp25 rb');
    expect(formatCompactRupiah(1000000), 'Rp1 jt');
    expect(formatCompactRupiah(1250000), 'Rp1,3 jt');
  });
}
