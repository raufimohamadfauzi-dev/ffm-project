import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/database/app_database.dart';
import '../ffm_assistant_insight.dart';
import '../ffm_assistant_models.dart';

class GoalProgressRiskDetector {
  const GoalProgressRiskDetector(this._db);

  final AppDatabase _db;

  /// Mengevaluasi risiko keterlambatan target keuangan terhadap tenggat waktu dan laju tabungan.
  Future<FfmAssistantInsight?> detect({
    required String householdId,
    required DateTime now,
  }) async {
    final activeGoals = await (_db.select(_db.goals)
          ..where((row) =>
              row.householdId.equals(householdId) &
              row.isActive.equals(true) &
              row.targetDate.isNotNull()))
        .get();

    if (activeGoals.isEmpty) return null;

    final sixtyDaysAgo = now.subtract(const Duration(days: 60));
    final allTxs = await (_db.select(_db.transactions)
          ..where((row) => row.householdId.equals(householdId)))
        .get();

    for (final goal in activeGoals) {
      if (goal.targetDate == null) continue;
      final targetDate = goal.targetDate!;

      // Lewati jika target sudah tercapai
      if (goal.currentAmount >= goal.targetAmount) continue;

      final daysRemaining = targetDate.difference(now).inDays;
      if (daysRemaining <= 0) continue;

      final monthsRemaining = (daysRemaining / 30.0);
      if (monthsRemaining <= 0.2) continue; // Terlalu dekat kurang dari 6 hari

      final shortage = goal.targetAmount - goal.currentAmount;
      final requiredMonthlyRate = (shortage / monthsRemaining).round();

      // Hitung laju setoran aktual dalam 60 hari terakhir
      final recentTxs = allTxs.where((t) {
        return !t.isArchived &&
            !t.isDeleted &&
            t.goalId == goal.id &&
            !t.date.isBefore(sixtyDaysAgo);
      }).toList();

      final totalSavedLast60Days =
          recentTxs.fold<int>(0, (sum, t) => sum + t.amount.abs());
      final currentMonthlyRate = (totalSavedLast60Days / 2).round();

      // Jika laju tabungan saat ini kurang dari 75% dari yang dibutuhkan
      if (currentMonthlyRate < (requiredMonthlyRate * 0.75)) {
        final requiredDelta = (requiredMonthlyRate - currentMonthlyRate);
        final dedupeKey = 'goal_risk_${goal.id}_${now.month}';

        return FfmAssistantInsight(
          id: const Uuid().v4(),
          householdId: householdId,
          type: FfmAssistantInsightType.goalProgressRisk,
          severity: FfmAssistantInsightSeverity.caution,
          priority: 65,
          confidence: 0.90,
          title: 'Target "${goal.name}" Berisiko Tidak Tercapai Tepat Waktu',
          summary:
              'Dengan sisa waktu ${monthsRemaining.toStringAsFixed(1)} bulan lagi, target "${goal.name}" '
              'masih kurang Rp ${shortage.toString()}. Untuk mencapai target sesuai tenggat '
              '(${targetDate.day}/${targetDate.month}/${targetDate.year}), '
              'Anda perlu menambah setoran sekitar Rp ${requiredDelta.toString()}/bulan '
              '(dari saat ini Rp ${currentMonthlyRate.toString()}/bulan menjadi Rp ${requiredMonthlyRate.toString()}/bulan).',
          evidence: {
            'goalId': goal.id,
            'goalName': goal.name,
            'targetAmount': goal.targetAmount,
            'currentAmount': goal.currentAmount,
            'shortage': shortage,
            'monthsRemaining': monthsRemaining.toStringAsFixed(1),
            'targetDate': targetDate.toIso8601String(),
            'currentMonthlyRate': currentMonthlyRate,
            'requiredMonthlyRate': requiredMonthlyRate,
            'requiredDelta': requiredDelta,
          },
          suggestedAction: 'Buka Target Keuangan untuk membuat setoran atau menyesuaikan tenggat',
          destination: FfmAssistantDestination.goals,
          createdAt: now,
          expiresAt: targetDate,
          dedupeKey: dedupeKey,
          cooldownKey: 'goal_risk_${goal.id}',
          status: FfmAssistantInsightStatus.newInsight,
        );
      }
    }

    return null;
  }
}
