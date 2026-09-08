import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../../liability/domain/services/debt_payoff_strategist_service.dart';
import '../ffm_assistant_insight.dart';
import '../ffm_assistant_models.dart';

/// Detektor deterministik yang merekomendasikan strategi percepatan pelunasan hutang
/// (Debt Snowball vs Avalanche) saat terdapat potensi surplus anggaran belanja.
class DebtPayoffAccelerationDetector {
  DebtPayoffAccelerationDetector(AppDatabase db)
      : _strategist = DebtPayoffStrategistService(db);

  final DebtPayoffStrategistService _strategist;

  Future<FfmAssistantInsight?> detect({
    required String householdId,
    required DateTime now,
  }) async {
    final liabilities = await _strategist.getAdaptiveLiabilities(
      householdId,
      now: now,
    );

    if (liabilities.isEmpty ||
        liabilities.every((l) => l.remainingBalance <= 0)) {
      return null;
    }

    final suggestedExtra =
        await _strategist.estimateSuggestedExtraPayment(householdId);
    if (suggestedExtra <= 0) return null;

    final comparison = _strategist.compareStrategies(
      liabilities: liabilities,
      extraMonthlyPayment: suggestedExtra,
      startDate: now,
    );

    // Hanya hasilkan rekomendasi jika alokasi ekstra menghasilkan penghematan bunga atau bulan
    if (comparison.monthsSavedAvalanche <= 0 &&
        comparison.interestSavedAvalanche <= 0 &&
        comparison.monthsSavedSnowball <= 0) {
      return null;
    }

    final highestDebt = List.of(liabilities)
      ..sort((a, b) => b.interestRate.compareTo(a.interestRate));
    final topDebt = highestDebt.first;

    final dedupeKey = 'debt_payoff_${now.year}_${now.month}';

    return FfmAssistantInsight(
      id: const Uuid().v4(),
      householdId: householdId,
      type: FfmAssistantInsightType.debtPayoffAcceleration,
      severity: FfmAssistantInsightSeverity.info,
      priority: 75,
      confidence: 0.90,
      title: 'Strategi Percepatan Hutang (Snowball vs Avalanche)',
      summary: comparison.recommendationText,
      evidence: {
        'suggestedExtraPayment': suggestedExtra,
        'monthsSavedAvalanche': comparison.monthsSavedAvalanche,
        'interestSavedAvalanche': comparison.interestSavedAvalanche,
        'monthsSavedSnowball': comparison.monthsSavedSnowball,
        'interestSavedSnowball': comparison.interestSavedSnowball,
        'targetLiabilityId': topDebt.id,
        'targetLiabilityName': topDebt.name,
      },
      suggestedAction: 'Terapkan Alokasi Pelunasan',
      destination: FfmAssistantDestination.liabilities,
      dedupeKey: dedupeKey,
      actionPayload: {
        'type': 'debt_payoff_allocation',
        'liabilityId': topDebt.id,
        'extraAmount': suggestedExtra,
      },
      createdAt: now,
    );
  }
}
