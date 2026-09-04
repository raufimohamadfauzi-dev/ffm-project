import 'ffm_assistant_capabilities.dart';

import 'ffm_assistant_execution_limits.dart';

enum FfmAssistantActionPlanStatus {
  planned,
  inspecting,
  ready,
  running,
  awaitingConfirmation,
  executing,
  completed,
  cancelled,
  expired,
  failed,
  blocked,
  blockedByBudget,
}

enum FfmAssistantActionStepStatus {
  pending,
  running,
  completed,
  skipped,
  failed,
  blocked,
}

class FfmAssistantActionStep {
  const FfmAssistantActionStep({
    required this.id,
    required this.capabilityId,
    this.parameters = const <String, Object?>{},
    this.status = FfmAssistantActionStepStatus.pending,
    this.result,
    this.error,
  });

  final String id;
  final String capabilityId;
  final Map<String, Object?> parameters;
  final FfmAssistantActionStepStatus status;
  final String? result;
  final String? error;

  FfmAssistantActionStep copyWith({
    FfmAssistantActionStepStatus? status,
    String? result,
    String? error,
  }) => FfmAssistantActionStep(
    id: id,
    capabilityId: capabilityId,
    parameters: parameters,
    status: status ?? this.status,
    result: result ?? this.result,
    error: error ?? this.error,
  );
}

class FfmAssistantActionPlan {
  const FfmAssistantActionPlan({
    required this.id,
    required this.summary,
    required this.steps,
    required this.createdAt,
    this.status = FfmAssistantActionPlanStatus.planned,
    this.requiresConfirmation = false,
    this.isComposite = false,
    this.confirmedAt,
    this.completedAt,
    this.blockedReason,
  });

  final String id;
  final String summary;
  final List<FfmAssistantActionStep> steps;
  final DateTime createdAt;
  final FfmAssistantActionPlanStatus status;
  final bool requiresConfirmation;
  final bool isComposite;
  final DateTime? confirmedAt;
  final DateTime? completedAt;
  final String? blockedReason;

  bool get hasMutation => steps.any((step) {
    final capability = FfmAssistantCapabilityRegistry.find(step.capabilityId);
    return capability != null &&
        capability.risk.index >= FfmAssistantCapabilityRisk.mutation.index;
  });

  /// Memastikan workflow yang membawa write tetap kecil, serial, dan dapat
  /// dibuktikan melalui langkah verifikasi setelah mutation.
  String? get workflowSafetyIssue {
    final mutationIndexes = <int>[];
    for (var index = 0; index < steps.length; index++) {
      final capability = FfmAssistantCapabilityRegistry.find(
        steps[index].capabilityId,
      );
      if (capability != null &&
          capability.risk.index >= FfmAssistantCapabilityRisk.mutation.index) {
        mutationIndexes.add(index);
      }
    }
    if (!isComposite && mutationIndexes.length > 1) {
      return 'Workflow memuat lebih dari satu mutasi. Pecah menjadi konfirmasi terpisah.';
    }
    if (mutationIndexes.isEmpty) return null;
    if (!requiresConfirmation) {
      return 'Workflow mutasi wajib meminta konfirmasi eksplisit.';
    }
    if (!isComposite) {
      final mutationIndex = mutationIndexes.single;
      final hasVerification = steps
          .skip(mutationIndex + 1)
          .any((step) => step.capabilityId.startsWith('verify.'));
      return hasVerification
          ? null
          : 'Workflow mutasi wajib memiliki pembacaan ulang untuk verifikasi.';
    } else {
      for (var i = 0; i < mutationIndexes.length; i++) {
        final currentMutIdx = mutationIndexes[i];
        final nextMutIdx =
            i + 1 < mutationIndexes.length ? mutationIndexes[i + 1] : steps.length;
        final hasVerification = steps
            .sublist(currentMutIdx + 1, nextMutIdx)
            .any((step) => step.capabilityId.startsWith('verify.'));
        if (!hasVerification) {
          return 'Setiap mutasi pada workflow bertahap wajib memiliki pembacaan ulang untuk verifikasi.';
        }
      }
      return null;
    }
  }

