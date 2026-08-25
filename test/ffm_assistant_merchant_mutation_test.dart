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
import 'package:ffm_manager/features/settings/data/merchant_repository.dart';

void main() {
  final now = DateTime(2026, 8, 25);
  late AppDatabase database;
  late MerchantRepository merchants;
  late FfmAssistantInterpreter interpreter;

  setUp(() async {
    database = createInMemoryDatabaseForTests();
    merchants = MerchantRepository(
      database,
      AuditLogger(database),
      clock: () => now,
    );
    interpreter = FfmAssistantInterpreter(database, clock: () => now);
    await merchants.create(
      id: 'warung-ibu',
      householdId: AppContext.householdId,
      name: 'Warung Ibu',
      details: 'Dekat rumah',
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

  test(
    'draft perubahan Toko/Tempat tidak menulis transaksi atau merchant',
    () async {
      final intent = await interpreter.interpret(
        'ubah toko warung ibu jadi Warung Sejahtera',
      );
      expect(intent.type, FfmAssistantIntentType.updateMerchant);
      expect(intent.draft?.kind, FfmAssistantDraftKind.merchantUpdate);
      expect(
        (await merchants.readActive(AppContext.householdId)).single.name,
        'Warung Ibu',
      );
      expect(await database.select(database.transactions).get(), isEmpty);

      final plan = FfmAssistantActionPlanner(now: () => now).planFor(intent)!;
      expect(
        plan.steps.map((step) => step.capabilityId),
        containsAll(<String>[
          'draft.merchant_update',
          'mutate.update',
          'verify.merchant_mutation',
        ]),
      );
    },
  );

  test(
    'target Toko/Tempat ambigu hanya meminta klarifikasi tanpa write',
    () async {
      await merchants.create(
        id: 'warung-kedua',
        householdId: AppContext.householdId,
        name: 'Warung Kantor',
      );
      final intent = await interpreter.interpret('arsipkan toko warung');
      expect(intent.type, FfmAssistantIntentType.archiveMerchant);
      expect(intent.clarification, isNotNull);
      expect(await merchants.readActive(AppContext.householdId), hasLength(2));
      expect(await database.select(database.transactions).get(), isEmpty);
    },
  );

  test(
    'update keterangan lalu arsip memakai repository, audit, dan readback',
    () async {
      final nameIntent = await interpreter.interpret(
        'ubah toko warung ibu jadi Warung Sejahtera',
      );
      expect(
        (await execute(
          FfmAssistantActionPlanner(now: () => now).planFor(nameIntent)!,
        ))?.status,
        FfmAssistantActionPlanStatus.completed,
      );

      final noteIntent = await interpreter.interpret(
        'ubah keterangan toko warung sejahtera jadi dekat kantor',
      );
      expect(
        (await execute(
          FfmAssistantActionPlanner(now: () => now).planFor(noteIntent)!,
        ))?.status,
        FfmAssistantActionPlanStatus.completed,
      );
      final changed = (await merchants.readActive(AppContext.householdId))
          .single;
      expect(changed.id, 'warung-ibu');
      expect(changed.name, 'warung sejahtera');
      expect(changed.details, 'dekat kantor');
      expect(await database.select(database.transactions).get(), isEmpty);

      final archiveIntent = await interpreter.interpret(
        'arsipkan toko warung sejahtera',
      );
      final archivePlan = FfmAssistantActionPlanner(now: () => now)
          .planFor(archiveIntent)!;
      expect(
        (await execute(archivePlan))?.status,
        FfmAssistantActionPlanStatus.completed,
      );
      expect(await merchants.readActive(AppContext.householdId), isEmpty);
      expect(
        (await merchants.get(AppContext.householdId, 'warung-ibu'))?.isActive,
        isFalse,
      );
      final audits = await database
          .customSelect(
            'SELECT action FROM audit_logs WHERE entity = ?',
            variables: [Variable<String>('merchant')],
          )
          .get();
      expect(
        audits.map((row) => row.read<String>('action')),
        containsAll(<String>['update', 'archive']),
      );
      expect(await database.select(database.transactions).get(), isEmpty);
    },
  );
}
