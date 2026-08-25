import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/database/audit_logger.dart';
import 'package:ffm_manager/features/activity/data/repositories/activity_repository.dart';
import 'package:ffm_manager/features/activity/domain/activity_context_bridge.dart';
import 'package:ffm_manager/features/activity/domain/activity_voice.dart';
import 'package:ffm_manager/features/activity/domain/entities/activity_entity.dart';
import 'package:ffm_manager/features/activity/domain/services/activity_application_service.dart';
import 'package:ffm_manager/features/activity/presentation/bloc/activity_bloc.dart';

void main() {
  late AppDatabase db;
  late ActivityRepository repo;
  late ActivityBloc bloc;
  late ActivityApplicationService appService;

  setUp(() async {
    db = createInMemoryDatabaseForTests();
    repo = ActivityRepository(db, AuditLogger(db));
    bloc = ActivityBloc(repo);
    appService = ActivityApplicationService(
      repository: repo,
      activityBloc: bloc,
    );
    await bloc.load();
  });

  tearDown(() async {
    await bloc.close();
    await db.close();
  });

  group('ActivityLiveSnapshot & Hierarchy Helpers', () {
    test('correctly identifies root, children, and last checkpoints', () {
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

      final child1 = ActivitySessionEntity(
        id: 'child-1',
        householdId: 'h1',
        parentSessionId: 'root-1',
        title: 'Makan di Rumah Makan',
        category: 'Konsumsi',
        startedAt: now.subtract(const Duration(minutes: 30)),
        status: ActivitySessionStatus.active,
        createdAt: now,
      );

      final cp1 = ActivityCheckpointEntity(
        id: 'cp-1',
        sessionId: 'root-1',
        sequence: 1,
        label: 'Rest Area KM 50',
        occurredAt: now.subtract(const Duration(hours: 2)),
        createdAt: now,
      );
      final cp2 = ActivityCheckpointEntity(
        id: 'cp-2',
        sessionId: 'root-1',
        sequence: 2,
        label: 'Masuk Kapal Merak',
        occurredAt: now.subtract(const Duration(hours: 1)),
        createdAt: now,
      );

      final note = ActivityNoteEntity(
        id: 'note-1',
        householdId: 'h1',
        text: 'Luas tanah 1200 m2',
        category: 'luas_tanah',
        numericValue: 1200,
        unit: 'm2',
        createdAt: now,
      );

      final snapshot = ActivityLiveSnapshot(
        activeSessions: [root, child1],
        checkpoints: {
          'root-1': [cp1, cp2],
        },
        notes: [note],
        revision: 4,
        lastUpdatedAt: now,
      );

      expect(snapshot.hasActiveSessions, isTrue);
      expect(snapshot.rootSession?.id, equals('root-1'));
      expect(snapshot.childSessions.length, equals(1));
      expect(snapshot.childSessions.first.id, equals('child-1'));
      expect(snapshot.childrenOf('root-1').length, equals(1));
      expect(snapshot.lastCheckpointFor('root-1')?.id, equals('cp-2'));
      expect(snapshot.notes.length, equals(1));
      expect(snapshot.revision, equals(4));
    });
  });

  group('ActivityContextBridge', () {
    test('bridges ActivityBloc state into ActivityLiveSnapshot', () async {
      final bridge = ActivityContextBridge(bloc);
      expect(bridge.snapshot.hasActiveSessions, isFalse);

      await appService.startSession(
        operationId: 'op-bridge-1',
        title: 'Ekspedisi Gudang',
        category: 'Kerja',
        source: ActivityEntrySource.manual,
      );

      final updated = bridge.snapshot;
      expect(updated.hasActiveSessions, isTrue);
      expect(updated.rootSession?.title, equals('Ekspedisi Gudang'));
      expect(updated.revision, greaterThanOrEqualTo(1));
    });
  });

  group('ActivityApplicationService - Core Guarantees', () {
    test('Idempotency: duplicate operationId returns cached result without duplicate entry', () async {
      final res1 = await appService.startSession(
        operationId: 'op-idem-1',
        title: 'Perjalanan Lampung',
        category: 'Perjalanan',
        source: ActivityEntrySource.assistant,
      );
      expect(res1.success, isTrue);
      final firstSessionId = res1.session!.id;

      // Repeat exactly same operationId
      final res2 = await appService.startSession(
        operationId: 'op-idem-1',
        title: 'Perjalanan Lampung',
        category: 'Perjalanan',
        source: ActivityEntrySource.assistant,
      );

      expect(res2.success, isTrue);
      expect(res2.session!.id, equals(firstSessionId));
      expect(bloc.state.activeSessions.length, equals(1));
    });

    test('Revision mismatch check: warns and refuses if state was modified elsewhere', () async {
      final res1 = await appService.startSession(
        operationId: 'op-rev-1',
        title: 'Sesi Awal',
        category: 'Umum',
        source: ActivityEntrySource.manual,
      );
      final currentRev = appService.currentRevision;

      final mismatchRes = await appService.finishSession(
        operationId: 'op-rev-2',
        sessionId: res1.session!.id,
        source: ActivityEntrySource.assistant,
        expectedRevision: currentRev - 5, // Old stale revision
      );

      expect(mismatchRes.revisionMismatch, isTrue);
      expect(mismatchRes.success, isFalse);
      expect(bloc.state.activeSessions.length, equals(1)); // Still active
    });

    test('Hierarchy Safety: Warns if finishing parent when child is still active', () async {
      final parentRes = await appService.startSession(
        operationId: 'op-parent-1',
        title: 'Perjalanan Palembang',
        category: 'Perjalanan',
        source: ActivityEntrySource.manual,
      );
      final parentId = parentRes.session!.id;

      await appService.startSession(
        operationId: 'op-child-1',
        title: 'Makan Siang',
        category: 'Makan',
        parentSessionId: parentId,
        source: ActivityEntrySource.manual,
      );

      // Attempt to finish parent without forceCloseChildren
      final finishAttempt = await appService.finishSession(
        operationId: 'op-finish-parent',
        sessionId: parentId,
        source: ActivityEntrySource.assistant,
        forceCloseChildren: false,
      );

      expect(finishAttempt.success, isFalse);
      expect(finishAttempt.activeChildrenCount, equals(1));
      expect(bloc.state.activeSessions.length, equals(2)); // Both still active

      // Finish parent WITH forceCloseChildren = true
      final forceFinish = await appService.finishSession(
        operationId: 'op-force-finish-parent',
        sessionId: parentId,
        source: ActivityEntrySource.assistant,
        forceCloseChildren: true,
      );

      expect(forceFinish.success, isTrue);
      expect(bloc.state.activeSessions.length, equals(0)); // Both closed
    });

    test('Undo Support: Reopens finished session', () async {
      final res1 = await appService.startSession(
        operationId: 'op-undo-1',
        title: 'Jogging Sore',
        category: 'Olahraga',
        source: ActivityEntrySource.manual,
      );
      final sId = res1.session!.id;

      final finishRes = await appService.finishSession(
        operationId: 'op-undo-finish',
        sessionId: sId,
        source: ActivityEntrySource.assistant,
      );
      expect(finishRes.success, isTrue);
      expect(bloc.state.activeSessions.length, equals(0));

      final undoRes = await appService.undo('op-undo-finish');
      expect(undoRes.success, isTrue);
      expect(bloc.state.activeSessions.length, equals(1));
      expect(bloc.state.activeSessions.first.id, equals(sId));
    });
  });

  group('ActivityVoiceParser - Hierarchy Resolution', () {
    const parser = ActivityVoiceParser();

    test('prioritizes active child session over parent when targeting child title', () {
      final parent = ActivitySessionEntity(
        id: 'parent-1',
        householdId: 'h1',
        title: 'Perjalanan ke Palembang',
        category: 'Perjalanan',
        startedAt: DateTime.now().subtract(const Duration(hours: 4)),
        status: ActivitySessionStatus.active,
        createdAt: DateTime.now(),
      );

      final child = ActivitySessionEntity(
        id: 'child-1',
        householdId: 'h1',
        parentSessionId: 'parent-1',
        title: 'Makan di Rest Area',
        category: 'Konsumsi',
        startedAt: DateTime.now().subtract(const Duration(minutes: 15)),
        status: ActivitySessionStatus.active,
        createdAt: DateTime.now(),
      );

      final intent = parser.parse(
        'selesai makan',
        activeSessions: [parent, child],
      );

      expect(intent.type, equals(ActivityVoiceIntentType.finish));
      expect(intent.targetSessionId, equals('child-1'));
      expect(intent.confidence, greaterThanOrEqualTo(0.85));
      expect(intent.ambiguityReason, isNull);
    });

    test('detects ambiguity when user says generic "selesai" with multiple active sessions', () {
      final s1 = ActivitySessionEntity(
        id: 's-1',
        householdId: 'h1',
        title: 'Makan Pagi',
        category: 'Konsumsi',
        startedAt: DateTime.now(),
        status: ActivitySessionStatus.active,
        createdAt: DateTime.now(),
      );
      final s2 = ActivitySessionEntity(
        id: 's-2',
        householdId: 'h1',
        title: 'Perjalanan Kantor',
        category: 'Perjalanan',
        startedAt: DateTime.now(),
        status: ActivitySessionStatus.active,
        createdAt: DateTime.now(),
      );

      final intent = parser.parse(
        'sudah selesai',
        activeSessions: [s1, s2],
      );

      expect(intent.ambiguityReason, isNotNull);
      expect(intent.confidence, lessThan(0.85));
    });
  });
}
