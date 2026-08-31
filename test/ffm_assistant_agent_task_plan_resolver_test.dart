import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_agent_task_plan_resolver.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_autonomy_repository.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_agent_work.dart';

void main() {
  late AppDatabase database;
  late FfmAssistantAutonomyRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = FfmAssistantAutonomyRepository(database);
  });

  tearDown(() => database.close());

  test('resolver membentuk plan hanya dari capability terdaftar', () async {
    const householdId = 'household-a';
    final goal = FfmAssistantAgentGoal(
      id: 'resolver-goal',
      householdId: householdId,
      domain: 'finance',
      title: 'Goal resolver',
      objective: 'Jalankan pembacaan ringkasan.',
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
    );
    final task = FfmAssistantAgentTask(
      id: 'resolver-task',
      goalId: goal.id,
      householdId: householdId,
      title: 'Baca ringkasan',
      capabilityId: 'read.summary',
      parameters: const {'scope': 'month'},
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
    );
    await repository.createGoal(goal);
    await repository.createTask(task);
    final resolver = FfmAssistantAgentTaskPlanResolver(
      repository,
      now: () => DateTime(2026, 9, 1, 12),
    );

    final plan = await resolver.resolve(
      FfmAssistantAutonomyEvent(
        id: 'due-event',
        type: 'agent.task.due',
        householdId: householdId,
        occurredAt: DateTime(2026, 9, 1, 11),
        payload: {'taskId': task.id},
      ),
    );

    expect(plan?.id, 'agent-task:${task.id}:due-event');
    expect(plan?.requiresConfirmation, isFalse);
    expect(plan?.steps.single.capabilityId, 'read.summary');
    expect(plan?.steps.single.parameters['scope'], 'month');
  });

  test(
    'resolver menolak household berbeda dan capability tidak terdaftar',
    () async {
      final goal = FfmAssistantAgentGoal(
        id: 'resolver-goal-invalid',
        householdId: 'household-a',
        domain: 'finance',
        title: 'Goal invalid',
        objective: 'Uji validasi.',
        createdAt: DateTime(2026, 9, 1),
        updatedAt: DateTime(2026, 9, 1),
      );
      await repository.createGoal(goal);
      await repository.createTask(
        FfmAssistantAgentTask(
          id: 'resolver-task-invalid',
          goalId: goal.id,
          householdId: goal.householdId,
          title: 'Task invalid',
          capabilityId: 'capability.not.registered',
          createdAt: DateTime(2026, 9, 1),
          updatedAt: DateTime(2026, 9, 1),
        ),
      );
      final resolver = FfmAssistantAgentTaskPlanResolver(repository);

      expect(
        await resolver.resolve(
          FfmAssistantAutonomyEvent(
            id: 'wrong-household',
            type: 'agent.task.due',
            householdId: 'household-b',
            occurredAt: DateTime(2026, 9, 1),
            payload: {'taskId': 'resolver-task-invalid'},
          ),
        ),
        isNull,
      );
      expect(
        await resolver.resolve(
          FfmAssistantAutonomyEvent(
            id: 'invalid-capability',
            type: 'agent.task.due',
            householdId: 'household-a',
            occurredAt: DateTime(2026, 9, 1),
            payload: {'taskId': 'resolver-task-invalid'},
          ),
        ),
        isNull,
      );
    },
  );
}
