import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_capability_adapters.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_plan.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_planner.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_capability_executor.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/receivable/domain/entities/receivable_entity.dart';
import 'package:ffm_manager/features/receivable/domain/usecases/receivable_crud_usecases.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 8, 25);
  late AppDatabase database;
  late FfmAssistantInterpreter interpreter;

  setUp(() async {
    database = createInMemoryDatabaseForTests();
    interpreter = FfmAssistantInterpreter(database, clock: () => now);
    await SaveReceivable(database)(
      ReceivableEntity(
        id: 'andi',
        householdId: AppContext.householdId,
        name: 'Piutang Andi',
        originalAmount: 1250000,
        remainingBalance: 750000,
        monthlyInstallment: 250000,
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
    'draft update Piutang tidak menulis, lalu update dan arsip menjaga batasan',
    () async {
      final update = await interpreter.interpret(
        'ubah piutang piutang andi jadi Piutang Proyek Andi',
      );
      expect(update.type, FfmAssistantIntentType.updateReceivable);
      expect(
        (await GetReceivables(database)(AppContext.householdId)).single.name,
        'Piutang Andi',
      );

      final updatePlan = FfmAssistantActionPlanner(now: () => now)
          .planFor(update)!;
      expect(
        updatePlan.steps.map((step) => step.capabilityId),
        containsAll(<String>[
          'draft.receivable_update',
          'mutate.update',
          'verify.receivable_mutation',
        ]),
      );
      expect(
        (await execute(updatePlan))?.status,
        FfmAssistantActionPlanStatus.completed,
      );

      final changed = (await GetReceivables(database)(AppContext.householdId))
          .single;
      expect(changed.name, 'piutang proyek andi');
      expect(changed.originalAmount, 1250000);
      expect(changed.remainingBalance, 750000);

      final archive = await interpreter.interpret(
        'arsipkan piutang piutang proyek andi',
      );
      expect(archive.type, FfmAssistantIntentType.archiveReceivable);
      final archivePlan = FfmAssistantActionPlanner(now: () => now)
          .planFor(archive)!;
      expect(
        archivePlan.steps.map((step) => step.capabilityId),
        containsAll(<String>[
          'draft.receivable_archive',
          'mutate.archive',
          'verify.receivable_mutation',
        ]),
      );
      expect(
        (await execute(archivePlan))?.status,
        FfmAssistantActionPlanStatus.completed,
      );
      expect(await GetReceivables(database)(AppContext.householdId), isEmpty);
    },
  );

  test('target Piutang ambigu hanya meminta klarifikasi tanpa write', () async {
    await SaveReceivable(database)(
      ReceivableEntity(
        id: 'andi-kedua',
        householdId: AppContext.householdId,
        name: 'Piutang Andi Kedua',
        originalAmount: 100000,
        remainingBalance: 100000,
        monthlyInstallment: 0,
        startDate: now,
        dueDate: DateTime(2027),
        updatedAt: now,
      ),
    );
    final intent = await interpreter.interpret('arsipkan piutang andi');
    expect(intent.type, FfmAssistantIntentType.archiveReceivable);
    expect(intent.clarification, isNotNull);
    expect(
      await GetReceivables(database)(AppContext.householdId),
      hasLength(2),
    );
  });
}
