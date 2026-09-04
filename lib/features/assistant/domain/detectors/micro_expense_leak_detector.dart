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

    final expenses = txs.where((t) {
      final isExpense = t.type == 'expense' || t.source == 'expense';
      final notIncomeOrTransfer = t.type != 'income' && t.type != 'transfer';
      return (isExpense || notIncomeOrTransfer) && t.amount.abs() > 0;
    }).toList();
    if (expenses.length < 5) return null;

    final totalExpense = expenses.fold<int>(0, (sum, t) => sum + t.amount.abs());
    if (totalExpense <= 0) return null;

    final microExpenses =
        expenses.where((t) => t.amount.abs() <= microThreshold).toList();
    if (microExpenses.length < 4) return null;

    final totalMicroExpense =
        microExpenses.fold<int>(0, (sum, t) => sum + t.amount.abs());

    // Identifikasi biaya admin transfer/top-up berulang
    final feeTxs = microExpenses.where((t) {
      final note = (t.note ?? '').toLowerCase();
      final source = (t.source ?? '').toLowerCase();
      return note.contains('admin') ||
          note.contains('biaya') ||
          source.contains('admin') ||
          note.contains('topup') ||
          note.contains('top up');
    }).toList();
    final totalFeeExpense =
        feeTxs.fold<int>(0, (sum, t) => sum + t.amount.abs());

    // Hitung rasio terhadap total pengeluaran
    final microRatio = totalMicroExpense / totalExpense;

    // Trigger jika pengeluaran mikro kumulatif >= 15% (minimal Rp 50.000),
    // biaya admin transfer terakumulasi >= Rp 10.000, atau total uang mikro >= Rp 100.000.
    final shouldTrigger =
        (microRatio >= 0.15 && totalMicroExpense >= 50000) ||
        totalFeeExpense >= 10000 ||
        totalMicroExpense >= 100000;

    if (shouldTrigger) {
      final monthlyProjected = (totalMicroExpense * 2.14).round();
      final dedupeKey = 'latte_factor_${now.year}_${now.month}_${now.day ~/ 14}';

      final feeInfo = feeTxs.isNotEmpty
          ? ' (termasuk ${feeTxs.length}x biaya admin sebesar Rp ${_formatRupiah(totalFeeExpense)})'
          : '';

      return FfmAssistantInsight(
        id: const Uuid().v4(),
        householdId: householdId,
        type: FfmAssistantInsightType.microExpenseLeak,
        severity: FfmAssistantInsightSeverity.info,
        priority: 60,
        confidence: 0.92,
        title: 'Deteksi Kebocoran Halus (Latte Factor & Biaya Mikro)',
        summary:
            'Dalam 14 hari terakhir, Anda melakukan ${microExpenses.length} transaksi kecil di bawah Rp ${_formatRupiah(microThreshold)} '
            'dengan total Rp ${_formatRupiah(totalMicroExpense)}$feeInfo (${(microRatio * 100).round()}% dari total belanja). '
            'Jika laju ini berlanjut, akumulasi bulanan diperkirakan mencapai Rp ${_formatRupiah(monthlyProjected)}. '
            'Mengontrol pos mikro ini dapat menambah saldo tabungan Anda secara nyata.',
        evidence: {
          'count': microExpenses.length,
          'microCount': microExpenses.length,
          'totalMicroExpense': totalMicroExpense,
          'totalExpense': totalExpense,
          'ratio': (microRatio * 100).round(),
          'monthlyProjected': monthlyProjected,
          'feeCount': feeTxs.length,
          'totalFeeExpense': totalFeeExpense,
        },
        suggestedAction:
            'Tinjau transaksi kecil & biaya transfer untuk menghemat hingga Rp ${_formatRupiah(monthlyProjected)}/bulan',
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

  static String _formatRupiah(int amount) {
    final str = amount.toString();
    final buf = StringBuffer();
    int count = 0;
    for (int i = str.length - 1; i >= 0; i--) {
      if (count > 0 && count % 3 == 0) buf.write('.');
      buf.write(str[i]);
      count++;
    }
    return buf.toString().split('').reversed.join();
  }
}
