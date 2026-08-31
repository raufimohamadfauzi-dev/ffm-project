import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_agent_task_event_handler.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_agent_task_plan_resolver.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_autonomy_repository.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_autonomy_worker.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_plan.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_agent_work.dart';

void main() {
  late AppDatabase database;
  late FfmAssistantAutonomyRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = FfmAssistantAutonomyRepository(
      database,
      now: () => DateTime(2026, 9, 1, 12),
    );
  });

  tearDown(() => database.close());

  test('worker handler mengeksekusi plan lalu menyelesaikan goal', () async {
    const householdId = FfmAssistantAutonomyRepository.householdId;
    final goal = FfmAssistantAgentGoal(
      id: 'handler-goal',
      householdId: householdId,
      domain: 'finance',
      title: 'Handler goal',
      objective: 'Selesaikan task.',
      completionCondition: 'all_tasks_completed',
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
    );
    final task = FfmAssistantAgentTask(
      id: 'handler-task',
      goalId: goal.id,
      householdId: householdId,
      title: 'Task handler',
      capabilityId: 'read.summary',
      nextRunAt: DateTime(2026, 9, 1, 11),
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
    );
    await repository.createGoal(goal);
    await repository.createTask(task);
    final resolver = FfmAssistantAgentTaskPlanResolver(
      repository,
      now: () => DateTime(2026, 9, 1, 12),
    );
    final handler = FfmAssistantAgentTaskEventHandler(
      repository: repository,
      resolver: resolver,
      executePlan: (plan) async =>
          plan.copyWith(status: FfmAssistantActionPlanStatus.completed),
    );

    final result = await FfmAssistantAutonomyWorker(repository: repository)
        .runOnce(handler.handle);

    expect(result.processed, 1);
    expect((await repository.taskById(task.id))?.status, 'completed');
    expect((await repository.goalById(goal.id))?.status, 'completed');
    expect(await repository.executionsForTask(task.id), hasLength(2));
  });

  test(
    'handler mencatat failed dan melempar ulang agar event dapat retry',
    () async {
      final goal = FfmAssistantAgentGoal(
        id: 'handler-failed-goal',
        householdId: FfmAssistantAutonomyRepository.householdId,
        domain: 'finance',
        title: 'Failed goal',
        objective: 'Uji gagal.',
        createdAt: DateTime(2026, 9, 1),
        updatedAt: DateTime(2026, 9, 1),
      );
      final task = FfmAssistantAgentTask(
        id: 'handler-failed-task',
        goalId: goal.id,
        householdId: goal.householdId,
        title: 'Task gagal',
        capabilityId: 'read.summary',
        nextRunAt: DateTime(2026, 9, 1, 11),
        createdAt: DateTime(2026, 9, 1),
        updatedAt: DateTime(2026, 9, 1),
      );
      await repository.createGoal(goal);
      await repository.createTask(task);
      final handler = FfmAssistantAgentTaskEventHandler(
        repository: repository,
        resolver: FfmAssistantAgentTaskPlanResolver(repository),
        executePlan: (_) async => throw StateError('executor gagal'),
      );

      final result = await FfmAssistantAutonomyWorker(
        repository: repository,
        maxAttempts: 1,
      ).runOnce(handler.handle);

      expect(result.failed, 1);
      expect((await repository.taskById(task.id))?.status, 'failed');
      expect((await repository.taskById(task.id))?.retryCount, 1);
    },
  );
}
