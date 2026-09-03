import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/di/injection.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_insight_repository.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_insight.dart';
import 'package:ffm_manager/features/assistant/presentation/pages/agent_inbox_page.dart';

void main() {
  late AppDatabase db;
  late FfmAssistantInsightRepository repo;

  setUp(() {
    db = createInMemoryDatabaseForTests();
    if (getIt.isRegistered<AppDatabase>()) {
      getIt.unregister<AppDatabase>();
    }
    getIt.registerSingleton<AppDatabase>(db);
    repo = FfmAssistantInsightRepository(db);
  });

  tearDown(() async {
    if (getIt.isRegistered<AppDatabase>()) {
      final database = getIt<AppDatabase>();
      await database.close();
      getIt.unregister<AppDatabase>();
    }
  });

  group('AgentInboxPage Widget Tests', () {
    testWidgets('Renders empty state when no insights exist', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AgentInboxPage(),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Laporan & Kotak Masuk Asisten'), findsOneWidget);
      expect(find.text('Kotak Masuk Bersih'), findsOneWidget);
      expect(find.text('Aktif'), findsOneWidget);
      expect(find.textContaining('Riwayat'), findsOneWidget);
    });

    testWidgets('Renders active insight card with title and expand evidence button', (tester) async {
      final now = DateTime(2026, 9, 3, 10, 0);
      await repo.saveInsight(
        FfmAssistantInsight(
          id: 'ins-test-ui',
          householdId: 'local-household',
          type: FfmAssistantInsightType.runwayRisk,
          severity: FfmAssistantInsightSeverity.warning,
          priority: 85,
          confidence: 0.95,
          title: 'Peringatan Laju Pengeluaran Sebelum Gajian',
          summary: 'Saldo diprediksi habis sebelum gajian.',
          evidence: {'daysToPayday': 12, 'safeSpend': 50000},
          suggestedAction: 'Tinjau pos pengeluaran',
          createdAt: now,
          dedupeKey: 'runway_test_ui',
        ),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: AgentInboxPage(),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Peringatan Laju Pengeluaran Sebelum Gajian'), findsOneWidget);
      expect(find.text('Saldo diprediksi habis sebelum gajian.'), findsOneWidget);
      expect(find.text('Lihat data pendukung'), findsOneWidget);
      expect(find.text('Tinjau pos pengeluaran'), findsOneWidget);

      // Ketuk lihat data pendukung
      await tester.tap(find.text('Lihat data pendukung'));
      await tester.pumpAndSettle();

      expect(find.text('Sembunyikan data pendukung'), findsOneWidget);
      expect(find.textContaining('daysToPayday:'), findsOneWidget);
    });
  });
}
