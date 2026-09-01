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
import 'package:ffm_manager/features/settings/data/tag_repository.dart';

void main() {
  final now = DateTime(2026, 8, 25);
  late AppDatabase database;
  late TagRepository tags;
  late FfmAssistantInterpreter interpreter;

  setUp(() async {
    database = createInMemoryDatabaseForTests();
    tags = TagRepository(database, AuditLogger(database), clock: () => now);
    interpreter = FfmAssistantInterpreter(database, clock: () => now);
    await tags.create(
      id: 'tag-belanja',
      householdId: AppContext.householdId,
      name: 'Belanja',
    );
    await database
        .into(database.transactionTags)
        .insert(
          TransactionTagsCompanion.insert(
            transactionId: 'historic-transaction',
            tagId: 'tag-belanja',
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

  Future<List<TransactionTag>> relations() =>
      database.select(database.transactionTags).get();

  test(
    'draft perubahan Tag tidak menulis metadata atau relasi transaksi',
    () async {
      final intent = await interpreter.interpret(
        'ubah tag belanja jadi Kebutuhan',
      );
      expect(intent.type, FfmAssistantIntentType.updateTag);
      expect(intent.draft?.kind, FfmAssistantDraftKind.tagUpdate);
      expect(
        (await tags.readActive(AppContext.householdId)).single.name,
        'Belanja',
      );
      expect(await relations(), hasLength(1));

      final plan = FfmAssistantActionPlanner(now: () => now).planFor(intent)!;
      expect(
        plan.steps.map((step) => step.capabilityId),
        containsAll(<String>[
          'draft.tag_update',
          'mutate.update',
          'verify.tag_mutation',
        ]),
      );
    },
  );

  test('target Tag ambigu hanya meminta klarifikasi tanpa write', () async {
    await tags.create(
      id: 'tag-beluarga',
      householdId: AppContext.householdId,
      name: 'Belanja Keluarga',
    );
    final intent = await interpreter.interpret('arsipkan tag belanja');
    expect(intent.type, FfmAssistantIntentType.archiveTag);
    expect(intent.clarification, isNotNull);
    expect(await tags.readActive(AppContext.householdId), hasLength(2));
    expect(await relations(), hasLength(1));
  });

  test(
    'update dan arsip Tag memakai repository tanpa mengubah relasi historis',
    () async {
      final updateIntent = await interpreter.interpret(
        'ubah tag belanja jadi Kebutuhan',
      );
      expect(
        (await execute(
          FfmAssistantActionPlanner(now: () => now).planFor(updateIntent)!,
        ))?.status,
        FfmAssistantActionPlanStatus.completed,
      );
      final changed = (await tags.readActive(AppContext.householdId)).single;
      expect(changed.id, 'tag-belanja');
      expect(changed.name, 'kebutuhan');
      expect(
        await relations(),
        contains(
          const TransactionTag(
            transactionId: 'historic-transaction',
            tagId: 'tag-belanja',
          ),
        ),
      );

      final archiveIntent = await interpreter.interpret(
        'arsipkan tag kebutuhan',
      );
      final archivePlan = FfmAssistantActionPlanner(now: () => now)
          .planFor(archiveIntent)!;
      expect(
        (await execute(archivePlan))?.status,
        FfmAssistantActionPlanStatus.completed,
      );
      expect(await tags.readActive(AppContext.householdId), isEmpty);
      expect(
        (await tags.get(AppContext.householdId, 'tag-belanja'))?.isArchived,
        isTrue,
      );
      expect(
        await relations(),
        contains(
          const TransactionTag(
            transactionId: 'historic-transaction',
            tagId: 'tag-belanja',
          ),
        ),
      );
      final audits = await database
          .customSelect(
            'SELECT action FROM audit_logs WHERE entity = ?',
            variables: [Variable<String>('tag')],
          )
          .get();
      expect(
        audits.map((row) => row.read<String>('action')),
        containsAll(<String>['update', 'archive']),
      );
    },
  );

  test('buat beberapa tag menghasilkan beberapa draft', () async {
    final result = await interpreter.interpretMany(
      'buat tag wajib dan sekolah',
    );

    expect(result.intents, hasLength(2));
    expect(
      result.intents.map((intent) => intent.draft?.kind),
      everyElement(FfmAssistantDraftKind.masterData),
    );
    expect(
      result.intents.map((intent) => intent.draft?.categoryName),
      everyElement('tag'),
    );
    expect(
      result.intents.map((intent) => intent.draft?.title),
      containsAll(<String>['Wajib', 'Sekolah']),
    );
  });
}
