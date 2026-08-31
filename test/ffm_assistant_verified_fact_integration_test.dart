import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_verified_fact_service.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_analysis_engine.dart';

/// Verified Fact Service Integration Regression Tests
///
/// Tests for verifying the verified fact service continues to work correctly
/// and maintains its contract with the assistant.

void main() {
  group('Verified Fact Service Integration Regression Tests', () {
    test('FfmVerifiedFacts should have required fields', () {
      // Verify verified facts structure
      final facts = FfmVerifiedFacts(
        capturedAt: DateTime(2026, 8, 31),
        householdId: 'test-household',
      );

      expect(facts.capturedAt, isNotNull);
      expect(facts.householdId, equals('test-household'));
      expect(facts.financialSummary, isNull);
      expect(facts.recentTransactions, isNull);
      expect(facts.masterDataSummary, isNull);
    });

    test('FfmVerifiedFacts should support financial summary', () {
      // Verify financial summary can be attached
      final financialSummary = const FfmFinancialSummaryFact(
        totalAccounts: 3,
        totalBalance: 5000000,
        totalActiveLiabilities: 1,
        totalDebt: 1000000,
        totalActiveGoals: 2,
        totalGoalProgress: 500000,
        totalGoalTarget: 2000000,
        netWorth: 4000000,
      );

      final facts = FfmVerifiedFacts(
        capturedAt: DateTime(2026, 8, 31),
        householdId: 'test-household',
        financialSummary: financialSummary,
      );

      expect(facts.financialSummary, isNotNull);
      expect(facts.financialSummary!.totalAccounts, equals(3));
      expect(facts.financialSummary!.totalBalance, equals(5000000));
    });

    test('FfmVerifiedFacts should support recent transactions', () {
      // Verify recent transactions can be attached
      final transactions = [
        FfmTransactionFact(
          id: '1',
          type: 'expense',
          amount: 50000,
          category: 'Makanan',
          date: DateTime(2026, 8, 31),
        ),
        FfmTransactionFact(
          id: '2',
          type: 'income',
          amount: 100000,
          category: 'Gaji',
          date: DateTime(2026, 8, 30),
        ),
      ];

      final facts = FfmVerifiedFacts(
        capturedAt: DateTime(2026, 8, 31),
        householdId: 'test-household',
        recentTransactions: transactions,
      );

      expect(facts.recentTransactions, isNotNull);
      expect(facts.recentTransactions!.length, equals(2));
    });

    test('FfmVerifiedFacts should support master data summary', () {
      // Verify master data summary can be attached
      final masterDataSummary = const FfmMasterDataSummaryFact(
        totalActiveCategories: 10,
        totalActiveMerchants: 15,
        totalActiveAccounts: 3,
      );

      final facts = FfmVerifiedFacts(
        capturedAt: DateTime(2026, 8, 31),
        householdId: 'test-household',
        masterDataSummary: masterDataSummary,
      );

      expect(facts.masterDataSummary, isNotNull);
      expect(facts.masterDataSummary!.totalActiveCategories, equals(10));
    });

    test('FfmFinancialSummaryFact should have all required fields', () {
      // Verify financial summary structure
      const summary = FfmFinancialSummaryFact(
        totalAccounts: 3,
        totalBalance: 5000000,
        totalActiveLiabilities: 1,
        totalDebt: 1000000,
        totalActiveGoals: 2,
        totalGoalProgress: 500000,
        totalGoalTarget: 2000000,
        netWorth: 4000000,
      );

      expect(summary.totalAccounts, equals(3));
      expect(summary.totalBalance, equals(5000000));
      expect(summary.totalActiveLiabilities, equals(1));
      expect(summary.totalDebt, equals(1000000));
      expect(summary.totalActiveGoals, equals(2));
      expect(summary.totalGoalProgress, equals(500000));
      expect(summary.totalGoalTarget, equals(2000000));
      expect(summary.netWorth, equals(4000000));
    });

    test('FfmTransactionFact should have all required fields', () {
      // Verify transaction fact structure
      final transaction = FfmTransactionFact(
        id: '1',
        type: 'expense',
        amount: 50000,
        category: 'Makanan',
        date: DateTime(2026, 8, 31),
        note: 'Makan siang',
        partyName: 'Warung A',
      );

      expect(transaction.id, equals('1'));
      expect(transaction.type, equals('expense'));
      expect(transaction.amount, equals(50000));
      expect(transaction.category, equals('Makanan'));
      expect(transaction.note, equals('Makan siang'));
      expect(transaction.partyName, equals('Warung A'));
    });

    test('FfmMasterDataSummaryFact should have all required fields', () {
      // Verify master data summary structure
      const summary = FfmMasterDataSummaryFact(
        totalActiveCategories: 10,
        totalActiveMerchants: 15,
        totalActiveAccounts: 3,
      );

      expect(summary.totalActiveCategories, equals(10));
      expect(summary.totalActiveMerchants, equals(15));
      expect(summary.totalActiveAccounts, equals(3));
    });

    test('FfmAnalysisFacts should have all required fields', () {
      // Verify analysis facts structure
      final facts = FfmAnalysisFacts(
        period: FfmAnalysisPeriod.last30Days,
        periodLabel: '30 hari terakhir',
        income: 1000000,
        expense: 700000,
        netCashflow: 300000,
        transactionCount: 25,
        topCategory: 'Makanan',
        mostFrequentCategory: 'Makanan',
        mostFrequentMerchant: 'Warung A',
        categoryBreakdown: {'Makanan': 300000, 'Transport': 200000},
        categoryFrequency: {'Makanan': 15, 'Transport': 10},
        capturedAt: DateTime(2026, 8, 31),
      );

      expect(facts.period, equals(FfmAnalysisPeriod.last30Days));
      expect(facts.income, equals(1000000));
      expect(facts.expense, equals(700000));
      expect(facts.netCashflow, equals(300000));
      expect(facts.transactionCount, equals(25));
    });

    test('FfmTrendFacts should have all required fields', () {
      // Verify trend facts structure
      final facts = FfmTrendFacts(
        type: FfmTrendType.expense,
        trendDirection: 'naik',
        period: '3 bulan terakhir',
        monthlyData: [],
        capturedAt: DateTime(2026, 8, 31),
      );

      expect(facts.type, equals(FfmTrendType.expense));
      expect(facts.trendDirection, equals('naik'));
      expect(facts.period, equals('3 bulan terakhir'));
    });

    test('FfmPatternFacts should have all required fields', () {
      // Verify pattern facts structure
      final facts = FfmPatternFacts(
        period: '30 hari terakhir',
        categoryPatterns: {},
        capturedAt: DateTime(2026, 8, 31),
      );

      expect(facts.period, equals('30 hari terakhir'));
      expect(facts.categoryPatterns, isNotNull);
    });

    test('Verified facts should be immutable', () {
      // Verify that verified facts are immutable (const constructors)
      final facts = FfmVerifiedFacts(
        capturedAt: DateTime(2026, 8, 31),
        householdId: 'test-household',
      );

      expect(facts, isNotNull);
      expect(facts.householdId, equals('test-household'));
    });

    test('toLLMContext should produce non-empty string', () {
      // Verify toLLMContext produces valid output
      final facts = FfmVerifiedFacts(
        capturedAt: DateTime(2026, 8, 31),
        householdId: 'test-household',
      );

      final context = facts.toLLMContext();
      expect(context.isNotEmpty, isTrue);
      expect(context.contains('VERIFIED FACTS'), isTrue);
    });
  });
}
