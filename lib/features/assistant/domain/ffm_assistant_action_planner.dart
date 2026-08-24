import 'ffm_assistant_action_plan.dart';
import 'ffm_assistant_models.dart';
import 'ffm_assistant_execution_limits.dart';

class FfmAssistantActionPlanner {
  const FfmAssistantActionPlanner({DateTime Function()? now}) : _now = now;

  final DateTime Function()? _now;

  FfmAssistantActionPlan? planFor(FfmAssistantIntent intent) {
    final steps = <FfmAssistantActionStep>[];
    final planId = _planId(intent);
    final readCapability = _readCapabilityFor(intent.type);
    if (readCapability != null) {
      steps.add(
        FfmAssistantActionStep(
          id: 'read',
          capabilityId: readCapability,
          parameters: {'query': intent.normalizedText},
        ),
      );
    }
    final destination = intent.destination;
    if (destination != null) {
      steps.add(
        FfmAssistantActionStep(
          id: 'navigate',
          capabilityId: 'navigate.${destination.name}',
        ),
      );
    }
    final draft = intent.draft;
    if (draft != null) {
      final capabilityId = switch (draft.kind) {
        FfmAssistantDraftKind.income => 'draft.income',
        FfmAssistantDraftKind.expense => 'draft.expense',
        FfmAssistantDraftKind.transfer => 'draft.transfer',
        FfmAssistantDraftKind.goalDeposit => 'draft.goal_deposit',
        FfmAssistantDraftKind.goalUsage => 'draft.goal_usage',
        FfmAssistantDraftKind.goal => 'draft.goal',
        FfmAssistantDraftKind.liability => 'draft.liability',
        FfmAssistantDraftKind.receivable => 'draft.receivable',
        FfmAssistantDraftKind.asset => 'draft.asset',
        FfmAssistantDraftKind.budget => 'draft.budget',
        FfmAssistantDraftKind.masterData => 'draft.master_data',
        FfmAssistantDraftKind.reminder => 'draft.reminder',
        FfmAssistantDraftKind.activity => 'draft.activity',
        FfmAssistantDraftKind.profile => 'draft.profile',
        FfmAssistantDraftKind.transactionUpdate => 'draft.transaction_update',
        FfmAssistantDraftKind.transactionArchive => 'draft.transaction_archive',
        FfmAssistantDraftKind.transactionDelete => 'draft.transaction_delete',
        FfmAssistantDraftKind.activityArchive => 'draft.activity_archive',
        FfmAssistantDraftKind.activityDelete => 'draft.activity_delete',
      };
      steps.add(
        FfmAssistantActionStep(
          id: 'draft',
          capabilityId: capabilityId,
          parameters: _draftParameters(draft),
        ),
      );
      final parameters = _draftParameters(draft);
      final mutationCapability = switch (draft.kind) {
        FfmAssistantDraftKind.transactionUpdate => 'mutate.update',
        FfmAssistantDraftKind.transactionArchive => 'mutate.archive',
        FfmAssistantDraftKind.transactionDelete => 'sensitive.delete',
        FfmAssistantDraftKind.activityArchive => 'mutate.archive',
        FfmAssistantDraftKind.activityDelete => 'sensitive.delete',
        _ => 'mutate.save_draft',
      };
      final idempotencyKey = '$planId:save';
      steps.add(
        FfmAssistantActionStep(
          id: 'save',
          capabilityId: mutationCapability,
          parameters: {...parameters, '_idempotencyKey': idempotencyKey},
        ),
      );
      steps.add(
        FfmAssistantActionStep(
          id: 'verify',
          capabilityId: switch (draft.kind) {
            FfmAssistantDraftKind.transactionUpdate ||
            FfmAssistantDraftKind.transactionArchive ||
            FfmAssistantDraftKind.transactionDelete =>
              'verify.transaction_mutation',
            FfmAssistantDraftKind.activityArchive ||
            FfmAssistantDraftKind.activityDelete => 'verify.activity_mutation',
            _ => 'verify.saved_draft',
          },
          parameters: {...parameters, '_idempotencyKey': idempotencyKey},
        ),
      );
    }
    if (steps.isEmpty) return null;
    final exceedsBudget =
        steps.length > FfmAssistantExecutionLimits.maxStepsPerPlan;
    final plan = FfmAssistantActionPlan(
      id: planId,
      summary: exceedsBudget
          ? FfmAssistantExecutionLimits.tooComplexMessage
          : (intent.response ?? intent.normalizedText),
      steps: steps,
      createdAt: (_now ?? DateTime.now)(),
      requiresConfirmation: draft != null,
      status: exceedsBudget
          ? FfmAssistantActionPlanStatus.blockedByBudget
          : FfmAssistantActionPlanStatus.planned,
      blockedReason: exceedsBudget
          ? FfmAssistantBudgetBlockReason.tooManySteps.name
          : null,
    );
    return plan;
  }

  String _planId(FfmAssistantIntent intent) =>
      'plan-${_stableHash('${intent.type.name}|${intent.normalizedText}').toRadixString(16)}';

  int _stableHash(String value) {
    var hash = 2166136261;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 16777619) & 0x7fffffff;
    }
    return hash;
  }

  String? _readCapabilityFor(FfmAssistantIntentType type) => switch (type) {
    FfmAssistantIntentType.queryData ||
    FfmAssistantIntentType.transactionStats => 'read.transactions',
    FfmAssistantIntentType.weeklyAnalysis ||
    FfmAssistantIntentType.financialWarnings => 'read.analysis',
    _ => null,
  };

  Map<String, Object?> _draftParameters(FfmAssistantDraft draft) => {
    'kind': draft.kind.name,
    if (draft.amount != null) 'amount': draft.amount,
    if (draft.title != null) 'title': draft.title,
    if (draft.partyName != null) 'party': draft.partyName,
    if (draft.fromAccountName != null) 'fromAccount': draft.fromAccountName,
    if (draft.toAccountName != null) 'toAccount': draft.toAccountName,
    if (draft.categoryName != null) 'category': draft.categoryName,
    if (draft.goalName != null) 'goal': draft.goalName,
    if (draft.note != null) 'note': draft.note,
    if (draft.date != null) 'date': draft.date!.toIso8601String(),
    ...draft.formValues,
  };
}
