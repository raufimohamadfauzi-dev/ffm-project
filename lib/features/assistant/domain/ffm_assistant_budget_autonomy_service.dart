import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../budget/data/budget_repository.dart';
import '../data/ffm_assistant_budget_autonomy_repository.dart';

enum FfmAssistantBudgetDelegationStatus { active, paused, revoked }

enum FfmAssistantBudgetLedgerOperation { adjustment, undo }

class FfmAssistantBudgetDelegation {
  const FfmAssistantBudgetDelegation({
    required this.id,
    required this.householdId,
    required this.budgetId,
    required this.status,
    required this.maxAdjustmentAmount,
    required this.maxAllocatedAmount,
    required this.maxExecutions,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String householdId;
  final String budgetId;
  final FfmAssistantBudgetDelegationStatus status;
  final int maxAdjustmentAmount;
  final int maxAllocatedAmount;
  final int maxExecutions;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class FfmAssistantBudgetLedgerEntry {
  const FfmAssistantBudgetLedgerEntry({
    required this.id,
    required this.householdId,
    required this.delegationId,
    required this.budgetId,
    required this.idempotencyKey,
    required this.operation,
    required this.previousAllocated,
    required this.appliedAllocated,
    required this.previousRevision,
    required this.appliedRevision,
    required this.delta,
    required this.executedAt,
    this.reversesLedgerId,
  });

  final String id;
  final String householdId;
  final String delegationId;
  final String budgetId;
  final String idempotencyKey;
  final FfmAssistantBudgetLedgerOperation operation;
  final String? reversesLedgerId;
  final int previousAllocated;
  final int appliedAllocated;
  final int previousRevision;
  final int appliedRevision;
  final int delta;
  final DateTime executedAt;
}

class FfmAssistantBudgetAutonomyResult {
  const FfmAssistantBudgetAutonomyResult({
    required this.ledger,
    required this.idempotent,
  });

  final BudgetAutonomyExecutionLedger ledger;
  final bool idempotent;
}

/// Executes only explicitly delegated `allocated` adjustments.
///
/// It deliberately does not expose create, archive, transfer, category, or
/// period operations. Allocation writes remain guarded by [BudgetRepository].
class FfmAssistantBudgetAutonomyService {
  FfmAssistantBudgetAutonomyService(
    this._database,
    this._budgetRepository,
    this._repository, {
    DateTime Function()? clock,
    Uuid? uuid,
  }) : _clock = clock ?? DateTime.now,
       _uuid = uuid ?? const Uuid();

  final AppDatabase _database;
  final BudgetRepository _budgetRepository;
  final FfmAssistantBudgetAutonomyRepository _repository;
  final DateTime Function() _clock;
  final Uuid _uuid;

  Future<void> saveDelegation(FfmAssistantBudgetDelegation delegation) =>
      _repository.saveDelegation(
        id: delegation.id,
        householdId: delegation.householdId,
        budgetId: delegation.budgetId,
        status: delegation.status.name,
        maxAdjustmentAmount: delegation.maxAdjustmentAmount,
        maxAllocatedAmount: delegation.maxAllocatedAmount,
        maxExecutions: delegation.maxExecutions,
        createdAt: delegation.createdAt,
        updatedAt: delegation.updatedAt,
      );

  Future<bool> setDelegationStatus({
    required String householdId,
    required String budgetId,
    required FfmAssistantBudgetDelegationStatus status,
  }) => _repository.setStatus(
    householdId: householdId,
    budgetId: budgetId,
    status: status.name,
    updatedAt: _clock(),
  );

  Future<FfmAssistantBudgetAutonomyResult> adjustAllocated({
    required String householdId,
    required String budgetId,
    required int allocated,
    required String idempotencyKey,
  }) => _database.transaction(() async {
    final prior = await _repository.ledgerByIdempotencyKey(
      householdId: householdId,
      idempotencyKey: idempotencyKey,
    );
    if (prior != null) {
      return FfmAssistantBudgetAutonomyResult(ledger: prior, idempotent: true);
    }
    final delegation = await _requireActiveDelegation(householdId, budgetId);
    final before = await _budgetRepository.snapshot(
      householdId: householdId,
      id: budgetId,
    );
    if (before == null) throw StateError('Pos Anggaran tidak ditemukan.');
    final delta = allocated - before.budget.allocated;
    if (delta == 0) throw StateError('Alokasi Anggaran tidak berubah.');
    if (delta.abs() > delegation.maxAdjustmentAmount ||
        allocated > delegation.maxAllocatedAmount) {
      throw StateError('Penyesuaian melampaui batas delegasi Anggaran.');
    }
    if (await _repository.executionCount(delegation.id) >=
        delegation.maxExecutions) {
      throw StateError(
        'Batas jumlah eksekusi delegasi Anggaran telah tercapai.',
      );
    }
    final updated = await _budgetRepository.updateAllocatedIfCurrent(
      householdId: householdId,
      id: budgetId,
      allocated: allocated,
      expectedAllocated: before.budget.allocated,
      expectedRevision: before.budget.revision,
    );
    if (updated == null) throw StateError('Pos Anggaran tidak ditemukan.');
    final entry = FfmAssistantBudgetLedgerEntry(
      id: _uuid.v4(),
      householdId: householdId,
      delegationId: delegation.id,
      budgetId: budgetId,
      idempotencyKey: idempotencyKey,
      operation: FfmAssistantBudgetLedgerOperation.adjustment,
      previousAllocated: before.budget.allocated,
      appliedAllocated: updated.budget.allocated,
      previousRevision: before.budget.revision,
      appliedRevision: updated.budget.revision,
      delta: delta,
      executedAt: _clock(),
    );
    await _repository.appendLedger(
      id: entry.id,
      householdId: entry.householdId,
      delegationId: entry.delegationId,
      budgetId: entry.budgetId,
      idempotencyKey: entry.idempotencyKey,
      operation: entry.operation.name,
      reversesLedgerId: entry.reversesLedgerId,
      previousAllocated: entry.previousAllocated,
      appliedAllocated: entry.appliedAllocated,
      previousRevision: entry.previousRevision,
      appliedRevision: entry.appliedRevision,
      delta: entry.delta,
      executedAt: entry.executedAt,
    );
    return FfmAssistantBudgetAutonomyResult(
      ledger: (await _repository.ledgerById(entry.id))!,
      idempotent: false,
    );
  });

  Future<FfmAssistantBudgetAutonomyResult> undo({
    required String householdId,
    required String ledgerId,
    required String idempotencyKey,
  }) => _database.transaction(() async {
    final prior = await _repository.ledgerByIdempotencyKey(
      householdId: householdId,
      idempotencyKey: idempotencyKey,
    );
    if (prior != null) {
      return FfmAssistantBudgetAutonomyResult(ledger: prior, idempotent: true);
    }
    final original = await _repository.ledgerById(ledgerId);
    if (original == null ||
        original.householdId != householdId ||
        original.operation !=
            FfmAssistantBudgetLedgerOperation.adjustment.name) {
      throw StateError('Eksekusi Anggaran tidak dapat dibatalkan.');
    }
    await _requireActiveDelegation(householdId, original.budgetId);
    final updated = await _budgetRepository.updateAllocatedIfCurrent(
      householdId: householdId,
      id: original.budgetId,
      allocated: original.previousAllocated,
      expectedAllocated: original.appliedAllocated,
      expectedRevision: original.appliedRevision,
    );
    if (updated == null) throw StateError('Pos Anggaran tidak ditemukan.');
    final entry = FfmAssistantBudgetLedgerEntry(
      id: _uuid.v4(),
      householdId: householdId,
      delegationId: original.delegationId,
      budgetId: original.budgetId,
      idempotencyKey: idempotencyKey,
      operation: FfmAssistantBudgetLedgerOperation.undo,
      reversesLedgerId: original.id,
      previousAllocated: original.appliedAllocated,
      appliedAllocated: updated.budget.allocated,
      previousRevision: original.appliedRevision,
      appliedRevision: updated.budget.revision,
      delta: updated.budget.allocated - original.appliedAllocated,
      executedAt: _clock(),
    );
    await _repository.appendLedger(
      id: entry.id,
      householdId: entry.householdId,
      delegationId: entry.delegationId,
      budgetId: entry.budgetId,
      idempotencyKey: entry.idempotencyKey,
      operation: entry.operation.name,
      reversesLedgerId: entry.reversesLedgerId,
      previousAllocated: entry.previousAllocated,
      appliedAllocated: entry.appliedAllocated,
      previousRevision: entry.previousRevision,
      appliedRevision: entry.appliedRevision,
      delta: entry.delta,
      executedAt: entry.executedAt,
    );
    return FfmAssistantBudgetAutonomyResult(
      ledger: (await _repository.ledgerById(entry.id))!,
      idempotent: false,
    );
  });

  Future<BudgetAutonomyDelegation> _requireActiveDelegation(
    String householdId,
    String budgetId,
  ) async {
    final delegation = await _repository.delegationForBudget(
      householdId: householdId,
      budgetId: budgetId,
    );
    if (delegation == null ||
        delegation.status != FfmAssistantBudgetDelegationStatus.active.name) {
      throw StateError('Tidak ada delegasi aktif untuk pos Anggaran ini.');
    }
    return delegation;
  }
}
