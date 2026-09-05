import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/di/injection.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_insight_repository.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_insight.dart';
import 'package:ffm_manager/features/assistant/data/autonomous_activity_repository.dart';
import 'package:ffm_manager/features/assistant/domain/entities/autonomous_activity_models.dart';
import 'package:ffm_manager/features/assistant/presentation/pages/agent_inbox_page.dart';

void main() {
  late AppDatabase db;
  late FfmAssistantInsightRepository repo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
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

    testWidgets('Renders autonomous activities tab and activity cards', (tester) async {
      final actRepo = AutonomousActivityRepository(
        database: db,
      );
      await actRepo.recordActivity(
        AutonomousActivityRecord(
          id: 'act-test-ui',
          householdId: 'local-household',
          title: 'Pergeseran Plafon Anggaran (Rebalance)',
          description: 'Menggeser Rp 50.000 dari Belanja ke Bahan Pokok.',
          activityType: AutonomousActivityType.envelopeRebalance,
          occurredAt: DateTime(2026, 9, 5, 12, 0),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AgentInboxPage(activityRepository: actRepo),
        ),
      );
      await tester.pumpAndSettle();

      // Ketuk tab Aktivitas Otonom
      await tester.tap(find.textContaining('Aktivitas Otonom'));
      await tester.pumpAndSettle();

      expect(find.text('Pergeseran Plafon Anggaran (Rebalance)'), findsOneWidget);
      expect(find.text('Menggeser Rp 50.000 dari Belanja ke Bahan Pokok.'), findsOneWidget);
      expect(find.text('Aktif'), findsNWidgets(2));
      expect(find.text('Koreksi'), findsOneWidget);
      expect(find.text('Batalkan'), findsOneWidget);
    });
  });
}

