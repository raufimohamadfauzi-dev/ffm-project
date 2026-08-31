import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_autonomy_repository.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_plan.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_autonomy_policy.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_tool_execution.dart';

void main() {
  late AppDatabase database;
  late FfmAssistantAutonomyRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = FfmAssistantAutonomyRepository(
      database,
      now: () => DateTime(2026, 8, 31, 12),
    );
  });

  tearDown(() => database.close());

  test(
    'event yang sudah completed tidak menjalankan handler dua kali',
    () async {
      final event = FfmAssistantAutonomyEvent(
        id: 'transaction-created-1',
        type: 'transaction.created',
        occurredAt: DateTime(2026, 8, 31, 11),
        entityId: 'transaction-1',
      );
      var calls = 0;

      final first = await repository.processEvent(event, (_) async => calls++);
      final second = await repository.processEvent(event, (_) async => calls++);
      final stored = await repository.eventById(event.id);

      expect(first, FfmAssistantAutonomyEventProcessResult.processed);
      expect(second, FfmAssistantAutonomyEventProcessResult.duplicate);
      expect(calls, 1);
      expect(stored?.status, FfmAssistantAutonomyEventStatus.completed.name);
      expect(stored?.attemptCount, 1);
      expect(stored?.processedAt, isNotNull);
    },
  );

  test('event gagal dapat dicoba kembali dengan attempt count baru', () async {
    final event = FfmAssistantAutonomyEvent(
      id: 'reminder-due-1',
      type: 'reminder.due',
      occurredAt: DateTime(2026, 8, 31, 11),
    );

    final failed = await repository.processEvent(event, (_) async {
      throw StateError('gateway offline');
    });
    final retried = await repository.processEvent(event, (_) async {});
    final stored = await repository.eventById(event.id);

    expect(failed, FfmAssistantAutonomyEventProcessResult.failed);
    expect(retried, FfmAssistantAutonomyEventProcessResult.processed);
    expect(stored?.status, FfmAssistantAutonomyEventStatus.completed.name);
    expect(stored?.attemptCount, 2);
    expect(stored?.error, isNull);
  });

  test('plan progress terakhir dipulihkan sebagai agent run', () async {
    final plan = FfmAssistantActionPlan(
      id: 'plan-1',
      summary: 'Baca ringkasan keuangan',
      createdAt: DateTime(2026, 8, 31, 11),
      steps: const [
        FfmAssistantActionStep(
          id: 'read-summary',
          capabilityId: 'read.summary',
          status: FfmAssistantActionStepStatus.completed,
          result: 'Ringkasan tersedia.',
        ),
      ],
      status: FfmAssistantActionPlanStatus.completed,
    );

    await repository.recordPlan(plan);
    final stored = await repository.runById(plan.id);

    expect(stored?.status, FfmAssistantActionPlanStatus.completed.name);
    expect(stored?.summary, plan.summary);
    expect(stored?.decisionSummary, '1 langkah selesai, 0 langkah gagal.');
    expect(stored?.finishedAt, isNotNull);
  });

  test('approval request dan keputusan disimpan untuk audit run', () async {
    final plan = FfmAssistantActionPlan(
      id: 'approval-plan',
      summary: 'Simpan pengeluaran',
      createdAt: DateTime(2026, 8, 31, 11),
      requiresConfirmation: true,
      steps: const [
        FfmAssistantActionStep(id: 'save', capabilityId: 'mutate.save_draft'),
      ],
    );

    await repository.recordApprovalRequest(plan);
    await repository.recordApprovalDecision(
      runId: plan.id,
      status: FfmAssistantApprovalStatus.approved,
    );
    final stored = await repository.approvalByRunId(plan.id);

    expect(stored?.status, FfmAssistantApprovalStatus.approved.name);
    expect(stored?.summary, plan.summary);
    expect(stored?.actor, 'user');
    expect(stored?.decidedAt, isNotNull);
  });

  test(
    'policy autonomy tersimpan per household dan dapat dimuat kembali',
    () async {
      const policy = FfmAssistantAutonomyPolicy(
        level: FfmAssistantAutonomyLevel.createDraft,
        maxActionsPerRun: 3,
      );

      await repository.savePolicy(householdId: 'household-a', policy: policy);
      await repository.savePolicy(
        householdId: 'household-b',
        policy: const FfmAssistantAutonomyPolicy(
          level: FfmAssistantAutonomyLevel.readOnly,
        ),
      );

      final loadedA = await repository.loadPolicy(householdId: 'household-a');
      final loadedB = await repository.loadPolicy(householdId: 'household-b');

      expect(loadedA?.level, FfmAssistantAutonomyLevel.createDraft);
      expect(loadedA?.maxActionsPerRun, 3);
      expect(loadedB?.level, FfmAssistantAutonomyLevel.readOnly);
    },
  );

  test('tool execution terakhir tersimpan tanpa parameter mentah', () async {
    final started = FfmAssistantToolExecution(
      id: 'tool-plan:step-1',
      runId: 'tool-plan',
      stepId: 'step-1',
      capabilityId: 'read.summary',
      status: FfmAssistantToolExecutionStatus.started,
      attemptCount: 0,
      startedAt: DateTime(2026, 8, 31, 11),
    );
    final completed = FfmAssistantToolExecution(
      id: started.id,
      runId: started.runId,
      stepId: started.stepId,
      capabilityId: started.capabilityId,
      status: FfmAssistantToolExecutionStatus.completed,
      attemptCount: 1,
      startedAt: started.startedAt,
      finishedAt: DateTime(2026, 8, 31, 11, 1),
      resultSummary: 'Ringkasan siap.',
    );

    await repository.recordToolExecution(started);
    await repository.recordToolExecution(completed);
    final rows = await repository.toolExecutionsForRun('tool-plan');

    expect(rows, hasLength(1));
    expect(rows.single.status, FfmAssistantToolExecutionStatus.completed.name);
    expect(rows.single.attemptCount, 1);
    expect(rows.single.resultSummary, 'Ringkasan siap.');
  });

  test('recent runs dibatasi dan diurutkan dari yang paling baru', () async {
    var clock = DateTime(2026, 8, 30);
    final orderedRepository = FfmAssistantAutonomyRepository(
      database,
      now: () => clock,
    );
    await orderedRepository.recordPlan(
      FfmAssistantActionPlan(
        id: 'old-run',
        summary: 'Run lama',
        createdAt: DateTime(2026, 8, 30),
        steps: const [],
      ),
    );
    clock = DateTime(2026, 8, 31);
    await orderedRepository.recordPlan(
      FfmAssistantActionPlan(
        id: 'new-run',
        summary: 'Run baru',
        createdAt: DateTime(2026, 8, 31),
        steps: const [],
      ),
    );

    final runs = await orderedRepository.recentRuns(limit: 1);

    expect(runs, hasLength(1));
    expect(runs.single.id, 'new-run');
  });
}
