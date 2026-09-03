import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_insight.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_proactive_delivery_policy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FfmProactiveDeliveryPolicy Tests', () {
    late FfmProactiveDeliveryPolicy policy;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      policy = FfmProactiveDeliveryPolicy();
    });

    FfmAssistantInsight buildInsight({
      FfmAssistantInsightType type = FfmAssistantInsightType.runwayRisk,
      FfmAssistantInsightSeverity severity = FfmAssistantInsightSeverity.warning,
      int priority = 80,
      FfmAssistantInsightStatus status = FfmAssistantInsightStatus.newInsight,
    }) {
      return FfmAssistantInsight(
        id: 'test-insight-1',
        householdId: 'house-1',
        type: type,
        severity: severity,
        priority: priority,
        confidence: 0.9,
        title: 'Runway Kas Tipis',
        summary: 'Sisa runway kas keluarga diperkirakan di bawah 30 hari.',
        evidence: {'runwayDays': 20},
        dedupeKey: 'dedupe-1',
        createdAt: DateTime(2026, 9, 15, 10, 0),
        status: status,
      );
    }

    test('shouldDeliverNotification returns true for valid new high-priority insight during daytime', () async {
      final daytime = DateTime(2026, 9, 15, 14, 0); // 14:00 siang
      final insight = buildInsight();

      final result = await policy.shouldDeliverNotification(insight, now: daytime);
      expect(result, isTrue);
    });

    test('shouldDeliverNotification returns false if notifications disabled', () async {
      final daytime = DateTime(2026, 9, 15, 14, 0);
      await policy.setEnabled(false);
      final insight = buildInsight();

      final result = await policy.shouldDeliverNotification(insight, now: daytime);
      expect(result, isFalse);
    });

    test('shouldDeliverNotification returns false during quiet hours (e.g. 23:00)', () async {
      final nightTime = DateTime(2026, 9, 15, 23, 0); // 23:00 malam
      final insight = buildInsight();

      final result = await policy.shouldDeliverNotification(insight, now: nightTime);
      expect(result, isFalse);
    });

    test('shouldDeliverNotification returns false during quiet hours early morning (e.g. 05:00)', () async {
      final earlyMorning = DateTime(2026, 9, 15, 5, 0); // 05:00 pagi
      final insight = buildInsight();

      final result = await policy.shouldDeliverNotification(insight, now: earlyMorning);
      expect(result, isFalse);
    });

    test('shouldDeliverNotification respects disabled detectors', () async {
      final daytime = DateTime(2026, 9, 15, 14, 0);
      await policy.setDetectorDisabled(FfmAssistantInsightType.runwayRisk.name, true);

      final insight = buildInsight(type: FfmAssistantInsightType.runwayRisk);
      final result = await policy.shouldDeliverNotification(insight, now: daytime);
      expect(result, isFalse);

      final otherInsight = buildInsight(type: FfmAssistantInsightType.anomalySpike);
      final otherResult = await policy.shouldDeliverNotification(otherInsight, now: daytime);
      expect(otherResult, isTrue);
    });

    test('shouldDeliverNotification enforces daily limit', () async {
      final daytime = DateTime(2026, 9, 15, 14, 0);
      await policy.setDailyLimit(2);

      final insight = buildInsight();

      // Kirim 2 notifikasi pertama
      expect(await policy.shouldDeliverNotification(insight, now: daytime), isTrue);
      await policy.recordNotificationDelivered(now: daytime);

      expect(await policy.shouldDeliverNotification(insight, now: daytime), isTrue);
      await policy.recordNotificationDelivered(now: daytime);

      // Notifikasi ke-3 ditolak karena sudah mencapai limit harian
      expect(await policy.shouldDeliverNotification(insight, now: daytime), isFalse);
    });

    test('shouldDeliverNotification rejects low-priority non-critical insights', () async {
      final daytime = DateTime(2026, 9, 15, 14, 0);
      final lowPriorityInsight = buildInsight(
        priority: 40,
        severity: FfmAssistantInsightSeverity.info,
      );

      final result = await policy.shouldDeliverNotification(lowPriorityInsight, now: daytime);
      expect(result, isFalse);
    });

    test('shouldDeliverNotification rejects non-new insights', () async {
      final daytime = DateTime(2026, 9, 15, 14, 0);
      final seenInsight = buildInsight(
        status: FfmAssistantInsightStatus.seen,
      );

      final result = await policy.shouldDeliverNotification(seenInsight, now: daytime);
      expect(result, isFalse);
    });
  });
}
