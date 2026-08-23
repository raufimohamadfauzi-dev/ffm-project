import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_financial_analysis.dart';

void main() {
  test('membatasi cicilan baru dengan batas 30% dan cashflow', () {
    const evidence = FfmAssistantFinancialEvidence(
      periodLabel: 'bulan Agustus 2026',
      transactionCount: 8,
      monthsWithIncome: 1,
      monthsWithExpense: 1,
      income: 10000000,
      expenses: 6000000,
      currentInstallments: 1000000,
      activeLiabilityCount: 1,
      quality: FfmAssistantDataQuality.sufficient,
    );

    final result = FfmAssistantLoanAffordabilityAnalysis.calculate(
      evidence: evidence,
    );

    expect(result.safeDebtServiceLimit, 3000000);
    expect(result.remainingDebtServiceCapacity, 2000000);
    expect(result.cashflowCapacity, 3000000);
    expect(result.recommendedNewInstallment, 2000000);
    expect(result.shouldAvoidNewLoan, isFalse);
  });

  test('menolak pinjaman baru saat cashflow setelah kewajiban negatif', () {
    const evidence = FfmAssistantFinancialEvidence(
      periodLabel: 'bulan Agustus 2026',
      transactionCount: 6,
      monthsWithIncome: 1,
      monthsWithExpense: 1,
      income: 5000000,
      expenses: 4000000,
      currentInstallments: 1500000,
      activeLiabilityCount: 2,
      quality: FfmAssistantDataQuality.sufficient,
    );

    final result = FfmAssistantLoanAffordabilityAnalysis.calculate(
      evidence: evidence,
    );

    expect(result.recommendedNewInstallment, 0);
    expect(result.shouldAvoidNewLoan, isTrue);
    expect(result.reason, contains('negatif'));
  });

  test('data tanpa pemasukan menghasilkan fallback tanpa angka personal', () {
    const evidence = FfmAssistantFinancialEvidence(
      periodLabel: 'bulan Agustus 2026',
      transactionCount: 2,
      monthsWithIncome: 0,
      monthsWithExpense: 1,
      income: 0,
      expenses: 1500000,
      currentInstallments: 0,
      activeLiabilityCount: 0,
      quality: FfmAssistantDataQuality.partial,
    );

    final result = FfmAssistantLoanAffordabilityAnalysis.calculate(
      evidence: evidence,
    );

    expect(result.hasEnoughData, isFalse);
    expect(result.recommendedNewInstallment, 0);
    expect(result.shouldAvoidNewLoan, isTrue);
    expect(result.reason, contains('Belum ada pemasukan'));
  });

  test('database kosong terklasifikasi empty', () {
    expect(
      classifyFinancialDataQuality(
        income: 0,
        expenses: 0,
        transactionCount: 0,
        monthsWithIncome: 0,
        monthsWithExpense: 0,
      ),
      FfmAssistantDataQuality.empty,
    );
  });
}