  bool get isTerminal => const {
    FfmAssistantActionPlanStatus.completed,
    FfmAssistantActionPlanStatus.cancelled,
    FfmAssistantActionPlanStatus.expired,
    FfmAssistantActionPlanStatus.failed,
    FfmAssistantActionPlanStatus.blocked,
    FfmAssistantActionPlanStatus.blockedByBudget,
  }.contains(status);

  FfmAssistantActionPlan copyWith({
    List<FfmAssistantActionStep>? steps,
    FfmAssistantActionPlanStatus? status,
    bool? requiresConfirmation,
    bool? isComposite,
    DateTime? confirmedAt,
    DateTime? completedAt,
    String? blockedReason,
  }) => FfmAssistantActionPlan(
    id: id,
    summary: summary,
    steps: steps ?? this.steps,
    createdAt: createdAt,
    status: status ?? this.status,
    requiresConfirmation: requiresConfirmation ?? this.requiresConfirmation,
    isComposite: isComposite ?? this.isComposite,
    confirmedAt: confirmedAt ?? this.confirmedAt,
    completedAt: completedAt ?? this.completedAt,
    blockedReason: blockedReason ?? this.blockedReason,
  );
}

class FfmAssistantActionPlanController {
  FfmAssistantActionPlanController({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final Map<String, FfmAssistantActionPlan> _plans = {};

  FfmAssistantActionPlan? get(String id) => _plans[id];

  FfmAssistantActionPlan register(FfmAssistantActionPlan plan) {
    final existing = _plans[plan.id];
    if (existing != null) return existing;
    final activeCount = _plans.values.where((item) => !item.isTerminal).length;
    if (activeCount >= FfmAssistantExecutionLimits.maxActivePlansPerRequest) {
      final blocked = plan.copyWith(
        status: FfmAssistantActionPlanStatus.blockedByBudget,
        blockedReason: FfmAssistantBudgetBlockReason.tooManyActivePlans.name,
      );
      _plans[plan.id] = blocked;
      return blocked;
    }
    _plans[plan.id] = plan;
    return plan;
  }

  FfmAssistantActionPlan update(FfmAssistantActionPlan plan) {
    _plans[plan.id] = plan;
    return plan;
  }

  FfmAssistantActionPlan? confirm(String id) {
    final plan = _plans[id];
    if (plan == null ||
        plan.isTerminal ||
        !plan.requiresConfirmation ||
        (plan.status != FfmAssistantActionPlanStatus.planned &&
            plan.status != FfmAssistantActionPlanStatus.awaitingConfirmation)) {
      return null;
    }
    final confirmed = plan.copyWith(
      status: FfmAssistantActionPlanStatus.executing,
      confirmedAt: _now(),
    );
    _plans[id] = confirmed;
    return confirmed;
  }

  FfmAssistantActionPlan? markAwaitingConfirmation(String id) {
    final plan = _plans[id];
    if (plan == null ||
        plan.isTerminal ||
        (plan.status != FfmAssistantActionPlanStatus.planned &&
            plan.status != FfmAssistantActionPlanStatus.ready &&
            plan.status != FfmAssistantActionPlanStatus.running)) {
      return plan;
    }
    final awaiting = plan.copyWith(
      status: FfmAssistantActionPlanStatus.awaitingConfirmation,
    );
    _plans[id] = awaiting;
    return awaiting;
  }

  FfmAssistantActionPlan? blockByBudget(
    String id,
    FfmAssistantBudgetBlockReason reason,
  ) {
    final plan = _plans[id];
    if (plan == null || plan.isTerminal) return plan;
    final blocked = plan.copyWith(
      status: FfmAssistantActionPlanStatus.blockedByBudget,
      blockedReason: reason.name,
    );
    _plans[id] = blocked;
    return blocked;
  }

  FfmAssistantActionPlan? cancel(String id) {
    final plan = _plans[id];
    if (plan == null || plan.isTerminal) return plan;
    final cancelled = plan.copyWith(
      status: FfmAssistantActionPlanStatus.cancelled,
    );
    _plans[id] = cancelled;
    return cancelled;
  }

  FfmAssistantActionPlan? complete(String id) {
    final plan = _plans[id];
    if (plan == null || plan.isTerminal) return plan;
    final completed = plan.copyWith(
      status: FfmAssistantActionPlanStatus.completed,
      completedAt: _now(),
    );
    _plans[id] = completed;
    return completed;
  }
}
