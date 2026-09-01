import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_plan.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_capabilities.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_capability_executor.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_circuit_breaker.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_tool_execution.dart';

void main() {
  test('executor menjalankan langkah read-only secara serial dan memverifikasi hasil', () async {
    final controller = FfmAssistantActionPlanController();
    controller.register(
      FfmAssistantActionPlan(
        id: 'read-plan',
        summary: 'Baca ringkasan',
        createdAt: DateTime(2026, 8, 23),
        steps: const [
          FfmAssistantActionStep(id: 'one', capabilityId: 'read.summary'),
          FfmAssistantActionStep(id: 'two', capabilityId: 'read.transactions'),
        ],
      ),
    );
    final executed = <String>[];
    final executor = FfmAssistantCapabilityExecutor(
      controller: controller,
      handlers: {
        'read.summary': (step) async {
          executed.add(step.id);
          return const FfmAssistantCapabilityExecutionResult.success(
            'ringkasan',
          );
        },
        'read.transactions': (step) async {
          executed.add(step.id);
          return const FfmAssistantCapabilityExecutionResult.success(
            'transaksi',
          );
        },
      },
    );

    final result = await executor.execute('read-plan');

    expect(executed, ['one', 'two']);
    expect(result?.status, FfmAssistantActionPlanStatus.completed);
    expect(
      result?.steps.every(
        (step) => step.status == FfmAssistantActionStepStatus.completed,
      ),
      isTrue,
    );
  });

  test(
    'executor melaporkan status langkah aktual kepada panel proses',
    () async {
      final controller = FfmAssistantActionPlanController();
      controller.register(
        FfmAssistantActionPlan(
          id: 'trace-plan',
          summary: 'Baca anggaran',
          createdAt: DateTime(2026, 8, 24),
          steps: const [
            FfmAssistantActionStep(id: 'budget', capabilityId: 'read.budget'),
          ],
        ),
      );
      final reportedStatuses = <FfmAssistantActionStepStatus>[];
      final executor = FfmAssistantCapabilityExecutor(
        controller: controller,
        handlers: {
          'read.budget': (_) async =>
              const FfmAssistantCapabilityExecutionResult.success('aman'),
        },
        onPlanProgress: (plan) {
          reportedStatuses.add(plan.steps.single.status);
        },
      );

      final result = await executor.execute('trace-plan');

      expect(result?.status, FfmAssistantActionPlanStatus.completed);
      expect(
        reportedStatuses,
        containsAllInOrder([
          FfmAssistantActionStepStatus.pending,
          FfmAssistantActionStepStatus.running,
          FfmAssistantActionStepStatus.completed,
        ]),
      );
    },
  );

  test('executor memblokir mutation sebelum confirmation', () async {
    final controller = FfmAssistantActionPlanController();
    controller.register(
      FfmAssistantActionPlan(
        id: 'mutation-plan',
        summary: 'Simpan transaksi',
        createdAt: DateTime(2026, 8, 23),
        steps: const [
          FfmAssistantActionStep(id: 'save', capabilityId: 'mutate.save_draft'),
        ],
        requiresConfirmation: true,
      ),
    );
    var executed = false;
    final executor = FfmAssistantCapabilityExecutor(
      controller: controller,
      handlers: {
        'mutate.save_draft': (_) async {
          executed = true;
          return const FfmAssistantCapabilityExecutionResult.success();
        },
      },
    );

    final result = await executor.execute('mutation-plan');

    expect(executed, isFalse);
    expect(result?.status, FfmAssistantActionPlanStatus.blocked);
  });

  test(
    'executor tidak pernah menjalankan capability di luar registry',
    () async {
      final controller = FfmAssistantActionPlanController();
      controller.register(
        FfmAssistantActionPlan(
          id: 'unknown-capability-plan',
          summary: 'Aksi tidak terdaftar',
          createdAt: DateTime(2026, 8, 31),
          steps: const [
            FfmAssistantActionStep(
              id: 'unknown-write',
              capabilityId: 'unregistered.write',
            ),
          ],
        ),
      );
      var executed = false;
      final executor = FfmAssistantCapabilityExecutor(
        controller: controller,
        handlers: {
          'unregistered.write': (_) async {
            executed = true;
            return const FfmAssistantCapabilityExecutionResult.success();
          },
        },
      );

      final result = await executor.execute('unknown-capability-plan');

      expect(executed, isFalse);
      expect(result?.status, FfmAssistantActionPlanStatus.blocked);
      expect(result?.blockedReason, contains('tidak terdaftar di registry'));
    },
  );

  test('verifikasi mutasi yang di-handle terdaftar di capability registry', () {
    final capabilityIds = FfmAssistantCapabilityRegistry.all
        .map((capability) => capability.id)
        .toSet();

    expect(
      capabilityIds,
      containsAll(<String>[
        'verify.asset_mutation',
        'verify.liability_mutation',
        'verify.budget_mutation',
      ]),
    );
  });

  test('executor mencatat lifecycle tool execution', () async {
    final controller = FfmAssistantActionPlanController()
      ..register(
        FfmAssistantActionPlan(
          id: 'tool-trace-plan',
          summary: 'Baca ringkasan',
          createdAt: DateTime(2026, 8, 31),
          steps: const [
            FfmAssistantActionStep(id: 'summary', capabilityId: 'read.summary'),
          ],
        ),
      );
    final records = <FfmAssistantToolExecution>[];
    final executor = FfmAssistantCapabilityExecutor(
      controller: controller,
      onToolExecution: (execution) async => records.add(execution),
      handlers: {
        'read.summary': (_) async =>
            const FfmAssistantCapabilityExecutionResult.success('siap'),
      },
    );

    await executor.execute('tool-trace-plan');

    expect(records.map((record) => record.status), [
      FfmAssistantToolExecutionStatus.started,
      FfmAssistantToolExecutionStatus.completed,
    ]);
    expect(records.last.attemptCount, 1);
    expect(records.last.resultSummary, 'siap');
  });

  test('circuit breaker membuka capability setelah kegagalan berulang', () {
    var now = DateTime(2026, 9, 1, 10);
    final breaker = FfmAssistantCircuitBreaker(
      failureThreshold: 2,
      cooldown: const Duration(minutes: 1),
      now: () => now,
    );

    expect(breaker.canExecute('read.summary'), isTrue);
    breaker.recordFailure('read.summary');
    expect(breaker.canExecute('read.summary'), isTrue);
    breaker.recordFailure('read.summary');
    expect(breaker.canExecute('read.summary'), isFalse);

    now = now.add(const Duration(minutes: 1));
    expect(breaker.canExecute('read.summary'), isTrue);
    breaker.recordSuccess('read.summary');
    expect(breaker.canExecute('read.summary'), isTrue);
  });

  test(
    'executor tidak memanggil handler saat circuit capability terbuka',
    () async {
      final breaker = FfmAssistantCircuitBreaker(failureThreshold: 1);
      breaker.recordFailure('read.summary');
      final controller = FfmAssistantActionPlanController()
        ..register(
          FfmAssistantActionPlan(
            id: 'open-circuit-plan',
            summary: 'Baca ringkasan',
            createdAt: DateTime(2026, 9, 1),
            steps: const [
              FfmAssistantActionStep(
                id: 'summary',
                capabilityId: 'read.summary',
              ),
            ],
          ),
        );
      var called = false;
      final executor = FfmAssistantCapabilityExecutor(
        controller: controller,
        circuitBreaker: breaker,
        handlers: {
          'read.summary': (_) async {
            called = true;
            return const FfmAssistantCapabilityExecutionResult.success();
          },
        },
      );

      final result = await executor.execute('open-circuit-plan');

      expect(called, isFalse);
      expect(result?.status, FfmAssistantActionPlanStatus.blocked);
      expect(result?.blockedReason, contains('Circuit breaker'));
    },
  );
}
