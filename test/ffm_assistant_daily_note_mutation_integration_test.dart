import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/database/audit_logger.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_capability_adapters.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_plan.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_planner.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_capability_executor.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/daily_notes/data/daily_note_repository.dart';

void main() {
  const householdId = 'local-household';
  final now = DateTime(2026, 8, 25, 11);
  late AppDatabase database;
  late DailyNoteRepository notes;

  setUp(() {
    database = createInMemoryDatabaseForTests();
    notes = DailyNoteRepository(
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

  test(
    'simpan Catatan Harian memakai konfirmasi, readback, dan audit',
    () async {
      final intent = FfmAssistantIntent(
        rawText: 'catat catatan harian: cek anggaran besok',
        normalizedText: 'catat catatan harian cek anggaran besok',
        type: FfmAssistantIntentType.createDailyNote,
        destination: FfmAssistantDestination.activity,
        draft: FfmAssistantDraft(
          kind: FfmAssistantDraftKind.dailyNote,
          createdAt: now,
          note: 'Cek anggaran besok.',
          date: now,
          formValues: const {'body': 'Cek anggaran besok.'},
        ),
      );
      final plan = FfmAssistantActionPlanner(now: () => now).planFor(intent)!;

      final completed = await executeConfirmed(plan);

      expect(completed?.status, FfmAssistantActionPlanStatus.completed);
      final saved = await notes.readActive(householdId);
      expect(saved, hasLength(1));
      expect(saved.single.body, 'Cek anggaran besok.');
      final logs = await database
          .customSelect(
            'SELECT action FROM audit_logs WHERE entity = ?',
            variables: [Variable<String>('daily_note')],
          )
          .get();
      expect(logs.map((row) => row.read<String>('action')), contains('create'));
    },
  );

  test(
    'arsip Catatan Harian memakai target tunggal, konfirmasi, dan readback',
    () async {
      await notes.create(
        id: 'daily-note-archive',
        householdId: householdId,
        noteDate: now,
        title: 'Pasar',
        body: 'Belanja kebutuhan rumah.',
      );
      final intent = FfmAssistantIntent(
        rawText: 'arsipkan catatan pasar',
        normalizedText: 'arsipkan catatan pasar',
        type: FfmAssistantIntentType.archiveDailyNote,
        destination: FfmAssistantDestination.activity,
        draft: FfmAssistantDraft(
          kind: FfmAssistantDraftKind.dailyNoteArchive,
          createdAt: now,
          title: 'Pasar',
          formValues: const {
            'entity': 'daily_note',
            'targetId': 'daily-note-archive',
            'operation': 'archive',
          },
        ),
      );
      final plan = FfmAssistantActionPlanner(now: () => now).planFor(intent)!;

      final completed = await executeConfirmed(plan);

      expect(completed?.status, FfmAssistantActionPlanStatus.completed);
      expect(
        (await notes.get(householdId, 'daily-note-archive'))?.isArchived,
        isTrue,
      );
    },
  );
}
