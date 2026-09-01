enum FfmAssistantToolExecutionStatus { started, completed, failed, blocked }

class FfmAssistantToolExecution {
  const FfmAssistantToolExecution({
    required this.id,
    required this.runId,
    required this.stepId,
    required this.capabilityId,
    required this.status,
    required this.attemptCount,
    required this.startedAt,
    this.resultSummary,
    this.error,
    this.finishedAt,
  });

  final String id;
  final String runId;
  final String stepId;
  final String capabilityId;
  final FfmAssistantToolExecutionStatus status;
  final int attemptCount;
  final String? resultSummary;
  final String? error;
  final DateTime startedAt;
  final DateTime? finishedAt;
}
