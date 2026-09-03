import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/database/app_database.dart';
import '../ffm_assistant_insight.dart';
import '../ffm_assistant_models.dart';

class PredictiveRunwayDetector {
  const PredictiveRunwayDetector(this._db);

  final AppDatabase _db;

  /// Mendeteksi risiko kehabisan uang tunai sebelum tanggal gajian berikutnya.
  Future<FfmAssistantInsight?> detect({
    required String householdId,
    required DateTime now,
    int defaultPaydayDay = 25,
  }) async {
    // 1. Hitung saldo likuid (rekening aktif non-arsip bertipe bank, ewallet, cash)
    final accounts = await (_db.select(_db.accounts)
          ..where((row) =>
              row.householdId.equals(householdId) &
              row.isActive.equals(true) &
              row.isArchived.equals(false)))
        .get();

    if (accounts.isEmpty) return null;

    final allTxs = await (_db.select(_db.transactions)
          ..where((row) => row.householdId.equals(householdId)))
        .get();

    final txs = allTxs
        .where((row) => !row.isArchived && !row.isDeleted)
        .toList(growable: false);

    int liquidCash = 0;
    for (final acc in accounts) {
      int balance = acc.openingBalance;
      for (final tx in txs) {
        if (tx.accountId == acc.id) {
          balance += tx.amount;
        }
      }
      liquidCash += balance;
    }

    if (liquidCash <= 0) return null;

    // 2. Tentukan tanggal gajian berikutnya
    DateTime nextPayday = DateTime(now.year, now.month, defaultPaydayDay);
    if (!now.isBefore(nextPayday)) {
      nextPayday = DateTime(
        now.month == 12 ? now.year + 1 : now.year,
        now.month == 12 ? 1 : now.month + 1,
        defaultPaydayDay,
      );
    }

    final daysToPayday = nextPayday.difference(now).inDays;
    if (daysToPayday <= 0) return null;

    // 3. Hitung kewajiban tagihan/cicilan yang belum jatuh tempo sebelum gajian
    final liabilities = await (_db.select(_db.liabilities)
          ..where((row) =>
              row.householdId.equals(householdId) &
              row.isActive.equals(true)))
        .get();

    final upcomingLiabilities = liabilities.where((l) {
      if (l.dueDate == null) return false;
      return !l.dueDate!.isBefore(now) && !l.dueDate!.isAfter(nextPayday);
    });

    int upcomingFixedBills = 0;
    for (final bill in upcomingLiabilities) {
      upcomingFixedBills += bill.monthlyInstallment > 0
          ? bill.monthlyInstallment
          : bill.remainingBalance;
    }

    final spendableCash = liquidCash - upcomingFixedBills;
    if (spendableCash <= 0) return null;

    final safeDailySpend = (spendableCash / daysToPayday).round();
    if (safeDailySpend <= 0) return null;

    // 4. Hitung pengeluaran aktual 14 hari terakhir untuk laju belanja harian
    final fourteenDaysAgo = now.subtract(const Duration(days: 14));
    final recentExpenses = txs.where((t) =>
        t.amount < 0 &&
        t.date.isAfter(fourteenDaysAgo) &&
        !t.date.isAfter(now));

    final totalRecentSpent =
        recentExpenses.fold<int>(0, (sum, t) => sum + t.amount.abs());
    final currentDailyBurn = (totalRecentSpent / 14).round();

    // Trigger jika pengeluaran harian > 1.25x dari batas aman belanja harian
    if (currentDailyBurn > (safeDailySpend * 1.25)) {
      final daysUntilRunwayEmpty = (spendableCash / currentDailyBurn).floor();
      final estimatedCashoutDate = now.add(Duration(days: daysUntilRunwayEmpty));
      final daysShort = daysToPayday - daysUntilRunwayEmpty;

      if (daysShort <= 0) return null;

      final dedupeMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';

      return FfmAssistantInsight(
        id: const Uuid().v4(),
        householdId: householdId,
        type: FfmAssistantInsightType.runwayRisk,
        severity: FfmAssistantInsightSeverity.warning,
        priority: 85,
        confidence: 0.95,
        title: 'Peringatan Laju Pengeluaran Sebelum Gajian',
        summary:
            'Laju pengeluaran Anda saat ini rata-rata Rp ${currentDailyBurn.toString()}/hari. '
            'Jika berlanjut, sisa saldo tunai Rp ${spendableCash.toString()} diprediksi habis sekitar tanggal '
            '${estimatedCashoutDate.day}/${estimatedCashoutDate.month}, yaitu $daysShort hari sebelum gajian. '
            'Batas belanja harian aman adalah Rp ${safeDailySpend.toString()}/hari.',
        evidence: {
          'liquidCash': liquidCash,
          'upcomingFixedBills': upcomingFixedBills,
          'spendableCash': spendableCash,
          'daysToPayday': daysToPayday,
          'currentDailyBurn': currentDailyBurn,
          'safeDailySpend': safeDailySpend,
          'daysShort': daysShort,
          'estimatedCashoutDate': estimatedCashoutDate.toIso8601String(),
        },
        suggestedAction: 'Tinjau pos pengeluaran terbesar untuk kurangi belanja non-esensial',
        destination: FfmAssistantDestination.analysis,
        createdAt: now,
        expiresAt: nextPayday,
        dedupeKey: 'runway_risk_$dedupeMonth',
        cooldownKey: 'runway_risk',
        status: FfmAssistantInsightStatus.newInsight,
      );
    }

    return null;
  }
}
