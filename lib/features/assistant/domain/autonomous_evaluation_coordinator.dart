import 'dart:async';
import '../../../core/database/app_database.dart';
import '../data/ffm_assistant_insight_repository.dart';
import 'detectors/anomaly_spike_detector.dart';
import 'detectors/debt_service_ratio_detector.dart';
import 'detectors/goal_progress_risk_detector.dart';
import 'detectors/intelligent_envelope_rebalance_detector.dart';
import 'detectors/micro_expense_leak_detector.dart';
import 'detectors/predictive_runway_detector.dart';
import 'ffm_assistant_insight.dart';

class AutonomousEvaluationCoordinator {
  AutonomousEvaluationCoordinator({
    required AppDatabase database,
    required FfmAssistantInsightRepository insightRepository,
    DateTime Function()? clock,
  })  : _repo = insightRepository,
        _clock = clock ?? DateTime.now,
        _runwayDetector = PredictiveRunwayDetector(database),
        _rebalanceDetector = IntelligentEnvelopeRebalanceDetector(database),
        _spikeDetector = AnomalySpikeDetector(database),
        _latteDetector = MicroExpenseLeakDetector(database),
        _dsrDetector = DebtServiceRatioDetector(database),
        _goalDetector = GoalProgressRiskDetector(database);

  final FfmAssistantInsightRepository _repo;
  final DateTime Function() _clock;

  final PredictiveRunwayDetector _runwayDetector;
  final IntelligentEnvelopeRebalanceDetector _rebalanceDetector;
  final AnomalySpikeDetector _spikeDetector;
  final MicroExpenseLeakDetector _latteDetector;
  final DebtServiceRatioDetector _dsrDetector;
  final GoalProgressRiskDetector _goalDetector;

  /// Menjalankan seluruh detektor deterministik, melakukan deduplikasi,
  /// pemeringkatan prioritas, dan menyimpan insight baru ke SQLite repository.
  Future<List<FfmAssistantInsight>> runEvaluation({
    required String householdId,
  }) async {
    final now = _clock();
    final candidates = <FfmAssistantInsight>[];

    // Jalankan setiap detektor secara independen dengan try/catch agar
    // kegagalan satu detektor tidak menghentikan detektor lainnya.
    try {
      final runway = await _runwayDetector.detect(householdId: householdId, now: now);
      if (runway != null) candidates.add(runway);
    } catch (_) {}

    try {
      final rebalance = await _rebalanceDetector.detect(householdId: householdId, now: now);
      if (rebalance != null) candidates.add(rebalance);
    } catch (_) {}

    try {
      final spike = await _spikeDetector.detect(householdId: householdId, now: now);
      if (spike != null) candidates.add(spike);
    } catch (_) {}

    try {
      final latte = await _latteDetector.detect(householdId: householdId, now: now);
      if (latte != null) candidates.add(latte);
    } catch (_) {}

    try {
      final dsr = await _dsrDetector.detect(householdId: householdId, now: now);
      if (dsr != null) candidates.add(dsr);
    } catch (_) {}

    try {
      final goal = await _goalDetector.detect(householdId: householdId, now: now);
      if (goal != null) candidates.add(goal);
    } catch (_) {}

    if (candidates.isEmpty) return const [];

    // Urutkan kandidat berdasarkan prioritas tertinggi
    candidates.sort((a, b) => b.priority.compareTo(a.priority));

    final savedInsights = <FfmAssistantInsight>[];

    // Simpan hanya insight yang belum aktif (deduplikasi dilakukan di repository)
    for (final candidate in candidates) {
      final existing = await _repo.findActiveByDedupeKey(
        householdId: householdId,
        dedupeKey: candidate.dedupeKey,
      );
      if (existing == null) {
        final saved = await _repo.saveInsight(candidate);
        savedInsights.add(saved);
      }
    }

    return savedInsights;
  }
}
