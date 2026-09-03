import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_insight_repository.dart';
import 'package:ffm_manager/features/assistant/domain/autonomous_evaluation_coordinator.dart';

void main() {
  late AppDatabase db;
  late FfmAssistantInsightRepository repo;
  final now = DateTime(2026, 9, 15, 10, 0);

  setUp(() {
    db = createInMemoryDatabaseForTests();
    repo = FfmAssistantInsightRepository(db, clock: () => now);
  });

  tearDown(() async {
    await db.close();
  });

  group('AutonomousEvaluationCoordinator Tests', () {
    test('Runs evaluation across detectors and saves insights without error', () async {
      final coordinator = AutonomousEvaluationCoordinator(
        database: db,
        insightRepository: repo,
        clock: () => now,
      );

      // Jalankan evaluasi pada database kosong
      final insights = await coordinator.runEvaluation(householdId: 'house-coord');
      expect(insights, isA<List>());

      // Verifikasi bahwa repo aktif
      final active = await repo.getActiveInsights(householdId: 'house-coord');
      expect(active, isA<List>());
    });
  });
}
