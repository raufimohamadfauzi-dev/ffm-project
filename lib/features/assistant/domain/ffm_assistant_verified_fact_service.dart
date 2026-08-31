import '../../../core/database/app_database.dart';
import 'ffm_assistant_analysis_engine.dart';
import 'ffm_assistant_reasoning_context.dart';
import 'package:drift/drift.dart';

/// Verified Fact Service
/// 
/// Service ini mengubah hasil database dan analysis engine menjadi context/fact
/// terstruktur sebelum diberikan kepada LLM. Ini memastikan LLM berfungsi sebagai
/// penyusun jawaban natural berdasarkan fakta terverifikasi, bukan sumber fakta utama.
/// 
/// Prinsip:
/// - Semua fakta berasal dari data database lokal atau analysis engine deterministik
/// - Tidak ada hallusinasi atau tebakan dari LLM
/// - Fakta terstruktur dan dapat diverifikasi
/// - LLM hanya menyusun bahasa natural dari verified facts
class FfmAssistantVerifiedFactService {
  const FfmAssistantVerifiedFactService({
    required this.database,
    required this.analysisEngine,
  });

  final AppDatabase database;
  final FfmAssistantAnalysisEngine analysisEngine;

  /// Generate verified facts untuk reasoning context
  Future<FfmVerifiedFacts> generateFacts({
    required String householdId,
    required FfmAssistantReasoningEvidenceScope scope,
    DateTime? referenceDate,
  }) async {
    final now = referenceDate ?? DateTime.now();
    
    final financialSummary = scope.includeFinancialSummary 
        ? await _getFinancialSummary(householdId, now)
        : null;
    
    final recentTransactions = scope.includeRecentTransactions
        ? await _getRecentTransactions(householdId, now)
        : null;
    
    final masterDataSummary = scope.includeMasterData
        ? await _getMasterDataSummary(householdId)
        : null;

    return FfmVerifiedFacts(
      capturedAt: now,
      householdId: householdId,
      financialSummary: financialSummary,
      recentTransactions: recentTransactions,
      masterDataSummary: masterDataSummary,
    );
  }

  /// Generate verified facts untuk analisis spesifik
  Future<FfmAnalysisFacts> generateAnalysisFacts({
    required String householdId,
    required FfmAnalysisPeriod period,
    DateTime? referenceDate,
  }) async {
    final now = referenceDate ?? DateTime.now();

    final periodAnalysis = await analysisEngine.analyzePeriod(
      householdId: householdId,
      period: period,
      referenceDate: now,
    );

    final frequencyAnalysis = await analysisEngine.analyzeFrequency(
      householdId: householdId,
      start: periodAnalysis.start,
      end: periodAnalysis.end,
    );

    return FfmAnalysisFacts(
      period: period,
      periodLabel: periodAnalysis.periodLabel,
      income: periodAnalysis.income,
      expense: periodAnalysis.expense,
      netCashflow: periodAnalysis.netCashflow,
      transactionCount: periodAnalysis.transactionCount,
      topCategory: periodAnalysis.topCategory,
      mostFrequentCategory: frequencyAnalysis.mostFrequentCategory,
      mostFrequentMerchant: frequencyAnalysis.mostFrequentMerchant,
      categoryBreakdown: periodAnalysis.categoryBreakdown,
      categoryFrequency: frequencyAnalysis.categoryFrequency,
      capturedAt: now,
    );
  }

  /// Generate verified facts untuk trend analysis
  Future<FfmTrendFacts> generateTrendFacts({
    required String householdId,
    required FfmTrendType type,
    DateTime? referenceDate,
  }) async {
    final now = referenceDate ?? DateTime.now();
    final start = DateTime(now.year, now.month - 3, 1);
    final end = DateTime(now.year, now.month + 1, 1);

    final trendAnalysis = await analysisEngine.analyzeTrend(
      householdId: householdId,
      start: start,
      end: end,
      type: type,
    );

    return FfmTrendFacts(
      type: type,
      trendDirection: trendAnalysis.trendDirection,
      period: trendAnalysis.period,
      monthlyData: trendAnalysis.monthlyData,
      capturedAt: now,
    );
  }

