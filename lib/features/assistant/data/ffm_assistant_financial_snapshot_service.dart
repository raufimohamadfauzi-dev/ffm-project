import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/ffm_assistant_financial_analysis.dart';

class FfmAssistantFinancialSnapshotService {
  const FfmAssistantFinancialSnapshotService(this._database);

  final AppDatabase _database;

  Future<FfmAssistantFinancialEvidence> readCurrentMonth({
    required String householdId,
    required DateTime now,
  }) async {
    final start = DateTime(now.year, now.month);
    final end = DateTime(now.year, now.month + 1);
    final rows =
        await (_database.select(_database.transactions)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isArchived.equals(false) &
                  row.isDeleted.equals(false),
            ))
            .get();

    var income = 0;
    var expenses = 0;
    var transactionCount = 0;
    for (final row in rows) {
      if (row.date.isBefore(start) || !row.date.isBefore(end)) continue;
      if (row.type == 'income') {
        income += row.amount.abs();
        transactionCount++;
      } else if (row.type == 'expense') {
        expenses += row.amount.abs();
        transactionCount++;
      }
    }

    final liabilities =
        await (_database.select(_database.liabilities)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isActive.equals(true),
            ))
            .get();
    final currentInstallments = liabilities.fold<int>(
      0,
      (sum, row) => sum + row.monthlyInstallment,
    );
    final quality = classifyFinancialDataQuality(
      income: income,
      expenses: expenses,
      transactionCount: transactionCount,
      monthsWithIncome: income > 0 ? 1 : 0,
      monthsWithExpense: expenses > 0 ? 1 : 0,
    );

    return FfmAssistantFinancialEvidence(
      periodLabel: 'bulan ${_monthLabel(now.month)} ${now.year}',
      transactionCount: transactionCount,
      monthsWithIncome: income > 0 ? 1 : 0,
      monthsWithExpense: expenses > 0 ? 1 : 0,
      income: income,
      expenses: expenses,
      currentInstallments: currentInstallments,
      activeLiabilityCount: liabilities.length,
      quality: quality,
    );
  }

  String buildBoundedPrompt(FfmAssistantFinancialEvidence evidence) {
    final income = evidence.income;
    final expense = evidence.expenses;
    final installments = evidence.currentInstallments;
    final cashflow = evidence.cashflowAfterDebt;
    final quality = switch (evidence.quality) {
      FfmAssistantDataQuality.sufficient => 'sufficient',
      FfmAssistantDataQuality.partial => 'partial',
      FfmAssistantDataQuality.empty => 'empty',
      FfmAssistantDataQuality.insufficientPeriod => 'insufficient_period',
    };
    return 'Financial snapshot lokal bounded: periode=${evidence.periodLabel}; '
        'quality=$quality; income=$income; expenses=$expense; '
        'active_installments=$installments; cashflow_after_debt=$cashflow; '
        'transaction_count=${evidence.transactionCount}; '
        'active_liability_count=${evidence.activeLiabilityCount}. '
        'Gunakan hanya sebagai evidence, jangan mengarang angka lain. '
        'Jika quality bukan sufficient, nyatakan keterbatasan data.';
  }

  String _monthLabel(int month) {
    const names = <String>[
      'Januari',
      'Februari',
      'Maret',
      'April',
      'Mei',
      'Juni',
      'Juli',
      'Agustus',
      'September',
      'Oktober',
      'November',
      'Desember',
    ];
    return month >= 1 && month <= 12 ? names[month - 1] : 'berjalan';
  }
}
