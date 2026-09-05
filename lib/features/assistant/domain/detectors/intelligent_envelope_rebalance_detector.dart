import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/database/app_database.dart';
import '../ffm_assistant_insight.dart';
import '../ffm_assistant_models.dart';

class IntelligentEnvelopeRebalanceDetector {
  const IntelligentEnvelopeRebalanceDetector(this._db);

  final AppDatabase _db;

  /// Mendeteksi pos anggaran yang hampir habis (defisit) dan mencari pos surplus
  /// untuk diusulkan penyeimbangan zero-sum tanpa menambah beban pengeluaran.
  Future<FfmAssistantInsight?> detect({
    required String householdId,
    required DateTime now,
  }) async {
    // 1. Ambil pos anggaran bulanan yang aktif
    final allBudgets = await (_db.select(_db.envelopeBudgets)
          ..where((row) =>
              row.householdId.equals(householdId) &
              row.isActive.equals(true)))
        .get();

    final budgets = allBudgets.where((b) {
      return !now.isBefore(b.startDate) && !now.isAfter(b.endDate);
    }).toList();

    if (budgets.length < 2) return null;

    final firstStart = budgets.first.startDate;
    final lastEnd = budgets.first.endDate;

    final allTxs = await (_db.select(_db.transactions)
          ..where((row) => row.householdId.equals(householdId)))
        .get();

    final txs = allTxs.where((t) {
      return !t.isArchived &&
          !t.isDeleted &&
          !t.date.isBefore(firstStart) &&
          !t.date.isAfter(lastEnd);
    }).toList();

    // Hitung persentase berjalannya waktu periode
    final totalDuration = lastEnd.difference(firstStart).inSeconds;
    if (totalDuration <= 0) return null;
    final elapsedDuration = now.difference(firstStart).inSeconds;
    final periodElapsedRatio = (elapsedDuration / totalDuration).clamp(0.0, 1.0);

    // Ambil transfer antar-amplop yang sudah terjadi periode ini
    final envelopeTransfers = await (_db.select(_db.envelopeTransfers)
          ..where((row) => row.householdId.equals(householdId)))
        .get();

    EnvelopeBudget? deficitBudget;
    int deficitNeeded = 0;
    EnvelopeBudget? surplusBudget;
    int surplusAvailable = 0;

    for (final b in budgets) {
      int spent = 0;
      for (final tx in txs) {
        if (tx.amount < 0 && tx.categoryId != null && tx.categoryId == b.categoryId) {
          spent += tx.amount.abs();
        }
      }

      // Perhitungkan transfer masuk & keluar amplop
      int transferIn = 0;
      int transferOut = 0;
      for (final et in envelopeTransfers) {
        if (et.toEnvelopeId == b.id) transferIn += et.amount;
        if (et.fromEnvelopeId == b.id) transferOut += et.amount;
      }

      final totalLimit = b.allocated + b.rollover + transferIn - transferOut;
      if (totalLimit <= 0) continue;

      final usedRatio = spent / totalLimit;

      // Kategori A: Defisit jika >90% terpakai sebelum 75% periode waktu berjalan
      if (periodElapsedRatio < 0.75 && usedRatio >= 0.90 && deficitBudget == null) {
        deficitBudget = b;
        deficitNeeded = (spent - (totalLimit * periodElapsedRatio)).round();
        if (deficitNeeded <= 0) {
          deficitNeeded = (totalLimit * 0.2).round(); // Minimal alokasi penyelamat 20%
        }
      }

      // Kategori B: Surplus jika pemakaian masih < 40% padahal periode sudah berjalan
      if (usedRatio < 0.40 && (totalLimit - spent) > surplusAvailable) {
        surplusBudget = b;
        surplusAvailable = totalLimit - spent;
      }
    }

    if (deficitBudget != null && surplusBudget != null && deficitBudget.id != surplusBudget.id) {
      // RebalanceAmount = min(DeficitNeeded, SurplusAvailable * 0.5)
      final maxTransferFromSurplus = (surplusAvailable * 0.5).round();
      final rebalanceAmount = deficitNeeded < maxTransferFromSurplus
          ? deficitNeeded
          : maxTransferFromSurplus;

      if (rebalanceAmount >= 10000) {
        final dedupeKey = 'rebalance_${deficitBudget.id}_${surplusBudget.id}_${now.month}';

        return FfmAssistantInsight(
          id: const Uuid().v4(),
          householdId: householdId,
          type: FfmAssistantInsightType.envelopeRebalance,
          severity: FfmAssistantInsightSeverity.caution,
          priority: 75,
          confidence: 0.90,
          title: 'Saran Penyeimbangan Anggaran (Zero-Sum)',
          summary:
              'Pos "${deficitBudget.name}" sudah terpakai lebih dari 90% padahal periode baru berjalan ${(periodElapsedRatio * 100).round()}%. '
              'Anda dapat menggeser saldo Rp ${rebalanceAmount.toString()} dari pos "${surplusBudget.name}" (sisa Rp ${surplusAvailable.toString()}) '
              'agar tidak over-budget tanpa menambah beban belanja bulanan.',
          evidence: {
            'fromBudget': surplusBudget.name,
            'fromBudgetId': surplusBudget.id,
            'toBudget': deficitBudget.name,
            'toBudgetId': deficitBudget.id,
            'rebalanceAmount': rebalanceAmount,
            'surplusAvailable': surplusAvailable,
            'deficitNeeded': deficitNeeded,
            'periodElapsedPercent': (periodElapsedRatio * 100).round(),
          },
          suggestedAction: 'Terapkan Pergeseran Sekarang (1-Ketukan)',
          destination: FfmAssistantDestination.budget,
          actionPayload: {
            'type': 'envelope_transfer',
            'fromEnvelopeId': surplusBudget.id,
            'fromBudgetName': surplusBudget.name,
            'toEnvelopeId': deficitBudget.id,
            'toBudgetName': deficitBudget.name,
            'amount': rebalanceAmount,
          },
          createdAt: now,
          expiresAt: lastEnd,
          dedupeKey: dedupeKey,
          cooldownKey: 'rebalance_${deficitBudget.id}',
          status: FfmAssistantInsightStatus.newInsight,
        );
      }
    }

    return null;
  }
}
