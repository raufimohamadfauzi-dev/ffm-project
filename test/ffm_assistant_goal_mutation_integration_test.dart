import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_capability_adapters.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_plan.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_planner.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_capability_executor.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/goal/domain/entities/goal_entity.dart';
import 'package:ffm_manager/features/goal/domain/usecases/goal_crud_usecases.dart';

void main() {
  final now = DateTime(2026, 8, 24, 9);
  late AppDatabase database;
  late FfmAssistantInterpreter interpreter;

  setUp(() async {
    database = createInMemoryDatabaseForTests();
    interpreter = FfmAssistantInterpreter(database, clock: () => now);
    await SaveGoal(database)(
      GoalEntity(
        id: 'goal-emergency',
        householdId: AppContext.householdId,
        name: 'Dana darurat',
        targetAmount: 5000000,
        currentAmount: 1000000,
        targetDate: DateTime(2026, 12, 31),
        createdAt: now,
      ),
    );
  });

  tearDown(() async {
    await database.close();
  });

  Future<FfmAssistantActionPlan?> executeConfirmed(
    FfmAssistantActionPlan plan,
  ) async {
    final controller = FfmAssistantActionPlanController(now: () => now)
      ..register(plan)
      ..markAwaitingConfirmation(plan.id)
      ..confirm(plan.id);
    final adapters = FfmAssistantCapabilityAdapterRegistry(
      database: database,
      householdId: AppContext.householdId,
      clock: () => now,
    );
    return FfmAssistantCapabilityExecutor(
      controller: controller,
      handlers: adapters.handlers,
    ).execute(plan.id);
  }

  test(
    'ubah target menghasilkan draft tanpa write sebelum konfirmasi',
    () async {
      final intent = await interpreter.interpret(
        'ubah target dana darurat jadi 6000000',
      );

      expect(intent.type, FfmAssistantIntentType.updateGoal);
      expect(intent.destination, FfmAssistantDestination.goals);
      expect(intent.draft?.kind, FfmAssistantDraftKind.goalUpdate);
      expect(intent.draft?.amount, 6000000);
      expect(intent.draft?.formValues['targetId'], 'goal-emergency');
      expect(intent.needsConfirmation, isTrue);
      final goal = await GetGoal(database)(
        AppContext.householdId,
        'goal-emergency',
      );
      expect(goal?.targetAmount, 5000000);
    },
  );

  test('target ambigu tidak dipilih secara diam-diam', () async {
    await SaveGoal(database)(
      GoalEntity(
        id: 'goal-emergency-home',
        householdId: AppContext.householdId,
        name: 'Dana darurat rumah',
        targetAmount: 3000000,
        currentAmount: 0,
        targetDate: DateTime(2026, 11, 1),
        createdAt: now,
      ),
    );

    final intent = await interpreter.interpret('arsip target dana darurat');

    expect(intent.type, FfmAssistantIntentType.archiveGoal);
    expect(intent.draft, isNull);
    expect(intent.clarification, contains('menemukan 2 target'));
  });

  test(
    'ubah target melewati preview, konfirmasi, audit, dan verifikasi',
    () async {
      final intent = await interpreter.interpret(
        'ubah target dana darurat jadi 6000000',
      );
      final plan = FfmAssistantActionPlanner(now: () => now).planFor(intent)!;

      final completed = await executeConfirmed(plan);

      expect(completed?.status, FfmAssistantActionPlanStatus.completed);
      expect(
        completed?.steps.map((step) => step.capabilityId),
        equals([
          'navigate.goals',
          'draft.goal_update',
          'mutate.update',
          'verify.goal_mutation',
        ]),
      );
      final goal = await GetGoal(database)(
        AppContext.householdId,
        'goal-emergency',
      );
      expect(goal?.targetAmount, 6000000);
      expect(goal?.currentAmount, 1000000);
      final logs = await database
          .customSelect('SELECT action, entity FROM audit_logs')
          .get();
      expect(logs.last.read<String>('action'), 'simpan target');
      expect(logs.last.read<String>('entity'), 'goal');
    },
  );

  test(
    'arsip target mempertahankan progres dan menonaktifkan target',
    () async {
      final intent = await interpreter.interpret('arsip target dana darurat');
      final plan = FfmAssistantActionPlanner(now: () => now).planFor(intent)!;

      final completed = await executeConfirmed(plan);

      expect(completed?.status, FfmAssistantActionPlanStatus.completed);
      final goal = await GetGoal(database)(
        AppContext.householdId,
        'goal-emergency',
      );
      expect(goal?.isActive, isFalse);
      expect(goal?.currentAmount, 1000000);
    },
  );

  test('target baru tidak boleh lebih kecil dari progres tersimpan', () async {
    final intent = await interpreter.interpret(
      'ubah target dana darurat jadi 500000',
    );
    final plan = FfmAssistantActionPlanner(now: () => now).planFor(intent)!;

    final completed = await executeConfirmed(plan);

    expect(completed?.status, FfmAssistantActionPlanStatus.failed);
    final goal = await GetGoal(database)(
      AppContext.householdId,
      'goal-emergency',
    );
    expect(goal?.targetAmount, 5000000);
  });
}
