import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_analysis_engine.dart';

void main() {
  group('FfmAssistantAnalysisEngine - Basic Tests', () {
    test('FfmFrequencyAnalysis should handle empty data correctly', () {
      final analysis = FfmFrequencyAnalysis(
        period: 'Test Period',
        totalTransactions: 0,
        categoryFrequency: {},
        merchantFrequency: {},
        dayOfWeekFrequency: {},
      );

      expect(analysis.totalTransactions, equals(0));
      expect(analysis.mostFrequentCategory, equals('tidak ada data'));
      expect(analysis.mostFrequentMerchant, equals('tidak ada data'));
    });

    test('FfmFrequencyAnalysis should calculate most frequent category', () {
      final analysis = FfmFrequencyAnalysis(
        period: 'Test Period',
        totalTransactions: 10,
        categoryFrequency: {
          'Makanan': 5,
          'Transport': 3,
          'Hiburan': 2,
        },
        merchantFrequency: {},
        dayOfWeekFrequency: {},
      );

      expect(analysis.mostFrequentCategory, equals('Makanan'));
    });

    test('FfmFrequencyAnalysis should calculate most frequent merchant', () {
      final analysis = FfmFrequencyAnalysis(
        period: 'Test Period',
        totalTransactions: 10,
        categoryFrequency: {},
        merchantFrequency: {
          'Warung A': 4,
          'Warung B': 3,
          'Toko C': 3,
        },
        dayOfWeekFrequency: {},
      );

      expect(analysis.mostFrequentMerchant, equals('Warung A'));
    });

    test('FfmTrendAnalysis should detect increasing trend', () {
      final analysis = FfmTrendAnalysis(
        period: 'Test Period',
        type: FfmTrendType.income,
        trendDirection: 'naik',
        monthlyData: [
          FfmMonthlyData(
            month: '2026-01',
            income: 1000000,
            expense: 500000,
            count: 10,
          ),
          FfmMonthlyData(
            month: '2026-02',
            income: 1500000,
            expense: 600000,
            count: 12,
          ),
        ],
      );

      expect(analysis.trendDirection, equals('naik'));
      expect(analysis.monthlyData.length, equals(2));
    });

    test('FfmComparisonAnalysis should calculate percentage changes', () {
      final analysis = FfmComparisonAnalysis(
        period1Label: 'January',
        period2Label: 'February',
        period1Data: const FfmPeriodData(
          income: 1000000,
          expense: 500000,
          count: 10,
        ),
        period2Data: const FfmPeriodData(
          income: 1500000,
          expense: 750000,
          count: 15,
        ),
        incomeChangePercent: 50,
        expenseChangePercent: 50,
        countChangePercent: 50,
      );

      expect(analysis.incomeChangePercent, equals(50));
      expect(analysis.expenseChangePercent, equals(50));
      expect(analysis.countChangePercent, equals(50));
    });

    test('FfmPatternAnalysis should calculate category statistics', () {
      final analysis = FfmPatternAnalysis(
        period: 'Test Period',
        categoryPatterns: {
          'Makanan': FfmCategoryPattern(
            category: 'Makanan',
            count: 3,
            total: 450000,
            average: 150000,
            median: 150000,
            min: 100000,
            max: 200000,
          ),
        },
      );

      final makananPattern = analysis.categoryPatterns['Makanan']!;
      expect(makananPattern.count, equals(3));
      expect(makananPattern.total, equals(450000));
      expect(makananPattern.average, equals(150000));
    });

    test('FfmPeriodAnalysis should calculate net cashflow and ratios', () {
      final analysis = FfmPeriodAnalysis(
        period: FfmAnalysisPeriod.last30Days,
        periodLabel: '30 hari terakhir',
        start: DateTime(2026, 1, 1),
        end: DateTime(2026, 1, 31),
        income: 2000000,
        expense: 800000,
        transactionCount: 15,
        categoryBreakdown: {
          'Makanan': 500000,
          'Transport': 300000,
        },
      );

      expect(analysis.netCashflow, equals(1200000));
      expect(analysis.expenseRatio, equals(0.4));
      expect(analysis.topCategory, equals('Makanan'));
    });

    test('FfmPeriodAnalysis should handle empty data', () {
      final analysis = FfmPeriodAnalysis(
        period: FfmAnalysisPeriod.last30Days,
        periodLabel: '30 hari terakhir',
        start: DateTime(2026, 1, 1),
        end: DateTime(2026, 1, 31),
        income: 0,
        expense: 0,
        transactionCount: 0,
        categoryBreakdown: {},
      );

      expect(analysis.netCashflow, equals(0));
      expect(analysis.topCategory, equals('tidak ada data'));
      expect(analysis.expenseRatio, isNull);
    });

    test('FfmAnalysisPeriod should have correct labels', () {
      expect(FfmAnalysisPeriod.last7Days, isNotNull);
      expect(FfmAnalysisPeriod.last30Days, isNotNull);
      expect(FfmAnalysisPeriod.last90Days, isNotNull);
      expect(FfmAnalysisPeriod.thisMonth, isNotNull);
      expect(FfmAnalysisPeriod.lastMonth, isNotNull);
      expect(FfmAnalysisPeriod.thisYear, isNotNull);
    });

    test('FfmTrendType should have expected values', () {
      expect(FfmTrendType.values, contains(FfmTrendType.income));
      expect(FfmTrendType.values, contains(FfmTrendType.expense));
      expect(FfmTrendType.values, contains(FfmTrendType.both));
    });
  });
}