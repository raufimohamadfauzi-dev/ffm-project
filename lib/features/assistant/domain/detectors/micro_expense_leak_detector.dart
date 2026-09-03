import 'package:uuid/uuid.dart';
import '../../../../core/database/app_database.dart';
import '../ffm_assistant_insight.dart';
import '../ffm_assistant_models.dart';

class MicroExpenseLeakDetector {
  const MicroExpenseLeakDetector(this._db);

  final AppDatabase _db;

  /// Mendeteksi fenomena "Latte Factor" (kebocoran halus dari pengeluaran kecil berulang < Rp 30.000).
  Future<FfmAssistantInsight?> detect({
    required String householdId,
    required DateTime now,
    int microThreshold = 30000,
  }) async {
    final fourteenDaysAgo = now.subtract(const Duration(days: 14));
    final allTxs = await (_db.select(_db.transactions)
          ..where((row) => row.householdId.equals(householdId)))
        .get();

    final txs = allTxs.where((t) {
      return !t.isArchived &&
          !t.isDeleted &&
          !t.date.isBefore(fourteenDaysAgo) &&
          !t.date.isAfter(now);
    }).toList();

    final expenses = txs.where((t) => t.amount < 0).toList();
    if (expenses.length < 5) return null;

    final totalExpense = expenses.fold<int>(0, (sum, t) => sum + t.amount.abs());
    if (totalExpense <= 0) return null;

    final microExpenses =
        expenses.where((t) => t.amount.abs() <= microThreshold).toList();
    if (microExpenses.length < 4) return null;

    final totalMicroExpense =
        microExpenses.fold<int>(0, (sum, t) => sum + t.amount.abs());

    // Hitung rasio terhadap total pengeluaran
    final microRatio = totalMicroExpense / totalExpense;

    // Trigger jika pengeluaran mikro kumulatif >= 15% dari total pengeluaran 14 hari
    // dan total uangnya minimal Rp 100.000
    if (microRatio >= 0.15 && totalMicroExpense >= 100000) {
      final monthlyProjected = (totalMicroExpense * 2).round();
      final dedupeKey = 'latte_factor_${now.year}_${now.month}_${now.day ~/ 14}';

      return FfmAssistantInsight(
        id: const Uuid().v4(),
        householdId: householdId,
        type: FfmAssistantInsightType.microExpenseLeak,
        severity: FfmAssistantInsightSeverity.info,
        priority: 55,
        confidence: 0.90,
        title: 'Deteksi Kebocoran Halus (Latte Factor)',
        summary:
            'Dalam 14 hari terakhir, Anda melakukan ${microExpenses.length} transaksi kecil (di bawah Rp ${microThreshold.toString()}) '
            'dengan total Rp ${totalMicroExpense.toString()} (${(microRatio * 100).round()}% dari total belanja). '
            'Jika berlanjut, pos pengeluaran mikro ini diperkirakan mencapai Rp ${monthlyProjected.toString()} dalam sebulan.',
        evidence: {
          'count': microExpenses.length,
          'totalMicroExpense': totalMicroExpense,
          'totalExpense': totalExpense,
          'ratio': (microRatio * 100).round(),
          'monthlyProjected': monthlyProjected,
        },
        suggestedAction: 'Tinjau transaksi kecil harian untuk evaluasi pos konsumtif',
        destination: FfmAssistantDestination.transactions,
        createdAt: now,
        expiresAt: now.add(const Duration(days: 7)),
        dedupeKey: dedupeKey,
        cooldownKey: 'micro_expense_leak',
        status: FfmAssistantInsightStatus.newInsight,
      );
    }

    return null;
  }
}
