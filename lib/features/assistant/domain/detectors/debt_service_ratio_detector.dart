import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/database/app_database.dart';
import '../ffm_assistant_insight.dart';
import '../ffm_assistant_models.dart';

class DebtServiceRatioDetector {
  const DebtServiceRatioDetector(this._db);

  final AppDatabase _db;

  /// Memantau Debt Service Ratio (DSR) atau beban cicilan/hutang terhadap pemasukan bulanan.
  /// Standar finansial sehat: DSR <= 30%. >30% waspada, >40% kritis.
  Future<FfmAssistantInsight?> detect({
    required String householdId,
    required DateTime now,
  }) async {
    // 1. Ambil seluruh kewajiban hutang/cicilan yang masih aktif
    final activeLiabilities = await (_db.select(_db.liabilities)
          ..where((row) =>
              row.householdId.equals(householdId) &
              row.isActive.equals(true)))
        .get();

    if (activeLiabilities.isEmpty) return null;

    // Hitung total cicilan/hutang yang jatuh tempo dalam 30 hari ke depan
    final thirtyDaysLater = now.add(const Duration(days: 30));
    final upcomingDebts = activeLiabilities.where((l) {
      if (l.dueDate == null) return false;
      return !l.dueDate!.isBefore(now) && !l.dueDate!.isAfter(thirtyDaysLater);
    }).toList();

    int totalMonthlyDebt = 0;
    for (final l in upcomingDebts) {
      totalMonthlyDebt += l.monthlyInstallment > 0
          ? l.monthlyInstallment
          : l.remainingBalance;
    }
    if (totalMonthlyDebt <= 0) return null;

    // 2. Hitung total pemasukan bulanan (30 hari terakhir)
    final thirtyDaysAgo = now.subtract(const Duration(days: 30));
    final allTxs = await (_db.select(_db.transactions)
          ..where((row) => row.householdId.equals(householdId)))
        .get();

    final incomeTxs = allTxs.where((t) {
      return !t.isArchived &&
          !t.isDeleted &&
          t.amount > 0 &&
          !t.date.isBefore(thirtyDaysAgo) &&
          !t.date.isAfter(now);
    }).toList();

    final totalMonthlyIncome =
        incomeTxs.fold<int>(0, (sum, t) => sum + t.amount);
    if (totalMonthlyIncome <= 0) return null;

    final dsr = totalMonthlyDebt / totalMonthlyIncome;

    if (dsr >= 0.30) {
      final isCritical = dsr >= 0.40;
      final dsrPercent = (dsr * 100).round();
      final dedupeKey = 'dsr_${now.year}_${now.month}';

      return FfmAssistantInsight(
        id: const Uuid().v4(),
        householdId: householdId,
        type: FfmAssistantInsightType.debtServiceRatio,
        severity: isCritical
            ? FfmAssistantInsightSeverity.critical
            : FfmAssistantInsightSeverity.caution,
        priority: isCritical ? 95 : 70,
        confidence: 0.95,
        title: isCritical
            ? 'Beban Cicilan Kritis (DSR $dsrPercent%)'
            : 'Peringatan Beban Cicilan (DSR $dsrPercent%)',
        summary:
            'Total kewajiban cicilan/hutang Anda bulan ini adalah Rp ${totalMonthlyDebt.toString()}, '
            'atau $dsrPercent% dari pemasukan bulanan (Rp ${totalMonthlyIncome.toString()}). '
            'Batas aman beban cicilan finansial adalah maksimal 30%. '
            '${isCritical ? 'Tunda komitmen cicilan baru dan prioritaskan pelunasan hutang berbunga tinggi.' : 'Pertahankan agar tidak menambah cicilan baru.'}',
        evidence: {
          'totalMonthlyDebt': totalMonthlyDebt,
          'totalMonthlyIncome': totalMonthlyIncome,
          'dsrPercent': dsrPercent,
          'debtCount': upcomingDebts.length,
          'isCritical': isCritical,
        },
        suggestedAction: 'Buka menu Hutang & Piutang untuk melihat rincian cicilan aktif',
        destination: FfmAssistantDestination.liabilities,
        createdAt: now,
        expiresAt: thirtyDaysLater,
        dedupeKey: dedupeKey,
        cooldownKey: 'debt_service_ratio',
        status: FfmAssistantInsightStatus.newInsight,
      );
    }

    return null;
  }
}