  /// Generate verified facts untuk pattern analysis
  Future<FfmPatternFacts> generatePatternFacts({
    required String householdId,
    DateTime? referenceDate,
  }) async {
    final now = referenceDate ?? DateTime.now();
    final start = now.subtract(const Duration(days: 30));
    final end = now;

    final patternAnalysis = await analysisEngine.analyzePatterns(
      householdId: householdId,
      start: start,
      end: end,
    );

    return FfmPatternFacts(
      period: patternAnalysis.period,
      categoryPatterns: patternAnalysis.categoryPatterns,
      capturedAt: now,
    );
  }

  Future<FfmFinancialSummaryFact> _getFinancialSummary(
    String householdId,
    DateTime now,
  ) async {
    final accounts = await (database.select(database.accounts)
          ..where((row) =>
              row.householdId.equals(householdId)))
        .get();

    var totalBalance = 0;
    for (final account in accounts) {
      totalBalance += account.openingBalance;
      // Calculate transaction balance for each account
      final transactions = await (database.select(database.transactions)
            ..where((row) =>
                row.householdId.equals(householdId) &
                row.accountId.equals(account.id) &
                row.isArchived.equals(false) &
                row.isDeleted.equals(false)))
          .get();
      for (final tx in transactions) {
        if (tx.type == 'income') {
          totalBalance += tx.amount.abs();
        } else if (tx.type == 'expense') {
          totalBalance -= tx.amount.abs();
        }
      }
    }

    // Get active liabilities
    final liabilities = await (database.select(database.liabilities)
          ..where((row) =>
              row.householdId.equals(householdId) &
              row.isActive.equals(true)))
        .get();

    var totalDebt = 0;
    for (final liability in liabilities) {
      totalDebt += liability.remainingBalance;
    }

    // Get active goals
    final goals = await (database.select(database.goals)
          ..where((row) =>
              row.householdId.equals(householdId) &
              row.isActive.equals(true)))
        .get();

    var totalGoalProgress = 0;
    var totalGoalTarget = 0;
    for (final goal in goals) {
      totalGoalProgress += goal.currentAmount;
      totalGoalTarget += goal.targetAmount;
    }

    return FfmFinancialSummaryFact(
      totalAccounts: accounts.length,
      totalBalance: totalBalance,
      totalActiveLiabilities: liabilities.length,
      totalDebt: totalDebt,
      totalActiveGoals: goals.length,
      totalGoalProgress: totalGoalProgress,
      totalGoalTarget: totalGoalTarget,
      netWorth: totalBalance - totalDebt,
    );
  }

  Future<List<FfmTransactionFact>> _getRecentTransactions(
    String householdId,
    DateTime now,
  ) async {
    final transactions = await (database.select(database.transactions)
          ..where((row) =>
              row.householdId.equals(householdId) &
              row.isArchived.equals(false) &
              row.isDeleted.equals(false))
          ..orderBy([(row) => OrderingTerm.desc(row.date)])
          ..limit(10))
        .get();

    final facts = <FfmTransactionFact>[];
    for (final tx in transactions) {
      // Get category name
      String categoryName = 'Uncategorized';
      if (tx.categoryId != null) {
        final category = await (database.select(database.categories)
              ..where((row) =>
                  row.id.equals(tx.categoryId!)))
            .getSingleOrNull();
        if (category != null) {
          categoryName = category.name;
        }
      }

      facts.add(FfmTransactionFact(
        id: tx.id,
        type: tx.type,
        amount: tx.amount.abs(),
        category: categoryName,
        date: tx.date,
        note: tx.note,
        partyName: tx.partyName,
      ));
    }

    return facts;
  }

  Future<FfmMasterDataSummaryFact> _getMasterDataSummary(
    String householdId,
  ) async {
    final categories = await (database.select(database.categories)
          ..where((row) =>
              row.householdId.equals(householdId) &
              row.isActive.equals(true)))
        .get();

    final merchants = await (database.select(database.merchants)
          ..where((row) =>
              row.householdId.equals(householdId) &
              row.isActive.equals(true)))
        .get();

    final accounts = await (database.select(database.accounts)
          ..where((row) =>
              row.householdId.equals(householdId)))
        .get();

    return FfmMasterDataSummaryFact(
      totalActiveCategories: categories.length,
      totalActiveMerchants: merchants.length,
      totalActiveAccounts: accounts.length,
    );
  }
}

// Data models untuk verified facts

