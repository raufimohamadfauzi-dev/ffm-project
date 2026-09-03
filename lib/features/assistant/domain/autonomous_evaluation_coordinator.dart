import 'dart:async';
import '../../../core/database/app_database.dart';
import '../../reminder/data/services/reminder_notification_service.dart';
import '../data/ffm_assistant_insight_repository.dart';
import 'detectors/anomaly_spike_detector.dart';
import 'detectors/debt_service_ratio_detector.dart';
import 'detectors/goal_progress_risk_detector.dart';
import 'detectors/intelligent_envelope_rebalance_detector.dart';
import 'detectors/micro_expense_leak_detector.dart';
import 'detectors/predictive_runway_detector.dart';
import 'ffm_assistant_insight.dart';
import 'ffm_proactive_delivery_policy.dart';

class AutonomousEvaluationCoordinator {
  AutonomousEvaluationCoordinator({
    required AppDatabase database,
    required FfmAssistantInsightRepository insightRepository,
    DateTime Function()? clock,
    this.notificationService,
    this.deliveryPolicy,
  })  : _repo = insightRepository,
        _clock = clock ?? DateTime.now,
        _runwayDetector = PredictiveRunwayDetector(database),
        _rebalanceDetector = IntelligentEnvelopeRebalanceDetector(database),
        _spikeDetector = AnomalySpikeDetector(database),
        _latteDetector = MicroExpenseLeakDetector(database),
        _dsrDetector = DebtServiceRatioDetector(database),
        _goalDetector = GoalProgressRiskDetector(database);

  static final Map<String, DateTime> _lastEvaluationTimes = {};
  static const Duration minimumEvaluationInterval = Duration(seconds: 15);

  /// Helper untuk reset debounce saat testing
  static void resetDebounce() => _lastEvaluationTimes.clear();

  final FfmAssistantInsightRepository _repo;
  final DateTime Function() _clock;
  final ReminderNotificationService? notificationService;
  final FfmProactiveDeliveryPolicy? deliveryPolicy;

  final PredictiveRunwayDetector _runwayDetector;
  final IntelligentEnvelopeRebalanceDetector _rebalanceDetector;
  final AnomalySpikeDetector _spikeDetector;
  final MicroExpenseLeakDetector _latteDetector;
  final DebtServiceRatioDetector _dsrDetector;
  final GoalProgressRiskDetector _goalDetector;

  /// Menjalankan seluruh detektor deterministik, melakukan deduplikasi,
  /// pemeringkatan prioritas, dan menyimpan insight baru ke SQLite repository.
  /// Parameter `force = true` dapat digunakan untuk melewati debounce (misal tombol manual refresh).
  Future<List<FfmAssistantInsight>> runEvaluation({
    required String householdId,
    bool force = false,
  }) async {
    final now = _clock();

    // Debounce/coalescing per household agar tidak membebani sistem
    if (!force) {
      final lastTime = _lastEvaluationTimes[householdId];
      if (lastTime != null &&
          now.difference(lastTime) < minimumEvaluationInterval) {
        return const [];
      }
    }
    _lastEvaluationTimes[householdId] = now;

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

    // Jika ada insight baru yang tersimpan, evaluasi kebijakan pengiriman notifikasi Android
    if (savedInsights.isNotEmpty &&
        notificationService != null &&
        deliveryPolicy != null) {
      for (final saved in savedInsights) {
        try {
          final shouldDeliver = await deliveryPolicy!.shouldDeliverNotification(
            saved,
            now: now,
          );
          if (shouldDeliver) {
            await notificationService!.showAssistantInsightNotification(
              insightId: saved.id,
              title: saved.title,
              summary: saved.summary,
            );
            await deliveryPolicy!.recordNotificationDelivered(now: now);
            // Batasi maksimal 1 notifikasi per siklus evaluasi agar tidak membanjiri user
            break;
          }
        } catch (_) {}
      }
    }

    return savedInsights;
  }
}
