import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/database/audit_logger.dart';
import 'package:ffm_manager/features/activity/data/repositories/activity_repository.dart';
import 'package:ffm_manager/features/activity/domain/entities/activity_entity.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_capability_adapters.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_proposal_json_service.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_plan.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_planner.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_capability_executor.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_draft_validator.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';

void main() {
  const householdId = 'local-household';
  final now = DateTime(2026, 8, 24, 11);
  late AppDatabase database;

  Future<void> seedActivity({
    required String id,
    required String title,
    ActivitySessionStatus status = ActivitySessionStatus.completed,
  }) => ActivityRepository(database, AuditLogger(database)).saveSession(
    ActivitySessionEntity(
      id: id,
      householdId: householdId,
      title: title,
      category: 'Keluarga',
      startedAt: now.subtract(const Duration(hours: 1)),
      endedAt: status == ActivitySessionStatus.active ? null : now,
      status: status,
      createdAt: now.subtract(const Duration(hours: 1)),
      updatedAt: now,
    ),
  );

  Future<void> seedActivityCategory() => database.customStatement(
    'INSERT INTO categories '
    '(id, household_id, name, type, default_budget_period, is_active, created_at) '
    'VALUES (?, ?, ?, ?, ?, ?, ?)',
    [
      'activity-test',
      householdId,
      'Aktivitas',
      'activity',
      'none',
      1,
      now.millisecondsSinceEpoch,
    ],
  );

  Future<void> seedTag() => database.customStatement(
    'INSERT INTO tags '
    '(id, household_id, name, is_archived, created_at) '
    'VALUES (?, ?, ?, ?, ?)',
    ['tag-pertanian', householdId, 'pertanian', 0, now.millisecondsSinceEpoch],
  );

  setUp(() async {
    database = createInMemoryDatabaseForTests();
    await seedTag();
  });

  tearDown(() async {
    await database.close();
  });

  Future<FfmAssistantCapabilityExecutionResult> saveDraft(
    Map<String, Object?> parameters,
  ) =>
      FfmAssistantCapabilityAdapterRegistry(
        database: database,
        householdId: householdId,
        clock: () => now,
      ).handlers['mutate.save_draft']!(
        FfmAssistantActionStep(
          id: 'save',
          capabilityId: 'mutate.save_draft',
          parameters: {
            ...parameters,
            '_idempotencyKey':
                parameters['_idempotencyKey'] ?? 'activity-test-key',
          },
        ),
      );

  FfmAssistantIntent mutationIntent({
    required FfmAssistantDraftKind kind,
    required FfmAssistantIntentType type,
    required String targetId,
  }) {
    final operation = kind == FfmAssistantDraftKind.activityArchive
        ? 'archive'
        : 'delete';
    return FfmAssistantIntent(
      rawText: '$operation aktivitas',
      normalizedText: '$operation aktivitas',
      type: type,
      destination: FfmAssistantDestination.activity,
      draft: FfmAssistantDraft(
        kind: kind,
        createdAt: now,
        formValues: {
          'entity': 'activity_session',
          'targetId': targetId,
          'operation': operation,
        },
      ),
    );
  }

  Future<FfmAssistantActionPlan?> executeConfirmed(
    FfmAssistantActionPlan plan,
  ) async {
    final controller = FfmAssistantActionPlanController(now: () => now)
      ..register(plan)
      ..markAwaitingConfirmation(plan.id)
      ..confirm(plan.id);
    final adapters = FfmAssistantCapabilityAdapterRegistry(
      database: database,
      householdId: householdId,
      clock: () => now,
    );

    // Create a custom executor that skips navigation steps
    final originalHandlers = adapters.handlers;
    final modifiedHandlers = <String, FfmAssistantCapabilityHandler>{};
    for (final entry in originalHandlers.entries) {
      if (entry.key.startsWith('navigate.')) {
        modifiedHandlers[entry.key] = (step) async =>
            FfmAssistantCapabilityExecutionResult.success(
              'Navigation skipped in test',
            );
      } else {
        modifiedHandlers[entry.key] = entry.value;
      }
    }

    return FfmAssistantCapabilityExecutor(
      controller: controller,
      handlers: modifiedHandlers,
    ).execute(plan.id);
  }

  test('archive aktivitas selesai memakai preview, confirmation, verify, dan audit', () async {
    await seedActivity(id: 'market', title: 'Belanja pasar');
    final plan = FfmAssistantActionPlanner(now: () => now).planFor(
      mutationIntent(
        kind: FfmAssistantDraftKind.activityArchive,
        type: FfmAssistantIntentType.archiveActivity,
        targetId: 'market',
      ),
    )!;

    final completed = await executeConfirmed(plan);

    expect(completed?.status, FfmAssistantActionPlanStatus.completed);
    final activity = await ActivityRepository(
      database,
      AuditLogger(database),
    ).getSession(householdId, 'market');
    expect(activity?.isArchived, isTrue);
    expect(activity?.category, 'Keluarga');
    expect(activity?.categoryId, isNotNull);
    final logs = await database
        .customSelect(
          'SELECT action FROM audit_logs WHERE entity = ?',
          variables: [Variable<String>('activity_session')],
        )
        .get();
    expect(logs.map((row) => row.read<String>('action')), contains('archive'));
  });

  test(
    'main timer terjadwal mempertahankan scheduledAt dan tidak mulai sekarang',
    () async {
      await seedActivityCategory();
      final scheduled = now.add(const Duration(hours: 2));
      final result = await saveDraft({
        'kind': 'activity',
        'title': 'Timer utama',
        'category': 'Aktivitas',
        'activityMode': 'timeTracking',
        'scheduledAt': scheduled.toIso8601String(),
        'startNow': false,
        '_idempotencyKey': 'main-timer',
      });

      final rows = await database.select(database.activitySessions).get();
      expect(result.isSuccess, isTrue);
      expect(rows.single.startedAt, scheduled);
      expect(rows.single.scheduledAt, scheduled);
      expect(rows.single.mode, 'timeTracking');
      expect(rows.single.status, 'active');
    },
  );

  test('child timer hanya boleh dibuat di parent aktif dan menyimpan parentSessionId', () async {
    await seedActivityCategory();
    await seedActivity(
      id: 'parent-active',
      title: 'Parent',
      status: ActivitySessionStatus.active,
    );
    final result = await saveDraft({
      'kind': 'activity',
      'title': 'Child timer',
      'category': 'Aktivitas',
      'activityMode': 'timeTracking',
      'startNow': true,
      'parentSessionId': 'parent-active',
      '_idempotencyKey': 'child-timer',
    });

    final rows = await database.select(database.activitySessions).get();
    final child = rows.singleWhere((row) => row.id != 'parent-active');
    expect(result.isSuccess, isTrue);
    expect(child.parentSessionId, 'parent-active');
    expect(child.startedAt, now);
    expect(child.mode, 'timeTracking');
  });

  test('activity history disimpan sebagai daily note kanonis', () async {
    await seedActivityCategory();
    final result = await saveDraft({
      'kind': 'activity',
      'title': 'Catatan aktivitas',
      'category': 'Aktivitas',
      'activityMode': 'history',
      'note': 'Selesai mengecek kebun.',
      'date': now.toIso8601String(),
      '_idempotencyKey': 'activity-note',
    });

    final sessions = await database.select(database.activitySessions).get();
    final notes = await database.select(database.dailyNotes).get();
    expect(result.isSuccess, isTrue);
    expect(sessions, isEmpty);
    expect(notes.single.title, 'Catatan aktivitas');
    expect(notes.single.body, 'Selesai mengecek kebun.');
  });

  test(
    'daily note hanya membuat row daily_notes, bukan activity_sessions',
    () async {
      final result = await saveDraft({
        'kind': 'dailyNote',
        'title': 'Catatan harian',
        'note': 'Panen berjalan baik.',
        'date': now.toIso8601String(),
        '_idempotencyKey': 'daily-note',
      });

      final notes = await database.select(database.dailyNotes).get();
      final sessions = await database.select(database.activitySessions).get();
      expect(result.isSuccess, isTrue);
      expect(notes.single.body, 'Panen berjalan baik.');
      expect(notes.single.noteDate, now);
      expect(sessions, isEmpty);
    },
  );

  test(
    'legacy migration tidak menyalin daily note ke activity_sessions',
    () async {
      await database
          .into(database.dailyNotes)
          .insert(
            DailyNotesCompanion.insert(
              id: 'legacy-note',
              householdId: householdId,
              noteDate: now,
              body: 'Catatan lama tetap terpisah.',
              createdAt: now,
            ),
          );

      await ActivityRepository(
        database,
        AuditLogger(database),
      ).migrateOldData(householdId);

      expect(
        await (database.select(
          database.dailyNotes,
        )..where((row) => row.id.equals('legacy-note'))).getSingle(),
        isNotNull,
      );
      expect(
        await (database.select(
          database.activitySessions,
        )..where((row) => row.id.equals('legacy-note'))).get(),
        isEmpty,
      );
    },
  );

  test(
    'activity retry dengan payload berbeda ditolak tanpa row kedua',
    () async {
      await seedActivityCategory();
      final first = await saveDraft({
        'kind': 'activity',
        'title': 'Aktivitas asli',
        'category': 'Aktivitas',
        'activityMode': 'history',
        'date': now.toIso8601String(),
        '_idempotencyKey': 'activity-idempotency',
      });
      final second = await saveDraft({
        'kind': 'activity',
        'title': 'Aktivitas berbeda',
        'category': 'Aktivitas',
        'activityMode': 'history',
        'date': now.toIso8601String(),
        '_idempotencyKey': 'activity-idempotency',
      });

      expect(first.isSuccess, isTrue);
      expect(second.isSuccess, isFalse);
      expect(await database.select(database.activitySessions).get(), isEmpty);
      final notes = await database.select(database.dailyNotes).get();
      expect(notes, hasLength(1));
      expect(notes.single.title, 'Aktivitas asli');
    },
  );

  test(
    'daily_note JSON melewati draft, plan, executor, dan verifier',
    () async {
      final parsed = FfmAssistantProposalJsonService.parse(
        '{"formatVersion":"ffm-assistant-proposal-v1","proposal":{"type":"daily_note","title":"Catatan panen","body":"Panen berjalan baik.","tags":["pertanian"],"noteDate":"2026-08-23T07:30:00.000"}}',
        createdAt: now,
      );
      expect(parsed.draft?.kind, FfmAssistantDraftKind.dailyNote);
      final intent = FfmAssistantIntent(
        rawText: 'catat harian',
        normalizedText: 'catat harian',
        type: FfmAssistantIntentType.createDailyNote,
        destination: FfmAssistantDestination.activity,
        draft: parsed.draft,
      );
      final plan = FfmAssistantActionPlanner(now: () => now).planFor(intent)!;
      final completed = await executeConfirmed(plan);

      expect(
        completed?.status,
        FfmAssistantActionPlanStatus.completed,
        reason: completed?.steps
            .map((step) => '${step.capabilityId}: ${step.error ?? step.result}')
            .join('\n'),
      );
      expect(
        completed?.steps.map((step) => step.capabilityId),
        containsAll(<String>[
          'draft.daily_note',
          'mutate.save_draft',
          'verify.daily_note_mutation',
        ]),
      );
      expect(await database.select(database.activitySessions).get(), isEmpty);
      expect(
        (await database.select(database.dailyNotes).get()).single.body,
        'Panen berjalan baik.',
      );
      final note = (await database.select(database.dailyNotes).get()).single;
      final noteTags = await (database.select(
        database.dailyNoteTags,
      )..where((row) => row.dailyNoteId.equals(note.id))).get();
      expect(noteTags.map((row) => row.tagId), contains('tag-pertanian'));
    },
  );

  test('daily note menolak tag yang tidak ada di Data Utama', () async {
    final result = await saveDraft({
      'kind': 'daily_note',
      'title': 'Catatan tanpa tag valid',
      'body': 'Tag ini belum dibuat.',
      'tags': 'tag-belum-ada',
      '_idempotencyKey': 'missing-daily-note-tag',
    });

    expect(result.isSuccess, isFalse);
    expect(result.message, contains('belum ada di Data Utama'));
    expect(await database.select(database.dailyNotes).get(), isEmpty);
  });

  test('daily note membuat tag baru dan relasinya secara atomik', () async {
    final result = await saveDraft({
      'kind': 'daily_note',
      'title': 'Pupuk cabai',
      'body': 'Saya sedang pupuk cabai di kebun AB',
      'tags': 'AB',
      'newTags': 'AB',
      '_idempotencyKey': 'daily-note-new-tag-ab',
    });

    expect(result.isSuccess, isTrue);
    final tag = (await database.select(database.tags).get()).singleWhere(
      (row) => row.name == 'AB',
    );
    final note = (await database.select(database.dailyNotes).get()).single;
    final links = await database.select(database.dailyNoteTags).get();
    expect(links, hasLength(1));
    expect(links.single.dailyNoteId, note.id);
    expect(links.single.tagId, tag.id);
  });

  test(
    'perintah natural membuat tag AB dan Catatan Harian dalam satu plan',
    () async {
      final interpreter = FfmAssistantInterpreter(database, clock: () => now);
      final intent = await interpreter.interpret(
        'tolong catat sekarang saya sedang pupuk cabai di kebun AB dan buat tag baru terkait tag AB',
      );
      final plan = FfmAssistantActionPlanner(now: () => now).planFor(intent)!;

      final completed = await executeConfirmed(plan);

      expect(completed?.status, FfmAssistantActionPlanStatus.completed);
      final tag = (await database.select(database.tags).get()).singleWhere(
        (row) => row.name == 'AB',
      );
      final note = (await database.select(database.dailyNotes).get()).single;
      expect(note.body, 'saya sedang pupuk cabai di kebun AB');
      final link = (await database.select(database.dailyNoteTags).get()).single;
      expect(link.dailyNoteId, note.id);
      expect(link.tagId, tag.id);
    },
  );

  test('gagal membuat Catatan Harian tidak meninggalkan tag baru', () async {
    await saveDraft({
      'kind': 'daily_note',
      'body': 'Catatan pertama',
      '_idempotencyKey': 'daily-note-atomic-rollback',
    });

    final result = await saveDraft({
      'kind': 'daily_note',
      'body': 'Isi berbeda dengan key sama',
      'tags': 'Tag rollback',
      'newTags': 'Tag rollback',
      '_idempotencyKey': 'daily-note-atomic-rollback',
    });

    expect(result.isSuccess, isFalse);
    expect(
      (await database.select(database.tags).get()).where(
        (row) => row.name == 'Tag rollback',
      ),
      isEmpty,
    );
  });

  test('delete aktivitas selesai menghapus session dan data turunan secara permanen', () async {
    await seedActivity(id: 'visit', title: 'Kunjungan keluarga');
    final plan = FfmAssistantActionPlanner(now: () => now).planFor(
      mutationIntent(
        kind: FfmAssistantDraftKind.activityDelete,
        type: FfmAssistantIntentType.deleteActivity,
        targetId: 'visit',
      ),
    )!;

    final completed = await executeConfirmed(plan);

    expect(completed?.status, FfmAssistantActionPlanStatus.completed);
    final activity = await ActivityRepository(
      database,
      AuditLogger(database),
    ).getSession(householdId, 'visit');
    expect(activity, isNull);
  });

  test(
    'arsip Catatan Harian memakai tabel daily_notes dan verifier khusus',
    () async {
      await database
          .into(database.dailyNotes)
          .insert(
            DailyNotesCompanion.insert(
              id: 'note-archive',
              householdId: householdId,
              noteDate: now,
              body: 'Catatan untuk diarsipkan.',
              createdAt: now,
            ),
          );
      final intent = FfmAssistantIntent(
        rawText: 'arsipkan catatan',
        normalizedText: 'arsipkan catatan',
        type: FfmAssistantIntentType.archiveDailyNote,
        destination: FfmAssistantDestination.activity,
        draft: FfmAssistantDraft(
          kind: FfmAssistantDraftKind.dailyNoteArchive,
          createdAt: now,
          formValues: const {
            'entity': 'daily_note',
            'targetId': 'note-archive',
            'operation': 'archive',
          },
        ),
      );
      final plan = FfmAssistantActionPlanner(now: () => now).planFor(intent)!;
      final completed = await executeConfirmed(plan);

      expect(completed?.status, FfmAssistantActionPlanStatus.completed);
      final note = await (database.select(
        database.dailyNotes,
      )..where((row) => row.id.equals('note-archive'))).getSingle();
      expect(note.isArchived, isTrue);
    },
  );

  test('reopen aktivitas arsip mengembalikan sesi menjadi aktif', () async {
    await seedActivity(id: 'archived-trip', title: 'Perjalanan lama');
    await ActivityRepository(
      database,
      AuditLogger(database),
    ).archiveSession(householdId, 'archived-trip');
    final intent = FfmAssistantIntent(
      rawText: 'buka kembali aktivitas perjalanan lama',
      normalizedText: 'buka kembali aktivitas perjalanan lama',
      type: FfmAssistantIntentType.updateActivity,
      destination: FfmAssistantDestination.activity,
      draft: FfmAssistantDraft(
        kind: FfmAssistantDraftKind.activityUpdate,
        createdAt: now,
        formValues: const {
          'entity': 'activity_session',
          'targetId': 'archived-trip',
          'operation': 'reopen',
        },
      ),
    );
    final plan = FfmAssistantActionPlanner(now: () => now).planFor(intent)!;
    final completed = await executeConfirmed(plan);

    expect(completed?.status, FfmAssistantActionPlanStatus.completed);
    final session = await ActivityRepository(
      database,
      AuditLogger(database),
    ).getSession(householdId, 'archived-trip');
    expect(session?.isArchived, isFalse);
    expect(session?.status, ActivitySessionStatus.active);
  });

  test(
    'edit dan hapus checkpoint aktivitas berjalan melewati verifier',
    () async {
      await seedActivity(
        id: 'active-trip',
        title: 'Perjalanan aktif',
        status: ActivitySessionStatus.active,
      );
      await ActivityRepository(database, AuditLogger(database)).saveCheckpoint(
        ActivityCheckpointEntity(
          id: 'checkpoint-1',
          sessionId: 'active-trip',
          label: 'Berangkat',
          occurredAt: now,
          sequence: 1,
          createdAt: now,
        ),
      );

      Future<FfmAssistantActionPlan?> runCheckpoint(
        String operation, {
        String? label,
      }) async {
        final intent = FfmAssistantIntent(
          rawText: operation,
          normalizedText: operation,
          type: FfmAssistantIntentType.updateActivity,
          destination: FfmAssistantDestination.activity,
          draft: FfmAssistantDraft(
            kind: FfmAssistantDraftKind.activityUpdate,
            createdAt: now,
            formValues: {
              'entity': 'activity_session',
              'targetId': 'active-trip',
              'operation': operation,
              'checkpointId': 'checkpoint-1',
              'label': ?label,
            },
          ),
        );
        final plan = FfmAssistantActionPlanner(now: () => now).planFor(intent)!;
        return executeConfirmed(plan);
      }

      final edited = await runCheckpoint(
        'checkpoint_edit',
        label: 'Sampai lokasi',
      );
      expect(edited?.status, FfmAssistantActionPlanStatus.completed);
      expect(
        (await ActivityRepository(
          database,
          AuditLogger(database),
        ).getCheckpoints('active-trip')).single.label,
        'Sampai lokasi',
      );

      final deleted = await runCheckpoint('checkpoint_delete');
      expect(deleted?.status, FfmAssistantActionPlanStatus.completed);
      expect(
        await ActivityRepository(
          database,
          AuditLogger(database),
        ).getCheckpoints('active-trip'),
        isEmpty,
      );
    },
  );

  test(
    'edit aktivitas mengganti kategori sesuai draft dan memverifikasinya',
    () async {
      await database.customStatement(
        'INSERT INTO categories '
        '(id, household_id, name, type, default_budget_period, is_active, created_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          'activity-garden',
          householdId,
          'Kebun Uji',
          'activity',
          'none',
          1,
          now.millisecondsSinceEpoch,
        ],
      );
      await seedActivity(id: 'market', title: 'Belanja pasar');
      final intent = FfmAssistantIntent(
        rawText: 'ubah kategori aktivitas belanja pasar jadi kebun',
        normalizedText: 'ubah kategori aktivitas belanja pasar jadi kebun',
        type: FfmAssistantIntentType.editActivity,
        destination: FfmAssistantDestination.activity,
        draft: FfmAssistantDraft(
          kind: FfmAssistantDraftKind.activityEdit,
          createdAt: now,
          title: 'Belanja pasar',
          categoryName: 'kebun uji',
          formValues: const {
            'entity': 'activity_session',
            'targetId': 'market',
            'operation': 'edit',
          },
        ),
      );

      final plan = FfmAssistantActionPlanner(now: () => now).planFor(intent)!;
      final completed = await executeConfirmed(plan);

      expect(completed?.status, FfmAssistantActionPlanStatus.completed);
      final activity = await ActivityRepository(
        database,
        AuditLogger(database),
      ).getSession(householdId, 'market');
      expect(activity?.title, 'Belanja pasar');
      expect(activity?.category, 'Kebun Uji');
      expect(activity?.categoryId, 'activity-garden');
    },
  );

  test(
    'read.activity scoped ke householdA tidak bocor ke householdB',
    () async {
      const homeA = 'home-A';
      const homeB = 'home-B';
      await ActivityRepository(database, AuditLogger(database)).saveSession(
        ActivitySessionEntity(
          id: 'a-travel',
          householdId: homeA,
          title: 'Perjalanan Alpha',
          category: 'Pekerjaan',
          startedAt: now.subtract(const Duration(hours: 2)),
          endedAt: now,
          status: ActivitySessionStatus.completed,
          createdAt: now.subtract(const Duration(hours: 2)),
          updatedAt: now,
        ),
      );
      await ActivityRepository(database, AuditLogger(database)).saveSession(
        ActivitySessionEntity(
          id: 'b-travel',
          householdId: homeB,
          title: 'Perjalanan Beta',
          category: 'Pekerjaan',
          startedAt: now.subtract(const Duration(minutes: 30)),
          endedAt: now,
          status: ActivitySessionStatus.completed,
          createdAt: now.subtract(const Duration(minutes: 30)),
          updatedAt: now,
        ),
      );

      final homeAHandler = FfmAssistantCapabilityAdapterRegistry(
        database: database,
        householdId: homeA,
        clock: () => now,
      ).handlers['read.activity'];

      final result = await homeAHandler!(
        const FfmAssistantActionStep(
          id: 'scope-a-read',
          capabilityId: 'read.activity',
          parameters: {},
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(result.message, contains('Perjalanan Alpha'));
      expect(result.message, isNot(contains('Perjalanan Beta')));
    },
  );

  test(
    'read.activity menerapkan periode, filter, limit, dan checkpoint',
    () async {
      final repo = ActivityRepository(database, AuditLogger(database));
      await repo.saveSession(
        ActivitySessionEntity(
          id: 'current-trip',
          householdId: householdId,
          title: 'Perjalanan kebun',
          category: 'Kerja',
          kind: ActivityKind.timer,
          mode: ActivityMode.timeTracking,
          startedAt: now.subtract(const Duration(hours: 2)),
          status: ActivitySessionStatus.active,
          createdAt: now.subtract(const Duration(hours: 2)),
          updatedAt: now,
        ),
      );
      await repo.saveCheckpoint(
        ActivityCheckpointEntity(
          id: 'current-checkpoint',
          sessionId: 'current-trip',
          label: 'Sampai kebun',
          occurredAt: now,
          sequence: 1,
          createdAt: now,
        ),
      );
      await repo.saveSession(
        ActivitySessionEntity(
          id: 'old-trip',
          householdId: householdId,
          title: 'Perjalanan lama',
          category: 'Kerja',
          startedAt: now.subtract(const Duration(days: 10)),
          endedAt: now.subtract(const Duration(days: 10, hours: -1)),
          status: ActivitySessionStatus.completed,
          createdAt: now.subtract(const Duration(days: 10)),
          updatedAt: now,
        ),
      );

      final handler = FfmAssistantCapabilityAdapterRegistry(
        database: database,
        householdId: householdId,
        clock: () => now,
      ).handlers['read.activity']!;
      final result = await handler(
        FfmAssistantActionStep(
          id: 'filtered-activity-read',
          capabilityId: 'read.activity',
          parameters: {
            'dateFrom': now.subtract(const Duration(days: 1)).toIso8601String(),
            'dateTo': now.toIso8601String(),
            'status': 'active',
            'kind': 'timer',
            'category': 'kerja',
            'query': 'perjalanan kebun',
            'limit': 1,
            'includeCheckpoints': true,
          },
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(result.message, contains('Perjalanan kebun'));
      expect(result.message, contains('Sampai kebun'));
      expect(result.message, isNot(contains('Perjalanan lama')));
    },
  );

  test(
    'read.dailyNotes tetap terpisah dari timer dan menghormati periode',
    () async {
      await database
          .into(database.dailyNotes)
          .insert(
            DailyNotesCompanion.insert(
              id: 'note-in-period',
              householdId: householdId,
              noteDate: now.subtract(const Duration(hours: 3)),
              body: 'Panen selesai.',
              createdAt: now,
            ),
          );
      await database
          .into(database.dailyNotes)
          .insert(
            DailyNotesCompanion.insert(
              id: 'note-outside-period',
              householdId: householdId,
              noteDate: now.subtract(const Duration(days: 10)),
              body: 'Catatan lama.',
              createdAt: now,
            ),
          );

      final handler = FfmAssistantCapabilityAdapterRegistry(
        database: database,
        householdId: householdId,
        clock: () => now,
      ).handlers['read.dailyNotes']!;
      final result = await handler(
        FfmAssistantActionStep(
          id: 'daily-note-read',
          capabilityId: 'read.dailyNotes',
          parameters: {
            'dateFrom': now.subtract(const Duration(days: 1)).toIso8601String(),
            'dateTo': now.toIso8601String(),
            'limit': 1,
          },
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(result.message, contains('Panen selesai.'));
      expect(result.message, isNot(contains('Catatan lama.')));
      expect(result.message, isNot(contains('activity_sessions')));
    },
  );

  test(
    'aktivitas aktif tetap diblokir walaupun plan sudah dikonfirmasi',
    () async {
      await seedActivity(
        id: 'travel',
        title: 'Perjalanan',
        status: ActivitySessionStatus.active,
      );
      final plan = FfmAssistantActionPlanner(now: () => now).planFor(
        mutationIntent(
          kind: FfmAssistantDraftKind.activityDelete,
          type: FfmAssistantIntentType.deleteActivity,
          targetId: 'travel',
        ),
      )!;

      final result = await executeConfirmed(plan);

      expect(result?.status, FfmAssistantActionPlanStatus.failed);
      final activity = await ActivityRepository(
        database,
        AuditLogger(database),
      ).getSession(householdId, 'travel');
      expect(activity?.status, ActivitySessionStatus.active);
    },
  );

  test(
    'filter kategori memakai categoryId konsisten lintas jalur input',
    () async {
      await database.customStatement(
        'INSERT INTO categories '
        '(id, household_id, name, type, default_budget_period, is_active, created_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          'cat-farm',
          householdId,
          'Pertanian',
          'activity',
          'none',
          1,
          now.millisecondsSinceEpoch,
        ],
      );
      await database.customStatement(
        'INSERT INTO categories '
        '(id, household_id, name, type, default_budget_period, is_active, created_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          'cat-shop',
          householdId,
          'Belanja',
          'activity',
          'none',
          1,
          now.millisecondsSinceEpoch,
        ],
      );

      final repo = ActivityRepository(database, AuditLogger(database));

      // Jalur 1: input manual via repository save (categoryId eksplisit).
      await repo.saveSession(
        ActivitySessionEntity(
          id: 'm-farm',
          householdId: householdId,
          title: 'Memupuk pagi',
          category: 'Pertanian',
          categoryId: 'cat-farm',
          startedAt: now.subtract(const Duration(hours: 3)),
          endedAt: now,
          status: ActivitySessionStatus.completed,
          createdAt: now.subtract(const Duration(hours: 3)),
          updatedAt: now,
        ),
      );

      // Jalur 2: input via asisten/voice (draft → executeVoiceIntent → save).
      await repo.saveSession(
        ActivitySessionEntity(
          id: 'v-farm',
          householdId: householdId,
          title: 'Menanam cabai',
          category: 'Pertanian',
          categoryId: 'cat-farm',
          startedAt: now.subtract(const Duration(hours: 2)),
          endedAt: now,
          status: ActivitySessionStatus.completed,
          createdAt: now.subtract(const Duration(hours: 2)),
          updatedAt: now,
        ),
      );

      // Jalur 3: kategori berbeda tidak boleh ikut terfilter.
      await repo.saveSession(
        ActivitySessionEntity(
          id: 'v-shop',
          householdId: householdId,
          title: 'Belanja pasar',
          category: 'Belanja',
          categoryId: 'cat-shop',
          startedAt: now.subtract(const Duration(hours: 1)),
          endedAt: now,
          status: ActivitySessionStatus.completed,
          createdAt: now.subtract(const Duration(hours: 1)),
          updatedAt: now,
        ),
      );

      final all = await repo.getSessions(householdId);

      // Semua jalur menyimpan categoryId master yang sama, bukan string bebas.
      final farm = all.where((s) => s.categoryId == 'cat-farm').toList();
      expect(farm, hasLength(2));
      expect(farm.map((s) => s.id).toSet(), {'m-farm', 'v-farm'});
      expect(farm.every((s) => s.category == 'Pertanian'), isTrue);

      // Kategori lain tetap terisolasi dari filter Pertanian.
      expect(all.where((s) => s.categoryId == 'cat-shop'), hasLength(1));
      expect(farm.any((s) => s.categoryId == 'cat-shop'), isFalse);
    },
  );

  test('saveActivity berhasil menyimpan draft aktivitas meskipun kategori belum ada di Data Utama', () async {
    final res = await saveDraft({
      'kind': 'activity',
      'title': 'Olahraga pagi keliling kompleks',
      'category': 'Olahraga Khusus',
      'activityMode': 'timeTracking',
    });
    expect(res.isSuccess, isTrue);

    final repo = ActivityRepository(database, AuditLogger(database));
    final sessions = await repo.getActiveSessions(householdId);
    expect(sessions, hasLength(1));
    expect(sessions.first.title, 'Olahraga pagi keliling kompleks');
    expect(sessions.first.category, 'Olahraga Khusus');
    expect(sessions.first.status, ActivitySessionStatus.active);
  });

  test('FfmAssistantDraftValidator memvalidasi dailyNote dengan body/note/title dan date fallback', () {
    // 1. Valid saat note ada
    final draft1 = FfmAssistantDraft(
      kind: FfmAssistantDraftKind.dailyNote,
      createdAt: now,
      title: 'Insiden kolam',
      note: 'Pipa pembuangan tersumbat lumut',
      date: now,
    );
    expect(FfmAssistantDraftValidator.validate(draft1), isEmpty);

    // 2. Valid saat teks ada di formValues['body'] dan date fallback ke formValues
    final draft2 = FfmAssistantDraft(
      kind: FfmAssistantDraftKind.dailyNote,
      createdAt: now,
      title: 'Insiden kolam',
      formValues: {
        'body': 'Pipa pembuangan tersumbat lumut',
        'date': now.toIso8601String(),
      },
    );
    expect(FfmAssistantDraftValidator.validate(draft2), isEmpty);

    // 3. Menolak jika tidak ada teks sama sekali
    final draftEmpty = FfmAssistantDraft(
      kind: FfmAssistantDraftKind.dailyNote,
      createdAt: now,
      date: now,
    );
    final issues = FfmAssistantDraftValidator.validate(draftEmpty);
    expect(issues.any((i) => i.code == 'daily_note_body_required'), isTrue);

    final mismatchedNewTag = FfmAssistantDraft(
      kind: FfmAssistantDraftKind.dailyNote,
      createdAt: now,
      note: 'Pupuk cabai',
      date: now,
      tags: 'Kebun',
      newTags: 'AB',
    );
    expect(
      FfmAssistantDraftValidator.validate(mismatchedNewTag)
          .map((issue) => issue.code),
      contains('daily_note_new_tags_mismatch'),
    );
  });

  test('validator activity mewajibkan judul tetapi menerima scheduledAt sebagai tanggal', () {
    final valid = FfmAssistantDraft(
      kind: FfmAssistantDraftKind.activity,
      createdAt: now,
      title: 'Perjalanan terjadwal',
      scheduledAt: now.add(const Duration(hours: 2)),
    );
    final missingTitle = FfmAssistantDraft(
      kind: FfmAssistantDraftKind.activity,
      createdAt: now,
      scheduledAt: now.add(const Duration(hours: 2)),
    );

    expect(FfmAssistantDraftValidator.validate(valid), isEmpty);
    expect(
      FfmAssistantDraftValidator.validate(missingTitle)
          .map((issue) => issue.code),
      contains('activity_title_required'),
    );
  });

  test('ProposalJsonService mem-parsing daily_note tanpa noteDate dengan fallback ke createdAt', () {
    final result = FfmAssistantProposalJsonService.parse(
      '{"formatVersion":"ffm-assistant-proposal-v1","proposal":{"type":"daily_note","title":"Ayam mati karena kepanasan","body":"2 ekor ayam pedaging ditemukan mati tadi siang","tags":"peternakan"}}',
      createdAt: now,
    );
    expect(result.isValid, isTrue);
    expect(result.draft?.kind, FfmAssistantDraftKind.dailyNote);
    expect(result.draft?.date, now);
    expect(
      result.draft?.note,
      '2 ekor ayam pedaging ditemukan mati tadi siang',
    );
  });
}
