enum FfmAssistantDataQuality { sufficient, partial, empty, insufficientPeriod }

class FfmAssistantFinancialEvidence {
  const FfmAssistantFinancialEvidence({
    required this.periodLabel,
    required this.transactionCount,
    required this.monthsWithIncome,
    required this.monthsWithExpense,
    required this.income,
    required this.expenses,
    required this.currentInstallments,
    required this.activeLiabilityCount,
    required this.quality,
  });

  final String periodLabel;
  final int transactionCount;
  final int monthsWithIncome;
  final int monthsWithExpense;
  final int income;
  final int expenses;
  final int currentInstallments;
  final int activeLiabilityCount;
  final FfmAssistantDataQuality quality;

  int get cashflowBeforeDebt => income - expenses;

  int get cashflowAfterDebt => cashflowBeforeDebt - currentInstallments;

  double? get expenseRatio => income <= 0 ? null : expenses / income;

  double? get debtServiceRatio =>
      income <= 0 ? null : currentInstallments / income;
}

class FfmAssistantLoanAffordabilityAnalysis {
  const FfmAssistantLoanAffordabilityAnalysis({
    required this.evidence,
    required this.safeDebtServiceLimit,
    required this.remainingDebtServiceCapacity,
    required this.cashflowCapacity,
    required this.recommendedNewInstallment,
    required this.shouldAvoidNewLoan,
    required this.reason,
    required this.assumptions,
  });

  final FfmAssistantFinancialEvidence evidence;
  final int safeDebtServiceLimit;
  final int remainingDebtServiceCapacity;
  final int cashflowCapacity;
  final int recommendedNewInstallment;
  final bool shouldAvoidNewLoan;
  final String reason;
  final List<String> assumptions;

  bool get hasEnoughData =>
      evidence.quality == FfmAssistantDataQuality.sufficient;

  String get qualityLabel => switch (evidence.quality) {
    FfmAssistantDataQuality.sufficient => 'data cukup',
    FfmAssistantDataQuality.partial => 'data sebagian',
    FfmAssistantDataQuality.empty => 'belum ada data',
    FfmAssistantDataQuality.insufficientPeriod => 'periode belum cukup',
  };

  factory FfmAssistantLoanAffordabilityAnalysis.calculate({
    required FfmAssistantFinancialEvidence evidence,
  }) {
    if (evidence.income <= 0) {
      return FfmAssistantLoanAffordabilityAnalysis(
        evidence: evidence,
        safeDebtServiceLimit: 0,
        remainingDebtServiceCapacity: 0,
        cashflowCapacity: 0,
        recommendedNewInstallment: 0,
        shouldAvoidNewLoan: true,
        reason: evidence.expenses > 0
            ? 'Belum ada pemasukan yang dapat dijadikan dasar perhitungan, sementara pengeluaran sudah tercatat.'
            : 'Belum ada pemasukan yang dapat dijadikan dasar perhitungan.',
        assumptions: const [
          'Nominal pinjaman pokok tidak dihitung tanpa bunga, biaya, dan tenor.',
          'Data kosong tidak boleh diganti dengan angka perkiraan kondisi pengguna.',
        ],
      );
    }

    // Batas internal konservatif aplikasi: total cicilan maksimum 30% dari
    // pemasukan. Ini adalah guardrail edukatif, bukan aturan bank atau jaminan.
    final safeLimit = (evidence.income * .30).floor();
    final remainingCapacity = safeLimit - evidence.currentInstallments;
    final cashflowCapacity = evidence.cashflowAfterDebt;
    final newInstallment = remainingCapacity <= 0 || cashflowCapacity <= 0
        ? 0
        : remainingCapacity < cashflowCapacity
        ? remainingCapacity
        : cashflowCapacity;

    final cashflowNegative = evidence.cashflowAfterDebt < 0;
    final ratioTooHigh = evidence.expenses / evidence.income >= .9;
    final avoid = cashflowNegative || ratioTooHigh || newInstallment <= 0;

    final reason = cashflowNegative
        ? 'Arus kas setelah pengeluaran dan cicilan saat ini masih negatif.'
        : ratioTooHigh
        ? 'Pengeluaran sudah menyerap sebagian besar pemasukan.'
        : newInstallment <= 0
        ? 'Ruang cicilan konservatif sudah habis setelah memperhitungkan kewajiban aktif.'
        : 'Ruang cicilan dibatasi oleh angka yang lebih rendah antara batas 30% pemasukan dan sisa cashflow setelah kewajiban aktif.';

    return FfmAssistantLoanAffordabilityAnalysis(
      evidence: evidence,
      safeDebtServiceLimit: safeLimit,
      remainingDebtServiceCapacity: remainingCapacity < 0
          ? 0
          : remainingCapacity,
      cashflowCapacity: cashflowCapacity < 0 ? 0 : cashflowCapacity,
      recommendedNewInstallment: newInstallment,
      shouldAvoidNewLoan: avoid,
      reason: reason,
      assumptions: const [
        'Batas total cicilan konservatif menggunakan 30% pemasukan bulanan.',
        'Kemampuan baru dibatasi lagi oleh cashflow setelah pengeluaran dan cicilan aktif.',
        'Transfer antar rekening tidak dianggap sebagai pemasukan atau pengeluaran.',
        'Piutang belum dianggap sebagai kas sampai benar-benar tercatat sebagai pemasukan.',
        'Nominal pokok pinjaman memerlukan bunga, biaya, dan tenor yang nyata.',
      ],
    );
  }
}

FfmAssistantDataQuality classifyFinancialDataQuality({
  required int income,
  required int expenses,
  required int transactionCount,
  required int monthsWithIncome,
  required int monthsWithExpense,
}) {
  if (income <= 0 && expenses <= 0 && transactionCount == 0) {
    return FfmAssistantDataQuality.empty;
  }
  if (monthsWithIncome == 0) return FfmAssistantDataQuality.partial;
  if (monthsWithExpense == 0) return FfmAssistantDataQuality.partial;
  return FfmAssistantDataQuality.sufficient;
}
