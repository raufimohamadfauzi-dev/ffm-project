import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_analysis_engine.dart';

/// Analysis Engine Integration Regression Tests
///
/// Tests for verifying the analysis engine continues to work correctly
/// and maintains its contract with the assistant.

void main() {
  group('Analysis Engine Integration Regression Tests', () {
    test('AnalysisPeriod enum should have all required periods', () {
      // Verify all analysis periods are available
      final requiredPeriods = [
        FfmAnalysisPeriod.last7Days,
        FfmAnalysisPeriod.last30Days,
        FfmAnalysisPeriod.last90Days,
        FfmAnalysisPeriod.thisMonth,
        FfmAnalysisPeriod.lastMonth,
        FfmAnalysisPeriod.thisYear,
      ];

      for (final period in requiredPeriods) {
        expect(FfmAnalysisPeriod.values.contains(period), isTrue,
            reason: 'Analysis period $period should be defined');
      }
    });

    test('TrendType enum should have all required types', () {
      // Verify all trend types are available
      final requiredTypes = [
        FfmTrendType.income,
        FfmTrendType.expense,
        FfmTrendType.both,
      ];

      for (final type in requiredTypes) {
        expect(FfmTrendType.values.contains(type), isTrue,
            reason: 'Trend type $type should be defined');
      }
    });

    test('AnalysisPeriod values should be distinct', () {
      // Verify no duplicate values in enum
      final values = FfmAnalysisPeriod.values;
      final uniqueValues = values.toSet();
      
      expect(values.length, equals(uniqueValues.length),
          reason: 'All analysis periods should be unique');
    });

    test('TrendType values should be distinct', () {
      // Verify no duplicate values in enum
      final values = FfmTrendType.values;
      final uniqueValues = values.toSet();
      
      expect(values.length, equals(uniqueValues.length),
          reason: 'All trend types should be unique');
    });

    test('AnalysisPeriod should have reasonable count', () {
      // Verify we have a reasonable number of analysis periods
      // This prevents accidental removal of periods
      expect(FfmAnalysisPeriod.values.length, greaterThanOrEqualTo(6),
          reason: 'Should have at least 6 analysis periods');
    });

    test('PeriodAnalysis should have required fields', () {
      // Verify period analysis result structure
      final result = FfmPeriodAnalysis(
        period: FfmAnalysisPeriod.last30Days,
        periodLabel: '30 hari terakhir',
        start: DateTime(2026, 8, 1),
        end: DateTime(2026, 8, 31),
        income: 1000000,
        expense: 700000,
        transactionCount: 25,
        categoryBreakdown: {'Makanan': 300000, 'Transport': 200000},
      );

      expect(result.period, equals(FfmAnalysisPeriod.last30Days));
      expect(result.income, equals(1000000));
      expect(result.expense, equals(700000));
      expect(result.netCashflow, equals(300000));
      expect(result.transactionCount, equals(25));
      expect(result.topCategory, equals('Makanan'));
    });

    test('FrequencyAnalysis should have required fields', () {
      // Verify frequency analysis result structure
      final result = FfmFrequencyAnalysis(
        period: '30 hari terakhir',
        totalTransactions: 25,
        categoryFrequency: {'Makanan': 15, 'Transport': 10},
        merchantFrequency: {'Warung A': 10, 'Warung B': 8},
        dayOfWeekFrequency: {1: 5, 2: 4, 3: 6},
      );

      expect(result.period, equals('30 hari terakhir'));
      expect(result.totalTransactions, equals(25));
      expect(result.categoryFrequency.length, greaterThan(0));
      expect(result.mostFrequentCategory, equals('Makanan'));
      expect(result.mostFrequentMerchant, equals('Warung A'));
    });

    test('TrendAnalysis should have required fields', () {
      // Verify trend analysis result structure
      final result = FfmTrendAnalysis(
        period: '3 bulan terakhir',
        type: FfmTrendType.expense,
        trendDirection: 'naik',
        monthlyData: [
          FfmMonthlyData(
            month: '2026-06',
            income: 5000000,
            expense: 3000000,
            count: 30,
          ),
          FfmMonthlyData(
            month: '2026-07',
            income: 5500000,
            expense: 3500000,
            count: 35,
          ),
        ],
      );

      expect(result.type, equals(FfmTrendType.expense));
      expect(result.trendDirection, equals('naik'));
      expect(result.monthlyData.length, greaterThan(0));
    });

    test('PatternAnalysis should have required fields', () {
      // Verify pattern analysis result structure
      final result = FfmPatternAnalysis(
        period: '30 hari terakhir',
        categoryPatterns: {
          'Makanan': FfmCategoryPattern(
            category: 'Makanan',
            count: 15,
            total: 300000,
            average: 20000,
            median: 15000,
            min: 5000,
            max: 50000,
          ),
        },
      );

      expect(result.period, equals('30 hari terakhir'));
      expect(result.categoryPatterns.length, greaterThan(0));
      
      final pattern = result.categoryPatterns['Makanan']!;
      expect(pattern.category, equals('Makanan'));
      expect(pattern.count, equals(15));
      expect(pattern.total, equals(300000));
    });

    test('Analysis engine data models should be immutable', () {
      // Verify that analysis results are immutable (const constructors)
      final result = const FfmFrequencyAnalysis(
        period: '30 hari terakhir',
        totalTransactions: 0,
        categoryFrequency: {},
        merchantFrequency: {},
        dayOfWeekFrequency: {},
      );

      expect(result, isNotNull);
      expect(result.totalTransactions, equals(0));
    });
  });
}
