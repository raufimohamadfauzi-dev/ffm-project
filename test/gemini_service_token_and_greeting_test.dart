import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/network/gemini_service.dart';
import 'package:ffm_manager/core/network/supabase_config.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_financial_snapshot_service.dart';
import 'package:ffm_manager/features/assistant/data/plugins/ffm_logic_plugins.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_planner.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/hijri/domain/hijri_calendar_service.dart';

void main() {
  group('Item 08: GeminiUsageMetadata extraction', () {
    test('ekstrak usageMetadata dari response body Gemini v1beta', () {
      final jsonResponse = {
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': 'Halo! Ada yang bisa saya bantu?'}
              ]
            }
          }
        ],
        'usageMetadata': {
          'promptTokenCount': 450,
          'candidatesTokenCount': 120,
          'totalTokenCount': 570,
        }
      };
      final metadata = GeminiUsageMetadata.fromJson(
        jsonResponse['usageMetadata'] as Map<String, dynamic>,
      );
      expect(metadata.promptTokenCount, 450);
      expect(metadata.candidatesTokenCount, 120);
      expect(metadata.totalTokenCount, 570);
      expect(metadata.toJson()['totalTokenCount'], 570);
    });
  });

  group('Item 05: Greeting intent & Action Plan without read.transactions', () {
    test('Gemini Cloud intent tanpa draft tidak memicu prerequisite read.transactions', () {
      const planner = FfmAssistantActionPlanner();
      final greetingIntent = FfmAssistantIntent(
        rawText: 'Hallo',
        normalizedText: 'hallo',
        type: FfmAssistantIntentType.help,
        confidence: 1.0,
        response: 'Halo! Ada yang bisa saya bantu?',
        responseOrigin: FfmAssistantResponseOrigin.geminiCloud,
      );

      final plan = planner.planFor(greetingIntent);
      // Sapaan / help tanpa navigasi dan tanpa draft tidak boleh menghasilkan steps
      expect(plan?.steps.isEmpty ?? true, isTrue);
    });

    test('Gemini Cloud intent queryData tanpa draft tidak memicu prerequisite read.transactions', () {
      const planner = FfmAssistantActionPlanner();
      final queryIntent = FfmAssistantIntent(
        rawText: 'Berapa inflasi tahun ini?',
        normalizedText: 'berapa inflasi tahun ini',
        type: FfmAssistantIntentType.queryData,
        confidence: 1.0,
        response: 'Inflasi tahun ini sekitar 2.5%.',
        responseOrigin: FfmAssistantResponseOrigin.geminiCloud,
      );

      final plan = planner.planFor(queryIntent);
      expect(plan?.steps.isEmpty ?? true, isTrue);
    });

    test('Local agent queryData tetap dapat memicu read.transactions', () {
      const planner = FfmAssistantActionPlanner();
      final localIntent = FfmAssistantIntent(
        rawText: 'Lihat transaksi',
        normalizedText: 'lihat transaksi',
        type: FfmAssistantIntentType.queryData,
        confidence: 1.0,
        response: 'Berikut transaksi Anda.',
        responseOrigin: FfmAssistantResponseOrigin.agentOrchestrator,
      );

      final plan = planner.planFor(localIntent);
      expect(plan, isNotNull);
      expect(plan!.steps.any((s) => s.capabilityId == 'read.transactions'), isTrue);
    });
  });

  group('Item 06: Emergency Fund Logic Plugin & Goals Digest', () {
    late AppDatabase database;
    late FfmAssistantFinancialSnapshotService snapshot;

    setUp(() {
      database = createInMemoryDatabaseForTests();
      snapshot = FfmAssistantFinancialSnapshotService(
        database,
        HijriCalendarService(database),
      );
    });

    tearDown(() async {
      await database.close();
    });

    test('FfmEmergencyFundLogicPlugin mengenali trigger target keuangan dana darurat', () {
      final plugin = FfmEmergencyFundLogicPlugin(database);
      expect(plugin.canHandle('target keuangan dana darurat'), isTrue);
      expect(plugin.canHandle('berapa bulan dana darurat'), isTrue);
      expect(plugin.canHandle('hitung dana darurat'), isTrue);
    });

    test('buildGoalsDigest memperkaya output dengan patokan pengeluaran rata-rata bulanan', () async {
      final now = DateTime(2026, 8, 15);
      // Insert pengeluaran 3 bulan terakhir
      await database.into(database.transactions).insert(
            TransactionsCompanion.insert(
              id: 'tx-exp-1',
              householdId: AppContext.householdId,
              type: 'expense',
              amount: 6000000,
              date: DateTime(2026, 7, 10),
              recordedAt: now,
              createdAt: now,
            ),
          );

      // Insert target keuangan
      await database.into(database.goals).insert(
            GoalsCompanion.insert(
              id: 'goal-1',
              householdId: AppContext.householdId,
              name: 'Dana Darurat Keluarga',
              targetAmount: 36000000,
              currentAmount: const Value(12000000),
              createdAt: now,
            ),
          );

      final digest = await snapshot.buildGoalsDigest(
        householdId: AppContext.householdId,
        now: now,
      );

      expect(digest, contains('Dana Darurat Keluarga'));
      expect(digest, contains('target=36000000'));
      expect(digest, contains('saved=12000000'));
      expect(digest, contains('Patokan Dana Darurat'));
    });
  });

  group('Gemini Daily Quota & Pacific Midnight Calculations', () {
    test('isPacificDst mendeteksi musim panas (PDT) vs musim dingin (PST)', () {
      // Juli adalah musim panas (PDT)
      expect(SupabaseConfig.isPacificDst(DateTime.utc(2026, 7, 15, 12)), isTrue);
      // Januari adalah musim dingin (PST)
      expect(SupabaseConfig.isPacificDst(DateTime.utc(2026, 1, 15, 12)), isFalse);
    });

    test('computeNextPacificMidnight menghitung tengah malam PT berikutnya dengan akurat', () {
      // 4 September 2026 pukul 05:00 UTC = 22:00 PDT 3 September
      final nowUtc = DateTime.utc(2026, 9, 4, 5, 0);
      final nextMidnight = SupabaseConfig.computeNextPacificMidnight(nowUtc);

      // Tengah malam berikutnya adalah 4 September 00:00 PDT = 07:00 UTC
      expect(nextMidnight, DateTime.utc(2026, 9, 4, 7, 0));
      expect(nextMidnight.difference(nowUtc).inHours, 2);

      // 4 September 2026 pukul 08:00 UTC = 01:00 PDT 4 September (sudah lewat tengah malam)
      final afterMidnightUtc = DateTime.utc(2026, 9, 4, 8, 0);
      final nextMidnightTomorrow = SupabaseConfig.computeNextPacificMidnight(afterMidnightUtc);

      // Tengah malam berikutnya adalah 5 September 07:00 UTC
      expect(nextMidnightTomorrow, DateTime.utc(2026, 9, 5, 7, 0));
      expect(nextMidnightTomorrow.difference(afterMidnightUtc).inHours, 23);
    });

    test('GeminiDailyQuotaSnapshot menghitung sisa, ratio, dan countdown dengan benar', () {
      final snapshot = GeminiDailyQuotaSnapshot(
        requestsUsed: 12,
        requestsLimit: 1500,
        promptTokens: 5400,
        candidateTokens: 1200,
        totalTokens: 6600,
        nextResetTime: DateTime.utc(2026, 9, 4, 7),
        timeUntilReset: const Duration(hours: 3, minutes: 45),
      );

      expect(snapshot.requestsRemaining, 1488);
      expect(snapshot.usageRatio, closeTo(12 / 1500, 0.0001));
      expect(snapshot.isExhausted, isFalse);
      expect(snapshot.formattedCountdown, '3 jam 45 menit');
    });
  });
}
