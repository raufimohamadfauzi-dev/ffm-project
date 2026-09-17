import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';

/// Read-only monthly spending habits used as a deterministic budget baseline.
///
/// This stays in the budget data boundary alongside [BudgetRepository]. It
/// reads the authoritative transaction ledger but never creates or changes a
/// budget, transaction, or category.
class BudgetHabitAnalyzer {
  BudgetHabitAnalyzer(this._database, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _database;
  final DateTime Function() _clock;

  /// Analyses completed calendar months immediately before [now].
  ///
  /// A category needs spending in at least two distinct months before it gets
  /// a recommendation. This avoids suggesting a recurring budget from a
  /// single, possibly exceptional purchase.
  Future<BudgetHabitAnalysis> analyze({
    required String householdId,
    DateTime? now,
    int historicalPeriodCount = 3,
  }) async {
    if (historicalPeriodCount < 3 || historicalPeriodCount > 12) {
      throw ArgumentError.value(
        historicalPeriodCount,
        'historicalPeriodCount',
        'Must be between 3 and 12 completed monthly periods.',
      );
    }

    final asOf = _dateOnly(now ?? _clock());
    final endExclusive = DateTime(asOf.year, asOf.month);
    final start = DateTime(
      endExclusive.year,
      endExclusive.month - historicalPeriodCount,
    );
    final categories =
        await (_database.select(_database.categories)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.type.equals('expense'),
            ))
            .get();
    final categoriesById = {
      for (final category in categories) category.id: category,
    };
    final transactions =
        await (_database.select(_database.transactions)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isArchived.equals(false) &
                  row.isDeleted.equals(false) &
                  row.type.equals('expense') &
                  row.date.isBiggerOrEqualValue(start) &
                  row.date.isSmallerThanValue(endExclusive),
            ))
            .get();

    final totalsByCategory = <String, List<int>>{};
    final sampledMonthsByCategory = <String, Set<int>>{};
    for (final transaction in transactions) {
      final categoryId = transaction.categoryId;
      if (categoryId == null ||
          !categoriesById.containsKey(categoryId) ||
          transaction.source == 'transfer' ||
          transaction.transferId != null) {
        continue;
      }
      final monthIndex = _monthDistance(start, transaction.date);
      final totals = totalsByCategory.putIfAbsent(
        categoryId,
        () => List<int>.filled(historicalPeriodCount, 0),
      );
      totals[monthIndex] += transaction.amount.abs();
      sampledMonthsByCategory
          .putIfAbsent(categoryId, () => <int>{})
          .add(monthIndex);
    }

    final recommendations = <BudgetHabitRecommendation>[];
    for (final entry in totalsByCategory.entries) {
      final sampleCount = sampledMonthsByCategory[entry.key]!.length;
      if (sampleCount < 2) continue;
      final monthlyTotals = List<int>.unmodifiable(entry.value);
      final median = _median(monthlyTotals);
      recommendations.add(
        BudgetHabitRecommendation(
          categoryId: entry.key,
          categoryName: categoriesById[entry.key]!.name,
          historicalPeriodCount: historicalPeriodCount,
          sampleCount: sampleCount,
          monthlyTotals: monthlyTotals,
          medianMonthlySpend: median,
          trend: _trendFor(monthlyTotals),
          recommendedMonthlyAmount: _roundUpSafely(median),
        ),
      );
    }
    recommendations.sort((a, b) => a.categoryName.compareTo(b.categoryName));
    return BudgetHabitAnalysis(
      householdId: householdId,
      asOf: asOf,
      historicalPeriodCount: historicalPeriodCount,
      recommendations: recommendations,
    );
  }

  int _monthDistance(DateTime start, DateTime date) =>
      (date.year - start.year) * 12 + date.month - start.month;

  int _median(List<int> values) {
    final sorted = [...values]..sort();
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[middle];
    return (sorted[middle - 1] + sorted[middle]) ~/ 2;
  }

  BudgetHabitTrend _trendFor(List<int> monthlyTotals) {
    final split = monthlyTotals.length ~/ 2;
    final earlier = _median(monthlyTotals.sublist(0, split));
    final later = _median(monthlyTotals.sublist(split));
    // Ignore minor normal variation while still reporting meaningful changes.
    final threshold = (earlier * .1).ceil();
    if (later > earlier + threshold) return BudgetHabitTrend.increasing;
    if (earlier > later + threshold) return BudgetHabitTrend.decreasing;
    return BudgetHabitTrend.stable;
  }

  int _roundUpSafely(int amount) =>
      amount == 0 ? 0 : ((amount + 999) ~/ 1000) * 1000;

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}

class BudgetHabitAnalysis {
  BudgetHabitAnalysis({
    required this.householdId,
    required this.asOf,
    required this.historicalPeriodCount,
    required List<BudgetHabitRecommendation> recommendations,
  }) : recommendations = List.unmodifiable(recommendations);

  final String householdId;
  final DateTime asOf;
  final int historicalPeriodCount;
  final List<BudgetHabitRecommendation> recommendations;
}

enum BudgetHabitTrend { increasing, stable, decreasing }

class BudgetHabitRecommendation {
  BudgetHabitRecommendation({
    required this.categoryId,
    required this.categoryName,
    required this.historicalPeriodCount,
    required this.sampleCount,
    required List<int> monthlyTotals,
    required this.medianMonthlySpend,
    required this.trend,
    required this.recommendedMonthlyAmount,
  }) : monthlyTotals = List.unmodifiable(monthlyTotals);

  final String categoryId;
  final String categoryName;
  final int historicalPeriodCount;
  final int sampleCount;
  final List<int> monthlyTotals;
  final int medianMonthlySpend;
  final BudgetHabitTrend trend;
  final int recommendedMonthlyAmount;
}
