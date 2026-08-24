import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_plan.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_capability_executor.dart';

void main() {
  test('read-only multi-step memakai satu wrapper transaction', () async {
    final controller = FfmAssistantActionPlanController();
    controller.register(
      FfmAssistantActionPlan(
        id: 'read-plan',
        summary: 'dua pembacaan',
        createdAt: DateTime(2026, 8, 23),
        steps: const [
          FfmAssistantActionStep(id: 'summary', capabilityId: 'read.summary'),
          FfmAssistantActionStep(
            id: 'transactions',
            capabilityId: 'read.transactions',
          ),
        ],
      ),
    );
    var transactionCount = 0;
    var handlerCount = 0;
    final executor = FfmAssistantCapabilityExecutor(
      controller: controller,
      readTransaction: <T>(action) async {
        transactionCount++;
        return action();
      },
      handlers: {
        'read.summary': (_) async {
          handlerCount++;
          return const FfmAssistantCapabilityExecutionResult.success('summary');
        },
        'read.transactions': (_) async {
          handlerCount++;
          return const FfmAssistantCapabilityExecutionResult.success(
            'transactions',
          );
        },
      },
    );

    final result = await executor.execute('read-plan');

    expect(result?.status, FfmAssistantActionPlanStatus.completed);
    expect(handlerCount, 2);
    expect(transactionCount, 1);
  });

  test('mutation plan tidak memakai read transaction wrapper', () async {
    final controller = FfmAssistantActionPlanController();
    controller.register(
      FfmAssistantActionPlan(
        id: 'mutation-plan',
        summary: 'mutation',
        createdAt: DateTime(2026, 8, 23),
        requiresConfirmation: true,
        status: FfmAssistantActionPlanStatus.executing,
        steps: const [
          FfmAssistantActionStep(id: 'save', capabilityId: 'mutate.save_draft'),
          FfmAssistantActionStep(
            id: 'verify',
            capabilityId: 'verify.saved_draft',
          ),
        ],
      ),
    );
    var transactionCount = 0;
    final executor = FfmAssistantCapabilityExecutor(
      controller: controller,
      readTransaction: <T>(action) async {
        transactionCount++;
        return action();
      },
      handlers: {
        'mutate.save_draft': (_) async =>
            const FfmAssistantCapabilityExecutionResult.success('saved'),
        'verify.saved_draft': (_) async =>
            const FfmAssistantCapabilityExecutionResult.success('verified'),
      },
    );

    final result = await executor.execute('mutation-plan');

    expect(result?.status, FfmAssistantActionPlanStatus.completed);
    expect(transactionCount, 0);
  });
}
