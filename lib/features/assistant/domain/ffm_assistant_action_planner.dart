import 'dart:convert';

import '../../reminder/domain/entities/reminder_entity.dart';
import 'ffm_assistant_action_plan.dart';
import 'ffm_assistant_budget_habit_proposal.dart';
import 'ffm_assistant_models.dart';
import 'ffm_assistant_execution_limits.dart';

class FfmAssistantActionPlanner {
  const FfmAssistantActionPlanner({this.now});

  final DateTime Function()? now;

  /// Returns canonical values that must survive into a save/preview step.
  /// This is deliberately non-throwing: the draft validator owns user-facing
  /// errors, while tests and callers can assert the plan contract explicitly.
  static List<String> missingRequiredParameters(
    FfmAssistantDraft draft,
    Map<String, Object?> parameters,
  ) {
    bool present(String key) {
      final value = parameters[key];
      return value != null && value.toString().trim().isNotEmpty;
    }

    final required = switch (draft.kind) {
      FfmAssistantDraftKind.income => const ['amount', 'toAccount', 'category'],
      FfmAssistantDraftKind.expense => const [
        'amount',
        'fromAccount',
        'category',
      ],
      FfmAssistantDraftKind.transfer => const [
        'amount',
        'fromAccount',
        'toAccount',
      ],
      FfmAssistantDraftKind.goal => const ['title', 'amount', 'date'],
      FfmAssistantDraftKind.goalDeposit => const [
        'amount',
        'goal',
        'fromAccount',
        'date',
      ],
      FfmAssistantDraftKind.goalUsage => const [
        'amount',
        'goal',
        'toAccount',
        'date',
      ],
      FfmAssistantDraftKind.activity => const ['title', 'date'],
      FfmAssistantDraftKind.dailyNote => const ['note', 'date'],
      FfmAssistantDraftKind.reminder => const ['title', 'date'],
      FfmAssistantDraftKind.budget => const ['title', 'amount', 'periodType'],
      FfmAssistantDraftKind.liability || FfmAssistantDraftKind.receivable =>
        const ['title', 'party', 'amount', 'date'],
      FfmAssistantDraftKind.liabilityPayment ||
      FfmAssistantDraftKind.receivablePayment => const [
        'amount',
        'targetId',
        'date',
        'accountId',
      ],
      FfmAssistantDraftKind.cashFlowProfile => const [
        'title',
        'initialCapital',
        'estimatedInflow',
        'targetHarvestDate',
        'cycleProfileType',
      ],
      FfmAssistantDraftKind.monitoringJob => const [
        'title',
        'preset',
        'cadence',
        'targetTimeMinutes',
      ],
      FfmAssistantDraftKind.masterData => const ['title', 'category'],
      _ => const <String>[],
    };
    return [
      for (final key in required)
        if (!present(key)) key,
    ];
  }

