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
}
