import 'dart:math';

import '../../../transaction/domain/entities/transaction_entity.dart';
import '../../domain/entities/cash_flow_profile_models.dart';

/// Hasil perhitungan laju belanja harian dan proyeksi kas akhir bulan.
class BurnRateProjectionResult {
  const BurnRateProjectionResult({
    required this.currentMonthExpense,
    required this.currentMonthIncome,
    required this.elapsedDays,
    required this.daysLeftInMonth,
    required this.dailyBurnRate,
    required this.projectedFinalExpense,
    required this.projectedNetCashflow,
    required this.safeDailySpend,
    required this.isSurplus,
  });

  final int currentMonthExpense;
  final int currentMonthIncome;
  final int elapsedDays;
  final int daysLeftInMonth;

  /// Rata-rata pengeluaran per hari di bulan berjalan.
  final int dailyBurnRate;

  /// Estimasi total pengeluaran sampai hari terakhir bulan ini.
  final int projectedFinalExpense;

  /// Estimasi surplus (+) atau defisit (-) kas di akhir bulan.
  final int projectedNetCashflow;

  /// Batas pengeluaran harian yang aman untuk sisa hari agar tidak defisit.
  final int safeDailySpend;

  /// Apakah kas diproyeksikan surplus di akhir bulan.
  final bool isSurplus;
}

/// Item kebocoran pengeluaran mikro yang berulang.
class MicroExpenseLeakItem {
  const MicroExpenseLeakItem({
    required this.title,
    required this.categoryName,
    required this.frequency,
    required this.totalAmount,
    required this.averageAmount,
    required this.impactOnSavingsRate,
  });

  final String title;
  final String categoryName;
  final int frequency;
  final int totalAmount;
  final int averageAmount;

  /// Persentase serapan terhadap total pemasukan atau potensi tabungan.
  final double impactOnSavingsRate;
}

/// Pangsa kategori pengeluaran (Pareto 80/20).
class CategoryExpenseShare {
  const CategoryExpenseShare({
    required this.categoryId,
    required this.categoryName,
    required this.totalAmount,
    required this.percentage,
  });

  final String categoryId;
  final String categoryName;
  final int totalAmount;

  /// Nilai 0.0 sampai 1.0 (misal 0.35 untuk 35%).
  final double percentage;
}

/// Hasil simulasi stress-test siklus AgroTrack.
class CycleStressTestResult {
  const CycleStressTestResult({
    required this.commodityOrBusinessType,
    required this.targetHarvestDate,
    required this.delayedHarvestDate,
    required this.delayedDays,
    required this.burnRateDaily,
    required this.additionalLivingCost,
    required this.remainingRunwayDays,
    required this.isStillSafe,
    required this.message,
  });

  final String commodityOrBusinessType;
  final DateTime targetHarvestDate;
  final DateTime delayedHarvestDate;
  final int delayedDays;
  final int burnRateDaily;
  final int additionalLivingCost;
  final int remainingRunwayDays;
  final bool isStillSafe;
  final String message;
}

/// Engine intelijen finansial deterministik untuk Halaman Analisis.
///
/// Seluruh kalkulasi murni matematis (deterministik), tidak ada ketergantungan
/// pada model LLM atau jaringan luar.
class FinancialAnalysisIntelligenceEngine {
  const FinancialAnalysisIntelligenceEngine();

  /// Menghitung laju pengeluaran harian dan proyeksi kas akhir bulan.
  BurnRateProjectionResult calculateBurnRateAndProjection({
    required List<TransactionWithItems> transactions,
    required DateTime referenceDate,
    int? manualIncome,
  }) {
    final year = referenceDate.year;
    final month = referenceDate.month;
    final currentDay = max(1, referenceDate.day);

    // Total hari dalam bulan ini
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final daysLeftInMonth = max(0, daysInMonth - currentDay);

    var income = manualIncome ?? 0;
    var expense = 0;

    for (final item in transactions) {
      final t = item.transaction;
      if (t.date.year == year && t.date.month == month && t.date.day <= currentDay) {
        if (t.amount > 0 && manualIncome == null) {
          income += t.amount;
        } else if (t.amount < 0) {
          expense += t.amount.abs();
        }
      }
    }

    final dailyBurnRate = (expense / currentDay).round();
    final projectedAdditionalExpense = dailyBurnRate * daysLeftInMonth;
    final projectedFinalExpense = expense + projectedAdditionalExpense;
    final projectedNetCashflow = income - projectedFinalExpense;

    // Batas belanja harian aman untuk sisa hari
    final remainingBudget = max(0, income - expense);
    final safeDailySpend = daysLeftInMonth > 0
        ? (remainingBudget / daysLeftInMonth).round()
        : 0;

    return BurnRateProjectionResult(
      currentMonthExpense: expense,
      currentMonthIncome: income,
      elapsedDays: currentDay,
      daysLeftInMonth: daysLeftInMonth,
      dailyBurnRate: dailyBurnRate,
      projectedFinalExpense: projectedFinalExpense,
      projectedNetCashflow: projectedNetCashflow,
      safeDailySpend: safeDailySpend,
      isSurplus: projectedNetCashflow >= 0,
    );
  }

