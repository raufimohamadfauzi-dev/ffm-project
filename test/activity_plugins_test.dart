import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/activity/domain/entities/activity_entity.dart';
import 'package:ffm_manager/features/assistant/data/plugins/ffm_activity_live_sense_plugin.dart';
import 'package:ffm_manager/features/assistant/data/plugins/ffm_activity_context_plugin.dart';
import 'package:ffm_manager/features/assistant/data/plugins/ffm_activity_guard_plugin.dart';
import 'package:ffm_manager/features/assistant/data/plugins/ffm_quick_note_actuator_plugin.dart';
import 'package:ffm_manager/features/assistant/data/plugins/ffm_sense_plugins.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_agent_harness.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = createInMemoryDatabaseForTests();
  });

  tearDown(() async {
    await db.close();
  });

  group('FfmLiveActivitySensePlugin', () {
    final plugin = FfmLiveActivitySensePlugin();

    test('returns empty message when no active sessions in snapshot', () async {
      final context = FfmHarnessContext(
        rawText: 'aktivitas sekarang',
        normalizedText: 'aktivitas sekarang',
        householdId: 'h1',
        now: DateTime.now(),
        activitySnapshot: ActivityLiveSnapshot(activeSessions: const []),
      );

      final result = await plugin.execute(context);
      expect(result, isNotNull);
      expect(result!.text, contains('belum ada aktivitas'));
      expect(result.metadata['hasActive'], isFalse);
    });

    test('returns structured root and child activity breakdown when active', () async {
      final now = DateTime(2026, 8, 25, 14, 0);
      final root = ActivitySessionEntity(
        id: 'root-1',
        householdId: 'h1',
        title: 'Perjalanan ke Palembang',
        category: 'Perjalanan',
        startedAt: DateTime(2026, 8, 25, 10, 0), // 4 jam yang lalu
        status: ActivitySessionStatus.active,
        createdAt: now,
      );

      final child = ActivitySessionEntity(
        id: 'child-1',
        householdId: 'h1',
        parentSessionId: 'root-1',
        title: 'Makan Siang',
        category: 'Makan',
        startedAt: DateTime(2026, 8, 25, 13, 30), // 30m yang lalu
        status: ActivitySessionStatus.active,
        createdAt: now,
      );

      final snapshot = ActivityLiveSnapshot(
        activeSessions: [root, child],
        revision: 2,
        lastUpdatedAt: now,
      );

      final context = FfmHarnessContext(
        rawText: 'lagi ngapain sekarang',
        normalizedText: 'lagi ngapain sekarang',
        householdId: 'h1',
        now: now,
        activitySnapshot: snapshot,
      );

      final result = await plugin.execute(context);
      expect(result, isNotNull);
      expect(result!.text, contains('Perjalanan ke Palembang'));
      expect(result.text, contains('Makan Siang'));
      expect(result.metadata['hasActive'], isTrue);
      expect(result.metadata['activeCount'], equals(2));
      expect(result.metadata['activity_payload_type'], equals('live_activity'));
    });
  });

  group('FfmActivityContextPlugin', () {
    final plugin = FfmActivityContextPlugin();

    test('computes single sub-activity duration correctly', () async {
      final now = DateTime(2026, 8, 25, 12, 30);
      final child = ActivitySessionEntity(
        id: 'child-1',
        householdId: 'h1',
        parentSessionId: 'root-1',
        title: 'Makan',
        category: 'Konsumsi',
        startedAt: DateTime(2026, 8, 25, 12, 15), // 15 menit
        status: ActivitySessionStatus.active,
        createdAt: now,
      );

      final snapshot = ActivityLiveSnapshot(
        activeSessions: [child],
        revision: 1,
        lastUpdatedAt: now,
      );

      final context = FfmHarnessContext(
        rawText: 'berapa lama makan',
        normalizedText: 'berapa lama makan',
        householdId: 'h1',
        now: now,
        activitySnapshot: snapshot,
      );

      final result = await plugin.execute(context);
      expect(result, isNotNull);
      expect(result!.text, contains('Makan'));
      expect(result.text, contains('15m'));
    });
  });

  group('FfmActivityGuardPlugin', () {
    final plugin = FfmActivityGuardPlugin();

    test('warns when user attempts to finish parent while child is still running', () async {
      final now = DateTime.now();
      final root = ActivitySessionEntity(
        id: 'root-1',
        householdId: 'h1',
        title: 'Perjalanan ke Palembang',
        category: 'Perjalanan',
        startedAt: now.subtract(const Duration(hours: 3)),
        status: ActivitySessionStatus.active,
        createdAt: now,
      );

      final child = ActivitySessionEntity(
        id: 'child-1',
        householdId: 'h1',
        parentSessionId: 'root-1',
        title: 'Makan',
        category: 'Konsumsi',
        startedAt: now.subtract(const Duration(minutes: 20)),
        status: ActivitySessionStatus.active,
        createdAt: now,
      );

      final snapshot = ActivityLiveSnapshot(
        activeSessions: [root, child],
        revision: 3,
        lastUpdatedAt: now,
      );

      final context = FfmHarnessContext(
        rawText: 'selesai perjalanan',
        normalizedText: 'selesai perjalanan',
        householdId: 'h1',
        now: now,
        activitySnapshot: snapshot,
      );

      final result = await plugin.execute(context);
      expect(result, isNotNull);
      expect(result!.isDraft, isTrue);
      expect(result.metadata['hasActiveChildren'], isTrue);
      expect(result.metadata['activeChildrenCount'], equals(1));
    });
  });

  group('FfmQuickNoteActuatorPlugin', () {
    final plugin = FfmQuickNoteActuatorPlugin();

    test('extracts structured area note draft', () async {
      final now = DateTime.now();
      final context = FfmHarnessContext(
        rawText: 'catat luas tanah 1200 m2',
        normalizedText: 'catat luas tanah 1200 m2',
        householdId: 'h1',
        now: now,
      );

      final result = await plugin.execute(context);
      expect(result, isNotNull);
      expect(result!.isDraft, isTrue);
      expect(result.metadata['category'], equals('luas_tanah'));
      expect(result.metadata['numericValue'], equals(1200.0));
      expect(result.metadata['unit'], equals('m2'));
    });

    test('calculates total area from notes: 1200 m2 + 500 m2 = 1700 m2', () async {
      final now = DateTime.now();
      final note1 = ActivityNoteEntity(
        id: 'n1',
        householdId: 'h1',
        text: 'Lahan A 1200 m2',
        category: 'luas_tanah',
        numericValue: 1200,
        unit: 'm2',
        createdAt: now,
      );
      final note2 = ActivityNoteEntity(
        id: 'n2',
        householdId: 'h1',
        text: 'Lahan B 500 m2',
        category: 'luas_tanah',
        numericValue: 500,
        unit: 'm2',
        createdAt: now,
      );

      final snapshot = ActivityLiveSnapshot(
        activeSessions: const [],
        notes: [note1, note2],
        revision: 1,
        lastUpdatedAt: now,
      );

      final context = FfmHarnessContext(
        rawText: 'berapa total luas tanah',
        normalizedText: 'berapa total luas tanah',
        householdId: 'h1',
        now: now,
        activitySnapshot: snapshot,
      );

      final result = await plugin.execute(context);
      expect(result, isNotNull);
      expect(result!.text, contains('1700 m2'));
      expect(result.metadata['total'], equals(1700.0));
      expect(result.metadata['count'], equals(2));
    });
  });

  group('FfmWeeklyActivityReportPlugin', () {
    test('separates root from nested sessions to prevent double-counting', () async {
      final plugin = FfmWeeklyActivityReportPlugin(db);
      final now = DateTime(2026, 8, 25, 18, 0);

      // Insert root session (4 hours)
      await db.into(db.activitySessions).insert(
        ActivitySessionsCompanion.insert(
          id: 'root-rep-1',
          householdId: 'local-household',
          title: 'Perjalanan Palembang',
          category: const Value('perjalanan'),
          startedAt: DateTime(2026, 8, 25, 10, 0),
          endedAt: Value(DateTime(2026, 8, 25, 14, 0)),
          status: const Value('completed'),
          createdAt: now,
          updatedAt: Value(now),
        ),
      );

      // Insert nested child session (1 hour inside root)
      await db.into(db.activitySessions).insert(
        ActivitySessionsCompanion.insert(
          id: 'child-rep-1',
          householdId: 'local-household',
          parentSessionId: const Value('root-rep-1'),
          title: 'Makan Siang',
          category: const Value('konsumsi'),
          startedAt: DateTime(2026, 8, 25, 12, 0),
          endedAt: Value(DateTime(2026, 8, 25, 13, 0)),
          status: const Value('completed'),
          createdAt: now,
          updatedAt: Value(now),
        ),
      );

      final context = FfmHarnessContext(
        rawText: 'laporan aktivitas',
        normalizedText: 'laporan aktivitas',
        householdId: 'local-household',
        now: now,
      );

      final result = await plugin.execute(context);
      expect(result, isNotNull);
      // Total root duration should be 4 hours (240 minutes), NOT 5 hours (300 minutes)
      expect(result!.metadata['totalDurationMinutes'], equals(240));
      expect(result.metadata['rootSessionsCount'], equals(1));
      expect(result.metadata['childSessionsCount'], equals(1));
      expect(result.text, contains('tanpa double counting'));
    });
  });
}