class FfmVerifiedFacts {
  const FfmVerifiedFacts({
    required this.capturedAt,
    required this.householdId,
    this.financialSummary,
    this.recentTransactions,
    this.masterDataSummary,
  });

  final DateTime capturedAt;
  final String householdId;
  final FfmFinancialSummaryFact? financialSummary;
  final List<FfmTransactionFact>? recentTransactions;
  final FfmMasterDataSummaryFact? masterDataSummary;

  /// Convert ke structured text untuk LLM context
  String toLLMContext() {
    final sections = <String>[];
    
    sections.add('VERIFIED FACTS (captured at ${capturedAt.toIso8601String()}):');
    
    if (financialSummary != null) {
      final fs = financialSummary!;
      sections.add('Financial Summary:');
      sections.add('- Total Accounts: ${fs.totalAccounts}');
      sections.add('- Total Balance: ${_formatCurrency(fs.totalBalance)}');
      sections.add('- Total Active Liabilities: ${fs.totalActiveLiabilities}');
      sections.add('- Total Debt: ${_formatCurrency(fs.totalDebt)}');
      sections.add('- Net Worth: ${_formatCurrency(fs.netWorth)}');
      sections.add('- Total Active Goals: ${fs.totalActiveGoals}');
      sections.add('- Goal Progress: ${_formatCurrency(fs.totalGoalProgress)} / ${_formatCurrency(fs.totalGoalTarget)}');
    }
    
    if (recentTransactions != null && recentTransactions!.isNotEmpty) {
      sections.add('Recent Transactions (${recentTransactions!.length}):');
      for (final tx in recentTransactions!.take(5)) {
        sections.add('- ${tx.type} ${_formatCurrency(tx.amount)} in ${tx.category} on ${tx.date.toIso8601String().substring(0, 10)}');
      }
    }
    
    if (masterDataSummary != null) {
      final md = masterDataSummary!;
      sections.add('Master Data Summary:');
      sections.add('- Active Categories: ${md.totalActiveCategories}');
      sections.add('- Active Merchants: ${md.totalActiveMerchants}');
      sections.add('- Active Accounts: ${md.totalActiveAccounts}');
    }
    
    sections.add('IMPORTANT: These are verified facts from database. Use them as ground truth. Do not hallucinate or make up numbers.');
    
    return sections.join('\n');
  }

  String _formatCurrency(int amount) {
    final digits = amount.abs().toString();
    final buffer = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) buffer.write('.');
      buffer.write(digits[index]);
    }
    return 'Rp$buffer';
  }
}

class FfmFinancialSummaryFact {
  const FfmFinancialSummaryFact({
    required this.totalAccounts,
    required this.totalBalance,
    required this.totalActiveLiabilities,
    required this.totalDebt,
    required this.totalActiveGoals,
    required this.totalGoalProgress,
    required this.totalGoalTarget,
    required this.netWorth,
  });

  final int totalAccounts;
  final int totalBalance;
  final int totalActiveLiabilities;
  final int totalDebt;
  final int totalActiveGoals;
  final int totalGoalProgress;
  final int totalGoalTarget;
  final int netWorth;
}

class FfmTransactionFact {
  const FfmTransactionFact({
    required this.id,
    required this.type,
    required this.amount,
    required this.category,
    required this.date,
    this.note,
    this.partyName,
  });

  final String id;
  final String type;
  final int amount;
  final String category;
  final DateTime date;
  final String? note;
  final String? partyName;
}

class FfmMasterDataSummaryFact {
  const FfmMasterDataSummaryFact({
    required this.totalActiveCategories,
    required this.totalActiveMerchants,
    required this.totalActiveAccounts,
  });

  final int totalActiveCategories;
  final int totalActiveMerchants;
  final int totalActiveAccounts;
}

class FfmAnalysisFacts {
  const FfmAnalysisFacts({
    required this.period,
    required this.periodLabel,
    required this.income,
    required this.expense,
    required this.netCashflow,
    required this.transactionCount,
    required this.topCategory,
    required this.mostFrequentCategory,
    required this.mostFrequentMerchant,
    required this.categoryBreakdown,
    required this.categoryFrequency,
    required this.capturedAt,
  });

  final FfmAnalysisPeriod period;
  final String periodLabel;
  final int income;
  final int expense;
  final int netCashflow;
  final int transactionCount;
  final String topCategory;
  final String mostFrequentCategory;
  final String mostFrequentMerchant;
  final Map<String, int> categoryBreakdown;
  final Map<String, int> categoryFrequency;
  final DateTime capturedAt;

