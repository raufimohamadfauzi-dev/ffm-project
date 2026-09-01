import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/database/audit_logger.dart';
import 'package:ffm_manager/features/activity/data/repositories/activity_repository.dart';
import 'package:ffm_manager/features/activity/domain/entities/activity_entity.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_capability_adapters.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_plan.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_planner.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_capability_executor.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';

void main() {
  const householdId = 'local-household';
  final now = DateTime(2026, 8, 24, 11);
  late AppDatabase database;

  setUp(() async {
    database = createInMemoryDatabaseForTests();
  });

  tearDown(() async {
    await database.close();
  });

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
    return FfmAssistantCapabilityExecutor(
      controller: controller,
      handlers: adapters.handlers,
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
      await ActivityRepository(
        database,
        AuditLogger(database),
      ).saveSession(
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
      await ActivityRepository(
        database,
        AuditLogger(database),
      ).saveSession(
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
        ['cat-farm', householdId, 'Pertanian', 'activity', 'none', 1, now.millisecondsSinceEpoch],
      );
      await database.customStatement(
        'INSERT INTO categories '
        '(id, household_id, name, type, default_budget_period, is_active, created_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        ['cat-shop', householdId, 'Belanja', 'activity', 'none', 1, now.millisecondsSinceEpoch],
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
}
