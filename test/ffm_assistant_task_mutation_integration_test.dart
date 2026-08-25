import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/database/audit_logger.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_capability_adapters.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_plan.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_planner.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_capability_executor.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/tasks/data/task_repository.dart';

void main() {
  const householdId = 'local-household';
  final now = DateTime(2026, 8, 25, 11);
  late AppDatabase database;
  late TaskRepository tasks;

  setUp(() {
    database = createInMemoryDatabaseForTests();
    tasks = TaskRepository(database, AuditLogger(database), clock: () => now);
  });

  tearDown(() => database.close());

  Future<FfmAssistantActionPlan?> executeConfirmed(
    FfmAssistantActionPlan plan,
  ) async {
    final controller = FfmAssistantActionPlanController(now: () => now)
      ..register(plan)
      ..markAwaitingConfirmation(plan.id)
      ..confirm(plan.id);
    final adapters = FfmAssistantCapabilityAdapterRegistry(
      database: database,
      householdId: householdId,
      clock: () => now,
    );
    return FfmAssistantCapabilityExecutor(
      controller: controller,
      handlers: adapters.handlers,
    ).execute(plan.id);
  }

  test('simpan Tugas memakai konfirmasi, readback, dan audit', () async {
    final intent = FfmAssistantIntent(
      rawText: 'buat tugas cek anggaran',
      normalizedText: 'buat tugas cek anggaran',
      type: FfmAssistantIntentType.createTask,
      destination: FfmAssistantDestination.activity,
      draft: FfmAssistantDraft(
        kind: FfmAssistantDraftKind.task,
        createdAt: now,
        title: 'Cek anggaran',
        formValues: const {'entity': 'task'},
      ),
    );
    final plan = FfmAssistantActionPlanner(now: () => now).planFor(intent)!;

    final completed = await executeConfirmed(plan);

    expect(completed?.status, FfmAssistantActionPlanStatus.completed);
    final saved = await tasks.readActive(householdId);
    expect(saved, hasLength(1));
    expect(saved.single.title, 'Cek anggaran');
    final logs = await database
        .customSelect(
          'SELECT action FROM audit_logs WHERE entity = ?',
          variables: [Variable<String>('task')],
        )
        .get();
    expect(logs.map((row) => row.read<String>('action')), contains('create'));
  });

  test(
    'selesaikan dan arsip Tugas memakai target tunggal serta readback',
    () async {
      final task = await tasks.create(
        id: 'task-finish-archive',
        householdId: householdId,
        title: 'Cek anggaran',
      );
      final completeIntent = FfmAssistantIntent(
        rawText: 'selesaikan tugas cek anggaran',
        normalizedText: 'selesaikan tugas cek anggaran',
        type: FfmAssistantIntentType.completeTask,
        destination: FfmAssistantDestination.activity,
        draft: FfmAssistantDraft(
          kind: FfmAssistantDraftKind.taskComplete,
          createdAt: now,
          title: task.title,
          formValues: {
            'entity': 'task',
            'targetId': task.id,
            'operation': 'complete',
          },
        ),
      );
      final completePlan = FfmAssistantActionPlanner(now: () => now)
          .planFor(completeIntent)!;

      expect(
        (await executeConfirmed(completePlan))?.status,
        FfmAssistantActionPlanStatus.completed,
      );
      expect((await tasks.get(householdId, task.id))?.isCompleted, isTrue);

      final archiveIntent = FfmAssistantIntent(
        rawText: 'arsipkan tugas cek anggaran',
        normalizedText: 'arsipkan tugas cek anggaran',
        type: FfmAssistantIntentType.archiveTask,
        destination: FfmAssistantDestination.activity,
        draft: FfmAssistantDraft(
          kind: FfmAssistantDraftKind.taskArchive,
          createdAt: now,
          title: task.title,
          formValues: {
            'entity': 'task',
            'targetId': task.id,
            'operation': 'archive',
          },
        ),
      );
      final archivePlan = FfmAssistantActionPlanner(now: () => now)
          .planFor(archiveIntent)!;

      expect(
        (await executeConfirmed(archivePlan))?.status,
        FfmAssistantActionPlanStatus.completed,
      );
      expect((await tasks.get(householdId, task.id))?.isArchived, isTrue);
    },
  );
}
