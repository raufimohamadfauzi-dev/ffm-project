import 'dart:convert';

import 'ffm_assistant_action_plan.dart';
import 'ffm_assistant_capabilities.dart';

enum FfmAssistantAutonomyLevel {
  readOnly,
  analyze,
  suggest,
  createDraft,
  executeLowRisk,
  explicitApproval,
}

enum FfmAssistantAutonomyBlockReason {
  tooManyActions,
  tokenBudgetExceeded,
  costBudgetExceeded,
  capabilityNotAllowed,
  approvalRequired,
}

class FfmAssistantAutonomyPolicy {
  const FfmAssistantAutonomyPolicy({
    this.level = FfmAssistantAutonomyLevel.explicitApproval,
    this.maxActionsPerRun = 8,
    this.maxEstimatedTokensPerRun = 4096,
    this.maxEstimatedCostMicrosPerRun = 100000,
    this.estimatedTokensPerAction = 256,
    this.estimatedCostMicrosPerAction = 1000,
    this.allowedCapabilityIds,
  });

  final FfmAssistantAutonomyLevel level;
  final int maxActionsPerRun;
  final int maxEstimatedTokensPerRun;
  final int maxEstimatedCostMicrosPerRun;
  final int estimatedTokensPerAction;
  final int estimatedCostMicrosPerAction;
  final Set<String>? allowedCapabilityIds;

  Map<String, Object?> toJson() => {
    'version': 1,
    'level': level.name,
    'maxActionsPerRun': maxActionsPerRun,
    'maxEstimatedTokensPerRun': maxEstimatedTokensPerRun,
    'maxEstimatedCostMicrosPerRun': maxEstimatedCostMicrosPerRun,
    'estimatedTokensPerAction': estimatedTokensPerAction,
    'estimatedCostMicrosPerAction': estimatedCostMicrosPerAction,
    if (allowedCapabilityIds != null)
      'allowedCapabilityIds': allowedCapabilityIds!.toList()..sort(),
  };

  String toJsonString() => jsonEncode(toJson());

  static FfmAssistantAutonomyPolicy? fromJsonString(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map) return null;
      return fromJson(decoded.cast<String, Object?>());
    } on Object {
      return null;
    }
  }

  static FfmAssistantAutonomyPolicy? fromJson(Map<String, Object?> json) {
    FfmAssistantAutonomyLevel? parsedLevel;
    for (final candidate in FfmAssistantAutonomyLevel.values) {
      if (candidate.name == json['level']) parsedLevel = candidate;
    }
    final maxActions = _positiveInt(json['maxActionsPerRun']);
    final maxTokens = _positiveInt(json['maxEstimatedTokensPerRun']);
    final maxCost = _positiveInt(json['maxEstimatedCostMicrosPerRun']);
    final tokensPerAction = _positiveInt(json['estimatedTokensPerAction']);
    final costPerAction = _positiveInt(json['estimatedCostMicrosPerAction']);
    if (parsedLevel == null ||
        maxActions == null ||
        maxTokens == null ||
        maxCost == null ||
        tokensPerAction == null ||
        costPerAction == null) {
      return null;
    }
    final rawAllowlist = json['allowedCapabilityIds'];
    final allowlist = rawAllowlist == null
        ? null
        : rawAllowlist is List
        ? rawAllowlist.whereType<String>().toSet()
        : null;
    if (rawAllowlist != null && allowlist == null) return null;
    return FfmAssistantAutonomyPolicy(
      level: parsedLevel,
      maxActionsPerRun: maxActions,
      maxEstimatedTokensPerRun: maxTokens,
      maxEstimatedCostMicrosPerRun: maxCost,
      estimatedTokensPerAction: tokensPerAction,
      estimatedCostMicrosPerAction: costPerAction,
      allowedCapabilityIds: allowlist,
    );
  }

  static int? _positiveInt(Object? value) {
    final integer = value is num ? value.toInt() : null;
    return integer != null && integer > 0 ? integer : null;
  }

  FfmAssistantAutonomyBlockReason? validatePlan(
    FfmAssistantActionPlan plan, {
    required bool approved,
  }) {
    if (plan.steps.length > maxActionsPerRun) {
      return FfmAssistantAutonomyBlockReason.tooManyActions;
    }
    if (plan.steps.length * estimatedTokensPerAction >
        maxEstimatedTokensPerRun) {
      return FfmAssistantAutonomyBlockReason.tokenBudgetExceeded;
    }
    if (plan.steps.length * estimatedCostMicrosPerAction >
        maxEstimatedCostMicrosPerRun) {
      return FfmAssistantAutonomyBlockReason.costBudgetExceeded;
    }
    for (final step in plan.steps) {
      final capability = FfmAssistantCapabilityRegistry.find(step.capabilityId);
      if (capability == null) continue;
      if (!allowsCapability(capability, approved: approved)) {
        return capability.requiresConfirmation ||
                capability.risk.index >=
                    FfmAssistantCapabilityRisk.mutation.index
            ? FfmAssistantAutonomyBlockReason.approvalRequired
            : FfmAssistantAutonomyBlockReason.capabilityNotAllowed;
      }
    }
    return null;
  }

  bool allowsCapability(
    FfmAssistantCapability capability, {
    required bool approved,
  }) {
    final allowlist = allowedCapabilityIds;
    if (allowlist != null && !allowlist.contains(capability.id)) return false;
    if (capability.risk == FfmAssistantCapabilityRisk.sensitive) {
      return approved && level == FfmAssistantAutonomyLevel.explicitApproval;
    }
    if (capability.risk == FfmAssistantCapabilityRisk.mutation) {
      return approved &&
          level.index >= FfmAssistantAutonomyLevel.executeLowRisk.index;
    }
    if (capability.risk == FfmAssistantCapabilityRisk.prepare) {
      return level.index >= FfmAssistantAutonomyLevel.createDraft.index;
    }
    return level.index >= FfmAssistantAutonomyLevel.readOnly.index;
  }
}
