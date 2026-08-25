import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/asset/domain/entities/asset_entity.dart';
import 'package:ffm_manager/features/asset/domain/usecases/asset_crud_usecases.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_capability_adapters.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_plan.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_planner.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_capability_executor.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';

void main() {
  final now = DateTime(2026, 8, 25, 11);
  late AppDatabase database;
  late FfmAssistantInterpreter interpreter;

  setUp(() async {
    database = createInMemoryDatabaseForTests();
    interpreter = FfmAssistantInterpreter(database, clock: () => now);
    await SaveAsset(database)(
      AssetEntity(
        id: 'gold-main',
        householdId: AppContext.householdId,
        name: 'Emas keluarga',
        assetType: 'emas',
        value: 20000000,
        placement: 'brankas',
        note: 'investasi',
        createdAt: now,
      ),
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
      householdId: AppContext.householdId,
      clock: () => now,
    );
    return FfmAssistantCapabilityExecutor(
      controller: controller,
      handlers: adapters.handlers,
    ).execute(plan.id);
  }

  test('ubah Aset menyiapkan draft tanpa write sebelum konfirmasi', () async {
    final intent = await interpreter.interpret(
      'ubah aset emas keluarga jadi 25000000',
    );

    expect(intent.type, FfmAssistantIntentType.updateAsset);
    expect(intent.draft?.kind, FfmAssistantDraftKind.assetUpdate);
    expect(intent.draft?.formValues['targetId'], 'gold-main');
    expect(intent.draft?.amount, 25000000);
    expect(intent.needsConfirmation, isTrue);
    final assets = await GetAssets(database)(AppContext.householdId);
    expect(assets.single.value, 20000000);
  });

  test('target Aset ambigu meminta klarifikasi tanpa write', () async {
    await SaveAsset(database)(
      AssetEntity(
        id: 'gold-secondary',
        householdId: AppContext.householdId,
        name: 'Emas investasi',
        assetType: 'emas',
        value: 5000000,
        placement: 'brankas',
        createdAt: now,
      ),
    );

    final intent = await interpreter.interpret('arsipkan aset emas');

    expect(intent.type, FfmAssistantIntentType.archiveAsset);
    expect(intent.draft, isNull);
    expect(intent.clarification, contains('menemukan 2 aset'));
  });

  test(
    'konfirmasi update dan arsip Aset memakai usecase, audit, dan readback',
    () async {
      final updateIntent = await interpreter.interpret(
        'ubah aset emas keluarga jadi 25000000',
      );
      final updatePlan = FfmAssistantActionPlanner(now: () => now)
          .planFor(updateIntent)!;
      expect(updatePlan.steps.last.capabilityId, 'verify.asset_mutation');
      expect(
        (await executeConfirmed(updatePlan))?.status,
        FfmAssistantActionPlanStatus.completed,
      );
      var assets = await GetAssets(database)(AppContext.householdId);
      expect(assets.single.value, 25000000);
      expect(assets.single.id, 'gold-main');
      expect(assets.single.createdAt, now);

      final archiveIntent = await interpreter.interpret(
        'arsipkan aset emas keluarga',
      );
      final archivePlan = FfmAssistantActionPlanner(now: () => now)
          .planFor(archiveIntent)!;
      expect(
        (await executeConfirmed(archivePlan))?.status,
        FfmAssistantActionPlanStatus.completed,
      );
      assets = await GetAssets(database)(AppContext.householdId);
      expect(assets, isEmpty);
      final audit = await database
          .customSelect(
            'SELECT action FROM audit_logs WHERE entity = ?',
            variables: [Variable<String>('asset')],
          )
          .get();
      expect(
        audit.map((row) => row.read<String>('action')),
        contains('arsip aset'),
      );
    },
  );
}
