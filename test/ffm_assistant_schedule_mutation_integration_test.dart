import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/database/audit_logger.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_capability_adapters.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_plan.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_planner.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_capability_executor.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/schedule/data/schedule_repository.dart';

void main() {
  const householdId = 'local-household';
  final now = DateTime(2026, 8, 25, 11);
  late AppDatabase database;
  late ScheduleRepository schedules;

  setUp(() {
    database = createInMemoryDatabaseForTests();
    schedules = ScheduleRepository(
      database,
      AuditLogger(database),
      clock: () => now,
    );
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

  FfmAssistantActionPlan schedulePlan(
    FfmAssistantIntentType type,
    FfmAssistantDraft draft,
  ) => FfmAssistantActionPlanner(now: () => now).planFor(
    FfmAssistantIntent(
      rawText: draft.title ?? type.name,
      normalizedText: draft.title?.toLowerCase() ?? type.name,
      type: type,
      destination: FfmAssistantDestination.activity,
      draft: draft,
    ),
  )!;

  test('simpan Jadwal memakai konfirmasi, repository, audit, dan readback tanpa Pengingat', () async {
    final plan = schedulePlan(
      FfmAssistantIntentType.createSchedule,
      FfmAssistantDraft(
        kind: FfmAssistantDraftKind.schedule,
        createdAt: now,
        title: 'Kontrol dokter',
        date: DateTime(2026, 8, 28),
        formValues: const {
          'entity': 'schedule_entry',
          'date': '2026-08-28T00:00:00.000',
          'isAllDay': 'true',
        },
      ),
    );

    expect(plan.steps.last.capabilityId, 'verify.schedule_mutation');
    expect(
      (await executeConfirmed(plan))?.status,
      FfmAssistantActionPlanStatus.completed,
    );
    final saved = await schedules.readActive(householdId);
    expect(saved, hasLength(1));
    expect(saved.single.title, 'Kontrol dokter');
    expect((await database.select(database.reminders).get()), isEmpty);
    final logs = await database
        .customSelect(
          'SELECT action FROM audit_logs WHERE entity = ?',
          variables: [Variable<String>('schedule_entry')],
        )
        .get();
    expect(logs.map((row) => row.read<String>('action')), contains('create'));
  });

  test('ubah dan arsip Jadwal memakai target tunggal serta readback', () async {
    final entry = await schedules.create(
      id: 'schedule-update-archive',
      householdId: householdId,
      title: 'Kontrol dokter',
      scheduledDate: now,
    );
    final updatePlan = schedulePlan(
      FfmAssistantIntentType.updateSchedule,
      FfmAssistantDraft(
        kind: FfmAssistantDraftKind.scheduleUpdate,
        createdAt: now,
        title: entry.title,
        date: DateTime(2026, 8, 26),
        formValues: {
          'entity': 'schedule_entry',
          'targetId': entry.id,
          'operation': 'update',
          'date': '2026-08-26T00:00:00.000',
          'isAllDay': 'false',
          'startMinutes': '570',
        },
      ),
    );
    expect(
      (await executeConfirmed(updatePlan))?.status,
      FfmAssistantActionPlanStatus.completed,
    );
    final updated = await schedules.get(householdId, entry.id);
    expect(updated?.scheduledDate, DateTime(2026, 8, 26));
    expect(updated?.startMinutes, 570);

    final archivePlan = schedulePlan(
      FfmAssistantIntentType.archiveSchedule,
      FfmAssistantDraft(
        kind: FfmAssistantDraftKind.scheduleArchive,
        createdAt: now,
        title: entry.title,
        formValues: {
          'entity': 'schedule_entry',
          'targetId': entry.id,
          'operation': 'archive',
        },
      ),
    );
    expect(
      (await executeConfirmed(archivePlan))?.status,
      FfmAssistantActionPlanStatus.completed,
    );
    expect((await schedules.get(householdId, entry.id))?.isArchived, isTrue);
  });
}