  /// Mendeteksi transaksi mikro (< threshold) yang terjadi berulang (>= minFrequency).
  List<MicroExpenseLeakItem> detectMicroExpenseLeaks({
    required List<TransactionWithItems> transactions,
    required DateTime referenceDate,
    required Map<String, String> categoryNamesById,
    int microThreshold = 50000,
    int minFrequency = 3,
    int lookbackDays = 30,
  }) {
    final cutoff = referenceDate.subtract(Duration(days: lookbackDays));

    // Filter pengeluaran mikro dalam jendela lookback
    final microTransactions = transactions.where((item) {
      final t = item.transaction;
      return t.amount < 0 &&
          t.amount.abs() <= microThreshold &&
          t.date.isAfter(cutoff) &&
          !t.date.isAfter(referenceDate);
    }).toList();

    // Hitung total pemasukan 30 hari untuk metrik impact
    var totalIncome = 0;
    for (final item in transactions) {
      final t = item.transaction;
      if (t.amount > 0 && t.date.isAfter(cutoff) && !t.date.isAfter(referenceDate)) {
        totalIncome += t.amount;
      }
    }

    // Kelompokkan berdasarkan note/partyName atau kategori
    final groups = <String, List<TransactionWithItems>>{};
    for (final item in microTransactions) {
      final t = item.transaction;
      var key = (t.note ?? t.partyName ?? '').trim().toLowerCase();
      if (key.isEmpty || key == '-' || key == 'pengeluaran') {
        key = categoryNamesById[t.categoryId ?? ''] ?? 'Lain-lain';
      }
      groups.putIfAbsent(key, () => []).add(item);
    }

    final leaks = <MicroExpenseLeakItem>[];

    groups.forEach((key, items) {
      if (items.length >= minFrequency) {
        final total = items.fold<int>(0, (sum, it) => sum + it.transaction.amount.abs());
        final avg = (total / items.length).round();
        final catId = items.first.transaction.categoryId ?? '';
        final categoryName = categoryNamesById[catId] ?? 'Umum';

        // Hitung dampak terhadap pemasukan/tabungan
        final impact = totalIncome > 0 ? (total / totalIncome) : 0.0;

        leaks.add(
          MicroExpenseLeakItem(
            title: _capitalize(key),
            categoryName: categoryName,
            frequency: items.length,
            totalAmount: total,
            averageAmount: avg,
            impactOnSavingsRate: impact,
          ),
        );
      }
    });

    // Urutkan dari total akumulasi terbesar
    leaks.sort((a, b) => b.totalAmount.compareTo(a.totalAmount));
    return leaks;
  }

  /// Menghitung pembagian kategori pengeluaran Pareto 80/20 untuk bulan berjalan.
  List<CategoryExpenseShare> calculateTopExpenseCategories({
    required List<TransactionWithItems> transactions,
    required DateTime referenceDate,
    required Map<String, String> categoryNamesById,
    int maxCategories = 4,
  }) {
    final year = referenceDate.year;
    final month = referenceDate.month;

    final categoryTotals = <String, int>{};
    var grandTotalExpense = 0;

    for (final item in transactions) {
      final t = item.transaction;
      if (t.date.year == year && t.date.month == month && t.amount < 0) {
        final amount = t.amount.abs();
        final catId = (t.categoryId != null && t.categoryId!.isNotEmpty)
            ? t.categoryId!
            : 'uncategorized';
        categoryTotals[catId] = (categoryTotals[catId] ?? 0) + amount;
        grandTotalExpense += amount;
      }
    }

    if (grandTotalExpense == 0) return const [];

    final sortedEntries = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final result = <CategoryExpenseShare>[];
    for (final entry in sortedEntries.take(maxCategories)) {
      final name = categoryNamesById[entry.key] ??
          (entry.key == 'uncategorized' ? 'Tanpa Kategori' : 'Kategori Lain');
      final percentage = entry.value / grandTotalExpense;

      result.add(
        CategoryExpenseShare(
          categoryId: entry.key,
          categoryName: name,
          totalAmount: entry.value,
          percentage: percentage,
        ),
      );
    }

    return result;
  }

  /// Menjalankan simulasi stress-test siklus panen jika tanggal panen mundur.
  CycleStressTestResult simulateCycleStressTest({
    required CashFlowProfile profile,
    required int currentLiquidCash,
    int delayedDays = 14,
  }) {
    final delayedDate = profile.targetHarvestDate.add(Duration(days: delayedDays));
    final burnRate = profile.dailyLivingBudget + profile.dailyOperationalBudget;
    final additionalLivingCost = burnRate * delayedDays;

    final newDaysRemaining = max(
      0,
      delayedDate.difference(DateTime.now()).inDays,
    );

    final newRunwayDays = burnRate > 0 ? (currentLiquidCash / burnRate).floor() : 999;
    final isStillSafe = newRunwayDays >= newDaysRemaining;

    final message = isStillSafe
        ? 'Kas likuid Anda (Rp $currentLiquidCash) masih sanggup menahan penundaan panen $delayedDays hari. Cadangan kas aman.'
        : 'Waspada! Mundur $delayedDays hari membutuhkan tambahan biaya hidup Rp $additionalLivingCost. Kas diproyeksikan defisit ${newDaysRemaining - newRunwayDays} hari sebelum panen.';

    return CycleStressTestResult(
      commodityOrBusinessType: profile.commodityOrBusinessType,
      targetHarvestDate: profile.targetHarvestDate,
      delayedHarvestDate: delayedDate,
      delayedDays: delayedDays,
      burnRateDaily: burnRate,
      additionalLivingCost: additionalLivingCost,
      remainingRunwayDays: newRunwayDays,
      isStillSafe: isStillSafe,
      message: message,
    );
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }
}
