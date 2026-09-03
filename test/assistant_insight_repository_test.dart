import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_insight_repository.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_insight.dart';

void main() {
  late AppDatabase db;
  late FfmAssistantInsightRepository repo;
  final fixedClock = DateTime(2026, 9, 3, 12, 0);

  setUp(() {
    db = createInMemoryDatabaseForTests();
    repo = FfmAssistantInsightRepository(db, clock: () => fixedClock);
  });

  tearDown(() async {
    await db.close();
  });

  group('FfmAssistantInsightRepository Tests', () {
    test('Saves insight and retrieves active insights without duplication', () async {
      final insight1 = FfmAssistantInsight(
        id: 'ins-1',
        householdId: 'house-1',
        type: FfmAssistantInsightType.runwayRisk,
        severity: FfmAssistantInsightSeverity.warning,
        priority: 85,
        confidence: 0.95,
        title: 'Laju Pengeluaran Tinggi',
        summary: 'Saldo diprediksi habis sebelum gajian.',
        evidence: {'dailyBurn': 150000, 'safeSpend': 80000},
        createdAt: fixedClock,
        dedupeKey: 'runway_risk_2026_09',
      );

      final saved = await repo.saveInsight(insight1);
      expect(saved.id, 'ins-1');

      final active = await repo.getActiveInsights(householdId: 'house-1');
      expect(active.length, 1);
      expect(active.first.title, 'Laju Pengeluaran Tinggi');
      expect(active.first.evidence['dailyBurn'], 150000);

      // Coba simpan insight kedua dengan dedupe_key yang sama
      final insightDuplicate = FfmAssistantInsight(
        id: 'ins-2',
        householdId: 'house-1',
        type: FfmAssistantInsightType.runwayRisk,
        severity: FfmAssistantInsightSeverity.warning,
        priority: 85,
        confidence: 0.95,
        title: 'Laju Pengeluaran Tinggi (Duplikat)',
        summary: 'Saldo diprediksi habis sebelum gajian.',
        evidence: {'dailyBurn': 160000},
        createdAt: fixedClock,
        dedupeKey: 'runway_risk_2026_09',
      );

      final duplicateSaved = await repo.saveInsight(insightDuplicate);
      // Harus mengembalikan insight pertama yang sudah ada (tidak terduplikasi)
      expect(duplicateSaved.id, 'ins-1');

      final activeAfter = await repo.getActiveInsights(householdId: 'house-1');
      expect(activeAfter.length, 1);
    });

    test('Transitions status: markSeen, snooze, dismiss, and markActed', () async {
      final insight = FfmAssistantInsight(
        id: 'ins-life',
        householdId: 'house-1',
        type: FfmAssistantInsightType.envelopeRebalance,
        severity: FfmAssistantInsightSeverity.caution,
        priority: 75,
        confidence: 0.90,
        title: 'Saran Rebalance',
        summary: 'Pindahkan alokasi amplop.',
        evidence: {},
        createdAt: fixedClock,
        dedupeKey: 'rebalance_1',
      );

      await repo.saveInsight(insight);

      // 1. Mark seen
      await repo.markSeen('ins-life');
      var active = await repo.getActiveInsights(householdId: 'house-1');
      expect(active.first.status, FfmAssistantInsightStatus.seen);

      // 2. Snooze for 1 day
      await repo.snooze('ins-life', const Duration(days: 1));
      active = await repo.getActiveInsights(householdId: 'house-1');
      // Karena snoozedUntil adalah besok, saat ini tidak muncul di active list
      expect(active.isEmpty, isTrue);

      // 3. Dismiss
      await repo.dismiss('ins-life');
      final all = await repo.getAllInsights(householdId: 'house-1');
      expect(all.first.status, FfmAssistantInsightStatus.dismissed);

      // 4. Mark acted
      await repo.markActed('ins-life');
      final allAfterActed = await repo.getAllInsights(householdId: 'house-1');
      expect(allAfterActed.first.status, FfmAssistantInsightStatus.acted);
    });
  });
}
