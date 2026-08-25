import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_capability_adapters.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_plan.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_planner.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_capability_executor.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/liability/domain/entities/liability_entity.dart';
import 'package:ffm_manager/features/liability/domain/usecases/liability_crud_usecases.dart';

void main() {
  final now = DateTime(2026, 8, 25);
  late AppDatabase database;
  late FfmAssistantInterpreter interpreter;
  setUp(() async {
    database = createInMemoryDatabaseForTests();
    interpreter = FfmAssistantInterpreter(database, clock: () => now);
    await SaveLiability(database)(
      LiabilityEntity(
        id: 'bank',
        householdId: AppContext.householdId,
        name: 'Hutang Bank',
        originalAmount: 10000000,
        remainingBalance: 8000000,
        monthlyInstallment: 500000,
        startDate: now,
        dueDate: DateTime(2027),
        updatedAt: now,
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

  test(
    'update Hutang menjaga nilai pokok dan sisa serta arsip lunak',
    () async {
      final update = await interpreter.interpret(
        'ubah hutang hutang bank jadi Hutang Rumah',
      );
      expect(update.type, FfmAssistantIntentType.updateLiability);
      expect(
        (await GetLiabilities(database)(AppContext.householdId)).single.name,
        'Hutang Bank',
      );
      expect(
        (await execute(
          FfmAssistantActionPlanner(now: () => now).planFor(update)!,
        ))?.status,
        FfmAssistantActionPlanStatus.completed,
      );
      final changed = (await GetLiabilities(database)(AppContext.householdId))
          .single;
      expect(changed.name, 'hutang rumah');
      expect(changed.originalAmount, 10000000);
      expect(changed.remainingBalance, 8000000);
      final archive = await interpreter.interpret(
        'arsipkan hutang hutang rumah',
      );
      expect(
        (await execute(
          FfmAssistantActionPlanner(now: () => now).planFor(archive)!,
        ))?.status,
        FfmAssistantActionPlanStatus.completed,
      );
      expect(await GetLiabilities(database)(AppContext.householdId), isEmpty);
    },
  );
}
