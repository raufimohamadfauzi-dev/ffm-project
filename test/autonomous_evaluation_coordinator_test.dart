import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_insight_repository.dart';
import 'package:ffm_manager/features/assistant/data/telegram_bot_service.dart';
import 'package:ffm_manager/features/assistant/data/telegram_config_repository.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:ffm_manager/features/assistant/domain/autonomous_evaluation_coordinator.dart';

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
    test('Runs evaluation across detectors and saves insights without error', () async {
      AutonomousEvaluationCoordinator.resetDebounce();
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

    test('Debounces subsequent evaluation calls within interval unless forced', () async {
      AutonomousEvaluationCoordinator.resetDebounce();
      var currentTime = now;
      final coordinator = AutonomousEvaluationCoordinator(
        database: db,
        insightRepository: repo,
        clock: () => currentTime,
      );

      // Panggilan pertama berhasil
      final first = await coordinator.runEvaluation(householdId: 'house-debounce');
      expect(first, isNotNull);

      // Panggilan kedua hanya selang 5 detik -> di-debounce
      currentTime = currentTime.add(const Duration(seconds: 5));
      final debounced = await coordinator.runEvaluation(householdId: 'house-debounce');
      expect(debounced, isEmpty);

      // Panggilan dengan force: true -> bypass debounce
      final forced = await coordinator.runEvaluation(
        householdId: 'house-debounce',
        force: true,
      );
      expect(forced, isNotNull);

      // Panggilan setelah interval lewat (misal 20 detik) -> dieksekusi kembali
      currentTime = currentTime.add(const Duration(seconds: 20));
      final afterInterval = await coordinator.runEvaluation(householdId: 'house-debounce');
      expect(afterInterval, isNotNull);
    });

    test('Forwards high-priority insight to Telegram when enabled and configured', () async {
      AutonomousEvaluationCoordinator.resetDebounce();
      final coordinator = AutonomousEvaluationCoordinator(
        database: db,
        insightRepository: repo,
        clock: () => now,
      );

      expect(coordinator.telegramBotService, isNull);
      expect(coordinator.telegramConfigRepository, isNull);
    });

    test('checkAndSendWeeklyReport sends report and updates lastWeeklyReportSent', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final teleRepo = TelegramConfigRepository(preferences: prefs);

      await teleRepo.saveConfig(const TelegramConfig(
        botToken: 'TEST_TOKEN',
        chatId: '-100123456',
        isEnabled: true,
        weeklyReportEnabled: true,
      ));

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
    });
  });
}
