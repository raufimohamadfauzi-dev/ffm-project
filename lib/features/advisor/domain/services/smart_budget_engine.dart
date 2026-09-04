import '../../../transaction/domain/usecases/transaction_crud_usecases.dart';

/// Hasil perhitungan baseline dinamis per kategori berdasarkan rata-rata bergerak 3 bulan.
class DynamicCategoryBaseline {
  const DynamicCategoryBaseline({
    required this.categoryName,
    required this.averageMonthlyAmount,
    required this.dataPointMonths,
  });

  final String categoryName;

  /// Rata-rata pengeluaran bulanan (Rupiah).
  final double averageMonthlyAmount;

  /// Jumlah bulan riwayat yang digunakan (1–3 bulan).
  final int dataPointMonths;
}

/// Hasil analisis laju kecepatan bakar uang (Burn Rate Velocity) & proyeksi akhir bulan.
class BurnRateAnalysis {
  const BurnRateAnalysis({
    required this.totalExpenseSoFar,
    required this.monthlyBudgetLimit,
    required this.daysElapsed,
    required this.totalDaysInMonth,
    required this.remainingDays,
    required this.dailyAverageExpense,
    required this.projectedMonthlyExpense,
    required this.safeDailySpendingLimit,
    required this.isOnTrack,
    this.projectedDepletionDate,
    required this.statusLabel,
  });

  /// Total pengeluaran bulan ini hingga hari ini (Rupiah).
  final double totalExpenseSoFar;

  /// Batas anggaran bulanan total (Rupiah).
  final double monthlyBudgetLimit;

  /// Jumlah hari yang telah berjalan dalam bulan ini.
  final int daysElapsed;

  /// Total jumlah hari dalam bulan ini (28–31 hari).
  final int totalDaysInMonth;

  /// Sisa hari dalam bulan ini.
  final int remainingDays;

  /// Rata-rata pengeluaran per hari hingga saat ini.
  final double dailyAverageExpense;

  /// Proyeksi total pengeluaran di akhir bulan berdasarkan laju belanja harian.
  final double projectedMonthlyExpense;

  /// Batas belanja harian aman agar anggaran tidak melampaui batas (Sisa Anggaran / Sisa Hari).
  final double safeDailySpendingLimit;

  /// True jika proyeksi pengeluaran masih berada di dalam batas anggaran.
  final bool isOnTrack;

  /// Tanggal estimasi anggaran akan habis jika laju belanja berlanjut (null jika aman).
  final DateTime? projectedDepletionDate;

  /// Label deskripsi status (misal: "Aman / On-Track", "Peringatan Dini", "Anggaran Habis").
  final String statusLabel;

  /// Sisa anggaran bulanan yang belum terpakai.
  double get remainingBudget => (monthlyBudgetLimit - totalExpenseSoFar).clamp(0.0, double.infinity);
}

/// Engine perhitungan anggaran pintar deterministik.
///
/// Bertanggung jawab untuk:
/// 1. Menghitung 3-Month Moving Average Dynamic Baseline per kategori.
/// 2. Menghitung Burn Rate Velocity, Proyeksi Tanggal Habis, dan Batas Belanja Harian Aman.
class SmartBudgetEngine {
  const SmartBudgetEngine();