  FfmAssistantActionPlan? planFor(FfmAssistantIntent intent) {
    final steps = <FfmAssistantActionStep>[];
    final planId = _planId(intent);
    final prerequisiteReads = _prerequisiteReadCapabilitiesFor(intent);
    for (var i = 0; i < prerequisiteReads.length; i++) {
      steps.add(
        FfmAssistantActionStep(
          id: prerequisiteReads.length == 1 ? 'read' : 'read_${i + 1}',
          capabilityId: prerequisiteReads[i],
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
    if (intent.type == FfmAssistantIntentType.changeTheme) {
      final theme = intent.pluginMetadata?['theme']?.toString() ?? 'system';
      steps.add(
        FfmAssistantActionStep(
          id: 'set_theme',
          capabilityId: 'system.set_theme',
          parameters: {'theme': theme},
        ),
      );
    }
    if (intent.type == FfmAssistantIntentType.changeHijriAdjustment) {
      final adjustment =
          intent.pluginMetadata?['adjustment']?.toString() ?? '0';
      steps.add(
        FfmAssistantActionStep(
          id: 'set_hijri_adjustment',
          capabilityId: 'system.set_hijri_adjustment',
          parameters: {'adjustment': adjustment},
        ),
      );
    }
    if (intent.pluginMetadata?['refreshMarketNews'] == true) {
      steps.add(
        const FfmAssistantActionStep(
          id: 'refresh_market',
          capabilityId: 'market.refresh',
        ),
      );
    }
    final draft = intent.draft;
    if (draft != null) {
      final existingReminder = _isExistingReminder(draft);
      final capabilityId = existingReminder
          ? 'draft.reminder_update'
          : _draftCapabilityFor(draft.kind);
      final draftParameters = {
        ..._draftParameters(draft),
        if (existingReminder) 'operation': 'update',
      };
      steps.add(
        FfmAssistantActionStep(
          id: 'draft',
          capabilityId: capabilityId,
          parameters: draftParameters,
        ),
      );
      final parameters = draftParameters;
        final mutationCapability = existingReminder
          ? 'mutate.update'
          : _mutationCapabilityFor(draft.kind);
        final verifyCapability = existingReminder
          ? 'verify.reminder_mutation'
          : _verifyCapabilityFor(draft.kind);
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
          capabilityId: verifyCapability,
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
      createdAt: (now ?? DateTime.now)(),
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

  /// Merancang Rencana Aksi Bertahap (Multi-Step Action Plan)
  /// untuk kebutuhan finansial gabungan (misal: target + alokasi pos + pengingat).
  FfmAssistantActionPlan? planCompositePlan({
    required String summary,
    required List<FfmAssistantDraft> drafts,
    String? customPlanId,
  }) {
    if (drafts.isEmpty) return null;
    final planId =
        customPlanId ??
        'composite-plan-${_stableHash(summary).toRadixString(16)}';
    final steps = <FfmAssistantActionStep>[];

    // Kumpulkan pembacaan prasyarat yang terdeduplikasi untuk seluruh draf
    final reads = <String>[];
    for (final draft in drafts) {
      for (final r in _prerequisiteReadsForDraft(draft.kind)) {
        if (!reads.contains(r)) {
          reads.add(r);
        }
      }
    }

    for (var i = 0; i < reads.length; i++) {
      steps.add(
        FfmAssistantActionStep(
          id: reads.length == 1 ? 'read' : 'read_${i + 1}',
          capabilityId: reads[i],
          parameters: {'query': summary},
        ),
      );
    }

    // Bangun rangkaian draft -> save -> verify untuk setiap draf berurutan
    for (var i = 0; i < drafts.length; i++) {
      final draft = drafts[i];
      final stepSuffix = drafts.length == 1 ? '' : '_${i + 1}';
        final existingReminder = _isExistingReminder(draft);
        final draftCapability = existingReminder
          ? 'draft.reminder_update'
          : _draftCapabilityFor(draft.kind);
        final mutationCapability = existingReminder
          ? 'mutate.update'
          : _mutationCapabilityFor(draft.kind);
        final verifyCapability = existingReminder
          ? 'verify.reminder_mutation'
          : _verifyCapabilityFor(draft.kind);
        final parameters = {
          ..._draftParameters(draft),
          if (existingReminder) 'operation': 'update',
        };
      final idempotencyKey = '$planId:save$stepSuffix';

      steps.add(
        FfmAssistantActionStep(
          id: 'draft$stepSuffix',
          capabilityId: draftCapability,
          parameters: parameters,
        ),
      );
      steps.add(
        FfmAssistantActionStep(
          id: 'save$stepSuffix',
          capabilityId: mutationCapability,
          parameters: {...parameters, '_idempotencyKey': idempotencyKey},
        ),
      );
      steps.add(
        FfmAssistantActionStep(
          id: 'verify$stepSuffix',
          capabilityId: verifyCapability,
          parameters: {...parameters, '_idempotencyKey': idempotencyKey},
        ),
      );
    }

    if (steps.isEmpty) return null;
    final exceedsBudget =
        steps.length > FfmAssistantExecutionLimits.maxStepsPerPlan;
    return FfmAssistantActionPlan(
      id: planId,
      summary: exceedsBudget
          ? FfmAssistantExecutionLimits.tooComplexMessage
          : summary,
      steps: steps,
      createdAt: (now ?? DateTime.now)(),
      requiresConfirmation: true,
      isComposite: drafts.length > 1,
      status: exceedsBudget
          ? FfmAssistantActionPlanStatus.blockedByBudget
          : FfmAssistantActionPlanStatus.planned,
      blockedReason: exceedsBudget
          ? FfmAssistantBudgetBlockReason.tooManySteps.name
          : null,
    );
  }

  /// Builds a confirmation-gated plan without letting habit analysis mutate data.
  FfmAssistantActionPlan? planBudgetHabitProposal(
    FfmAssistantBudgetHabitProposal proposal,
  ) {
    final batches = planBudgetHabitProposalBatches(proposal);
    return batches != null && batches.plans.length == 1
        ? batches.plans.single.plan
        : null;
  }

  /// Builds all safe, confirmation-gated execution batches for a proposal.
  /// Callers must present and confirm each returned plan independently.
  FfmAssistantBudgetHabitProposalPlanBatches? planBudgetHabitProposalBatches(
    FfmAssistantBudgetHabitProposal proposal,
  ) {
    if (!proposal.isValid) return null;
    // Each batch has one prerequisite read plus draft/save/verify per item.
    const prerequisiteSteps = 1;
    const stepsPerItem = 3;
    final maxItemsPerBatch =
        (FfmAssistantExecutionLimits.maxStepsPerPlan - prerequisiteSteps) ~/
        stepsPerItem;
    if (maxItemsPerBatch <= 0) return null;

    final createdAt = (now ?? DateTime.now)();
    final proposalBatches = proposal.batches(
      maxItemsPerBatch: maxItemsPerBatch,
    );
    final plans = <FfmAssistantBudgetHabitProposalPlanBatch>[];
    final proposalId = _stableHash(
      proposal.items
          .map(
            (item) => '${item.categoryId}|${item.cadence!.name}|${item.amount}',
          )
          .join(';'),
    ).toRadixString(16);
    for (final batch in proposalBatches) {
      final drafts = batch.items
          .map(
            (item) => FfmAssistantDraft(
              kind: FfmAssistantDraftKind.budget,
              createdAt: createdAt,
              title: item.categoryName,
              categoryName: item.categoryName,
              amount: item.amount,
              date: createdAt,
              formValues: {
                'categoryId': item.categoryId,
                'categoryIdsJson': jsonEncode([item.categoryId]),
                'periodType': item.cadence!.periodType,
              },
            ),
          )
          .toList(growable: false);
      final plan = planCompositePlan(
        summary:
            'Usulan anggaran berdasarkan kebiasaan belanja (${batch.batchNumber}/${batch.totalBatches}).',
        drafts: drafts,
        customPlanId: 'budget-habit-$proposalId-batch-${batch.batchNumber}',
      );
      if (plan == null ||
          plan.steps.length > FfmAssistantExecutionLimits.maxStepsPerPlan) {
        return null;
      }
      plans.add(
        FfmAssistantBudgetHabitProposalPlanBatch(batch: batch, plan: plan),
      );
    }
    return FfmAssistantBudgetHabitProposalPlanBatches(plans: plans);
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

  static String _draftCapabilityFor(
    FfmAssistantDraftKind kind,
  ) => switch (kind) {
    FfmAssistantDraftKind.income => 'draft.income',
    FfmAssistantDraftKind.expense => 'draft.expense',
    FfmAssistantDraftKind.transfer => 'draft.transfer',
    FfmAssistantDraftKind.goalDeposit => 'draft.goal_deposit',
    FfmAssistantDraftKind.goalUsage => 'draft.goal_usage',
    FfmAssistantDraftKind.goal => 'draft.goal',
    FfmAssistantDraftKind.liability => 'draft.liability',
    FfmAssistantDraftKind.liabilityUpdate => 'draft.liability_update',
    FfmAssistantDraftKind.liabilityArchive => 'draft.liability_archive',
    FfmAssistantDraftKind.liabilityPayment => 'draft.liability_payment',
    FfmAssistantDraftKind.receivable => 'draft.receivable',
    FfmAssistantDraftKind.receivableUpdate => 'draft.receivable_update',
    FfmAssistantDraftKind.receivableArchive => 'draft.receivable_archive',
    FfmAssistantDraftKind.receivablePayment => 'draft.receivable_payment',
    FfmAssistantDraftKind.asset => 'draft.asset',
    FfmAssistantDraftKind.assetUpdate => 'draft.asset_update',
    FfmAssistantDraftKind.assetArchive => 'draft.asset_archive',
    FfmAssistantDraftKind.budget => 'draft.budget',
    FfmAssistantDraftKind.budgetUpdate => 'draft.budget_update',
    FfmAssistantDraftKind.budgetArchive => 'draft.budget_archive',
    FfmAssistantDraftKind.masterData => 'draft.master_data',
    FfmAssistantDraftKind.merchantUpdate => 'draft.merchant_update',
    FfmAssistantDraftKind.merchantArchive => 'draft.merchant_archive',
    FfmAssistantDraftKind.merchantDelete => 'draft.merchant_delete',
    FfmAssistantDraftKind.tagUpdate => 'draft.tag_update',
    FfmAssistantDraftKind.tagArchive => 'draft.tag_archive',
    FfmAssistantDraftKind.tagDelete => 'draft.tag_delete',
    FfmAssistantDraftKind.incomeSourceUpdate => 'draft.income_source_update',
    FfmAssistantDraftKind.incomeSourceArchive => 'draft.income_source_archive',
    FfmAssistantDraftKind.incomeSourceDelete => 'draft.income_source_delete',
    FfmAssistantDraftKind.categoryUpdate => 'draft.category_update',
    FfmAssistantDraftKind.categoryArchive => 'draft.category_archive',
    FfmAssistantDraftKind.categoryDelete => 'draft.category_delete',
    FfmAssistantDraftKind.accountUpdate => 'draft.account_update',
    FfmAssistantDraftKind.accountArchive => 'draft.account_archive',
    FfmAssistantDraftKind.accountDelete => 'draft.account_delete',
    FfmAssistantDraftKind.reminder => 'draft.reminder',
    FfmAssistantDraftKind.reminderUpdate => 'draft.reminder_update',
    FfmAssistantDraftKind.activity => 'draft.activity',
    FfmAssistantDraftKind.dailyNote => 'draft.daily_note',
    FfmAssistantDraftKind.dailyNoteArchive => 'draft.daily_note_archive',
    FfmAssistantDraftKind.dailyNoteUpdate => 'draft.daily_note_update',
    FfmAssistantDraftKind.dailyNoteRestore => 'draft.daily_note_restore',
    FfmAssistantDraftKind.dailyNoteDelete => 'draft.daily_note_delete',
    FfmAssistantDraftKind.task => 'draft.task',
    FfmAssistantDraftKind.taskUpdate => 'draft.task_update',
    FfmAssistantDraftKind.taskComplete => 'draft.task_complete',
    FfmAssistantDraftKind.taskReopen => 'draft.task_reopen',
    FfmAssistantDraftKind.taskArchive => 'draft.task_archive',
    FfmAssistantDraftKind.routine => 'draft.routine',
    FfmAssistantDraftKind.routineUpdate => 'draft.routine_update',
    FfmAssistantDraftKind.routineMarkComplete => 'draft.routine_mark_complete',
    FfmAssistantDraftKind.routineUnmarkComplete =>
      'draft.routine_unmark_complete',
    FfmAssistantDraftKind.routineActivate => 'draft.routine_activate',
    FfmAssistantDraftKind.routineDeactivate => 'draft.routine_deactivate',
    FfmAssistantDraftKind.routineArchive => 'draft.routine_archive',
    FfmAssistantDraftKind.schedule => 'draft.schedule',
    FfmAssistantDraftKind.scheduleUpdate => 'draft.schedule_update',
    FfmAssistantDraftKind.scheduleArchive => 'draft.schedule_archive',
    FfmAssistantDraftKind.recurringTransactionUpdate =>
      'draft.recurring_transaction_update',
    FfmAssistantDraftKind.recurringTransactionArchive =>
      'draft.recurring_transaction_archive',
    FfmAssistantDraftKind.profile => 'draft.profile',
    FfmAssistantDraftKind.goalUpdate => 'draft.goal_update',
    FfmAssistantDraftKind.goalArchive => 'draft.goal_archive',
    FfmAssistantDraftKind.reminderArchive => 'draft.reminder_archive',
    FfmAssistantDraftKind.reminderComplete => 'draft.reminder_complete',
    FfmAssistantDraftKind.transactionUpdate => 'draft.transaction_update',
    FfmAssistantDraftKind.transactionArchive => 'draft.transaction_archive',
    FfmAssistantDraftKind.transactionDelete => 'draft.transaction_delete',
    FfmAssistantDraftKind.activityArchive => 'draft.activity_archive',
    FfmAssistantDraftKind.activityDelete => 'draft.activity_delete',
    FfmAssistantDraftKind.activityFinish => 'draft.activity_finish',
    FfmAssistantDraftKind.activityUpdate => 'draft.activity_update',
    FfmAssistantDraftKind.activityEdit => 'draft.activity_edit',
    FfmAssistantDraftKind.cashFlowProfile => 'draft.cash_flow_profile',
    FfmAssistantDraftKind.monitoringJob => 'draft.monitoring_job',
    FfmAssistantDraftKind.meterReading => 'draft.meter_reading',
  };

  static bool _isExistingReminder(FfmAssistantDraft draft) =>
      draft.kind == FfmAssistantDraftKind.reminder &&
      (draft.formValues['targetId']?.toString().trim().isNotEmpty ?? false);

  static String _mutationCapabilityFor(FfmAssistantDraftKind kind) =>
      switch (kind) {
        FfmAssistantDraftKind.goalUpdate => 'mutate.update',
        FfmAssistantDraftKind.goalArchive => 'mutate.archive',
        FfmAssistantDraftKind.assetUpdate => 'mutate.update',
        FfmAssistantDraftKind.assetArchive => 'mutate.archive',
        FfmAssistantDraftKind.liabilityUpdate => 'mutate.update',
        FfmAssistantDraftKind.liabilityArchive => 'mutate.archive',
        FfmAssistantDraftKind.liabilityPayment => 'mutate.debt_payment',
        FfmAssistantDraftKind.receivableUpdate => 'mutate.update',
        FfmAssistantDraftKind.receivableArchive => 'mutate.archive',
        FfmAssistantDraftKind.receivablePayment => 'mutate.debt_payment',
        FfmAssistantDraftKind.reminderArchive => 'mutate.archive',
        FfmAssistantDraftKind.reminderComplete => 'mutate.complete',
        FfmAssistantDraftKind.reminderUpdate => 'mutate.update',
        FfmAssistantDraftKind.transactionUpdate => 'mutate.update',
        FfmAssistantDraftKind.transactionArchive => 'mutate.archive',
        FfmAssistantDraftKind.transactionDelete => 'sensitive.delete',
        FfmAssistantDraftKind.activityArchive => 'mutate.archive',
        FfmAssistantDraftKind.activityDelete => 'sensitive.delete',
        FfmAssistantDraftKind.activityFinish => 'mutate.update',
        FfmAssistantDraftKind.activityUpdate => 'mutate.update',
        FfmAssistantDraftKind.activityEdit => 'mutate.update',
        FfmAssistantDraftKind.dailyNoteArchive => 'mutate.archive',
        FfmAssistantDraftKind.dailyNoteUpdate => 'mutate.update',
        FfmAssistantDraftKind.dailyNoteRestore => 'mutate.update',
        FfmAssistantDraftKind.dailyNoteDelete => 'sensitive.delete',
        FfmAssistantDraftKind.taskUpdate => 'mutate.update',
        FfmAssistantDraftKind.taskComplete => 'mutate.update',
        FfmAssistantDraftKind.taskReopen => 'mutate.update',
        FfmAssistantDraftKind.taskArchive => 'mutate.archive',
        FfmAssistantDraftKind.routineUpdate ||
        FfmAssistantDraftKind.routineMarkComplete ||
        FfmAssistantDraftKind.routineUnmarkComplete ||
        FfmAssistantDraftKind.routineActivate ||
        FfmAssistantDraftKind.routineDeactivate => 'mutate.update',
        FfmAssistantDraftKind.routineArchive => 'mutate.archive',
        FfmAssistantDraftKind.scheduleUpdate => 'mutate.update',
        FfmAssistantDraftKind.scheduleArchive => 'mutate.archive',
        FfmAssistantDraftKind.recurringTransactionUpdate => 'mutate.update',
        FfmAssistantDraftKind.recurringTransactionArchive => 'mutate.archive',
        FfmAssistantDraftKind.merchantUpdate => 'mutate.update',
        FfmAssistantDraftKind.merchantArchive => 'mutate.archive',
        FfmAssistantDraftKind.merchantDelete => 'sensitive.delete',
        FfmAssistantDraftKind.tagUpdate => 'mutate.update',
        FfmAssistantDraftKind.tagArchive => 'mutate.archive',
        FfmAssistantDraftKind.tagDelete => 'sensitive.delete',
        FfmAssistantDraftKind.incomeSourceUpdate => 'mutate.update',
        FfmAssistantDraftKind.incomeSourceArchive => 'mutate.archive',
        FfmAssistantDraftKind.incomeSourceDelete => 'sensitive.delete',
        FfmAssistantDraftKind.categoryUpdate => 'mutate.update',
        FfmAssistantDraftKind.categoryArchive => 'mutate.archive',
        FfmAssistantDraftKind.categoryDelete => 'sensitive.delete',
        FfmAssistantDraftKind.accountUpdate => 'mutate.update',
        FfmAssistantDraftKind.accountArchive => 'mutate.archive',
        FfmAssistantDraftKind.accountDelete => 'sensitive.delete',
        FfmAssistantDraftKind.budgetUpdate => 'mutate.update',
        FfmAssistantDraftKind.budgetArchive => 'mutate.archive',
        _ => 'mutate.save_draft',
      };

  static String _verifyCapabilityFor(
    FfmAssistantDraftKind kind,
  ) => switch (kind) {
    FfmAssistantDraftKind.transactionUpdate ||
    FfmAssistantDraftKind.transactionArchive ||
    FfmAssistantDraftKind.transactionDelete => 'verify.transaction_mutation',
    FfmAssistantDraftKind.activityArchive ||
    FfmAssistantDraftKind.activityDelete ||
    FfmAssistantDraftKind.activityFinish ||
    FfmAssistantDraftKind.activityUpdate ||
    FfmAssistantDraftKind.activityEdit => 'verify.activity_mutation',
    FfmAssistantDraftKind.dailyNote ||
    FfmAssistantDraftKind.dailyNoteArchive ||
    FfmAssistantDraftKind.dailyNoteUpdate ||
    FfmAssistantDraftKind.dailyNoteRestore ||
    FfmAssistantDraftKind.dailyNoteDelete => 'verify.daily_note_mutation',
    FfmAssistantDraftKind.task ||
    FfmAssistantDraftKind.taskUpdate ||
    FfmAssistantDraftKind.taskComplete ||
    FfmAssistantDraftKind.taskReopen ||
    FfmAssistantDraftKind.taskArchive => 'verify.task_mutation',
    FfmAssistantDraftKind.routine ||
    FfmAssistantDraftKind.routineUpdate ||
    FfmAssistantDraftKind.routineMarkComplete ||
    FfmAssistantDraftKind.routineUnmarkComplete ||
    FfmAssistantDraftKind.routineActivate ||
    FfmAssistantDraftKind.routineDeactivate ||
    FfmAssistantDraftKind.routineArchive => 'verify.routine_mutation',
    FfmAssistantDraftKind.schedule ||
    FfmAssistantDraftKind.scheduleUpdate ||
    FfmAssistantDraftKind.scheduleArchive => 'verify.schedule_mutation',
    FfmAssistantDraftKind.recurringTransactionUpdate ||
    FfmAssistantDraftKind.recurringTransactionArchive =>
      'verify.recurring_transaction_mutation',
    FfmAssistantDraftKind.merchantUpdate ||
    FfmAssistantDraftKind.merchantArchive ||
    FfmAssistantDraftKind.merchantDelete => 'verify.merchant_mutation',
    FfmAssistantDraftKind.tagUpdate ||
    FfmAssistantDraftKind.tagArchive ||
    FfmAssistantDraftKind.tagDelete => 'verify.tag_mutation',
    FfmAssistantDraftKind.incomeSourceUpdate ||
    FfmAssistantDraftKind.incomeSourceArchive ||
    FfmAssistantDraftKind.incomeSourceDelete => 'verify.income_source_mutation',
    FfmAssistantDraftKind.categoryUpdate ||
    FfmAssistantDraftKind.categoryArchive ||
    FfmAssistantDraftKind.categoryDelete => 'verify.category_mutation',
    FfmAssistantDraftKind.accountUpdate ||
    FfmAssistantDraftKind.accountArchive ||
    FfmAssistantDraftKind.accountDelete => 'verify.account_mutation',
    FfmAssistantDraftKind.budgetUpdate ||
    FfmAssistantDraftKind.budgetArchive => 'verify.budget_mutation',
    FfmAssistantDraftKind.goalUpdate ||
    FfmAssistantDraftKind.goalArchive ||
    FfmAssistantDraftKind.goalDeposit ||
    FfmAssistantDraftKind.goalUsage ||
    FfmAssistantDraftKind.goal => 'verify.goal_mutation',
    FfmAssistantDraftKind.assetUpdate ||
    FfmAssistantDraftKind.assetArchive => 'verify.asset_mutation',
    FfmAssistantDraftKind.liabilityUpdate ||
    FfmAssistantDraftKind.liabilityArchive ||
    FfmAssistantDraftKind.liabilityPayment => 'verify.debt_payment',
    FfmAssistantDraftKind.receivableUpdate ||
    FfmAssistantDraftKind.receivableArchive => 'verify.receivable_mutation',
    FfmAssistantDraftKind.receivablePayment => 'verify.debt_payment',
    FfmAssistantDraftKind.reminderArchive ||
    FfmAssistantDraftKind.reminderComplete => 'verify.reminder_mutation',
    FfmAssistantDraftKind.reminderUpdate => 'verify.reminder_mutation',
    FfmAssistantDraftKind.monitoringJob => 'verify.monitoring_job',
    _ => 'verify.saved_draft',
  };

  static List<String> _prerequisiteReadsForDraft(FfmAssistantDraftKind kind) =>
      switch (kind) {
        FfmAssistantDraftKind.income || FfmAssistantDraftKind.expense => const [
          'read.accounts',
          'read.categories',
        ],
        FfmAssistantDraftKind.transfer => const ['read.accounts'],
        FfmAssistantDraftKind.goalDeposit ||
        FfmAssistantDraftKind.goalUsage ||
        FfmAssistantDraftKind.goal => const ['read.goals', 'read.accounts'],
        FfmAssistantDraftKind.goalUpdate ||
        FfmAssistantDraftKind.goalArchive => const ['read.goals'],
        FfmAssistantDraftKind.liability ||
        FfmAssistantDraftKind.liabilityUpdate ||
        FfmAssistantDraftKind.liabilityArchive ||
        FfmAssistantDraftKind.liabilityPayment => const ['read.liabilities'],
        FfmAssistantDraftKind.receivable ||
        FfmAssistantDraftKind.receivableUpdate ||
        FfmAssistantDraftKind.receivableArchive ||
        FfmAssistantDraftKind.receivablePayment => const ['read.receivable'],
        FfmAssistantDraftKind.asset ||
        FfmAssistantDraftKind.assetUpdate ||
        FfmAssistantDraftKind.assetArchive => const ['read.assets'],
        FfmAssistantDraftKind.budget ||
        FfmAssistantDraftKind.budgetUpdate ||
        FfmAssistantDraftKind.budgetArchive => const ['read.budget'],
        FfmAssistantDraftKind.activity ||
        FfmAssistantDraftKind.activityArchive ||
        FfmAssistantDraftKind.activityDelete ||
        FfmAssistantDraftKind.activityFinish ||
        FfmAssistantDraftKind.activityUpdate ||
        FfmAssistantDraftKind.activityEdit => const ['read.activity'],
        FfmAssistantDraftKind.reminder ||
        FfmAssistantDraftKind.reminderUpdate ||
        FfmAssistantDraftKind.reminderArchive ||
        FfmAssistantDraftKind.reminderComplete => const ['read.reminders'],
        _ => const <String>[],
      };

  List<String> _prerequisiteReadCapabilitiesFor(FfmAssistantIntent intent) {
    final reads = <String>[];
    if (intent.pluginMetadata?['localReadCompleted'] == true) {
      return reads;
    }
    // Gemini Cloud answers queries directly in its bounded orchestrator turn.
    // Do not plan redundant read capabilities if there is no draft to populate.
    final isGeminiCloudWithoutDraft =
        intent.responseOrigin == FfmAssistantResponseOrigin.geminiCloud &&
        intent.draft == null;

    if (!isGeminiCloudWithoutDraft) {
      final explicitRead = _readCapabilityFor(intent.type);
      if (explicitRead != null) {
        reads.add(explicitRead);
      }
    }

    final draft = intent.draft;
    if (draft != null) {
      final draftReads = _prerequisiteReadsForDraft(draft.kind);
      for (final r in draftReads) {
        if (!reads.contains(r)) {
          reads.add(r);
        }
      }
    }
    return reads;
  }

  Map<String, Object?> _draftParameters(FfmAssistantDraft draft) => {
    // Form values may contain UI-only metadata, but must not override the
    // canonical values that came from the typed draft fields.
    ...draft.formValues,
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
    if (draft.location != null) 'location': draft.location,
    if (draft.linkedActivityId != null)
      'linkedActivityId': draft.linkedActivityId,
    if (draft.parentSessionId != null) 'parentSessionId': draft.parentSessionId,
    if (draft.activityMode != null) 'activityMode': draft.activityMode!.value,
    if (draft.scheduledAt != null)
      'scheduledAt': draft.scheduledAt!.toIso8601String(),
    if (draft.sourceId != null) 'sourceId': draft.sourceId,
    if (draft.source != null) 'source': draft.source,
    if (draft.recurringTransactionId != null)
      'recurringTransactionId': draft.recurringTransactionId,
    if (draft.tags != null) 'tags': draft.tags,
    if (draft.newTags != null) 'newTags': draft.newTags,
    if (draft.newMerchant != null) 'newMerchant': draft.newMerchant,
    if (draft.attachmentPaths.isNotEmpty)
      'attachmentPathsJson': jsonEncode(draft.attachmentPaths),
    if (draft.adminFee != null) 'adminFee': draft.adminFee,
    if (draft.commodityOrBusinessType != null)
      'commodityOrBusinessType': draft.commodityOrBusinessType,
    if (draft.targetHarvestDate != null)
      'targetHarvestDate': draft.targetHarvestDate!.toIso8601String(),
    if (draft.initialCapital != null) 'initialCapital': draft.initialCapital,
    if (draft.estimatedInflow != null) 'estimatedInflow': draft.estimatedInflow,
    if (draft.dailyLivingBudget != null)
      'dailyLivingBudget': draft.dailyLivingBudget,
    if (draft.dailyOperationalBudget != null)
      'dailyOperationalBudget': draft.dailyOperationalBudget,
    if (draft.cycleProfileType != null)
      'cycleProfileType': draft.cycleProfileType,
    if (draft.soundUri != null) 'soundUri': draft.soundUri,
    if (draft.soundName != null) 'soundName': draft.soundName,
    if (draft.recurrenceType != null) ...{
      'recurrence': draft.recurrenceType!.storageValue,
      'recurrenceType': draft.recurrenceType!.storageValue,
    },
    if (draft.weekdays.isNotEmpty) 'weekdays': draft.weekdays,
    if (draft.kind == FfmAssistantDraftKind.reminder ||
        draft.reminderMode != null)
      'reminderMode':
          draft.reminderMode?.storageValue ??
          draft.reminderMode?.name ??
          draft.formValues['reminderMode']?.toString() ??
          draft.formValues['mode']?.toString() ??
          'notification',
    if (draft.kind == FfmAssistantDraftKind.reminder ||
        draft.reminderMode != null)
      'mode':
          draft.reminderMode?.storageValue ??
          draft.reminderMode?.name ??
          draft.formValues['reminderMode']?.toString() ??
          draft.formValues['mode']?.toString() ??
          'notification',
    if (draft.destinationRoute != null ||
        draft.formValues['destinationRoute'] != null)
      'destinationRoute':
          draft.destinationRoute ?? draft.formValues['destinationRoute'],
    // Payload pembelajaran: tebakan awal + merchant agar adapter simpan
    // dapat merekam koreksi user terhadap nilai SLM/rule.
    if (draft.merchantName != null) 'merchant': draft.merchantName,
    if (draft.merchantName != null) 'assistantMerchantName': draft.merchantName,
    if (draft.slmFieldValues.isNotEmpty)
      'assistantSlmFieldValues': draft.slmFieldValues,

    // Gunakan draft.items sebagai sumber kebenaran, bukan formValues.itemsJson
    // untuk menghindari kontradiksi antara dua representasi data
    if (draft.items.isNotEmpty)
      'itemsJson': jsonEncode(
        draft.items
            .map(
              (i) => {
                'name': i.name,
                'itemName': i.name,
                'price': i.price,
                'qty': i.quantity,
                'quantity': i.quantity,
                'unit': i.unit,
                'lineTotal': i.lineTotal,
                'subtotal': i.lineTotal,
              },
            )
            .toList(),
      ),
    if (draft.receiptNumber != null) 'receiptNumber': draft.receiptNumber,
    if (draft.receiptPaidAmount != null)
      'receiptPaidAmount': draft.receiptPaidAmount,
    if (draft.receiptChangeAmount != null)
      'receiptChangeAmount': draft.receiptChangeAmount,
    if (draft.receiptRawText != null) 'receiptRawText': draft.receiptRawText,
    if (draft.tax != null) 'tax': draft.tax,
    if (draft.discount != null) 'discount': draft.discount,
    if (draft.metadata != null) 'metadata': draft.metadata,
    if (draft.attachmentPaths.isNotEmpty)
      'attachmentPaths': draft.attachmentPaths,
    if (draft.soundUri != null) 'soundUri': draft.soundUri,
    if (draft.soundName != null) 'soundName': draft.soundName,
  };
}

/// Immutable plans and source-page metadata for a budget-habit proposal.
class FfmAssistantBudgetHabitProposalPlanBatches {
  FfmAssistantBudgetHabitProposalPlanBatches({
    required List<FfmAssistantBudgetHabitProposalPlanBatch> plans,
  }) : plans = List.unmodifiable(plans);

  final List<FfmAssistantBudgetHabitProposalPlanBatch> plans;
}

class FfmAssistantBudgetHabitProposalPlanBatch {
  const FfmAssistantBudgetHabitProposalPlanBatch({
    required this.batch,
    required this.plan,
  });

  final FfmAssistantBudgetHabitProposalBatch batch;
  final FfmAssistantActionPlan plan;
}
