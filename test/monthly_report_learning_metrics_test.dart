import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/assistant/presentation/widgets/ffm_assistant_page_context.dart';
import 'package:ffm_manager/features/backup/presentation/pages/monthly_report_page.dart';

void main() {
  group('MonthlyReportLearningMetrics Calculations', () {
    test('Kondisi Sehat: Rasio tabungan >= 20% dan cicilan aman <= 30%', () {
      final metrics = MonthlyReportLearningMetrics.calculate(
        income: 10000000,
        expense: 7000000,
        totalMonthlyInstallments: 2000000,
        totalAssetsValue: 50000000,
        topExpenseCategories: [
          const MapEntry('Belanja Bulanan', 3500000),
          const MapEntry('Makan di Luar', 1500000),
        ],
      );

      expect(metrics.savingsRate, 30.0);
      expect(metrics.debtToIncomeRatio, 20.0);
      expect(metrics.topExpenseCategoryShare, closeTo(50.0, 0.1));
      expect(metrics.keyLearningPoints, hasLength(3));

      expect(metrics.keyLearningPoints[0], contains('Rasio tabungan sehat di angka 30.0%'));
      expect(metrics.keyLearningPoints[1], contains('Pos "Belanja Bulanan" mendominasi 50.0% pengeluaran'));
      expect(metrics.keyLearningPoints[2], contains('Beban cicilan bulanan aman di angka 20.0%'));
    });

    test('Kondisi Defisit & Cicilan Berlebih (>30%)', () {
      final metrics = MonthlyReportLearningMetrics.calculate(
        income: 10000000,
        expense: 12000000,
        totalMonthlyInstallments: 4000000,
        totalAssetsValue: 10000000,
        topExpenseCategories: [
          const MapEntry('Cicilan & Belanja', 6000000),
        ],
      );

      expect(metrics.savingsRate, -20.0);
      expect(metrics.debtToIncomeRatio, 40.0);
      expect(metrics.topExpenseCategoryShare, closeTo(50.0, 0.1));

      expect(metrics.keyLearningPoints[0], contains('Arus kas mengalami defisit Rp 2000000'));
      expect(metrics.keyLearningPoints[1], contains('Pos "Cicilan & Belanja" mendominasi 50.0% pengeluaran'));
      expect(metrics.keyLearningPoints[2], contains('Perhatian: Beban cicilan (40.0%) di atas ambang aman 30%'));
    });

    test('Kondisi Tanpa Pemasukan (Zero Income)', () {
      final metrics = MonthlyReportLearningMetrics.calculate(
        income: 0,
        expense: 2000000,
        totalMonthlyInstallments: 0,
        totalAssetsValue: 0,
        topExpenseCategories: [
          const MapEntry('Operasional', 2000000),
        ],
      );

      expect(metrics.savingsRate, 0.0);
      expect(metrics.debtToIncomeRatio, 0.0);
      expect(metrics.topExpenseCategoryShare, 100.0);
      expect(metrics.keyLearningPoints, isNotEmpty);
    });
  });

  group('FfmAssistantScreenContextPolicy with Report Page Summary', () {
    test('forPrompt menyertakan dataSummary laporan lengkap untuk konteks LLM', () {
      final snapshot = FfmAssistantPageContextSnapshot(
        destination: FfmAssistantDestination.monthlyReport,
        capabilityIds: const ['read.summary'],
        updatedAt: DateTime(2026, 9, 3),
        dataSummary:
            'Laporan September 2026: Pemasukan Rp 10.000.000, Pengeluaran Rp 7.000.000, Surplus Rp 3.000.000. Rasio Tabungan: 30.0%, Rasio Cicilan: 20.0%. Pos Terbesar: Belanja Bulanan Rp 3.500.000. Evaluasi: Rasio tabungan sehat di angka 30.0%.',
      );

      final prompt = FfmAssistantScreenContextPolicy.forPrompt(
        destination: FfmAssistantDestination.monthlyReport,
        snapshot: snapshot,
      );

      expect(prompt, contains('Halaman aktif:'));
      expect(prompt, contains('Laporan September 2026: Pemasukan Rp 10.000.000'));
      expect(prompt, contains('Rasio Tabungan: 30.0%'));
      expect(prompt, contains('Evaluasi: Rasio tabungan sehat'));
    });
  });
}
