import '../../../core/database/app_database.dart';
import 'package:drift/drift.dart';

/// Analysis Engine untuk FFM Assistant
/// 
/// Engine ini menyediakan kemampuan analisis deterministik di atas data
/// yang sudah ada, bukan meminta LLM menghitung sendiri.
/// 
/// Prinsip:
/// - Semua perhitungan berasal dari data database lokal
/// - Tidak ada tebakan atau hallusinasi dari LLM
/// - Hasil diverifikasi dan dapat direplay
class FfmAssistantAnalysisEngine {
  const FfmAssistantAnalysisEngine(this.database);

  final AppDatabase database;

  /// Analisis frekuensi - seberapa sering sesuatu terjadi
  Future<FfmFrequencyAnalysis> analyzeFrequency({
    required String householdId,
    required DateTime start,
    required DateTime end,
    String? category,
    String? account,
  }) async {
    var query = database.select(database.transactions)
      ..where((row) =>
          row.householdId.equals(householdId) &
          row.isArchived.equals(false) &
          row.isDeleted.equals(false));

    if (category != null) {
      // Find category by name and get its ID
      final categoryRow = await (database.select(database.categories)
            ..where((row) =>
                row.householdId.equals(householdId) &
                row.name.equals(category) &
                row.isActive.equals(true)))
          .getSingleOrNull();
      if (categoryRow != null) {
        query.where((row) => row.categoryId.equals(categoryRow.id));
      }
    }
    if (account != null) {
      // Find account by name and get its ID
      final accountRow = await (database.select(database.accounts)
            ..where((row) =>
                row.householdId.equals(householdId) &
                row.name.equals(account) &
                row.isActive.equals(true) &
                row.isArchived.equals(false)))
          .getSingleOrNull();
      if (accountRow != null) {
        query.where((row) => row.accountId.equals(accountRow.id));
      }
    }

    final transactions = await query.get();
    
    // Filter by date range in memory (following existing pattern)
    final filteredTransactions = transactions.where((tx) {
      return !tx.date.isBefore(start) && tx.date.isBefore(end);
    }).toList();

    // Hitung frekuensi per kategori
    final categoryFrequency = <String, int>{};
    // Hitung frekuensi per merchant
    final merchantFrequency = <String, int>{};
    // Hitung frekuensi per hari dalam seminggu
    final dayOfWeekFrequency = <int, int>{};

    for (final tx in filteredTransactions) {
      // Get category name from categoryId
      String categoryName = 'Uncategorized';
      if (tx.categoryId != null) {
        final category = await (database.select(database.categories)
              ..where((row) =>
                  row.id.equals(tx.categoryId!) &
                  row.householdId.equals(householdId)))
            .getSingleOrNull();
        if (category != null) {
          categoryName = category.name;
        }
      }

      // Frekuensi kategori
      categoryFrequency[categoryName] = (categoryFrequency[categoryName] ?? 0) + 1;

      // Frekuensi merchant
      if (tx.merchantId != null) {
        final merchant = await (database.select(database.merchants)
              ..where((row) =>
                  row.id.equals(tx.merchantId!) &
                  row.householdId.equals(householdId)))
            .getSingleOrNull();
        if (merchant != null && merchant.name.isNotEmpty) {
          merchantFrequency[merchant.name] = (merchantFrequency[merchant.name] ?? 0) + 1;
        }
      }

      // Frekuensi hari dalam seminggu
      final dayOfWeek = tx.date.weekday;
      dayOfWeekFrequency[dayOfWeek] = (dayOfWeekFrequency[dayOfWeek] ?? 0) + 1;
    }

    return FfmFrequencyAnalysis(
      period: '${start.day}/${start.month}/${start.year} - ${end.day}/${end.month}/${end.year}',
      totalTransactions: filteredTransactions.length,
      categoryFrequency: categoryFrequency,
      merchantFrequency: merchantFrequency,
      dayOfWeekFrequency: dayOfWeekFrequency,
    );
  }