  String toLLMContext() {
    final sections = <String>[];
    
    sections.add('ANALYSIS FACTS ($periodLabel, captured at ${capturedAt.toIso8601String()}):');
    sections.add('- Income: ${_formatCurrency(income)}');
    sections.add('- Expense: ${_formatCurrency(expense)}');
    sections.add('- Net Cashflow: ${_formatCurrency(netCashflow)}');
    sections.add('- Transaction Count: $transactionCount');
    sections.add('- Top Category: $topCategory');
    sections.add('- Most Frequent Category: $mostFrequentCategory');
    sections.add('- Most Frequent Merchant: $mostFrequentMerchant');
    
    if (categoryBreakdown.isNotEmpty) {
      sections.add('- Category Breakdown:');
      final sorted = categoryBreakdown.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final entry in sorted.take(5)) {
        sections.add('  - ${entry.key}: ${_formatCurrency(entry.value)}');
      }
    }
    
    sections.add('IMPORTANT: These are verified analysis results from database. Use them as ground truth.');
    
    return sections.join('\n');
  }

  String _formatCurrency(int amount) {
    final digits = amount.abs().toString();
    final buffer = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) buffer.write('.');
      buffer.write(digits[index]);
    }
    return 'Rp$buffer';
  }
}

class FfmTrendFacts {
  const FfmTrendFacts({
    required this.type,
    required this.trendDirection,
    required this.period,
    required this.monthlyData,
    required this.capturedAt,
  });

  final FfmTrendType type;
  final String trendDirection;
  final String period;
  final List<FfmMonthlyData> monthlyData;
  final DateTime capturedAt;

  String toLLMContext() {
    final sections = <String>[];
    
    sections.add('TREND FACTS ($type, captured at ${capturedAt.toIso8601String()}):');
    sections.add('- Trend Direction: $trendDirection');
    sections.add('- Period: $period');
    sections.add('- Monthly Data:');
    
    for (final month in monthlyData) {
      sections.add('  - ${month.month}:');
      if (type == FfmTrendType.income || type == FfmTrendType.both) {
        sections.add('    Income: ${_formatCurrency(month.income)}');
      }
      if (type == FfmTrendType.expense || type == FfmTrendType.both) {
        sections.add('    Expense: ${_formatCurrency(month.expense)}');
      }
      sections.add('    Count: ${month.count}');
    }
    
    sections.add('IMPORTANT: These are verified trend calculations from database. Use them as ground truth.');
    
    return sections.join('\n');
  }

  String _formatCurrency(int amount) {
    final digits = amount.abs().toString();
    final buffer = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) buffer.write('.');
      buffer.write(digits[index]);
    }
    return 'Rp$buffer';
  }
}

class FfmPatternFacts {
  const FfmPatternFacts({
    required this.period,
    required this.categoryPatterns,
    required this.capturedAt,
  });

  final String period;
  final Map<String, FfmCategoryPattern> categoryPatterns;
  final DateTime capturedAt;

  String toLLMContext() {
    final sections = <String>[];
    
    sections.add('PATTERN FACTS ($period, captured at ${capturedAt.toIso8601String()}):');
    sections.add('- Category Patterns:');
    
    final sortedPatterns = categoryPatterns.entries.toList()
      ..sort((a, b) => b.value.total.compareTo(a.value.total));
    
    for (final entry in sortedPatterns.take(5)) {
      final pattern = entry.value;
      sections.add('  - ${pattern.category}:');
      sections.add('    Count: ${pattern.count}');
      sections.add('    Total: ${_formatCurrency(pattern.total)}');
      sections.add('    Average: ${_formatCurrency(pattern.average)}');
      sections.add('    Median: ${_formatCurrency(pattern.median)}');
      sections.add('    Range: ${_formatCurrency(pattern.min)} - ${_formatCurrency(pattern.max)}');
    }
    
    sections.add('IMPORTANT: These are verified pattern calculations from database. Use them as ground truth.');
    
    return sections.join('\n');
  }

  String _formatCurrency(int amount) {
    final digits = amount.abs().toString();
    final buffer = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) buffer.write('.');
      buffer.write(digits[index]);
    }
    return 'Rp$buffer';
  }
}