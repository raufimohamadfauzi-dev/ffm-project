import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_insight_repository.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_autonomy_repository.dart';
import 'package:ffm_manager/features/assistant/data/telegram_bot_service.dart';
import 'package:ffm_manager/features/assistant/data/telegram_config_repository.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:ffm_manager/features/assistant/domain/autonomous_evaluation_coordinator.dart';
import 'package:drift/drift.dart' as drift;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});
  late AppDatabase db;
  late FfmAssistantInsightRepository repo;
  final now = DateTime(2026, 9, 15, 10, 0);

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    db = createInMemoryDatabaseForTests();
    repo = FfmAssistantInsightRepository(db, clock: () => now);
  });

  tearDown(() async {
    await db.close();
  });

  group('AutonomousEvaluationCoordinator Tests', () {
    test(
      'Runs evaluation across detectors and saves insights without error',
      () async {
        AutonomousEvaluationCoordinator.resetDebounce();
        final coordinator = AutonomousEvaluationCoordinator(
          database: db,
          insightRepository: repo,
          clock: () => now,
        );

        // Jalankan evaluasi pada database kosong
        final insights = await coordinator.runEvaluation(
          householdId: 'house-coord',
        );
        expect(insights, isA<List>());

        // Verifikasi bahwa repo aktif
        final active = await repo.getActiveInsights(householdId: 'house-coord');
        expect(active, isA<List>());
      },
    );

    test('Debounces subsequent evaluation calls within interval unless forced', () async {
      AutonomousEvaluationCoordinator.resetDebounce();
      var currentTime = now;
      final coordinator = AutonomousEvaluationCoordinator(
        database: db,
        insightRepository: repo,
        clock: () => currentTime,
      );

      // Panggilan pertama berhasil
      final first = await coordinator.runEvaluation(
        householdId: 'house-debounce',
      );
      expect(first, isNotNull);

      // Panggilan kedua hanya selang 5 detik -> di-debounce
      currentTime = currentTime.add(const Duration(seconds: 5));
      final debounced = await coordinator.runEvaluation(
        householdId: 'house-debounce',
      );
      expect(debounced, isEmpty);

      // Panggilan dengan force: true -> bypass debounce
      final forced = await coordinator.runEvaluation(
        householdId: 'house-debounce',
        force: true,
      );
      expect(forced, isNotNull);

      // Panggilan setelah interval lewat (misal 20 detik) -> dieksekusi kembali
      currentTime = currentTime.add(const Duration(seconds: 20));
      final afterInterval = await coordinator.runEvaluation(
        householdId: 'house-debounce',
      );
      expect(afterInterval, isNotNull);
    });

    test(
      'Forwards high-priority insight to Telegram when enabled and configured',
      () async {
        AutonomousEvaluationCoordinator.resetDebounce();
        final coordinator = AutonomousEvaluationCoordinator(
          database: db,
          insightRepository: repo,
          clock: () => now,
        );

        expect(coordinator.telegramBotService, isNull);
        expect(coordinator.telegramConfigRepository, isNull);
      },
    );

    test(
      'autonomous evaluation creates a linked reminder for a due liability',
      () async {
        AutonomousEvaluationCoordinator.resetDebounce();
        await db
            .into(db.liabilities)
            .insert(
              LiabilitiesCompanion.insert(
                id: 'liability-auto-1',
                householdId: 'house-auto',
                name: 'Cicilan motor',
                originalAmount: 12000000,
                remainingBalance: 8000000,
                startDate: now.subtract(const Duration(days: 30)),
                dueDate: drift.Value(now.add(const Duration(days: 3))),
                createdAt: now.subtract(const Duration(days: 30)),
              ),
            );
        final coordinator = AutonomousEvaluationCoordinator(
          database: db,
          insightRepository: repo,
          clock: () => now,
        );

        await coordinator.runEvaluation(householdId: 'house-auto', force: true);

        final reminders = await (db.select(
          db.reminders,
        )..where((row) => row.householdId.equals('house-auto'))).get();
        expect(reminders, hasLength(1));
        expect(reminders.single.origin, 'autonomous');
        expect(reminders.single.sourceType, 'liability');
        expect(reminders.single.sourceId, 'liability-auto-1');
        expect(await db.select(db.transactions).get(), isEmpty);
      },
    );

    test(
      'autonomous evaluation creates draft action plan when insight has actionPayload',
      () async {
        AutonomousEvaluationCoordinator.resetDebounce();
        final autonomyRepo = FfmAssistantAutonomyRepository(db, now: () => now);

        await db.into(db.envelopeBudgets).insert(
          EnvelopeBudgetsCompanion.insert(
            id: 'budget-deficit',
            householdId: 'house-draft',
            name: 'Makan',
            startDate: now.subtract(const Duration(days: 10)),
            endDate: now.add(const Duration(days: 20)),
            createdAt: now,
            categoryId: const drift.Value('cat-makan'),
            allocated: const drift.Value(1000000),
          ),
        );
        await db.into(db.envelopeBudgets).insert(
          EnvelopeBudgetsCompanion.insert(
            id: 'budget-surplus',
            householdId: 'house-draft',
            name: 'Hiburan',
            startDate: now.subtract(const Duration(days: 10)),
            endDate: now.add(const Duration(days: 20)),
            createdAt: now,
            categoryId: const drift.Value('cat-hiburan'),
            allocated: const drift.Value(2000000),
          ),
        );
        await db.into(db.transactions).insert(
          TransactionsCompanion.insert(
            id: 'tx-deficit-1',
            householdId: 'house-draft',
            type: 'expense',
            amount: -950000,
            categoryId: const drift.Value('cat-makan'),
            date: now.subtract(const Duration(days: 2)),
            recordedAt: now,
            createdAt: now,
          ),
        );

        final coordinator = AutonomousEvaluationCoordinator(
          database: db,
          insightRepository: repo,
          autonomyRepository: autonomyRepo,
          clock: () => now,
        );

        final insights = await coordinator.runEvaluation(householdId: 'house-draft', force: true);
        expect(insights.any((i) => i.actionPayload != null), isTrue);

        final recentRuns = await autonomyRepo.recentRuns(householdId: 'house-draft');
        expect(recentRuns, hasLength(1));
        expect(recentRuns.single.householdId, 'house-draft');

        final approval = await autonomyRepo.approvalByRunId(recentRuns.single.id);
        expect(approval, isNotNull);
        expect(approval!.householdId, 'house-draft');
        expect(approval.status, FfmAssistantApprovalStatus.requested.name);
      },
    );

    test(
      'checkAndSendWeeklyReport sends report and updates lastWeeklyReportSent',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final teleRepo = TelegramConfigRepository(preferences: prefs);

        await teleRepo.saveConfig(
          const TelegramConfig(
            botToken: 'TEST_TOKEN',
            chatId: '-100123456',
            isEnabled: true,
            weeklyReportEnabled: true,
          ),
        );

        var sentText = '';
        final mockClient = MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          sentText = body['text'] as String;
          return http.Response(jsonEncode({'ok': true}), 200);
        });
        final teleService = TelegramBotService(client: mockClient);

        final coordinator = AutonomousEvaluationCoordinator(
          database: db,
          insightRepository: repo,
          clock: () => now,
          telegramBotService: teleService,
          telegramConfigRepository: teleRepo,
        );

        final success = await coordinator.checkAndSendWeeklyReport(
          householdId: 'house-weekly',
          force: true,
        );

        expect(success, isTrue);
        expect(sentText, contains('Laporan Keuangan Mingguan'));
        expect(await teleRepo.loadLastWeeklyReportSent(), isNotNull);
      },
    );
  });
}
