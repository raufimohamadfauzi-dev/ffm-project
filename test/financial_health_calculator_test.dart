import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/features/advisor/domain/usecases/financial_health_calculator.dart';

void main() {
  const calculator = FinancialHealthCalculator();

  group('FinancialHealthCalculator 5 Pilar', () {
    test('Skenario Prima (Skor 85-100): Pemasukan besar, hemat, tanpa hutang, dana darurat cukup', () {
      final input = FinancialHealthInput(
        totalIncome: 10000000,
        totalExpenses: 4000000,
        totalMonthlyInstallments: 0,
        emergencyFundAmount: 30000000,
        averageMonthlyExpenses: 4000000,
        totalAssets: 100000000,
        totalLiabilities: 0,
      );

      final score = calculator.calculate(input);

      expect(score.totalScore, greaterThanOrEqualTo(85));
      expect(score.status, FinancialHealthStatus.excellent);
      expect(score.pillars.length, 5);
      expect(score.cashflow, 6000000);
      expect(score.savingsRate, 0.6);
      expect(score.debtToIncomeRatio, 0.0);
      expect(score.emergencyMonths, 7.5);
      expect(score.netWorth, 100000000);
      expect(score.headline, contains('prima'));
      expect(score.strengths, isNotEmpty);
      expect(score.warnings, isEmpty);
    });

    test('Skenario Sehat (Skor 70-84): Pengeluaran terkendali, cicilan wajar, cadangan cukup', () {
      final input = FinancialHealthInput(
        totalIncome: 8000000,
        totalExpenses: 6800000,
        totalMonthlyInstallments: 2000000,
        emergencyFundAmount: 24000000,
        averageMonthlyExpenses: 6800000,
        totalAssets: 30000000,
        totalLiabilities: 20000000,
      );

      final score = calculator.calculate(input);

      expect(score.totalScore, inInclusiveRange(70, 84));
      expect(score.status, FinancialHealthStatus.good);
      expect(score.headline, contains('sehat'));
      expect(score.pillars[0].score, 20); // surplus 15%
      expect(score.pillars[1].score, 12); // expense 85%
      expect(score.pillars[2].score, 15); // debt 25%
      expect(score.pillars[3].score, 16); // emergency 3.5 months
      expect(score.pillars[4].score, 10); // net worth > 0, assets < 2x liabilities
    });

    test('Skenario Defisit Berat & Cicilan Tinggi: Status Critical', () {
      final input = FinancialHealthInput(
        totalIncome: 5000000,
        totalExpenses: 6500000,
        totalMonthlyInstallments: 2500000,
        emergencyFundAmount: 500000,
        averageMonthlyExpenses: 6000000,
        totalAssets: 2000000,
        totalLiabilities: 20000000,
      );

      final score = calculator.calculate(input);

      expect(score.totalScore, lessThan(40));
      expect(score.status, FinancialHealthStatus.critical);
      expect(score.cashflow, lessThan(0));
      expect(score.warnings, isNotEmpty);
      expect(score.recommendations, isNotEmpty);
      expect(score.headline, contains('butuh perhatian'));
    });

    test('Skenario Tanpa Transaksi / Pengguna Baru', () {
      const input = FinancialHealthInput(
        totalIncome: 0,
        totalExpenses: 0,
        totalMonthlyInstallments: 0,
        emergencyFundAmount: 0,
        averageMonthlyExpenses: 0,
        totalAssets: 0,
        totalLiabilities: 0,
      );

      final score = calculator.calculate(input);

      expect(score.totalScore, inInclusiveRange(50, 65));
      expect(score.status, isIn([FinancialHealthStatus.fair, FinancialHealthStatus.warning]));
      expect(score.pillars.length, 5);
      expect(score.pillars.every((p) => p.maxScore > 0), isTrue);
    });

    test('Pilar rincian persentase dan deskripsi akurat', () {
      final input = FinancialHealthInput(
        totalIncome: 10000000,
        totalExpenses: 7000000,
        totalMonthlyInstallments: 1500000,
        emergencyFundAmount: 14000000,
        averageMonthlyExpenses: 7000000,
        totalAssets: 50000000,
        totalLiabilities: 10000000,
      );

      final score = calculator.calculate(input);

      final cashflowPillar = score.pillars.firstWhere((p) => p.id == 'cashflow');
      expect(cashflowPillar.maxScore, 25);
      expect(cashflowPillar.percentage, inInclusiveRange(0.0, 1.0));
      expect(cashflowPillar.factDescription, isNotEmpty);

      final netWorthPillar = score.pillars.firstWhere((p) => p.id == 'net_worth');
      expect(netWorthPillar.maxScore, 15);
      expect(netWorthPillar.percentage, 1.0);
    });
  });
}
