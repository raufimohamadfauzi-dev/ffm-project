import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_autonomy_repository.dart';
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

  test('goal dan task menyimpan relasi activity/entity serta status', () async {
    final goal = FfmAssistantAgentGoal(
      id: 'goal-farm-a',
      householdId: 'household-a',
      domain: 'farming',
      entityId: 'field-a',
      activityId: 'activity-cucumber-a',
      title: 'Pantau Timun Lahan A',
      objective: 'Pantau sampai panen.',
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
    );
    final task = FfmAssistantAgentTask(
      id: 'task-farm-a-1',
      goalId: goal.id,
      householdId: goal.householdId,
      title: 'Periksa histori tujuh hari',
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
    );

    expect(await repository.createGoal(goal), same(goal));
    expect(await repository.createTask(task), same(task));
    expect(
      await repository.setGoalStatus(
        goal.id,
        FfmAssistantAgentGoalStatus.paused,
      ),
      isTrue,
    );
    expect(
      await repository.setGoalStatus(
        goal.id,
        FfmAssistantAgentGoalStatus.active,
      ),
      isTrue,
    );

    final storedGoal = await repository.goalById(goal.id);
    final storedTasks = await repository.tasksForGoal(goal.id);

    expect(storedGoal?.activityId, goal.activityId);
    expect(storedGoal?.entityId, goal.entityId);
    expect(storedGoal?.status, 'active');
    expect(storedTasks.single.title, task.title);
  });

  test('task execution mencatat retry dan history secara durable', () async {
    final goal = FfmAssistantAgentGoal(
      id: 'goal-finance',
      householdId: 'household-a',
      domain: 'finance',
      title: 'Pantau anggaran',
      objective: 'Cek kondisi anggaran.',
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
    );
    final task = FfmAssistantAgentTask(
      id: 'task-finance-1',
      goalId: goal.id,
      householdId: goal.householdId,
      title: 'Baca anggaran',
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
    );
    await repository.createGoal(goal);
    await repository.createTask(task);

    await repository.recordTaskExecution(
      FfmAssistantAgentTaskExecution(
        id: 'execution-start',
        taskId: task.id,
        goalId: goal.id,
        householdId: goal.householdId,
        status: FfmAssistantAgentTaskExecutionStatus.started,
        startedAt: DateTime(2026, 9, 1, 12),
      ),
    );
    await repository.recordTaskExecution(
      FfmAssistantAgentTaskExecution(
        id: 'execution-failed',
        taskId: task.id,
        goalId: goal.id,
        householdId: goal.householdId,
        status: FfmAssistantAgentTaskExecutionStatus.failed,
        startedAt: DateTime(2026, 9, 1, 12),
        finishedAt: DateTime(2026, 9, 1, 12, 1),
        error: 'Provider tidak tersedia.',
      ),
    );

    final storedAfterFailure = (await repository.tasksForGoal(goal.id)).single;
    final history = await repository.executionsForTask(task.id);

    expect(storedAfterFailure.status, 'failed');
    expect(storedAfterFailure.retryCount, 1);
    expect(storedAfterFailure.lastError, 'Provider tidak tersedia.');
    expect(history, hasLength(2));
  });

  test(
    'completion condition menyelesaikan goal setelah semua task selesai',
    () async {
      final goal = FfmAssistantAgentGoal(
        id: 'goal-completion',
        householdId: 'household-a',
        domain: 'finance',
        title: 'Selesaikan pemeriksaan',
        objective: 'Semua pemeriksaan harus selesai.',
        completionCondition: 'all_tasks_completed',
        createdAt: DateTime(2026, 9, 1),
        updatedAt: DateTime(2026, 9, 1),
      );
      final task = FfmAssistantAgentTask(
        id: 'completion-task',
        goalId: goal.id,
        householdId: goal.householdId,
        title: 'Pemeriksaan pertama',
        createdAt: DateTime(2026, 9, 1),
        updatedAt: DateTime(2026, 9, 1),
      );
      await repository.createGoal(goal);
      await repository.createTask(task);
      await repository.recordTaskExecution(
        FfmAssistantAgentTaskExecution(
          id: 'completion-execution',
          taskId: task.id,
          goalId: goal.id,
          householdId: goal.householdId,
          status: FfmAssistantAgentTaskExecutionStatus.completed,
          startedAt: DateTime(2026, 9, 1, 12),
          finishedAt: DateTime(2026, 9, 1, 12, 1),
        ),
      );

      expect(await repository.evaluateAndCompleteGoal(goal.id), isTrue);
      expect((await repository.goalById(goal.id))?.status, 'completed');
    },
  );

  test('goal menolak task otomatis setelah batas dua puluh task', () async {
    final goal = FfmAssistantAgentGoal(
      id: 'goal-limit',
      householdId: 'household-a',
      domain: 'finance',
      title: 'Goal dengan batas',
      objective: 'Uji batas task.',
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
    );
    await repository.createGoal(goal);

    for (
      var index = 0;
      index < FfmAssistantAutonomyRepository.maxTasksPerGoal;
      index++
    ) {
      final created = await repository.createTask(
        FfmAssistantAgentTask(
          id: 'limited-task-$index',
          goalId: goal.id,
          householdId: goal.householdId,
          title: 'Task $index',
          createdAt: DateTime(2026, 9, 1),
          updatedAt: DateTime(2026, 9, 1),
        ),
      );
      expect(created, isNotNull);
    }

    final rejected = await repository.createTask(
      FfmAssistantAgentTask(
        id: 'limited-task-overflow',
        goalId: goal.id,
        householdId: goal.householdId,
        title: 'Task overflow',
        createdAt: DateTime(2026, 9, 1),
        updatedAt: DateTime(2026, 9, 1),
      ),
    );

    expect(rejected, isNull);
  });

  test(
    'goal dapat membuat batch task dan ID tidak dapat menimpa goal lain',
    () async {
      final firstGoal = FfmAssistantAgentGoal(
        id: 'batch-goal-a',
        householdId: 'household-a',
        domain: 'finance',
        title: 'Goal A',
        objective: 'Tujuan A.',
        createdAt: DateTime(2026, 9, 1),
        updatedAt: DateTime(2026, 9, 1),
      );
      final secondGoal = FfmAssistantAgentGoal(
        id: 'batch-goal-b',
        householdId: 'household-a',
        domain: 'finance',
        title: 'Goal B',
        objective: 'Tujuan B.',
        createdAt: DateTime(2026, 9, 1),
        updatedAt: DateTime(2026, 9, 1),
      );
      await repository.createGoal(firstGoal);
      await repository.createGoal(secondGoal);

      final created = await repository.createTasksFromGoal(
        goalId: firstGoal.id,
        householdId: firstGoal.householdId,
        tasks: [
          FfmAssistantAgentTask(
            id: 'batch-task-1',
            goalId: firstGoal.id,
            householdId: firstGoal.householdId,
            title: 'Task satu',
            createdAt: DateTime(2026, 9, 1),
            updatedAt: DateTime(2026, 9, 1),
          ),
          FfmAssistantAgentTask(
            id: 'batch-task-2',
            goalId: firstGoal.id,
            householdId: firstGoal.householdId,
            title: 'Task dua',
            createdAt: DateTime(2026, 9, 1),
            updatedAt: DateTime(2026, 9, 1),
          ),
          FfmAssistantAgentTask(
            id: 'wrong-goal-task',
            goalId: secondGoal.id,
            householdId: secondGoal.householdId,
            title: 'Tidak boleh masuk',
            createdAt: DateTime(2026, 9, 1),
            updatedAt: DateTime(2026, 9, 1),
          ),
        ],
      );
      expect(created.map((task) => task.id), ['batch-task-1', 'batch-task-2']);

      expect(
        await repository.createTask(
          FfmAssistantAgentTask(
            id: 'batch-task-1',
            goalId: secondGoal.id,
            householdId: secondGoal.householdId,
            title: 'Collision',
            createdAt: DateTime(2026, 9, 1),
            updatedAt: DateTime(2026, 9, 1),
          ),
        ),
        isNull,
      );
      expect((await repository.tasksForGoal(firstGoal.id)), hasLength(2));
      expect((await repository.tasksForGoal(secondGoal.id)), isEmpty);
    },
  );
}
