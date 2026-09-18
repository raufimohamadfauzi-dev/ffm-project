import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_plan.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_autonomy_policy.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_capability_executor.dart';

void main() {
  test('policy read-only menolak draft dan mutation', () {
    const policy = FfmAssistantAutonomyPolicy(
      level: FfmAssistantAutonomyLevel.readOnly,
    );
    final plan = FfmAssistantActionPlan(
      id: 'read-only-policy',
      summary: 'uji policy',
      createdAt: DateTime(2026, 8, 31),
      steps: const [
        FfmAssistantActionStep(id: 'draft', capabilityId: 'draft.expense'),
      ],
    );

    expect(
      policy.validatePlan(plan, approved: false),
      FfmAssistantAutonomyBlockReason.capabilityNotAllowed,
    );
  });

  test('policy mewajibkan approval untuk mutation', () {
    const policy = FfmAssistantAutonomyPolicy();
    final plan = FfmAssistantActionPlan(
      id: 'approval-policy',
      summary: 'uji approval',
      createdAt: DateTime(2026, 8, 31),
      requiresConfirmation: true,
      steps: const [
        FfmAssistantActionStep(id: 'save', capabilityId: 'mutate.save_draft'),
        FfmAssistantActionStep(
          id: 'verify',
          capabilityId: 'verify.saved_draft',
        ),
      ],
    );

    expect(
      policy.validatePlan(plan, approved: false),
      FfmAssistantAutonomyBlockReason.approvalRequired,
    );
    expect(policy.validatePlan(plan, approved: true), isNull);
  });

  test('policy createDraft mengizinkan mutation jika sudah diapprove', () {
    const policy = FfmAssistantAutonomyPolicy(
      level: FfmAssistantAutonomyLevel.createDraft,
    );
    final plan = FfmAssistantActionPlan(
      id: 'approval-policy-create-draft',
      summary: 'uji approval create draft',
      createdAt: DateTime(2026, 8, 31),
      requiresConfirmation: true,
      steps: const [
        FfmAssistantActionStep(id: 'save', capabilityId: 'mutate.save_draft'),
      ],
    );

    expect(
      policy.validatePlan(plan, approved: false),
      FfmAssistantAutonomyBlockReason.approvalRequired,
    );
    expect(policy.validatePlan(plan, approved: true), isNull);
  });

  test('executor mengizinkan mutate.save_draft pada level createDraft setelah status executing', () async {
    final controller = FfmAssistantActionPlanController();
    final plan = FfmAssistantActionPlan(
      id: 'save-draft-confirmed',
      summary: 'uji eksekusi draf',
      createdAt: DateTime(2026, 8, 31),
      status: FfmAssistantActionPlanStatus.executing,
      requiresConfirmation: true,
      steps: const [
        FfmAssistantActionStep(id: 'save', capabilityId: 'mutate.save_draft'),
        FfmAssistantActionStep(id: 'verify', capabilityId: 'verify.saved_draft'),
      ],
    );
    controller.register(plan);
    var executed = false;
    var verified = false;
    final executor = FfmAssistantCapabilityExecutor(
      controller: controller,
      autonomyPolicy: const FfmAssistantAutonomyPolicy(
        level: FfmAssistantAutonomyLevel.createDraft,
      ),
      handlers: {
        'mutate.save_draft': (_) async {
          executed = true;
          return const FfmAssistantCapabilityExecutionResult.success('tersimpan');
        },
        'verify.saved_draft': (_) async {
          verified = true;
          return const FfmAssistantCapabilityExecutionResult.success('terverifikasi');
        },
      },
    );

    final result = await executor.execute('save-draft-confirmed');

    expect(executed, isTrue);
    expect(verified, isTrue);
    expect(result?.status, FfmAssistantActionPlanStatus.completed);
    expect(result?.blockedReason, isNull);
  });

  test('controller.update menggantikan plan yang sebelumnya berstatus blocked', () {
    final controller = FfmAssistantActionPlanController();
    final initialPlan = FfmAssistantActionPlan(
      id: 'plan-1',
      summary: 'plan awal',
      createdAt: DateTime(2026, 8, 31),
      status: FfmAssistantActionPlanStatus.blocked,
      blockedReason: 'error sebelumnya',
      steps: const [
        FfmAssistantActionStep(id: 'save', capabilityId: 'mutate.save_draft'),
      ],
    );
    controller.register(initialPlan);
    expect(controller.get('plan-1')?.status, FfmAssistantActionPlanStatus.blocked);

    // Jika dipanggil register lagi, status tetap blocked karena register idempoten
    controller.register(initialPlan.copyWith(status: FfmAssistantActionPlanStatus.planned));
    expect(controller.get('plan-1')?.status, FfmAssistantActionPlanStatus.blocked);

    // Dengan update, plan ter-reset ke status baru dan bisa dikonfirmasi
    final updatedPlan = initialPlan.copyWith(
      status: FfmAssistantActionPlanStatus.planned,
      blockedReason: null,
    );
    controller.update(updatedPlan);
    expect(controller.get('plan-1')?.status, FfmAssistantActionPlanStatus.planned);

    controller.markAwaitingConfirmation('plan-1');
    final confirmed = controller.confirm('plan-1');
    expect(confirmed?.status, FfmAssistantActionPlanStatus.executing);
  });

  test('executor memblokir plan yang melewati token budget policy', () async {
    final controller = FfmAssistantActionPlanController()
      ..register(
        FfmAssistantActionPlan(
          id: 'token-budget-policy',
          summary: 'uji budget',
          createdAt: DateTime(2026, 8, 31),
          steps: const [
            FfmAssistantActionStep(id: 'read', capabilityId: 'read.summary'),
          ],
        ),
      );
    var called = false;
    final executor = FfmAssistantCapabilityExecutor(
      controller: controller,
      autonomyPolicy: const FfmAssistantAutonomyPolicy(
        maxEstimatedTokensPerRun: 100,
      ),
      handlers: {
        'read.summary': (_) async {
          called = true;
          return const FfmAssistantCapabilityExecutionResult.success();
        },
      },
    );

    final result = await executor.execute('token-budget-policy');

    expect(called, isFalse);
    expect(result?.status, FfmAssistantActionPlanStatus.blockedByBudget);
    expect(result?.blockedReason, 'tokenBudgetExceeded');
  });

  test('policy allowlist membatasi capability per run', () {
    const policy = FfmAssistantAutonomyPolicy(
      allowedCapabilityIds: {'read.summary'},
    );
    final plan = FfmAssistantActionPlan(
      id: 'allowlist-policy',
      summary: 'uji allowlist',
      createdAt: DateTime(2026, 8, 31),
      steps: const [
        FfmAssistantActionStep(
          id: 'transactions',
          capabilityId: 'read.transactions',
        ),
      ],
    );

    expect(
      policy.validatePlan(plan, approved: false),
      FfmAssistantAutonomyBlockReason.capabilityNotAllowed,
    );
  });

  test('policy dapat diserialisasi dan menolak data konfigurasi rusak', () {
    const policy = FfmAssistantAutonomyPolicy(
      level: FfmAssistantAutonomyLevel.createDraft,
      maxActionsPerRun: 4,
      allowedCapabilityIds: {'read.summary', 'draft.expense'},
    );

    final restored = FfmAssistantAutonomyPolicy.fromJsonString(
      policy.toJsonString(),
    );

    expect(restored?.level, FfmAssistantAutonomyLevel.createDraft);
    expect(restored?.maxActionsPerRun, 4);
    expect(restored?.allowedCapabilityIds, policy.allowedCapabilityIds);
    expect(
      FfmAssistantAutonomyPolicy.fromJsonString('{"level":"bad"}'),
      isNull,
    );
  });
}
