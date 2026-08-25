import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/database/audit_logger.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_capability_adapters.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_plan.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_planner.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_capability_executor.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/routines/data/routine_repository.dart';

void main() {
  const householdId = 'local-household';
  final now = DateTime(2026, 8, 25, 11);
  late AppDatabase database;
  late RoutineRepository routines;

  setUp(() {
    database = createInMemoryDatabaseForTests();
    routines = RoutineRepository(
      database,
      AuditLogger(database),
      clock: () => now,
    );
  });

  tearDown(() => database.close());

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

  FfmAssistantActionPlan routinePlan(
    FfmAssistantIntentType type,
    FfmAssistantDraft draft,
  ) => FfmAssistantActionPlanner(now: () => now).planFor(
    FfmAssistantIntent(
      rawText: draft.title ?? type.name,
      normalizedText: draft.title?.toLowerCase() ?? type.name,
      type: type,
      destination: FfmAssistantDestination.activity,
      draft: draft,
    ),
  )!;

  test(
    'simpan Rutinitas memakai konfirmasi, repository, audit, dan readback',
    () async {
      final plan = routinePlan(
        FfmAssistantIntentType.createRoutine,
        FfmAssistantDraft(
          kind: FfmAssistantDraftKind.routine,
          createdAt: now,
          title: 'Minum air',
          formValues: const {'entity': 'daily_routine'},
        ),
      );

      expect(plan.steps.last.capabilityId, 'verify.routine_mutation');
      expect(
        (await executeConfirmed(plan))?.status,
        FfmAssistantActionPlanStatus.completed,
      );
      final saved = await routines.readActive(householdId);
      expect(saved, hasLength(1));
      expect(saved.single.title, 'Minum air');
      final logs = await database
          .customSelect(
            'SELECT action FROM audit_logs WHERE entity = ?',
            variables: [Variable<String>('daily_routine')],
          )
          .get();
      expect(logs.map((row) => row.read<String>('action')), contains('create'));
    },
  );

  test('tanda dan pembatalan hari ini memakai target tunggal, idempoten, serta readback', () async {
    final routine = await routines.create(
      id: 'routine-mark',
      householdId: householdId,
      title: 'Peregangan',
    );
    final markPlan = routinePlan(
      FfmAssistantIntentType.markRoutineComplete,
      FfmAssistantDraft(
        kind: FfmAssistantDraftKind.routineMarkComplete,
        createdAt: now,
        title: routine.title,
        date: now,
        formValues: {
          'entity': 'daily_routine',
          'targetId': routine.id,
          'operation': 'mark',
        },
      ),
    );

    expect(
      (await executeConfirmed(markPlan))?.status,
      FfmAssistantActionPlanStatus.completed,
    );
    expect(
      await routines.completionForDay(
        householdId: householdId,
        routineId: routine.id,
        day: now,
      ),
      isNotNull,
    );
    expect(
      (await executeConfirmed(markPlan))?.status,
      FfmAssistantActionPlanStatus.completed,
    );
    expect(
      (await database.select(database.dailyRoutineCompletions).get()),
      hasLength(1),
    );

    final unmarkPlan = routinePlan(
      FfmAssistantIntentType.unmarkRoutineComplete,
      FfmAssistantDraft(
        kind: FfmAssistantDraftKind.routineUnmarkComplete,
        createdAt: now,
        title: routine.title,
        date: now,
        formValues: {
          'entity': 'daily_routine',
          'targetId': routine.id,
          'operation': 'unmark',
        },
      ),
    );
    expect(
      (await executeConfirmed(unmarkPlan))?.status,
      FfmAssistantActionPlanStatus.completed,
    );
    expect(
      await routines.completionForDay(
        householdId: householdId,
        routineId: routine.id,
        day: now,
      ),
      isNull,
    );
  });

  test(
    'aktif/nonaktif dan arsip Rutinitas memakai repository serta readback',
    () async {
      final routine = await routines.create(
        id: 'routine-state',
        householdId: householdId,
        title: 'Jalan pagi',
      );
      for (final step in [
        (
          FfmAssistantIntentType.deactivateRoutine,
          FfmAssistantDraftKind.routineDeactivate,
          'deactivate',
        ),
        (
          FfmAssistantIntentType.activateRoutine,
          FfmAssistantDraftKind.routineActivate,
          'activate',
        ),
        (
          FfmAssistantIntentType.archiveRoutine,
          FfmAssistantDraftKind.routineArchive,
          'archive',
        ),
      ]) {
        final plan = routinePlan(
          step.$1,
          FfmAssistantDraft(
            kind: step.$2,
            createdAt: now,
            title: routine.title,
            formValues: {
              'entity': 'daily_routine',
              'targetId': routine.id,
              'operation': step.$3,
            },
          ),
        );
        expect(
          (await executeConfirmed(plan))?.status,
          FfmAssistantActionPlanStatus.completed,
        );
      }
      expect((await routines.get(householdId, routine.id))?.isArchived, isTrue);
    },
  );
}