  /// Analisis trend - perubahan dari waktu ke waktu
  Future<FfmTrendAnalysis> analyzeTrend({
    required String householdId,
    required DateTime start,
    required DateTime end,
    required FfmTrendType type,
  }) async {
    final query = database.select(database.transactions)
      ..where((row) =>
          row.householdId.equals(householdId) &
          row.isArchived.equals(false) &
          row.isDeleted.equals(false));

    final allTransactions = await query.get();
    
    // Filter by date range in memory (following existing pattern)
    final filteredTransactions = allTransactions.where((tx) {
      return !tx.date.isBefore(start) && tx.date.isBefore(end);
    }).toList();

    // Group by month
    final monthlyData = <String, FfmMonthlyData>{};

    for (final tx in filteredTransactions) {
      final monthKey = '${tx.date.year}-${tx.date.month.toString().padLeft(2, '0')}';
      
      if (!monthlyData.containsKey(monthKey)) {
        monthlyData[monthKey] = FfmMonthlyData(
          month: monthKey,
          income: 0,
          expense: 0,
          count: 0,
        );
      }

      final data = monthlyData[monthKey]!;
      var updatedData = data;
      if (tx.type == 'income') {
        updatedData = data.copyWith(income: data.income + tx.amount.abs());
      } else if (tx.type == 'expense') {
        updatedData = data.copyWith(expense: data.expense + tx.amount.abs());
      }
      updatedData = updatedData.copyWith(count: updatedData.count + 1);
      monthlyData[monthKey] = updatedData;
    }

    // Urutkan berdasarkan bulan
    final sortedMonths = monthlyData.keys.toList()..sort();
    final monthlyTrend = sortedMonths.map((key) => monthlyData[key]!).toList();

    // Hitung trend (naik/turun/stabil)
    String trendDirection = 'stabil';
    if (monthlyTrend.length >= 2) {
      final first = monthlyTrend.first;
      final last = monthlyTrend.last;
      
      if (type == FfmTrendType.income) {
        if (last.income > first.income * 1.1) {
          trendDirection = 'naik';
        } else if (last.income < first.income * 0.9) {
          trendDirection = 'turun';
        }
      } else if (type == FfmTrendType.expense) {
        if (last.expense > first.expense * 1.1) {
          trendDirection = 'naik';
        } else if (last.expense < first.expense * 0.9) {
          trendDirection = 'turun';
        }
      }
    }

    return FfmTrendAnalysis(
      period: '${start.day}/${start.month}/${start.year} - ${end.day}/${end.month}/${end.year}',
      type: type,
      trendDirection: trendDirection,
      monthlyData: monthlyTrend,
    );
  }

  /// Analisis perbandingan - membandingkan dua periode
  Future<FfmComparisonAnalysis> comparePeriods({
    required String householdId,
    required DateTime period1Start,
    required DateTime period1End,
    required DateTime period2Start,
    required DateTime period2End,
  }) async {
    final period1Data = await _getPeriodData(
      householdId: householdId,
      start: period1Start,
      end: period1End,
    );

    final period2Data = await _getPeriodData(
      householdId: householdId,
      start: period2Start,
      end: period2End,
    );

    // Hitung perubahan persentase
    final incomeChange = period1Data.income > 0
        ? ((period2Data.income - period1Data.income) / period1Data.income * 100).round()
        : 0;
    final expenseChange = period1Data.expense > 0
        ? ((period2Data.expense - period1Data.expense) / period1Data.expense * 100).round()
        : 0;
    final countChange = period1Data.count > 0
        ? ((period2Data.count - period1Data.count) / period1Data.count * 100).round()
        : 0;

    return FfmComparisonAnalysis(
      period1Label: '${period1Start.day}/${period1Start.month}/${period1Start.year} - ${period1End.day}/${period1End.month}/${period1End.year}',
      period2Label: '${period2Start.day}/${period2Start.month}/${period2Start.year} - ${period2End.day}/${period2End.month}/${period2End.year}',
      period1Data: period1Data,
      period2Data: period2Data,
      incomeChangePercent: incomeChange,
      expenseChangePercent: expenseChange,
      countChangePercent: countChange,
    );
  }

  /// Analisis pattern - pola pengeluaran/pemasukan yang berulang
  Future<FfmPatternAnalysis> analyzePatterns({
    required String householdId,
    required DateTime start,
    required DateTime end,
  }) async {
    final query = database.select(database.transactions)
      ..where((row) =>
          row.householdId.equals(householdId) &
          row.isArchived.equals(false) &
          row.isDeleted.equals(false));

    final allTransactions = await query.get();
    
    // Filter by date range in memory (following existing pattern)
    final filteredTransactions = allTransactions.where((tx) {
      return !tx.date.isBefore(start) && tx.date.isBefore(end);
    }).toList();

    // Analisis pattern berdasarkan kategori
    final categoryPatterns = <String, FfmCategoryPattern>{};
    final categoryAmounts = <String, List<int>>{};

    for (final tx in filteredTransactions) {
      // Get category name from categoryId
      String categoryName = 'Uncategorized';
      if (tx.categoryId != null) {
        final category = await (database.select(database.categories)
              ..where((row) =>
                  row.id.equals(tx.categoryId!) &
                  row.householdId.equals(householdId)))
            .getSingleOrNull();
        if (category != null) {
          categoryName = category.name;
        }
      }

      if (!categoryAmounts.containsKey(categoryName)) {
        categoryAmounts[categoryName] = [];
      }
      categoryAmounts[categoryName]!.add(tx.amount.abs());
    }

    // Hitung statistik per kategori
    for (final entry in categoryAmounts.entries) {
      final amounts = entry.value;
      amounts.sort();
      
      final total = amounts.reduce((a, b) => a + b);
      final average = total / amounts.length;
      final median = amounts.length % 2 == 0
          ? (amounts[amounts.length ~/ 2 - 1] + amounts[amounts.length ~/ 2]) / 2
          : amounts[amounts.length ~/ 2].toDouble();
      final min = amounts.first;
      final max = amounts.last;

      categoryPatterns[entry.key] = FfmCategoryPattern(
        category: entry.key,
        count: amounts.length,
        total: total,
        average: average.round(),
        median: median.round(),
        min: min,
        max: max,
      );
    }

    return FfmPatternAnalysis(
      period: '${start.day}/${start.month}/${start.year} - ${end.day}/${end.month}/${end.year}',
      categoryPatterns: categoryPatterns,
    );
  }

