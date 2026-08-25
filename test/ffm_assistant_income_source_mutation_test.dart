import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/database/audit_logger.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_capability_adapters.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_plan.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_planner.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_capability_executor.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/settings/data/income_source_repository.dart';

void main() {
  final now = DateTime(2026, 8, 25);
  late AppDatabase database;
  late IncomeSourceRepository sources;
  late FfmAssistantInterpreter interpreter;

  setUp(() async {
    database = createInMemoryDatabaseForTests();
    sources = IncomeSourceRepository(
      database,
      AuditLogger(database),
      clock: () => now,
    );
    interpreter = FfmAssistantInterpreter(database, clock: () => now);
    await sources.create(
      id: 'source-gaji',
      householdId: AppContext.householdId,
      name: 'Gaji Bulanan',
      details: 'Perusahaan utama',
    );
    await database
        .into(database.transactions)
        .insert(
          TransactionsCompanion.insert(
            id: 'historic-income',
            householdId: AppContext.householdId,
            type: 'income',
            amount: 5000000,
            date: now,
            recordedAt: now,
            sourceId: const Value('source-gaji'),
            createdAt: now,
          ),
        );
  });

  tearDown(() => database.close());

  Future<FfmAssistantActionPlan?> execute(FfmAssistantActionPlan plan) async {
    final controller = FfmAssistantActionPlanController(now: () => now)
      ..register(plan)
      ..markAwaitingConfirmation(plan.id)
      ..confirm(plan.id);
    return FfmAssistantCapabilityExecutor(
      controller: controller,
      handlers: FfmAssistantCapabilityAdapterRegistry(
        database: database,
        householdId: AppContext.householdId,
        clock: () => now,
      ).handlers,
    ).execute(plan.id);
  }

  Future<String?> historicSourceId() async =>
      (await database.select(database.transactions).getSingle()).sourceId;

  test(
    'draft perubahan Sumber Pemasukan tidak menulis sumber atau sourceId',
    () async {
      final intent = await interpreter.interpret(
        'ubah sumber pemasukan gaji bulanan jadi Gaji Utama',
      );
      expect(intent.type, FfmAssistantIntentType.updateIncomeSource);
      expect(intent.draft?.kind, FfmAssistantDraftKind.incomeSourceUpdate);
      expect(
        (await sources.readActive(AppContext.householdId)).single.name,
        'Gaji Bulanan',
      );
      expect(await historicSourceId(), 'source-gaji');

      final plan = FfmAssistantActionPlanner(now: () => now).planFor(intent)!;
      expect(
        plan.steps.map((step) => step.capabilityId),
        containsAll(<String>[
          'draft.income_source_update',
          'mutate.update',
          'verify.income_source_mutation',
        ]),
      );
    },
  );

  test(
    'target Sumber Pemasukan ambigu hanya meminta klarifikasi tanpa write',
    () async {
      await sources.create(
        id: 'source-gaji-sampingan',
        householdId: AppContext.householdId,
        name: 'Gaji Sampingan',
      );
      final intent = await interpreter.interpret(
        'arsipkan sumber pemasukan gaji',
      );
      expect(intent.type, FfmAssistantIntentType.archiveIncomeSource);
      expect(intent.clarification, isNotNull);
      expect(await sources.readActive(AppContext.householdId), hasLength(2));
      expect(await historicSourceId(), 'source-gaji');
    },
  );

  test(
    'update keterangan lalu arsip menjaga kind role dan sourceId historis',
    () async {
      final nameIntent = await interpreter.interpret(
        'ubah sumber pemasukan gaji bulanan jadi Gaji Utama',
      );
      expect(
        (await execute(
          FfmAssistantActionPlanner(now: () => now).planFor(nameIntent)!,
        ))?.status,
        FfmAssistantActionPlanStatus.completed,
      );
      final noteIntent = await interpreter.interpret(
        'ubah keterangan sumber pemasukan gaji utama jadi penghasilan pokok',
      );
      expect(
        (await execute(
          FfmAssistantActionPlanner(now: () => now).planFor(noteIntent)!,
        ))?.status,
        FfmAssistantActionPlanStatus.completed,
      );
      final changed = (await sources.readActive(AppContext.householdId)).single;
      expect(changed.id, 'source-gaji');
      expect(changed.name, 'gaji utama');
      expect(changed.details, 'penghasilan pokok');
      expect(changed.kind, IncomeSourceRepository.kind);
      expect(changed.role, IncomeSourceRepository.role);
      expect(await historicSourceId(), 'source-gaji');

      final archiveIntent = await interpreter.interpret(
        'arsipkan sumber pemasukan gaji utama',
      );
      final archivePlan = FfmAssistantActionPlanner(now: () => now)
          .planFor(archiveIntent)!;
      expect(
        (await execute(archivePlan))?.status,
        FfmAssistantActionPlanStatus.completed,
      );
      expect(await sources.readActive(AppContext.householdId), isEmpty);
      final archived = await sources.get(AppContext.householdId, 'source-gaji');
      expect(archived?.isArchived, isTrue);
      expect(archived?.kind, IncomeSourceRepository.kind);
      expect(archived?.role, IncomeSourceRepository.role);
      expect(await historicSourceId(), 'source-gaji');
      final audits = await database
          .customSelect(
            'SELECT action FROM audit_logs WHERE entity = ?',
            variables: [Variable<String>('income_source')],
          )
          .get();
      expect(
        audits.map((row) => row.read<String>('action')),
        containsAll(<String>['update', 'archive']),
      );
    },
  );
}
