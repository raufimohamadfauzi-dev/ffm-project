import '../../../core/database/app_database.dart';
import '../../budget/data/budget_repository.dart';
import '../domain/ffm_assistant_budget_autonomy_service.dart';
import 'ffm_assistant_autonomy_repository.dart';
import 'ffm_assistant_budget_autonomy_repository.dart';

/// Dedicated deterministic path for explicitly delegated budget adjustments.
/// It is intentionally separate from agent tasks and capability execution.
class FfmAssistantBudgetAutonomyEventService {
  FfmAssistantBudgetAutonomyEventService({
    required this.eventRepository,
    required this.delegationRepository,
    required this.budgetRepository,
    required this.budgetAutonomyService,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const eventType = 'budget.autonomy.alert_threshold';
  static const _reason = 'alert-threshold';

  final FfmAssistantAutonomyRepository eventRepository;
  final FfmAssistantBudgetAutonomyRepository delegationRepository;
  final BudgetRepository budgetRepository;
  final FfmAssistantBudgetAutonomyService budgetAutonomyService;
  final DateTime Function() _clock;

  /// Queues one durable candidate per observed budget revision. No write occurs
  /// here; the worker will later process the dedicated event.
  Future<int> enqueueCandidates({required String householdId}) async {
    var enqueued = 0;
    final delegations = await delegationRepository.activeDelegations(
      householdId: householdId,
    );
    for (final delegation in delegations) {
      final candidate = await _candidateFor(delegation);
      if (candidate == null) continue;
      final event = FfmAssistantAutonomyEvent(
        id: candidate.idempotencyKey,
        type: eventType,
        occurredAt: _clock(),
        householdId: householdId,
        entityId: delegation.budgetId,
        payload: <String, Object?>{
          'budgetId': delegation.budgetId,
          'delegationId': delegation.id,
          'idempotencyKey': candidate.idempotencyKey,
        },
      );
      if (await eventRepository.enqueueEvent(event)) enqueued++;
    }
    return enqueued;
  }

  /// Rechecks every condition at execution time so a queued event never grants
  /// authority after a delegation, budget, or limit has changed.
  Future<void> handle(FfmAssistantAutonomyEvent event) async {
    if (event.type != eventType) {
      throw StateError('Tipe event otonomi Anggaran tidak valid.');
    }
    final budgetId = event.payload['budgetId'];
    final delegationId = event.payload['delegationId'];
    final idempotencyKey = event.payload['idempotencyKey'];
    if (budgetId is! String ||
        delegationId is! String ||
        idempotencyKey is! String ||
        event.entityId != budgetId) {
      throw StateError('Payload event otonomi Anggaran tidak valid.');
    }
    final delegation = await delegationRepository.delegationForBudget(
      householdId: event.householdId,
      budgetId: budgetId,
    );
    if (delegation == null ||
        delegation.id != delegationId ||
        delegation.status != FfmAssistantBudgetDelegationStatus.active.name) {
      return;
    }
    final candidate = await _candidateFor(delegation);
    if (candidate == null || candidate.idempotencyKey != idempotencyKey) return;
    await budgetAutonomyService.adjustAllocated(
      householdId: event.householdId,
      budgetId: budgetId,
      allocated: candidate.allocated,
      // The persisted key includes the deterministic reason and source revision.
      idempotencyKey: idempotencyKey,
    );
  }

  Future<_BudgetAutonomyCandidate?> _candidateFor(
    BudgetAutonomyDelegation delegation,
  ) async {
    if (await delegationRepository.executionCount(delegation.id) >=
        delegation.maxExecutions) {
      return null;
    }
    final snapshots = await budgetRepository.readSnapshots(
      householdId: delegation.householdId,
      now: _clock(),
      budgetId: delegation.budgetId,
      limit: 1,
    );
    if (snapshots.length != 1) return null;
    final snapshot = snapshots.single;
    final alertPercent = snapshot.budget.alertPercent;
    if (alertPercent <= 0 || snapshot.progress * 100 <= alertPercent) {
      return null;
    }
    final targetAvailable = (snapshot.spent * 100 / alertPercent).ceil();
    final allocated =
        targetAvailable -
        snapshot.rollover -
        snapshot.transferredIn +
        snapshot.transferredOut;
    final delta = allocated - snapshot.allocated;
    if (allocated <= snapshot.allocated ||
        allocated <= 0 ||
        delta > delegation.maxAdjustmentAmount ||
        allocated > delegation.maxAllocatedAmount) {
      return null;
    }
    return _BudgetAutonomyCandidate(
      allocated: allocated,
      idempotencyKey:
          'budget-autonomy:$_reason:${delegation.id}:${snapshot.budget.id}:r${snapshot.budget.revision}',
    );
  }
}

class _BudgetAutonomyCandidate {
  const _BudgetAutonomyCandidate({
    required this.allocated,
    required this.idempotencyKey,
  });

  final int allocated;
  final String idempotencyKey;
}
