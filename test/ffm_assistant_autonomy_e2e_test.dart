import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_agent_task_event_handler.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_agent_task_plan_resolver.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_autonomy_repository.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_autonomy_task_execution_host.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_autonomy_worker.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_capability_adapters.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_agent_work.dart';

void main() {
  test('finance dan farming berjalan dari goal sampai completion', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = FfmAssistantAutonomyRepository(
      database,
      now: () => DateTime(2026, 9, 1, 12),
    );
    final adapters = FfmAssistantCapabilityAdapterRegistry(
      database: database,
      householdId: FfmAssistantAutonomyRepository.householdId,
    );
    final host = FfmAssistantAutonomyTaskExecutionHost(
      database: database,
      repository: repository,
      adapters: adapters,
    );
    final resolver = FfmAssistantAgentTaskPlanResolver(
      repository,
      now: () => DateTime(2026, 9, 1, 12),
    );
    final handler = FfmAssistantAgentTaskEventHandler(
      repository: repository,
      resolver: resolver,
      executePlan: host.execute,
    );
    final timestamp = DateTime(2026, 9, 1);

    for (final item in const [
      ('finance-goal-e2e', 'read.summary'),
      ('farming-goal-e2e', 'read.activity'),
    ]) {
      final goal = FfmAssistantAgentGoal(
        id: item.$1,
        householdId: FfmAssistantAutonomyRepository.householdId,
        domain: item.$1.startsWith('finance') ? 'finance' : 'farming',
        title: item.$1,
        objective: 'Jalankan monitoring.',
        completionCondition: 'all_tasks_completed',
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      await repository.createGoal(goal);
      await repository.createTask(
        FfmAssistantAgentTask(
          id: '${item.$1}-task',
          goalId: goal.id,
          householdId: goal.householdId,
          title: 'Monitoring ${goal.domain}',
          capabilityId: item.$2,
          nextRunAt: DateTime(2026, 9, 1, 11),
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      );
    }

    final result = await FfmAssistantAutonomyWorker(repository: repository)
        .runOnce(handler.handle);

    expect(result.enqueued, 2);
    expect(result.processed, 2);
    expect(
      (await repository.goalsForHousehold('local-household'))
          .every((goal) => goal.status == 'completed'),
      isTrue,
    );
  });
}
