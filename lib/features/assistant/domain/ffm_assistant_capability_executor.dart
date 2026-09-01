import 'dart:async';

import 'ffm_assistant_action_plan.dart';
import 'ffm_assistant_capabilities.dart';
import 'ffm_assistant_circuit_breaker.dart';
import 'ffm_assistant_autonomy_policy.dart';
import 'ffm_assistant_execution_limits.dart';
import 'ffm_assistant_tool_execution.dart';
import '../data/ffm_error_logging_service.dart';

/// Menjalankan rangkaian read-only pada transaction/snapshot yang sama.
typedef FfmAssistantReadTransaction = Future<T> Function<T>(
  Future<T> Function() action,
);

class FfmAssistantCapabilityExecutionResult {
  const FfmAssistantCapabilityExecutionResult.success([
    this.message = 'Berhasil',
  ]) : isSuccess = true;

  const FfmAssistantCapabilityExecutionResult.failure(this.message)
    : isSuccess = false;

  final bool isSuccess;
  final String message;
}

typedef FfmAssistantCapabilityHandler =
    Future<FfmAssistantCapabilityExecutionResult> Function(
      FfmAssistantActionStep step,
    );

typedef FfmAssistantPlanProgressListener = void Function(
  FfmAssistantActionPlan plan,
);

typedef FfmAssistantPlanRecordListener = Future<void> Function(
  FfmAssistantActionPlan plan,
);

typedef FfmAssistantToolExecutionListener = Future<void> Function(
  FfmAssistantToolExecution execution,
);

/// Menjalankan plan secara serial melalui handler yang di-allowlist aplikasi.
/// SLM tidak pernah menjadi handler dan tidak dapat menulis database langsung.
class FfmAssistantCapabilityExecutor {
  FfmAssistantCapabilityExecutor({
    required FfmAssistantActionPlanController controller,
    Map<String, FfmAssistantCapabilityHandler> handlers = const {},
    FfmAssistantReadTransaction? readTransaction,
    Future<void> Function()? pageReadySignal,
    FfmAssistantPlanProgressListener? onPlanProgress,
    FfmAssistantPlanRecordListener? onPlanRecorded,
    FfmAssistantToolExecutionListener? onToolExecution,
    FfmAssistantCircuitBreaker? circuitBreaker,
    FfmAssistantAutonomyPolicy autonomyPolicy =
        const FfmAssistantAutonomyPolicy(),
    Duration stepTimeout = const Duration(seconds: 10),
    int maxRetries = 2,
    FfmErrorLoggingService? errorLogger,
  }) : _handlers = Map.unmodifiable(handlers) {
    _controller = controller;
    _readTransaction = readTransaction;
    _pageReadySignal = pageReadySignal;
    _onPlanProgress = onPlanProgress;
    _onPlanRecorded = onPlanRecorded;
    _onToolExecution = onToolExecution;
    _circuitBreaker = circuitBreaker ?? FfmAssistantCircuitBreaker();
    _autonomyPolicy = autonomyPolicy;
    _stepTimeout = stepTimeout;
    _maxRetries = maxRetries;
    _errorLogger = errorLogger;
  }

  late final FfmAssistantActionPlanController _controller;
  final Map<String, FfmAssistantCapabilityHandler> _handlers;
  final Set<String> _executedSteps = <String>{};
  FfmAssistantReadTransaction? _readTransaction;
  Future<void> Function()? _pageReadySignal;
  FfmAssistantPlanProgressListener? _onPlanProgress;
  FfmAssistantPlanRecordListener? _onPlanRecorded;
  FfmAssistantToolExecutionListener? _onToolExecution;
  late final FfmAssistantCircuitBreaker _circuitBreaker;
  late FfmAssistantAutonomyPolicy _autonomyPolicy;
  late final Duration _stepTimeout;
  late final int _maxRetries;
  FfmErrorLoggingService? _errorLogger;

  FfmAssistantActionPlan? _report(FfmAssistantActionPlan? plan) {
    if (plan != null) {
      _onPlanProgress?.call(plan);
      final onPlanRecorded = _onPlanRecorded;
      if (onPlanRecorded != null) unawaited(_recordPlan(plan, onPlanRecorded));
    }
    return plan;
  }

  void setAutonomyPolicy(FfmAssistantAutonomyPolicy policy) {
    _autonomyPolicy = policy;
  }

