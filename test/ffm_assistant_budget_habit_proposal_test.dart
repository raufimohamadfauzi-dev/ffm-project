import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_planner.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_budget_habit_proposal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final facts = FfmAssistantBudgetHabitAnalysisFacts({
    'sampleMonths': 3,
    'averageSpend': 250000,
  });

  FfmAssistantBudgetHabitProposalItem item({
    String categoryId = 'category-food',
    String categoryName = 'Makan',
    FfmAssistantBudgetHabitCadence cadence =
        FfmAssistantBudgetHabitCadence.monthly,
    int amount = 300000,
  }) => FfmAssistantBudgetHabitProposalItem(
    categoryId: categoryId,
    categoryName: categoryName,
    cadence: cadence,
    amount: amount,
    analysisFacts: facts,
  );

  test('proposal immutable and validates duplicates and amounts globally', () {
    final source = [item(), item()];
    final proposal = FfmAssistantBudgetHabitProposal(items: source);
    source.clear();

    expect(proposal.items, hasLength(2));
    expect(() => proposal.items.add(item()), throwsUnsupportedError);
    expect(() => facts.values['sampleMonths'] = 2, throwsUnsupportedError);

    final invalid = FfmAssistantBudgetHabitProposal(
      items: [
        item(amount: 0),
        item(),
        item(categoryId: 'category-transport', categoryName: 'Transport'),
      ],
    );
    expect(
      invalid.validate().map((issue) => issue.code),
      containsAll(['amount_must_be_positive', 'duplicate_budget']),
    );

    final invalidCadence = FfmAssistantBudgetHabitProposal(
      items: [
        FfmAssistantBudgetHabitProposalItem.fromPeriodType(
          categoryId: 'category-food',
          categoryName: 'Makan',
          periodType: 'yearly',
          amount: 300000,
          analysisFacts: facts,
        ),
      ],
    );
    expect(invalidCadence.validate().single.code, 'invalid_cadence');
  });

  test('planner creates a safe composite budget plan from valid items', () {
    final proposal = FfmAssistantBudgetHabitProposal(
      items: [
        item(),
        item(
          categoryId: 'category-transport',
          categoryName: 'Transport',
          cadence: FfmAssistantBudgetHabitCadence.weekly,
          amount: 100000,
        ),
      ],
    );
    final plan = FfmAssistantActionPlanner(now: () => DateTime(2026, 9, 17))
        .planBudgetHabitProposal(proposal);

    expect(plan, isNotNull);
    expect(plan!.isComposite, isTrue);
    expect(plan.requiresConfirmation, isTrue);
    expect(plan.workflowSafetyIssue, isNull);
    expect(
      plan.steps.where((step) => step.capabilityId == 'read.budget'),
      hasLength(1),
    );
    expect(plan.steps.map((step) => step.capabilityId), [
      'read.budget',
      'draft.budget',
      'mutate.save_draft',
      'verify.saved_draft',
      'draft.budget',
      'mutate.save_draft',
      'verify.saved_draft',
    ]);
    expect(plan.steps[1].parameters['categoryId'], 'category-food');
    expect(plan.steps[1].parameters['category'], 'Makan');
    expect(plan.steps[4].parameters['periodType'], 'weekly');
  });

  test('planner rejects invalid proposals before making drafts', () {
    final proposal = FfmAssistantBudgetHabitProposal(items: [item(amount: -1)]);

    expect(
      const FfmAssistantActionPlanner().planBudgetHabitProposal(proposal),
      isNull,
    );
  });

  test(
    'planner splits large proposals into stable confirmation-gated batches',
    () {
      final proposal = FfmAssistantBudgetHabitProposal(
        items: [
          item(),
          item(categoryId: 'category-transport', categoryName: 'Transport'),
          item(categoryId: 'category-bills', categoryName: 'Tagihan'),
          item(categoryId: 'category-health', categoryName: 'Kesehatan'),
          item(categoryId: 'category-education', categoryName: 'Pendidikan'),
        ],
      );
      final planner = FfmAssistantActionPlanner(
        now: () => DateTime(2026, 9, 17),
      );

      final batches = planner.planBudgetHabitProposalBatches(proposal);

      expect(batches, isNotNull);
      expect(batches!.plans, hasLength(3));
      expect(batches.plans.map((batch) => batch.batch.batchNumber), [1, 2, 3]);
      expect(batches.plans.map((batch) => batch.batch.totalBatches), [3, 3, 3]);
      expect(
        batches.plans
            .expand((batch) => batch.batch.items)
            .map((item) => item.categoryId),
        proposal.items.map((item) => item.categoryId),
      );
      for (final batch in batches.plans) {
        expect(batch.plan.requiresConfirmation, isTrue);
        expect(batch.plan.steps.length, lessThanOrEqualTo(8));
        expect(batch.plan.workflowSafetyIssue, isNull);
      }
      expect(
        planner
            .planBudgetHabitProposalBatches(proposal)!
            .plans
            .map((batch) => batch.plan.id),
        batches.plans.map((batch) => batch.plan.id),
      );
      expect(
        planner.planBudgetHabitProposal(proposal),
        isNull,
        reason: 'The single-plan API must not silently omit later batches.',
      );
    },
  );

  test('invalid entries in later batches reject the complete proposal', () {
    final proposal = FfmAssistantBudgetHabitProposal(
      items: [
        item(),
        item(categoryId: 'category-transport', categoryName: 'Transport'),
        item(categoryId: 'category-bills', categoryName: 'Tagihan', amount: 0),
        FfmAssistantBudgetHabitProposalItem.fromPeriodType(
          categoryId: 'category-health',
          categoryName: 'Kesehatan',
          periodType: 'yearly',
          amount: 100000,
          analysisFacts: facts,
        ),
        item(categoryId: 'category-food', categoryName: 'Makan kedua'),
      ],
    );

    expect(
      proposal.validate().map((issue) => issue.code),
      containsAll([
        'amount_must_be_positive',
        'invalid_cadence',
        'duplicate_budget',
      ]),
    );
    expect(proposal.batches(maxItemsPerBatch: 2), isEmpty);
    expect(
      const FfmAssistantActionPlanner().planBudgetHabitProposalBatches(
        proposal,
      ),
      isNull,
    );
  });
}
