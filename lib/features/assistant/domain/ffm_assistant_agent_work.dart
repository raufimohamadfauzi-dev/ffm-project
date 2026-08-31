import 'dart:convert';

enum FfmAssistantAgentGoalStatus { active, paused, completed, cancelled }

enum FfmAssistantAgentTaskStatus {
  pending,
  running,
  completed,
  failed,
  cancelled,
}

enum FfmAssistantAgentTaskExecutionStatus {
  started,
  completed,
  failed,
  cancelled,
}

class FfmAssistantAgentCompletionEvaluator {
  const FfmAssistantAgentCompletionEvaluator();

  bool isSatisfied(
    String? condition,
    Iterable<FfmAssistantAgentTaskStatus> taskStatuses,
  ) {
    final normalized = condition?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return false;
    final statuses = taskStatuses.toList(growable: false);
    if (statuses.isEmpty) return false;
    return switch (normalized) {
      'all_tasks_completed' || 'no_pending_tasks' => statuses.every(
        (status) => status == FfmAssistantAgentTaskStatus.completed,
      ),
      'any_task_completed' => statuses.any(
        (status) => status == FfmAssistantAgentTaskStatus.completed,
      ),
      _ => false,
    };
  }
}

class FfmAssistantAgentGoal {
  const FfmAssistantAgentGoal({
    required this.id,
    required this.householdId,
    required this.domain,
    required this.title,
    required this.objective,
    required this.createdAt,
    required this.updatedAt,
    this.entityId,
    this.activityId,
    this.status = FfmAssistantAgentGoalStatus.active,
    this.priority = 0,
    this.lastRunAt,
    this.nextRunAt,
    this.completionCondition,
  });

  final String id;
  final String householdId;
  final String domain;
  final String? entityId;
  final String? activityId;
  final String title;
  final String objective;
  final FfmAssistantAgentGoalStatus status;
  final int priority;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastRunAt;
  final DateTime? nextRunAt;
  final String? completionCondition;
}

class FfmAssistantAgentTask {
  const FfmAssistantAgentTask({
    required this.id,
    required this.goalId,
    required this.householdId,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.objective,
    this.capabilityId,
    this.parameters = const <String, Object?>{},
    this.status = FfmAssistantAgentTaskStatus.pending,
    this.priority = 0,
    this.retryCount = 0,
    this.maxRetries = 3,
    this.dueAt,
    this.lastRunAt,
    this.nextRunAt,
    this.lastError,
    this.completedAt,
  });

  final String id;
  final String goalId;
  final String householdId;
  final String title;
  final String? objective;
  final String? capabilityId;
  final Map<String, Object?> parameters;
  final FfmAssistantAgentTaskStatus status;
  final int priority;
  final int retryCount;
  final int maxRetries;
  final DateTime? dueAt;
  final DateTime? lastRunAt;
  final DateTime? nextRunAt;
  final String? lastError;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;

  String get parametersJson => jsonEncode(parameters);
}

class FfmAssistantAgentTaskExecution {
  const FfmAssistantAgentTaskExecution({
    required this.id,
    required this.taskId,
    required this.goalId,
    required this.householdId,
    required this.status,
    required this.startedAt,
    this.runId,
    this.summary,
    this.error,
    this.finishedAt,
  });

  final String id;
  final String taskId;
  final String goalId;
  final String householdId;
  final String? runId;
  final FfmAssistantAgentTaskExecutionStatus status;
  final String? summary;
  final String? error;
  final DateTime startedAt;
  final DateTime? finishedAt;
}
