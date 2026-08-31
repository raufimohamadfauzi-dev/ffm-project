import '../domain/ffm_assistant_action_plan.dart';
import '../domain/ffm_assistant_agent_work.dart';
import 'ffm_assistant_agent_task_plan_resolver.dart';
import 'ffm_assistant_autonomy_repository.dart';

typedef FfmAssistantAgentPlanExecutor =
    Future<FfmAssistantActionPlan?> Function(FfmAssistantActionPlan plan);

/// Adapter dari event durable ke executor plan aplikasi.
/// Resolver tidak mengeksekusi capability dan executor tetap menjadi boundary
/// untuk policy, confirmation, registry, serta verification.
class FfmAssistantAgentTaskEventHandler {
  FfmAssistantAgentTaskEventHandler({
    required this._repository,
    required this._resolver,
    required this._executePlan,
  });

  final FfmAssistantAutonomyRepository _repository;
  final FfmAssistantAgentTaskPlanResolver _resolver;
  final FfmAssistantAgentPlanExecutor _executePlan;

  Future<void> handle(FfmAssistantAutonomyEvent event) async {
    final plan = await _resolver.resolve(event);
    if (plan == null) {
      throw StateError(
        'Event task tidak dapat diubah menjadi plan yang valid.',
      );
    }
    final taskId = event.payload['taskId'];
    if (taskId is! String) throw StateError('Event taskId tidak valid.');
    final task = await _repository.taskById(taskId);
    if (task == null) throw StateError('Task tidak ditemukan.');
    final attempt = task.retryCount + 1;
    final executionId = '${plan.id}:attempt:$attempt';
    await _repository.recordTaskExecution(
      FfmAssistantAgentTaskExecution(
        id: '$executionId:started',
        taskId: task.id,
        goalId: task.goalId,
        householdId: task.householdId,
        runId: plan.id,
        status: FfmAssistantAgentTaskExecutionStatus.started,
        startedAt: DateTime.now(),
      ),
    );

    try {
      final result = await _executePlan(plan);
      final completed =
          result?.status == FfmAssistantActionPlanStatus.completed;
      final executionStatus = completed
          ? FfmAssistantAgentTaskExecutionStatus.completed
          : FfmAssistantAgentTaskExecutionStatus.failed;
      await _repository.recordTaskExecution(
        FfmAssistantAgentTaskExecution(
          id: '$executionId:finished',
          taskId: task.id,
          goalId: task.goalId,
          householdId: task.householdId,
          runId: plan.id,
          status: executionStatus,
          startedAt: DateTime.now(),
          finishedAt: DateTime.now(),
          summary: completed ? 'Task selesai.' : 'Plan task tidak selesai.',
          error: completed ? null : result?.blockedReason,
        ),
      );
      if (completed) await _repository.evaluateAndCompleteGoal(task.goalId);
    } on Object catch (error) {
      await _repository.recordTaskExecution(
        FfmAssistantAgentTaskExecution(
          id: '$executionId:failed',
          taskId: task.id,
          goalId: task.goalId,
          householdId: task.householdId,
          runId: plan.id,
          status: FfmAssistantAgentTaskExecutionStatus.failed,
          startedAt: DateTime.now(),
          finishedAt: DateTime.now(),
          error: error.toString(),
        ),
      );
      rethrow;
    }
  }
}
