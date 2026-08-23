import 'ffm_assistant_models.dart';

class FfmAssistantRecommendationFacts {
  const FfmAssistantRecommendationFacts({
    this.budgetUsedRatio,
    this.cashflowAmount,
    this.goalProgressRatio,
    this.upcomingRecurringCount = 0,
    this.unusualTransactionCount = 0,
    this.sourceLabel = 'data lokal FFM',
  });

  final double? budgetUsedRatio;
  final int? cashflowAmount;
  final double? goalProgressRatio;
  final int upcomingRecurringCount;
  final int unusualTransactionCount;
  final String sourceLabel;
}

class FfmAssistantRecommendation {
  const FfmAssistantRecommendation({
    required this.id,
    required this.title,
    required this.facts,
    required this.insight,
    required this.suggestedActions,
    required this.risk,
    required this.expiresAt,
    this.destination,
  });

  final String id;
  final String title;
  final Map<String, Object?> facts;
  final String insight;
  final List<String> suggestedActions;
  final String risk;
  final DateTime expiresAt;
  final FfmAssistantDestination? destination;
}

/// Rule engine read-only. Tidak pernah memanggil mutation atau menyimpan data.
class FfmAssistantRecommendationService {
  const FfmAssistantRecommendationService();

  List<FfmAssistantRecommendation> generate(
    FfmAssistantRecommendationFacts facts, {
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    final recommendations = <FfmAssistantRecommendation>[];
    if (facts.budgetUsedRatio != null && facts.budgetUsedRatio! >= 1) {
      recommendations.add(
        _recommendation(
          id: 'budget-over-limit',
          title: 'Anggaran melewati batas',
          facts: {'budgetUsedRatio': facts.budgetUsedRatio},
          insight: 'Pemakaian anggaran sudah mencapai atau melewati batas yang dipantau.',
          actions: const [
            'Baca rincian kategori',
            'Tinjau draft penyesuaian anggaran',
          ],
          risk: 'read-only',
          destination: FfmAssistantDestination.budget,
          now: current,
        ),
      );
    } else if (facts.budgetUsedRatio != null && facts.budgetUsedRatio! >= .8) {
      recommendations.add(
        _recommendation(
          id: 'budget-near-limit',
          title: 'Anggaran mendekati batas',
          facts: {'budgetUsedRatio': facts.budgetUsedRatio},
          insight: 'Pemakaian anggaran sudah mendekati batas yang dipantau.',
          actions: const [
            'Baca rincian kategori',
            'Tinjau pengeluaran berikutnya',
          ],
          risk: 'read-only',
          destination: FfmAssistantDestination.budget,
          now: current,
        ),
      );
    }
    if (facts.cashflowAmount != null && facts.cashflowAmount! < 0) {
      recommendations.add(
        _recommendation(
          id: 'negative-cashflow',
          title: 'Arus kas sedang negatif',
          facts: {'cashflowAmount': facts.cashflowAmount},
          insight:
              'Total arus kas pada periode yang dipantau lebih kecil dari nol.',
          actions: const [
            'Ringkas pemasukan dan pengeluaran',
            'Baca transaksi terbesar',
          ],
          risk: 'read-only',
          destination: FfmAssistantDestination.analysis,
          now: current,
        ),
      );
    }
    if (facts.goalProgressRatio != null && facts.goalProgressRatio! < .5) {
      recommendations.add(
        _recommendation(
          id: 'goal-behind',
          title: 'Progress target perlu ditinjau',
          facts: {'goalProgressRatio': facts.goalProgressRatio},
          insight: 'Progress target masih di bawah setengah nilai tujuan.',
          actions: const [
            'Baca progress target',
            'Siapkan draft setoran untuk ditinjau',
          ],
          risk: 'read-only',
          destination: FfmAssistantDestination.goals,
          now: current,
        ),
      );
    }
    if (facts.upcomingRecurringCount > 0) {
      recommendations.add(
        _recommendation(
          id: 'upcoming-recurring',
          title: 'Transaksi berkala akan datang',
          facts: {'upcomingRecurringCount': facts.upcomingRecurringCount},
          insight: 'Ada transaksi berkala yang perlu diperiksa sebelum tanggal berikutnya.',
          actions: const [
            'Baca jadwal recurring',
            'Siapkan draft tanpa autosave',
          ],
          risk: 'read-only',
          destination: FfmAssistantDestination.recurringTransaction,
          now: current,
        ),
      );
    }
    if (facts.unusualTransactionCount > 0) {
      recommendations.add(
        _recommendation(
          id: 'unusual-transactions',
          title: 'Transaksi tidak biasa perlu ditinjau',
          facts: {'unusualTransactionCount': facts.unusualTransactionCount},
          insight: 'Ada transaksi yang ditandai berbeda dari ringkasan pembanding lokal.',
          actions: const [
            'Baca transaksi terkait',
            'Jangan simpan perubahan tanpa preview',
          ],
          risk: 'read-only',
          destination: FfmAssistantDestination.transactions,
          now: current,
        ),
      );
    }
    return recommendations;
  }

  FfmAssistantRecommendation _recommendation({
    required String id,
    required String title,
    required Map<String, Object?> facts,
    required String insight,
    required List<String> actions,
    required String risk,
    required FfmAssistantDestination destination,
    required DateTime now,
  }) => FfmAssistantRecommendation(
    id: id,
    title: title,
    facts: facts,
    insight: insight,
    suggestedActions: actions,
    risk: risk,
    destination: destination,
    expiresAt: now.add(const Duration(hours: 12)),
  );
}
