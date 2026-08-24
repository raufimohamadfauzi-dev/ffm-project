import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/features/assistant/domain/ffm_assistant_recommendation.dart';

void main() {
  test(
    'recommendation memisahkan facts, insight, opsi, risiko, dan expiry',
    () {
      final now = DateTime(2026, 8, 23, 10);
      final recommendations = const FfmAssistantRecommendationService()
          .generate(
            FfmAssistantRecommendationFacts(
              budgetUsedRatio: .85,
              cashflowAmount: -250000,
              goalProgressRatio: .3,
              upcomingRecurringCount: 2,
              unusualTransactionCount: 1,
            ),
            now: now,
          );

      expect(recommendations, hasLength(5));
      expect(recommendations.map((item) => item.id).toSet(), hasLength(5));
      for (final recommendation in recommendations) {
        expect(recommendation.facts, isNotEmpty);
        expect(recommendation.insight, isNotEmpty);
        expect(recommendation.suggestedActions, isNotEmpty);
        expect(recommendation.risk, 'read-only');
        expect(recommendation.expiresAt, now.add(const Duration(hours: 12)));
      }
    },
  );

  test('budget over limit tidak menghasilkan saran near limit ganda', () {
    final recommendations = const FfmAssistantRecommendationService().generate(
      const FfmAssistantRecommendationFacts(budgetUsedRatio: 1.2),
      now: DateTime(2026, 8, 23),
    );

    expect(recommendations.map((item) => item.id), ['budget-over-limit']);
  });

  test('tanpa fakta risiko tidak ada recommendation', () {
    final recommendations = const FfmAssistantRecommendationService().generate(
      const FfmAssistantRecommendationFacts(),
      now: DateTime(2026, 8, 23),
    );

    expect(recommendations, isEmpty);
  });
}
