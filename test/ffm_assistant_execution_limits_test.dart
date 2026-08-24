import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_plan.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_planner.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_capability_executor.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_execution_limits.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';

void main() {
  test(
    'lebih dari tiga sub-perintah diblokir dengan pesan yang jelas',
    () async {
      final database = createInMemoryDatabaseForTests();
      addTearDown(database.close);
      final interpreter = FfmAssistantInterpreter(database);

      final intents = await interpreter.interpretMany(
        'cek ringkasan lalu cek transaksi kemudian cek target lalu cek utang',
      );

      expect(intents, hasLength(1));
      expect(intents.single.type, FfmAssistantIntentType.unknown);
      expect(
        intents.single.response,
        FfmAssistantExecutionLimits.tooComplexMessage,
      );
    },
  );

  test('plan dengan lebih dari delapan step menjadi blocked_by_budget', () {
    final now = DateTime(2026, 8, 23);
    final intent = FfmAssistantIntent(
      rawText: 'test',
      normalizedText: 'test',
      type: FfmAssistantIntentType.queryData,
      confidence: 1,
    );
    final planner = FfmAssistantActionPlanner(now: () => now);
    final plan = planner.planFor(intent);
    expect(plan, isNotNull);

    final oversized = FfmAssistantActionPlan(
      id: 'oversized',
      summary: 'test',
      createdAt: now,
      steps: List<FfmAssistantActionStep>.generate(
        FfmAssistantExecutionLimits.maxStepsPerPlan + 1,
        (index) => FfmAssistantActionStep(
          id: 'step-$index',
          capabilityId: 'read.summary',
        ),
      ),
    );
    final controller = FfmAssistantActionPlanController(now: () => now)
      ..register(oversized);
    final executor = FfmAssistantCapabilityExecutor(
      controller: controller,
      handlers: {
        'read.summary': (_) async =>
            const FfmAssistantCapabilityExecutionResult.success(),
      },
    );

    return executor.execute('oversized').then((result) {
      expect(result?.status, FfmAssistantActionPlanStatus.blockedByBudget);
      expect(result?.blockedReason, 'tooManySteps');
    });
  });

  test('controller memblokir plan aktif kedua dalam scope request', () {
    final controller = FfmAssistantActionPlanController();
    final first = FfmAssistantActionPlan(
      id: 'first',
      summary: 'first',
      createdAt: DateTime(2026, 8, 23),
      steps: const [
        FfmAssistantActionStep(id: 'read', capabilityId: 'read.summary'),
      ],
    );
    final second = FfmAssistantActionPlan(
      id: 'second',
      summary: 'second',
      createdAt: DateTime(2026, 8, 23),
      steps: const [
        FfmAssistantActionStep(id: 'read', capabilityId: 'read.summary'),
      ],
    );

    expect(
      controller.register(first).status,
      FfmAssistantActionPlanStatus.planned,
    );
    final blocked = controller.register(second);
    expect(blocked.status, FfmAssistantActionPlanStatus.blockedByBudget);
    expect(blocked.blockedReason, 'tooManyActivePlans');
  });
}