  /// Analisis period - analisis berdasarkan periode spesifik (30 hari, 90 hari, dll)
  Future<FfmPeriodAnalysis> analyzePeriod({
    required String householdId,
    required FfmAnalysisPeriod period,
    DateTime? referenceDate,
  }) async {
    final now = referenceDate ?? DateTime.now();
    final (start, end) = _getPeriodRange(period, now);

    final transactions = await (database.select(database.transactions)
          ..where((row) =>
              row.householdId.equals(householdId) &
              row.isArchived.equals(false) &
              row.isDeleted.equals(false)))
        .get();

    // Filter by date range in memory (following existing pattern)
    final filteredTransactions = transactions.where((tx) {
      return !tx.date.isBefore(start) && tx.date.isBefore(end);
    }).toList();

    var income = 0;
    var expense = 0;
    final categoryBreakdown = <String, int>{};

    for (final tx in filteredTransactions) {
      if (tx.type == 'income') {
        income += tx.amount.abs();
      } else if (tx.type == 'expense') {
        expense += tx.amount.abs();
        
        // Get category name from categoryId
        if (tx.categoryId != null) {
          final category = await (database.select(database.categories)
                ..where((row) =>
                    row.id.equals(tx.categoryId!) &
                    row.householdId.equals(householdId)))
              .getSingleOrNull();
          if (category != null) {
            categoryBreakdown[category.name] = 
                (categoryBreakdown[category.name] ?? 0) + tx.amount.abs();
          }
        }
      }
    }

    return FfmPeriodAnalysis(
      period: period,
      periodLabel: _getPeriodLabel(period),
      start: start,
      end: end,
      income: income,
      expense: expense,
      transactionCount: transactions.length,
      categoryBreakdown: categoryBreakdown,
    );
  }

  Future<FfmPeriodData> _getPeriodData({
    required String householdId,
    required DateTime start,
    required DateTime end,
  }) async {
    final transactions = await (database.select(database.transactions)
          ..where((row) =>
              row.householdId.equals(householdId) &
              row.isArchived.equals(false) &
              row.isDeleted.equals(false)))
        .get();

    // Filter by date range in memory (following existing pattern)
    final filteredTransactions = transactions.where((tx) {
      return !tx.date.isBefore(start) && tx.date.isBefore(end);
    }).toList();

    var income = 0;
    var expense = 0;
    var count = 0;

    for (final tx in filteredTransactions) {
      if (tx.type == 'income') {
        income += tx.amount.abs();
      } else if (tx.type == 'expense') {
        expense += tx.amount.abs();
      }
      count++;
    }

    return FfmPeriodData(
      income: income,
      expense: expense,
      count: count,
    );
  }

  (DateTime, DateTime) _getPeriodRange(FfmAnalysisPeriod period, DateTime now) {
    switch (period) {
      case FfmAnalysisPeriod.last7Days:
        return (now.subtract(const Duration(days: 7)), now);
      case FfmAnalysisPeriod.last30Days:
        return (now.subtract(const Duration(days: 30)), now);
      case FfmAnalysisPeriod.last90Days:
        return (now.subtract(const Duration(days: 90)), now);
      case FfmAnalysisPeriod.thisMonth:
        return (DateTime(now.year, now.month, 1), now);
      case FfmAnalysisPeriod.lastMonth:
        final lastMonth = DateTime(now.year, now.month - 1, 1);
        return (lastMonth, DateTime(now.year, now.month, 1));
      case FfmAnalysisPeriod.thisYear:
        return (DateTime(now.year, 1, 1), now);
    }
  }

