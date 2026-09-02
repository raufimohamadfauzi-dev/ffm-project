import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_plan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_planner.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';

void main() {
  test('planner membuat navigasi untuk intent halaman', () {
    final intent = FfmAssistantIntent(
      rawText: 'buka anggaran',
      normalizedText: 'buka anggaran',
      type: FfmAssistantIntentType.openPage,
      destination: FfmAssistantDestination.budget,
      response: 'Membuka Anggaran.',
    );

    final plan = const FfmAssistantActionPlanner().planFor(intent);

    expect(plan, isNotNull);
    expect(plan!.steps.single.capabilityId, 'navigate.budget');
    expect(plan.requiresConfirmation, isFalse);
  });

  test('planner membuat draft dan save gate untuk intent transaksi', () {
    final intent = FfmAssistantIntent(
      rawText: 'catat makan 50000',
      normalizedText: 'catat makan 50000',
      type: FfmAssistantIntentType.createExpense,
      destination: FfmAssistantDestination.transactions,
      draft: FfmAssistantDraft(
        kind: FfmAssistantDraftKind.expense,
        amount: 50000,
        categoryName: 'Makanan',
        createdAt: DateTime(2026, 8, 23),
      ),
    );

    final plan = const FfmAssistantActionPlanner().planFor(intent);

    expect(plan, isNotNull);
    expect(plan!.steps.map((step) => step.capabilityId), [
      'read.accounts',
      'read.categories',
      'navigate.transactions',
      'draft.expense',
      'mutate.save_draft',
      'verify.saved_draft',
    ]);
    expect(plan.requiresConfirmation, isTrue);
    expect(plan.hasMutation, isTrue);
    expect(plan.workflowSafetyIssue, isNull);
    expect(const FfmAssistantActionPlanner().planFor(intent)!.id, plan.id);
  });

  test('guard workflow memblokir multi-mutasi dan mutasi tanpa verifikasi', () {
    final multiMutation = FfmAssistantActionPlan(
      id: 'unsafe-multi',
      summary: 'uji',
      createdAt: DateTime(2026, 8, 24),
      requiresConfirmation: true,
      steps: const [
        FfmAssistantActionStep(id: 'save-a', capabilityId: 'mutate.save_draft'),
        FfmAssistantActionStep(id: 'save-b', capabilityId: 'mutate.archive'),
      ],
    );
    final noVerification = FfmAssistantActionPlan(
      id: 'unsafe-verify',
      summary: 'uji',
      createdAt: DateTime(2026, 8, 24),
      requiresConfirmation: true,
      steps: const [
        FfmAssistantActionStep(id: 'save', capabilityId: 'mutate.save_draft'),
      ],
    );

    expect(multiMutation.workflowSafetyIssue, contains('lebih dari satu'));
    expect(noVerification.workflowSafetyIssue, contains('pembacaan ulang'));
  });
}
