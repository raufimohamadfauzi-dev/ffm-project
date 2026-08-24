import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_plan.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_capability_executor.dart';

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
}
