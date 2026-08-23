import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_plan.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_capability_executor.dart';

void main() {
  test(
    'step kedua gagal, step ketiga tidak jalan, hasil pertama tetap ada',
    () async {
      final controller = FfmAssistantActionPlanController();
      controller.register(
        FfmAssistantActionPlan(
          id: 'partial',
          summary: 'partial',
          createdAt: DateTime(2026, 8, 23),
          steps: const [
            FfmAssistantActionStep(id: 'one', capabilityId: 'read.summary'),
            FfmAssistantActionStep(id: 'two', capabilityId: 'read.analysis'),
            FfmAssistantActionStep(id: 'three', capabilityId: 'read.accounts'),
          ],
        ),
      );
      var thirdCalled = false;
      final executor = FfmAssistantCapabilityExecutor(
        controller: controller,
        handlers: {
          'read.summary': (_) async =>
              const FfmAssistantCapabilityExecutionResult.success(
                'pemasukan berhasil',
              ),
          'read.analysis': (_) async =>
              const FfmAssistantCapabilityExecutionResult.failure(
                'data analisis gagal',
              ),
          'read.accounts': (_) async {
            thirdCalled = true;
            return const FfmAssistantCapabilityExecutionResult.success();
          },
        },
      );

      final result = await executor.execute('partial');

      expect(result?.status, FfmAssistantActionPlanStatus.failed);
      expect(result?.steps[0].status, FfmAssistantActionStepStatus.completed);
      expect(result?.steps[0].result, 'pemasukan berhasil');
      expect(result?.steps[1].status, FfmAssistantActionStepStatus.failed);
      expect(result?.steps[1].error, 'data analisis gagal');
      expect(result?.steps[2].status, FfmAssistantActionStepStatus.pending);
      expect(thirdCalled, isFalse);
    },
  );
}