  Future<void> _recordPlan(
    FfmAssistantActionPlan plan,
    FfmAssistantPlanRecordListener onPlanRecorded,
  ) async {
    try {
      await onPlanRecorded(plan);
    } on Object catch (error) {
      await _errorLogger?.logError(
        feature: 'capability-executor',
        errorType: error.runtimeType.toString(),
        message: 'Gagal menyimpan status plan ${plan.id}: $error',
      );
    }
  }

  Future<void> _recordToolExecution(FfmAssistantToolExecution execution) async {
    final listener = _onToolExecution;
    if (listener == null) return;
    try {
      await listener(execution);
    } on Object catch (error) {
      await _errorLogger?.logError(
        feature: 'capability-executor',
        errorType: error.runtimeType.toString(),
        message: 'Gagal menyimpan audit tool ${execution.capabilityId}: $error',
      );
    }
  }

  Future<FfmAssistantActionPlan?> execute(String planId) async {
    final plan = _controller.get(planId);
    final readTransaction = _readTransaction;
    if (plan != null && !plan.hasMutation && readTransaction != null) {
      return readTransaction(() => _executeInternal(planId));
    }
    return _executeInternal(planId);
  }

  Future<FfmAssistantActionPlan?> _executeInternal(String planId) async {
    var plan = _controller.get(planId);
    if (plan == null || plan.isTerminal) return plan;
    final policyReason = _autonomyPolicy.validatePlan(
      plan,
      approved: plan.status == FfmAssistantActionPlanStatus.executing,
    );
    if (policyReason != null &&
        policyReason != FfmAssistantAutonomyBlockReason.approvalRequired) {
      unawaited(
        _recordToolExecution(
          FfmAssistantToolExecution(
            id: '$planId:plan',
            runId: planId,
            stepId: 'plan',
            capabilityId: 'plan.policy',
            status: FfmAssistantToolExecutionStatus.blocked,
            attemptCount: 0,
            startedAt: DateTime.now(),
            finishedAt: DateTime.now(),
            error: policyReason.name,
          ),
        ),
      );
      return _report(
        _controller.blockByBudget(planId, switch (policyReason) {
          FfmAssistantAutonomyBlockReason.tooManyActions =>
            FfmAssistantBudgetBlockReason.tooManySteps,
          FfmAssistantAutonomyBlockReason.tokenBudgetExceeded =>
            FfmAssistantBudgetBlockReason.tokenBudgetExceeded,
          FfmAssistantAutonomyBlockReason.costBudgetExceeded =>
            FfmAssistantBudgetBlockReason.costBudgetExceeded,
          _ => FfmAssistantBudgetBlockReason.tooManySteps,
        }),
      );
    }
    if (plan.steps.length > FfmAssistantExecutionLimits.maxStepsPerPlan) {
      return _report(
        _controller.blockByBudget(
          planId,
          FfmAssistantBudgetBlockReason.tooManySteps,
        ),
      );
    }
    final workflowSafetyIssue = plan.workflowSafetyIssue;
    if (workflowSafetyIssue != null) {
      return _report(_controller.block(planId, workflowSafetyIssue));
    }
    if (plan.hasMutation &&
        plan.status != FfmAssistantActionPlanStatus.executing) {
      return _report(
        _controller.block(planId, 'Plan mutation belum dikonfirmasi.'),
      );
    }
    if (!plan.hasMutation &&
        plan.status == FfmAssistantActionPlanStatus.planned) {
      plan = _report(_controller.start(planId));
    }
    if (plan == null) return null;

    for (final step in plan.steps) {
      if (step.status == FfmAssistantActionStepStatus.completed ||
          step.status == FfmAssistantActionStepStatus.skipped) {
        continue;
      }
      final capability = FfmAssistantCapabilityRegistry.find(step.capabilityId);
      if (capability == null) {
        unawaited(
          _recordToolExecution(
            FfmAssistantToolExecution(
              id: '$planId:${step.id}',
              runId: planId,
              stepId: step.id,
              capabilityId: step.capabilityId,
              status: FfmAssistantToolExecutionStatus.blocked,
              attemptCount: 0,
              startedAt: DateTime.now(),
              finishedAt: DateTime.now(),
              error: 'Capability tidak terdaftar di registry.',
            ),
          ),
        );
        return _report(
          _controller.block(
            planId,
            'Capability ${step.capabilityId} tidak terdaftar di registry.',
          ),
        );
      }
      final resolvedCapability = capability;
      if (!_autonomyPolicy.allowsCapability(
        resolvedCapability,
        approved: plan!.status == FfmAssistantActionPlanStatus.executing,
      )) {
        unawaited(
          _recordToolExecution(
            FfmAssistantToolExecution(
              id: '$planId:${step.id}',
              runId: planId,
              stepId: step.id,
              capabilityId: step.capabilityId,
              status: FfmAssistantToolExecutionStatus.blocked,
              attemptCount: 0,
              startedAt: DateTime.now(),
              finishedAt: DateTime.now(),
              error: 'Capability diblokir policy autonomy.',
            ),
          ),
        );
        return _report(
          _controller.block(
            planId,
            resolvedCapability.requiresConfirmation ||
                    resolvedCapability.risk.index >=
                        FfmAssistantCapabilityRisk.mutation.index
                ? 'Capability ${step.capabilityId} membutuhkan konfirmasi eksplisit.'
                : 'Capability ${step.capabilityId} tidak diizinkan policy autonomy.',
          ),
        );
      }
      if (step.capabilityId.startsWith('navigate.')) {
        plan = _report(
          _controller.skipStep(
            planId,
            step.id,
            'Navigasi ditangani oleh AppShell/UI.',
          ),
        );
        if (plan == null) return null;
        final pageReadySignal = _pageReadySignal;
        if (pageReadySignal != null) {
          try {
            await pageReadySignal().timeout(
              const Duration(seconds: 5),
              onTimeout: () {},
            );
          } on Object {
            // Signal timeout is non-blocking; continue to next step.
          }
        }
        continue;
      }
      final executionKey = '$planId:${step.id}';
      if (_executedSteps.contains(executionKey)) {
        return _report(
          _controller.blockByBudget(
            planId,
            FfmAssistantBudgetBlockReason.stepAlreadyExecuted,
          ),
        );
      }
      final handler = _handlers[step.capabilityId];
      if (handler == null) {
        unawaited(
          _recordToolExecution(
            FfmAssistantToolExecution(
              id: executionKey,
              runId: planId,
              stepId: step.id,
              capabilityId: step.capabilityId,
              status: FfmAssistantToolExecutionStatus.blocked,
              attemptCount: 0,
              startedAt: DateTime.now(),
              finishedAt: DateTime.now(),
              error: 'Adapter capability tidak tersedia.',
            ),
          ),
        );
        return _report(
          _controller.failPlan(
            planId,
            'Capability ${step.capabilityId} belum memiliki adapter eksekusi.',
          ),
        );
      }
      if (!_circuitBreaker.canExecute(step.capabilityId)) {
        unawaited(
          _recordToolExecution(
            FfmAssistantToolExecution(
              id: executionKey,
              runId: planId,
              stepId: step.id,
              capabilityId: step.capabilityId,
              status: FfmAssistantToolExecutionStatus.blocked,
              attemptCount: 0,
              startedAt: DateTime.now(),
              finishedAt: DateTime.now(),
              error: 'Circuit breaker capability masih terbuka.',
            ),
          ),
        );
        return _report(
          _controller.block(
            planId,
            'Circuit breaker menghentikan capability ${step.capabilityId} sementara setelah beberapa kegagalan. Coba lagi nanti.',
          ),
        );
      }
      _report(_controller.startStep(planId, step.id));
      _executedSteps.add(executionKey);
      final startedAt = DateTime.now();
      await _recordToolExecution(
        FfmAssistantToolExecution(
          id: executionKey,
          runId: planId,
          stepId: step.id,
          capabilityId: step.capabilityId,
          status: FfmAssistantToolExecutionStatus.started,
          attemptCount: 0,
          startedAt: startedAt,
        ),
      );
      final isReadOnly = resolvedCapability.readOnly;
      var attempts = 0;
      var succeeded = false;
      final maxAttempts = isReadOnly ? _maxRetries + 1 : 1;
      FfmAssistantCapabilityExecutionResult result =
          const FfmAssistantCapabilityExecutionResult.failure(
            'Tidak dijalankan',
          );
      while (!succeeded && attempts < maxAttempts) {
        attempts++;
        try {
          result = await handler(step).timeout(
            _stepTimeout,
            onTimeout: () => FfmAssistantCapabilityExecutionResult.failure(
              'Capability ${step.capabilityId} melampaui batas waktu.',
            ),
          );
        } catch (error) {
          result = FfmAssistantCapabilityExecutionResult.failure(
            'Capability ${step.capabilityId} gagal. Periksa data dan coba lagi.',
          );
          await _errorLogger?.logError(
            feature: 'capability-executor',
            errorType: error.runtimeType.toString(),
            message: 'Capability ${step.capabilityId} gagal: $error',
            context: {
              'planId': planId,
              'stepId': step.id,
              'capabilityId': step.capabilityId,
              'attempt': attempts,
            },
          );
        }
        if (result.isSuccess) {
          succeeded = true;
          _circuitBreaker.recordSuccess(step.capabilityId);
        } else if (!isReadOnly || attempts >= maxAttempts) {
          _circuitBreaker.recordFailure(step.capabilityId);
          await _recordToolExecution(
            FfmAssistantToolExecution(
              id: executionKey,
              runId: planId,
              stepId: step.id,
              capabilityId: step.capabilityId,
              status: FfmAssistantToolExecutionStatus.failed,
              attemptCount: attempts,
              startedAt: startedAt,
              finishedAt: DateTime.now(),
              error: result.message,
            ),
          );
          return _report(
            _controller.failStepAndPlan(planId, step.id, result.message),
          );
        }
      }
      await _recordToolExecution(
        FfmAssistantToolExecution(
          id: executionKey,
          runId: planId,
          stepId: step.id,
          capabilityId: step.capabilityId,
          status: FfmAssistantToolExecutionStatus.completed,
          attemptCount: attempts,
          startedAt: startedAt,
          finishedAt: DateTime.now(),
          resultSummary: result.message,
        ),
      );
      plan = _report(_controller.completeStep(planId, step.id, result.message));
      if (plan == null) return null;
    }
    return _report(_controller.complete(planId));
  }
}