  String _getPeriodLabel(FfmAnalysisPeriod period) {
    switch (period) {
      case FfmAnalysisPeriod.last7Days:
        return '7 hari terakhir';
      case FfmAnalysisPeriod.last30Days:
        return '30 hari terakhir';
      case FfmAnalysisPeriod.last90Days:
        return '90 hari terakhir';
      case FfmAnalysisPeriod.thisMonth:
        return 'bulan ini';
      case FfmAnalysisPeriod.lastMonth:
        return 'bulan lalu';
      case FfmAnalysisPeriod.thisYear:
        return 'tahun ini';
    }
  }
}

// Data models untuk analysis results

class FfmFrequencyAnalysis {
  const FfmFrequencyAnalysis({
    required this.period,
    required this.totalTransactions,
    required this.categoryFrequency,
    required this.merchantFrequency,
    required this.dayOfWeekFrequency,
  });

  final String period;
  final int totalTransactions;
  final Map<String, int> categoryFrequency;
  final Map<String, int> merchantFrequency;
  final Map<int, int> dayOfWeekFrequency;

  String get mostFrequentCategory {
    if (categoryFrequency.isEmpty) return 'tidak ada data';
    return categoryFrequency.entries
        .reduce((a, b) => a.value > b.value ? a : b)
        .key;
  }

  String get mostFrequentMerchant {
    if (merchantFrequency.isEmpty) return 'tidak ada data';
    return merchantFrequency.entries
        .reduce((a, b) => a.value > b.value ? a : b)
        .key;
  }

  int get mostFrequentDay {
    if (dayOfWeekFrequency.isEmpty) return -1;
    return dayOfWeekFrequency.entries
        .reduce((a, b) => a.value > b.value ? a : b)
        .key;
  }
}

enum FfmTrendType { income, expense, both }

class FfmTrendAnalysis {
  const FfmTrendAnalysis({
    required this.period,
    required this.type,
    required this.trendDirection,
    required this.monthlyData,
  });

  final String period;
  final FfmTrendType type;
  final String trendDirection; // 'naik', 'turun', 'stabil'
  final List<FfmMonthlyData> monthlyData;
}

class FfmMonthlyData {
  const FfmMonthlyData({
    required this.month,
    required this.income,
    required this.expense,
    required this.count,
  });

  final String month;
  final int income;
  final int expense;
  final int count;

  FfmMonthlyData copyWith({
    String? month,
    int? income,
    int? expense,
    int? count,
  }) {
    return FfmMonthlyData(
      month: month ?? this.month,
      income: income ?? this.income,
      expense: expense ?? this.expense,
      count: count ?? this.count,
    );
  }
}

class FfmComparisonAnalysis {
  const FfmComparisonAnalysis({
    required this.period1Label,
    required this.period2Label,
    required this.period1Data,
    required this.period2Data,
    required this.incomeChangePercent,
    required this.expenseChangePercent,
    required this.countChangePercent,
  });

  final String period1Label;
  final String period2Label;
  final FfmPeriodData period1Data;
  final FfmPeriodData period2Data;
  final int incomeChangePercent;
  final int expenseChangePercent;
  final int countChangePercent;
}

class FfmPeriodData {
  const FfmPeriodData({
    required this.income,
    required this.expense,
    required this.count,
  });

  final int income;
  final int expense;
  final int count;
}

class FfmPatternAnalysis {
  const FfmPatternAnalysis({
    required this.period,
    required this.categoryPatterns,
  });

  final String period;
  final Map<String, FfmCategoryPattern> categoryPatterns;
}

class FfmCategoryPattern {
  const FfmCategoryPattern({
    required this.category,
    required this.count,
    required this.total,
    required this.average,
    required this.median,
    required this.min,
    required this.max,
  });

  final String category;
  final int count;
  final int total;
  final int average;
  final int median;
  final int min;
  final int max;
}

enum FfmAnalysisPeriod {
  last7Days,
  last30Days,
  last90Days,
  thisMonth,
  lastMonth,
  thisYear,
}

class FfmPeriodAnalysis {
  const FfmPeriodAnalysis({
    required this.period,
    required this.periodLabel,
    required this.start,
    required this.end,
    required this.income,
    required this.expense,
    required this.transactionCount,
    required this.categoryBreakdown,
  });

  final FfmAnalysisPeriod period;
  final String periodLabel;
  final DateTime start;
  final DateTime end;
  final int income;
  final int expense;
  final int transactionCount;
  final Map<String, int> categoryBreakdown;

  int get netCashflow => income - expense;
  
  double? get expenseRatio => income > 0 ? expense / income : null;
  
  String get topCategory {
    if (categoryBreakdown.isEmpty) return 'tidak ada data';
    return categoryBreakdown.entries
        .reduce((a, b) => a.value > b.value ? a : b)
        .key;
  }
}