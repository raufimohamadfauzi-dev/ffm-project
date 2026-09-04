import '../entities/cash_flow_profile_models.dart';

/// Engine kalkulasi deterministik 100% untuk model arus kas musiman,
/// pertanian (AgroTrack), dan bisnis (Sesuai AGENTS.md).
///
/// Bebas dari dependensi UI atau AI LLM demi kepatuhan kebenaran finansial mutlak.
class FlexibleCashFlowCalculator {
  const FlexibleCashFlowCalculator();

  /// Menghitung ketahanan kas (Runway) dan batas belanja harian yang aman.
  CashFlowRunwayResult calculateRunway({
    required int effectiveLiquidCash,
    required int dailyLivingBudget,
    required int dailyOperationalBudget,
    required int daysRemainingToHarvest,
  }) {
    final totalDailyBurnRate = dailyLivingBudget + dailyOperationalBudget;

    // Kasus tanpa pengeluaran terdaftar
    if (totalDailyBurnRate <= 0) {
      final safeToSpend = daysRemainingToHarvest > 0
          ? (effectiveLiquidCash / daysRemainingToHarvest).floor()
          : effectiveLiquidCash;
      return CashFlowRunwayResult(
        runwayDays: 999,
        safeToSpendDaily: safeToSpend > 0 ? safeToSpend : 0,
        healthStatus: CycleHealthStatus.safe,
        totalDailyBurnRate: 0,
        effectiveLiquidCash: effectiveLiquidCash,
        deficitDays: 0,
        message: 'Tidak ada beban pengeluaran harian yang terdaftar.',
        recommendation:
            'Tentukan anggaran harian dapur dan operasional untuk analisa yang lebih akurat.',
      );
    }

    // Kasus kas habis / minus
    if (effectiveLiquidCash <= 0) {
      return CashFlowRunwayResult(
        runwayDays: 0,
        safeToSpendDaily: 0,
        healthStatus: CycleHealthStatus.critical,
        totalDailyBurnRate: totalDailyBurnRate,
        effectiveLiquidCash: effectiveLiquidCash,
        deficitDays: daysRemainingToHarvest > 0 ? daysRemainingToHarvest : 0,
        message: 'Kas likuid saat ini kosong atau mengalami defisit.',
        recommendation:
            'Dibutuhkan suntikan modal kerja darurat untuk menjaga kelangsungan siklus.',
      );
    }

    final runwayDays = (effectiveLiquidCash / totalDailyBurnRate).floor();
    final deficitDays =
        daysRemainingToHarvest > runwayDays ? (daysRemainingToHarvest - runwayDays) : 0;

    // Hitung safe-to-spend: Kas likuid setelah diproteksi untuk modal operasional sisa hari
    final remainingOperationalNeeded =
        dailyOperationalBudget * (daysRemainingToHarvest > 0 ? daysRemainingToHarvest : 0);
    final remainingForLiving = effectiveLiquidCash - remainingOperationalNeeded;

    final safeToSpend = daysRemainingToHarvest > 0
        ? (remainingForLiving / daysRemainingToHarvest).floor()
        : remainingForLiving;

    final safeToSpendDaily = safeToSpend > 0 ? safeToSpend : 0;

    if (daysRemainingToHarvest <= 0) {
      return CashFlowRunwayResult(
        runwayDays: runwayDays,
        safeToSpendDaily: safeToSpendDaily,
        healthStatus: CycleHealthStatus.safe,
        totalDailyBurnRate: totalDailyBurnRate,
        effectiveLiquidCash: effectiveLiquidCash,
        deficitDays: 0,
        message: 'Siklus telah mencapai tanggal target panen / pencairan.',
        recommendation:
            'Segera catat realisasi hasil panen atau pencairan untuk menutup siklus ini.',
      );
    }

    if (runwayDays >= daysRemainingToHarvest) {
      return CashFlowRunwayResult(
        runwayDays: runwayDays,
        safeToSpendDaily: safeToSpendDaily,
        healthStatus: CycleHealthStatus.safe,
        totalDailyBurnRate: totalDailyBurnRate,
        effectiveLiquidCash: effectiveLiquidCash,
        deficitDays: 0,
        message:
            'Kas aman ($runwayDays hari) mencukupi hingga estimasi panen ($daysRemainingToHarvest hari lagi).',
        recommendation:
            'Pertahankan ritme belanja keluarga maksimal Rp ${_formatNumber(safeToSpendDaily)}/hari agar modal tetap aman.',
      );
    }

    if (runwayDays >= daysRemainingToHarvest - 14) {
      return CashFlowRunwayResult(
        runwayDays: runwayDays,
        safeToSpendDaily: safeToSpendDaily,
        healthStatus: CycleHealthStatus.warning,
        totalDailyBurnRate: totalDailyBurnRate,
        effectiveLiquidCash: effectiveLiquidCash,
        deficitDays: deficitDays,
        message:
            'Waspada: Kas berpotensi menipis $deficitDays hari sebelum waktu panen tiba.',
        recommendation:
            'Batasi belanja jajan/non-esensial dapur menjadi maksimal Rp ${_formatNumber(safeToSpendDaily)}/hari.',
      );
    }

    return CashFlowRunwayResult(
      runwayDays: runwayDays,
      safeToSpendDaily: safeToSpendDaily,
      healthStatus: CycleHealthStatus.critical,
      totalDailyBurnRate: totalDailyBurnRate,
      effectiveLiquidCash: effectiveLiquidCash,
      deficitDays: deficitDays,
      message:
          'Kritis: Kas diproyeksikan defisit $deficitDays hari sebelum hasil panen cair.',
      recommendation:
          'Segera lakukan efisiensi pengeluaran atau persiapkan pencairan piutang/cadangan modal darurat.',
    );
  }

  /// Menghitung simulasi pembagian hasil panen saat siklus berhasil diselesaikan:
  /// 1. Cadangan modal siklus berikutnya (misal 40%)
  /// 2. Dana darurat & cadangan risiko (misal 20%)
  /// 3. Kas bersih keluarga yang aman dibagikan / ditabung (misal 40%)
  Map<String, int> simulateHarvestAllocation({
    required int actualHarvestRevenue,
    double nextCycleCapitalPercent = 0.45,
    double emergencyFundPercent = 0.15,
  }) {
    final nextCapital =
        (actualHarvestRevenue * nextCycleCapitalPercent).round();
    final emergency = (actualHarvestRevenue * emergencyFundPercent).round();
    final familyNetSavings = actualHarvestRevenue - nextCapital - emergency;

    return {
      'nextCycleCapital': nextCapital > 0 ? nextCapital : 0,
      'emergencyFund': emergency > 0 ? emergency : 0,
      'familyProfit': familyNetSavings > 0 ? familyNetSavings : 0,
    };
  }

  static String _formatNumber(int val) {
    return val.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]}.',
        );
  }
}
