import 'dart:convert';

import '../domain/ffm_assistant_action_plan.dart';
import '../domain/ffm_assistant_capabilities.dart';
import '../domain/ffm_assistant_agent_work.dart';
import 'ffm_assistant_autonomy_repository.dart';

class FfmAssistantAgentTaskPlanResolver {
  FfmAssistantAgentTaskPlanResolver(
    this._repository, {
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final FfmAssistantAutonomyRepository _repository;
  final DateTime Function() _now;

  Future<FfmAssistantActionPlan?> resolve(
    FfmAssistantAutonomyEvent event,
  ) async {
    if (event.type != 'agent.task.due') return null;
    final taskId = event.payload['taskId'];
    if (taskId is! String || taskId.trim().isEmpty) return null;
    final task = await _repository.taskById(taskId);
    if (task == null || task.householdId != event.householdId) return null;
    if (task.status != FfmAssistantAgentTaskStatus.pending.name &&
        task.status != FfmAssistantAgentTaskStatus.failed.name) {
      return null;
    }
    final capabilityId = task.capabilityId?.trim();
    if (capabilityId == null || capabilityId.isEmpty) return null;
    final capability = FfmAssistantCapabilityRegistry.find(capabilityId);
    if (capability == null) return null;

    final parameters = _decodeParameters(task.parametersJson);
    if (parameters == null) return null;
    final runId = 'agent-task:${task.id}:${event.id}';
    return FfmAssistantActionPlan(
      id: runId,
      summary: task.title,
      createdAt: _now(),
      requiresConfirmation:
          capability.requiresConfirmation ||
          capability.risk.index >= FfmAssistantCapabilityRisk.mutation.index,
      steps: [
        FfmAssistantActionStep(
          id: '${task.id}:execute',
          capabilityId: capabilityId,
          parameters: parameters,
        ),
      ],
    );
  }

  Map<String, Object?>? _decodeParameters(String value) {
    if (value.length > 4096) return null;
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map) return null;
      return decoded.cast<String, Object?>();
    } on Object {
      return null;
    }
  }
}