extension FfmAssistantActionPlanControllerExecution
    on FfmAssistantActionPlanController {
  FfmAssistantActionPlan? start(String id) {
    final plan = get(id);
    if (plan == null || plan.isTerminal) return plan;
    return replace(plan.copyWith(status: FfmAssistantActionPlanStatus.running));
  }

  FfmAssistantActionPlan? startStep(String planId, String stepId) {
    final plan = get(planId);
    if (plan == null || plan.isTerminal) return plan;
    return replace(
      plan.copyWith(
        steps: [
          for (final step in plan.steps)
            step.id == stepId
                ? step.copyWith(status: FfmAssistantActionStepStatus.running)
                : step,
        ],
      ),
    );
  }

  FfmAssistantActionPlan? skipStep(
    String planId,
    String stepId,
    String message,
  ) {
    final plan = get(planId);
    if (plan == null || plan.isTerminal) return plan;
    return replace(
      plan.copyWith(
        steps: [
          for (final step in plan.steps)
            step.id == stepId
                ? step.copyWith(
                    status: FfmAssistantActionStepStatus.skipped,
                    result: message,
                  )
                : step,
        ],
      ),
    );
  }

  FfmAssistantActionPlan? completeStep(
    String planId,
    String stepId,
    String message,
  ) {
    final plan = get(planId);
    if (plan == null || plan.isTerminal) return plan;
    return replace(
      plan.copyWith(
        steps: [
          for (final step in plan.steps)
            step.id == stepId
                ? step.copyWith(
                    status: FfmAssistantActionStepStatus.completed,
                    result: message,
                  )
                : step,
        ],
      ),
    );
  }

  FfmAssistantActionPlan? failStepAndPlan(
    String planId,
    String stepId,
    String message,
  ) {
    final plan = get(planId);
    if (plan == null || plan.isTerminal) return plan;
    return replace(
      plan.copyWith(
        status: FfmAssistantActionPlanStatus.failed,
        steps: [
          for (final step in plan.steps)
            step.id == stepId
                ? step.copyWith(
                    status: FfmAssistantActionStepStatus.failed,
                    error: message,
                  )
                : step,
        ],
      ),
    );
  }

  FfmAssistantActionPlan? failPlan(String id, String message) {
    final plan = get(id);
    if (plan == null || plan.isTerminal) return plan;
    return replace(plan.copyWith(status: FfmAssistantActionPlanStatus.failed));
  }

  FfmAssistantActionPlan? block(String id, String message) {
    final plan = get(id);
    if (plan == null || plan.isTerminal) return plan;
    return replace(
      plan.copyWith(
        status: FfmAssistantActionPlanStatus.blocked,
        blockedReason: message,
      ),
    );
  }

  FfmAssistantActionPlan replace(FfmAssistantActionPlan plan) {
    update(plan);
    return plan;
  }
}
