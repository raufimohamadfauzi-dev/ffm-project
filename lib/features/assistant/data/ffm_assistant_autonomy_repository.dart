import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/ffm_assistant_action_plan.dart';
import '../domain/ffm_assistant_autonomy_policy.dart';
import '../domain/ffm_assistant_agent_work.dart';
import '../domain/ffm_assistant_tool_execution.dart';

enum FfmAssistantAutonomyEventStatus { pending, processing, completed, failed }

enum FfmAssistantAutonomyEventProcessResult { processed, duplicate, failed }

enum FfmAssistantApprovalStatus { requested, approved, rejected, expired }

class FfmAssistantAutonomyEvent {
  const FfmAssistantAutonomyEvent({
    required this.id,
    required this.type,
    required this.occurredAt,
    this.householdId = FfmAssistantAutonomyRepository.householdId,
    this.entityId,
    this.activityId,
    this.payload = const <String, Object?>{},
  });

  final String id;
  final String type;
  final DateTime occurredAt;
  final String householdId;
  final String? entityId;
  final String? activityId;
  final Map<String, Object?> payload;
}

typedef FfmAssistantAutonomyEventHandler = Future<void> Function(
  FfmAssistantAutonomyEvent event,
);

/// Penyimpanan event dan ringkasan run yang durable serta aman untuk audit.
///
/// Payload hanya untuk metadata event terstruktur. Prompt dan input tool mentah
/// tidak boleh disimpan di sini.
class FfmAssistantAutonomyRepository {
  FfmAssistantAutonomyRepository(this._db, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  static const householdId = 'local-household';
  static const autonomyPolicyPreferenceKey = 'assistant.autonomy.policy.v1';
  static const maxTasksPerGoal = 20;

  final AppDatabase _db;
  final DateTime Function() _now;
  Future<void> _runWriteQueue = Future<void>.value();

  /// Memasukkan event satu kali. Event ID adalah idempotency key lintas sesi.
  Future<bool> enqueueEvent(FfmAssistantAutonomyEvent event) async {
    final columns = <String>[
      'event_id',
      'household_id',
      'event_type',
      'payload_json',
      'occurred_at',
    ];
    final placeholders = List<String>.generate(columns.length, (_) => '?');
    final variables = <Variable<Object>>[
      Variable.withString(event.id),
      Variable.withString(event.householdId),
      Variable.withString(event.type),
      Variable.withString(jsonEncode(event.payload)),
      Variable.withDateTime(event.occurredAt),
    ];
    if (event.entityId != null) {
      columns.add('entity_id');
      placeholders.add('?');
      variables.add(Variable.withString(event.entityId!));
    }
    if (event.activityId != null) {
      columns.add('activity_id');
      placeholders.add('?');
      variables.add(Variable.withString(event.activityId!));
    }
    final inserted = await _db.customUpdate(
      'INSERT OR IGNORE INTO assistant_agent_events '
      '(${columns.join(', ')}) VALUES (${placeholders.join(', ')})',
      variables: variables,
      updates: {_db.assistantAgentEvents},
    );
    return inserted == 1;
  }

  /// Menjalankan handler tepat satu kali untuk event yang sudah selesai.
  /// Event gagal boleh diproses ulang; event completed selalu ditolak.
  Future<FfmAssistantAutonomyEventProcessResult> processEvent(
    FfmAssistantAutonomyEvent event,
    FfmAssistantAutonomyEventHandler handler,
  ) async {
    await enqueueEvent(event);
    if (!await _claimEvent(event.id)) {
      return FfmAssistantAutonomyEventProcessResult.duplicate;
    }
    try {
      await handler(event);
      await _setEventStatus(
        event.id,
        FfmAssistantAutonomyEventStatus.completed,
      );
      return FfmAssistantAutonomyEventProcessResult.processed;
    } on Object catch (error) {
      await _setEventStatus(
        event.id,
        FfmAssistantAutonomyEventStatus.failed,
        error: error.toString(),
      );
      return FfmAssistantAutonomyEventProcessResult.failed;
    }
  }

  Future<bool> _claimEvent(String eventId) async {
    final changed = await _db.customUpdate(
      'UPDATE assistant_agent_events '
      'SET status = ?, attempt_count = attempt_count + 1, last_attempt_at = ? '
      "WHERE event_id = ? AND status IN ('pending', 'failed')",
      variables: [
        Variable.withString(FfmAssistantAutonomyEventStatus.processing.name),
        Variable.withDateTime(_now()),
        Variable.withString(eventId),
      ],
      updates: {_db.assistantAgentEvents},
    );
    return changed == 1;
  }

  Future<void> _setEventStatus(
    String eventId,
    FfmAssistantAutonomyEventStatus status, {
    String? error,
  }) async {
    await (_db.update(
      _db.assistantAgentEvents,
    )..where((row) => row.eventId.equals(eventId))).write(
      AssistantAgentEventsCompanion(
        status: Value(status.name),
        error: Value(error),
        processedAt: status == FfmAssistantAutonomyEventStatus.completed
            ? Value(_now())
            : const Value.absent(),
      ),
    );
  }

  Future<AssistantAgentEvent?> eventById(String eventId) => (_db.select(
    _db.assistantAgentEvents,
  )..where((row) => row.eventId.equals(eventId))).getSingleOrNull();

  Future<List<FfmAssistantAutonomyEvent>> pendingEvents({
    String householdId = FfmAssistantAutonomyRepository.householdId,
    int limit = 10,
    int maxAttempts = 3,
  }) async {
    final boundedLimit = limit < 1
        ? 1
        : limit > 100
        ? 100
        : limit;
    final rows =
        await (_db.select(_db.assistantAgentEvents)
              ..where(
                (row) =>
                    row.householdId.equals(householdId) &
                    row.status.isIn(const ['pending', 'failed']),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.occurredAt)])
              ..limit(boundedLimit))
            .get();
    return rows
        .where((row) => row.attemptCount < maxAttempts)
        .map((row) {
          Map<String, Object?> payload = const {};
          try {
            final decoded = jsonDecode(row.payloadJson);
            if (decoded is Map) payload = decoded.cast<String, Object?>();
          } on Object {
            payload = const {};
          }
          return FfmAssistantAutonomyEvent(
            id: row.eventId,
            type: row.eventType,
            occurredAt: row.occurredAt,
            householdId: row.householdId,
            entityId: row.entityId,
            activityId: row.activityId,
            payload: payload,
          );
        })
        .toList(growable: false);
  }

  /// Menyimpan status plan dengan urutan penulisan serial agar status lama
  /// tidak menimpa status terbaru ketika UI menerima banyak progress update.
  Future<void> recordPlan(FfmAssistantActionPlan plan) {
    _runWriteQueue = _runWriteQueue.then((_) => _recordPlan(plan));
    return _runWriteQueue;
  }

  Future<void> _recordPlan(FfmAssistantActionPlan plan) async {
    final existing = await (_db.select(
      _db.assistantAgentRuns,
    )..where((row) => row.id.equals(plan.id))).getSingleOrNull();
    final now = _now();
    final completed = plan.steps
        .where((step) => step.status == FfmAssistantActionStepStatus.completed)
        .length;
    final failed = plan.steps
        .where((step) => step.status == FfmAssistantActionStepStatus.failed)
        .length;
    final error =
        plan.blockedReason ??
        plan.steps.map((step) => step.error).whereType<String>().firstOrNull;
    await _db
        .into(_db.assistantAgentRuns)
        .insertOnConflictUpdate(
          AssistantAgentRunsCompanion.insert(
            id: plan.id,
            householdId: householdId,
            trigger: 'chat',
            status: plan.status.name,
            summary: plan.summary,
            decisionSummary: Value(
              '$completed langkah selesai, $failed langkah gagal.',
            ),
            error: Value(error),
            startedAt: existing?.startedAt ?? now,
            finishedAt: Value(plan.isTerminal ? now : existing?.finishedAt),
            updatedAt: now,
          ),
        );
  }

  Future<AssistantAgentRun?> runById(String runId) => (_db.select(
    _db.assistantAgentRuns,
  )..where((row) => row.id.equals(runId))).getSingleOrNull();

  Future<List<AssistantAgentRun>> recentRuns({
    String householdId = FfmAssistantAutonomyRepository.householdId,
    int limit = 30,
  }) {
    final boundedLimit = limit < 1
        ? 1
        : limit > 100
        ? 100
        : limit;
    return (_db.select(_db.assistantAgentRuns)
          ..where((row) => row.householdId.equals(householdId))
          ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)])
          ..limit(boundedLimit))
        .get();
  }

  Future<FfmAssistantAgentGoal?> createGoal(FfmAssistantAgentGoal goal) async {
    if (goal.id.trim().isEmpty ||
        goal.householdId.trim().isEmpty ||
        goal.title.trim().isEmpty ||
        goal.objective.trim().isEmpty) {
      return null;
    }
    await _db
        .into(_db.assistantAgentGoals)
        .insertOnConflictUpdate(
          AssistantAgentGoalsCompanion.insert(
            id: goal.id,
            householdId: goal.householdId,
            domain: goal.domain,
            entityId: Value(goal.entityId),
            activityId: Value(goal.activityId),
            title: goal.title,
            objective: goal.objective,
            status: Value(goal.status.name),
            priority: Value(goal.priority),
            createdAt: goal.createdAt,
            updatedAt: goal.updatedAt,
            lastRunAt: Value(goal.lastRunAt),
            nextRunAt: Value(goal.nextRunAt),
            completionCondition: Value(goal.completionCondition),
          ),
        );
    return goal;
  }

  Future<AssistantAgentGoal?> goalById(String goalId) => (_db.select(
    _db.assistantAgentGoals,
  )..where((row) => row.id.equals(goalId))).getSingleOrNull();

  Future<List<AssistantAgentGoal>> goalsForHousehold(String household) =>
      (_db.select(_db.assistantAgentGoals)
            ..where((row) => row.householdId.equals(household))
            ..orderBy([
              (row) => OrderingTerm.desc(row.priority),
              (row) => OrderingTerm.desc(row.updatedAt),
            ]))
          .get();

  Future<bool> setGoalStatus(
    String goalId,
    FfmAssistantAgentGoalStatus status,
  ) async {
    final changed =
        await (_db.update(
          _db.assistantAgentGoals,
        )..where((row) => row.id.equals(goalId))).write(
          AssistantAgentGoalsCompanion(
            status: Value(status.name),
            updatedAt: Value(_now()),
          ),
        );
    return changed > 0;
  }

  Future<bool> evaluateAndCompleteGoal(String goalId) async {
    final goal = await goalById(goalId);
    if (goal == null ||
        goal.status != FfmAssistantAgentGoalStatus.active.name) {
      return false;
    }
    final tasks = await tasksForGoal(goalId);
    final taskStatuses = tasks.map(
      (task) => FfmAssistantAgentTaskStatus.values.firstWhere(
        (status) => status.name == task.status,
        orElse: () => FfmAssistantAgentTaskStatus.pending,
      ),
    );
    const evaluator = FfmAssistantAgentCompletionEvaluator();
    if (!evaluator.isSatisfied(goal.completionCondition, taskStatuses)) {
      return false;
    }
    return setGoalStatus(goalId, FfmAssistantAgentGoalStatus.completed);
  }

  Future<int> enqueueDueTaskEvents({
    String householdId = FfmAssistantAutonomyRepository.householdId,
    int limit = 20,
  }) async {
    final boundedLimit = limit < 1
        ? 1
        : limit > 100
        ? 100
        : limit;
    final now = _now();
    final tasks =
        await (_db.select(_db.assistantAgentTasks)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.status.isIn(const ['pending', 'failed']),
            ))
            .get();
    final dueTasks =
        tasks
            .where(
              (task) => task.nextRunAt != null && !task.nextRunAt!.isAfter(now),
            )
            .toList()
          ..sort((left, right) => left.nextRunAt!.compareTo(right.nextRunAt!));
    var inserted = 0;
    for (final task in dueTasks.take(boundedLimit)) {
      final goal = await goalById(task.goalId);
      if (goal?.status != FfmAssistantAgentGoalStatus.active.name) continue;
      final event = FfmAssistantAutonomyEvent(
        id: 'agent-task:${task.id}:due:${task.nextRunAt!.toIso8601String()}',
        type: 'agent.task.due',
        occurredAt: task.nextRunAt!,
        entityId: task.goalId,
        payload: <String, Object?>{'taskId': task.id, 'goalId': task.goalId},
      );
      if (await enqueueEvent(event)) inserted++;
    }
    return inserted;
  }

  Future<FfmAssistantAgentTask?> createTask(FfmAssistantAgentTask task) async {
    final goal =
        await (_db.select(_db.assistantAgentGoals)..where(
              (row) =>
                  row.id.equals(task.goalId) &
                  row.householdId.equals(task.householdId),
            ))
            .getSingleOrNull();
    if (goal == null ||
        goal.status == FfmAssistantAgentGoalStatus.completed.name ||
        goal.status == FfmAssistantAgentGoalStatus.cancelled.name ||
        task.id.trim().isEmpty ||
        task.title.trim().isEmpty) {
      return null;
    }
    final existingById = await (_db.select(
      _db.assistantAgentTasks,
    )..where((row) => row.id.equals(task.id))).getSingleOrNull();
    if (existingById != null &&
        (existingById.goalId != task.goalId ||
            existingById.householdId != task.householdId)) {
      return null;
    }
    final count = await (_db.select(
      _db.assistantAgentTasks,
    )..where((row) => row.goalId.equals(task.goalId))).get();
    if (count.length >= maxTasksPerGoal) return null;
    await _insertTask(task);
    return task;
  }

  Future<List<FfmAssistantAgentTask>> createTasksFromGoal({
    required String goalId,
    required String householdId,
    required Iterable<FfmAssistantAgentTask> tasks,
  }) async {
    final goal =
        await (_db.select(_db.assistantAgentGoals)..where(
              (row) =>
                  row.id.equals(goalId) & row.householdId.equals(householdId),
            ))
            .getSingleOrNull();
    if (goal == null ||
        goal.status == FfmAssistantAgentGoalStatus.completed.name ||
        goal.status == FfmAssistantAgentGoalStatus.cancelled.name) {
      return const [];
    }
    final existing =
        await (_db.select(_db.assistantAgentTasks)..where(
              (row) =>
                  row.goalId.equals(goalId) &
                  row.householdId.equals(householdId),
            ))
            .get();
    final existingIds = existing.map((task) => task.id).toSet();
    final available = maxTasksPerGoal - existing.length;
    if (available <= 0) return const [];

    final accepted = <FfmAssistantAgentTask>[];
    for (final task in tasks) {
      if (accepted.length >= available ||
          task.id.trim().isEmpty ||
          task.title.trim().isEmpty ||
          task.goalId != goalId ||
          task.householdId != householdId ||
          existingIds.contains(task.id) ||
          accepted.any((item) => item.id == task.id)) {
        continue;
      }
      accepted.add(task);
    }
    if (accepted.isEmpty) return const [];

    await _db.transaction(() async {
      for (final task in accepted) {
        final conflicting = await (_db.select(
          _db.assistantAgentTasks,
        )..where((row) => row.id.equals(task.id))).getSingleOrNull();
        if (conflicting != null) {
          throw StateError('Task ID sudah digunakan: ${task.id}');
        }
        await _insertTask(task);
      }
    });
    return accepted;
  }

  Future<void> _insertTask(FfmAssistantAgentTask task) => _db
      .into(_db.assistantAgentTasks)
      .insertOnConflictUpdate(
        AssistantAgentTasksCompanion.insert(
          id: task.id,
          goalId: task.goalId,
          householdId: task.householdId,
          title: task.title,
          objective: Value(task.objective),
          capabilityId: Value(task.capabilityId),
          parametersJson: Value(task.parametersJson),
          status: Value(task.status.name),
          priority: Value(task.priority),
          retryCount: Value(task.retryCount),
          maxRetries: Value(task.maxRetries),
          dueAt: Value(task.dueAt),
          lastRunAt: Value(task.lastRunAt),
          nextRunAt: Value(task.nextRunAt),
          lastError: Value(task.lastError),
          createdAt: task.createdAt,
          updatedAt: task.updatedAt,
          completedAt: Value(task.completedAt),
        ),
      );

  Future<List<AssistantAgentTask>> tasksForGoal(String goalId) =>
      (_db.select(_db.assistantAgentTasks)
            ..where((row) => row.goalId.equals(goalId))
            ..orderBy([
              (row) => OrderingTerm.desc(row.priority),
              (row) => OrderingTerm.asc(row.createdAt),
            ]))
          .get();

  Future<AssistantAgentTask?> taskById(String taskId) => (_db.select(
    _db.assistantAgentTasks,
  )..where((row) => row.id.equals(taskId))).getSingleOrNull();

  Future<bool> recordTaskExecution(
    FfmAssistantAgentTaskExecution execution,
  ) async {
    final task =
        await (_db.select(_db.assistantAgentTasks)..where(
              (row) =>
                  row.id.equals(execution.taskId) &
                  row.goalId.equals(execution.goalId) &
                  row.householdId.equals(execution.householdId),
            ))
            .getSingleOrNull();
    if (task == null) return false;
    await _db.transaction(() async {
      await _db
          .into(_db.assistantAgentTaskExecutions)
          .insertOnConflictUpdate(
            AssistantAgentTaskExecutionsCompanion.insert(
              id: execution.id,
              taskId: execution.taskId,
              goalId: execution.goalId,
              householdId: execution.householdId,
              runId: Value(execution.runId),
              status: execution.status.name,
              summary: Value(execution.summary),
              error: Value(execution.error),
              startedAt: execution.startedAt,
              finishedAt: Value(execution.finishedAt),
            ),
          );
      final now = _now();
      switch (execution.status) {
        case FfmAssistantAgentTaskExecutionStatus.started:
          await (_db.update(
            _db.assistantAgentTasks,
          )..where((row) => row.id.equals(task.id))).write(
            AssistantAgentTasksCompanion(
              status: Value(FfmAssistantAgentTaskStatus.running.name),
              lastRunAt: Value(now),
              updatedAt: Value(now),
            ),
          );
        case FfmAssistantAgentTaskExecutionStatus.completed:
          await (_db.update(
            _db.assistantAgentTasks,
          )..where((row) => row.id.equals(task.id))).write(
            AssistantAgentTasksCompanion(
              status: Value(FfmAssistantAgentTaskStatus.completed.name),
              updatedAt: Value(now),
              completedAt: Value(execution.finishedAt ?? now),
              lastError: const Value(null),
            ),
          );
        case FfmAssistantAgentTaskExecutionStatus.failed:
          await (_db.update(
            _db.assistantAgentTasks,
          )..where((row) => row.id.equals(task.id))).write(
            AssistantAgentTasksCompanion(
              status: Value(FfmAssistantAgentTaskStatus.failed.name),
              retryCount: Value(task.retryCount + 1),
              lastError: Value(execution.error),
              updatedAt: Value(now),
            ),
          );
        case FfmAssistantAgentTaskExecutionStatus.cancelled:
          await (_db.update(
            _db.assistantAgentTasks,
          )..where((row) => row.id.equals(task.id))).write(
            AssistantAgentTasksCompanion(
              status: Value(FfmAssistantAgentTaskStatus.cancelled.name),
              updatedAt: Value(now),
            ),
          );
      }
    });
    return true;
  }

  Future<List<AssistantAgentTaskExecution>> executionsForTask(String taskId) =>
      (_db.select(_db.assistantAgentTaskExecutions)
            ..where((row) => row.taskId.equals(taskId))
            ..orderBy([(row) => OrderingTerm.desc(row.startedAt)]))
          .get();

  Future<void> recordApprovalRequest(FfmAssistantActionPlan plan) async {
    await _db
        .into(_db.assistantAgentApprovals)
        .insert(
          AssistantAgentApprovalsCompanion.insert(
            id: plan.id,
            runId: plan.id,
            householdId: householdId,
            status: FfmAssistantApprovalStatus.requested.name,
            summary: plan.summary,
            requestedAt: plan.createdAt,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<void> recordApprovalDecision({
    required String runId,
    required FfmAssistantApprovalStatus status,
    String actor = 'user',
    String? reason,
  }) async {
    await (_db.update(
      _db.assistantAgentApprovals,
    )..where((row) => row.runId.equals(runId))).write(
      AssistantAgentApprovalsCompanion(
        status: Value(status.name),
        actor: Value(actor),
        reason: Value(reason),
        decidedAt: Value(_now()),
      ),
    );
  }

  Future<AssistantAgentApproval?> approvalByRunId(String runId) => (_db.select(
    _db.assistantAgentApprovals,
  )..where((row) => row.runId.equals(runId))).getSingleOrNull();

  Future<void> recordToolExecution(FfmAssistantToolExecution execution) async {
    await _db
        .into(_db.assistantAgentToolExecutions)
        .insertOnConflictUpdate(
          AssistantAgentToolExecutionsCompanion.insert(
            id: execution.id,
            runId: execution.runId,
            householdId: householdId,
            stepId: execution.stepId,
            capabilityId: execution.capabilityId,
            status: execution.status.name,
            attemptCount: Value(execution.attemptCount),
            resultSummary: Value(execution.resultSummary),
            error: Value(execution.error),
            startedAt: execution.startedAt,
            finishedAt: Value(execution.finishedAt),
          ),
        );
  }

  Future<List<AssistantAgentToolExecution>> toolExecutionsForRun(
    String runId, {
    String householdId = FfmAssistantAutonomyRepository.householdId,
  }) =>
      (_db.select(_db.assistantAgentToolExecutions)
            ..where(
              (row) =>
                  row.runId.equals(runId) & row.householdId.equals(householdId),
            )
            ..orderBy([(row) => OrderingTerm.asc(row.startedAt)]))
          .get();

  Future<FfmAssistantAutonomyPolicy?> loadPolicy({
    String householdId = FfmAssistantAutonomyRepository.householdId,
  }) async {
    final row =
        await (_db.select(_db.userPreferences)..where(
              (item) =>
                  item.householdId.equals(householdId) &
                  item.preferenceKey.equals(autonomyPolicyPreferenceKey),
            ))
            .getSingleOrNull();
    if (row == null) return null;
    return FfmAssistantAutonomyPolicy.fromJsonString(row.preferenceValue);
  }

  Future<void> savePolicy({
    required FfmAssistantAutonomyPolicy policy,
    String householdId = FfmAssistantAutonomyRepository.householdId,
  }) async {
    if (householdId.trim().isEmpty) return;
    final existing =
        await (_db.select(_db.userPreferences)..where(
              (item) =>
                  item.householdId.equals(householdId) &
                  item.preferenceKey.equals(autonomyPolicyPreferenceKey),
            ))
            .getSingleOrNull();
    final now = _now();
    final value = policy.toJsonString();
    if (existing == null) {
      await _db
          .into(_db.userPreferences)
          .insert(
            UserPreferencesCompanion.insert(
              id: '$householdId:$autonomyPolicyPreferenceKey',
              householdId: householdId,
              preferenceKey: autonomyPolicyPreferenceKey,
              preferenceValue: value,
              updatedAt: now,
            ),
          );
    } else {
      await (_db.update(
        _db.userPreferences,
      )..where((item) => item.id.equals(existing.id))).write(
        UserPreferencesCompanion(
          preferenceValue: Value(value),
          updatedAt: Value(now),
        ),
      );
    }
  }
}
