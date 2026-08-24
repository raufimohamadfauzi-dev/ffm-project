import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_capability_adapters.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_plan.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_planner.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_capability_executor.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = createInMemoryDatabaseForTests();
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'orchestrator menjalankan query statistik melalui read adapter',
    () async {
      final intent = FfmAssistantIntent(
        rawText: 'berapa transaksi bulan ini',
        normalizedText: 'berapa transaksi bulan ini',
        type: FfmAssistantIntentType.transactionStats,
        response: 'Aku cek statistik lokal dulu.',
      );
      final plan = const FfmAssistantActionPlanner().planFor(intent);
      expect(plan, isNotNull);
      expect(plan!.hasMutation, isFalse);
      expect(plan.steps.single.capabilityId, 'read.transactions');

      final controller = FfmAssistantActionPlanController();
      controller.register(plan);
      final adapters = FfmAssistantCapabilityAdapterRegistry(
        database: database,
        householdId: 'local-household',
        clock: () => DateTime(2026, 8, 23),
      );
      final executed = await FfmAssistantCapabilityExecutor(
        controller: controller,
        handlers: adapters.handlers,
      ).execute(plan.id);

      expect(executed?.status, FfmAssistantActionPlanStatus.completed);
      expect(
        executed?.steps.single.status,
        FfmAssistantActionStepStatus.completed,
      );
      expect(executed?.steps.single.result, contains('Tidak ada transaksi'));
    },
  );
}