  /// Menghitung rata-rata bergerak 3 bulan terakhir per kategori dari transaksi riil.
  List<DynamicCategoryBaseline> calculateDynamicBaselines({
    required List<TransactionEntity> transactions,
    required DateTime now,
  }) {
    final expenses = transactions.where((t) => t.isExpense && !t.isInternalTransfer).toList();
    if (expenses.isEmpty) return const [];

    // Tentukan rentang 3 bulan kalender terakhir sebelum bulan berjalan
    final monthKeys = <String>[];
    for (int i = 1; i <= 3; i++) {
      final prevMonth = DateTime(now.year, now.month - i, 1);
      monthKeys.add('${prevMonth.year}-${prevMonth.month.toString().padLeft(2, '0')}');
    }

    // Kelompokkan pengeluaran per kategori & per bulan
    final categoryMonthTotals = <String, Map<String, double>>{};

    for (final tx in expenses) {
      final txDate = tx.date;
      final key = '${txDate.year}-${txDate.month.toString().padLeft(2, '0')}';
      if (!monthKeys.contains(key)) continue;

      final rawCat = tx.category.trim();
      final cat = rawCat.isEmpty ? 'Lain-lain' : rawCat;
      categoryMonthTotals.putIfAbsent(cat, () => {});
      categoryMonthTotals[cat]![key] = (categoryMonthTotals[cat]![key] ?? 0.0) + tx.amount.toDouble();
    }

    // Hitung rata-rata bulanan per kategori
    final result = <DynamicCategoryBaseline>[];

    categoryMonthTotals.forEach((catName, monthMap) {
      if (monthMap.isEmpty) return;
      final monthsWithData = monthMap.length;
      final totalAmount = monthMap.values.fold(0.0, (sum, val) => sum + val);
      final average = totalAmount / (monthsWithData > 0 ? monthsWithData : 1);

      result.add(DynamicCategoryBaseline(
        categoryName: catName,
        averageMonthlyAmount: average,
        dataPointMonths: monthsWithData,
      ));
    });

    result.sort((a, b) => b.averageMonthlyAmount.compareTo(a.averageMonthlyAmount));
    return result;
  }

  /// Menghitung laju kecepatan bakar uang (Burn Rate) dan batas belanja harian aman.
  BurnRateAnalysis calculateBurnRate({
    required List<TransactionEntity> currentMonthExpenses,
    required double monthlyBudgetLimit,
    required DateTime now,
  }) {
    final totalSpent = currentMonthExpenses
        .where((t) => t.isExpense && !t.isInternalTransfer)
        .fold(0.0, (sum, t) => sum + t.amount.toDouble());

    final totalDaysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final daysElapsed = now.day.clamp(1, totalDaysInMonth);
    final remainingDays = (totalDaysInMonth - daysElapsed).clamp(1, totalDaysInMonth);

    final dailyAvg = totalSpent / daysElapsed;
    final projectedExpense = dailyAvg * totalDaysInMonth;

    final remainingBudget = (monthlyBudgetLimit - totalSpent).clamp(0.0, double.infinity);
    final safeDailyLimit = remainingBudget / remainingDays;

    final isOnTrack = projectedExpense <= monthlyBudgetLimit || monthlyBudgetLimit <= 0;

    DateTime? depletionDate;
    String statusLabel;

    if (monthlyBudgetLimit <= 0) {
      statusLabel = 'Tanpa Batas Anggaran';
    } else if (totalSpent >= monthlyBudgetLimit) {
      statusLabel = 'Anggaran Telah Habis';
      depletionDate = now;
    } else if (isOnTrack) {
      statusLabel = 'Aman / On-Track';
    } else {
      // Hitung proyeksi hari ke berapa anggaran akan habis
      final daysUntilDepleted = (remainingBudget / (dailyAvg > 0 ? dailyAvg : 1.0)).floor();
      depletionDate = now.add(Duration(days: daysUntilDepleted));
      statusLabel = 'Peringatan Dini: Laju Belanja Tinggi';
    }

    return BurnRateAnalysis(
      totalExpenseSoFar: totalSpent,
      monthlyBudgetLimit: monthlyBudgetLimit,
      daysElapsed: daysElapsed,
      totalDaysInMonth: totalDaysInMonth,
      remainingDays: remainingDays,
      dailyAverageExpense: dailyAvg,
      projectedMonthlyExpense: projectedExpense,
      safeDailySpendingLimit: safeDailyLimit,
      isOnTrack: isOnTrack,
      projectedDepletionDate: depletionDate,
      statusLabel: statusLabel,
    );
  }
}
