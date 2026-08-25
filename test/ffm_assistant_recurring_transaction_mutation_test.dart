import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_capability_adapters.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_plan.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_planner.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_capability_executor.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/recurring_transaction/domain/usecases/recurring_transaction_crud_usecases.dart';

void main() {
  final now = DateTime(2026, 8, 25);
  late AppDatabase database;
  late FfmAssistantInterpreter interpreter;

  setUp(() async {
    database = createInMemoryDatabaseForTests();
    interpreter = FfmAssistantInterpreter(database, clock: () => now);
    await CreateRecurringTransaction(database)(
      householdId: AppContext.householdId,
      name: 'Internet Rumah',
      type: 'expense',
      amount: 350000,
      startDate: now,
      periodType: 'monthly',
      note: 'Tagihan internet',
      calcMode: 'fixed',
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
    'draft update tidak menjalankan jadwal atau membentuk transaksi',
    () async {
      final intent = await interpreter.interpret(
        'ubah transaksi berkala internet rumah jadi Internet Fiber',
      );
      expect(intent.type, FfmAssistantIntentType.updateRecurringTransaction);
      expect(
        (await GetRecurringTransactions(database)(AppContext.householdId))
            .single
            .name,
        'Internet Rumah',
      );
      expect(await database.select(database.transactions).get(), isEmpty);
      expect(
        await database.select(database.recurringTransactionRuns).get(),
        isEmpty,
      );

      final plan = FfmAssistantActionPlanner(now: () => now).planFor(intent)!;
      expect(
        plan.steps.map((step) => step.capabilityId),
        containsAll(<String>[
          'draft.recurring_transaction_update',
          'mutate.update',
          'verify.recurring_transaction_mutation',
        ]),
      );
      expect(
        (await execute(plan))?.status,
        FfmAssistantActionPlanStatus.completed,
      );

      final updated = (await GetRecurringTransactions(database)(
        AppContext.householdId,
      )).single;
      expect(updated.name, 'internet fiber');
      expect(updated.amount, 350000);
      expect(updated.type, 'expense');
      expect(updated.periodType, 'monthly');
      expect(updated.calcMode, 'fixed');
      expect(updated.note, 'Tagihan internet');
      expect(await database.select(database.transactions).get(), isEmpty);
      expect(
        await database.select(database.recurringTransactionRuns).get(),
        isEmpty,
      );
    },
  );

  test(
    'perubahan catatan menjaga field terlindungi lalu arsip lunak',
    () async {
      final noteIntent = await interpreter.interpret(
        'ubah catatan transaksi berkala internet rumah jadi tagihan prioritas',
      );
      expect(
        noteIntent.type,
        FfmAssistantIntentType.updateRecurringTransaction,
      );
      expect(
        (await execute(
          FfmAssistantActionPlanner(now: () => now).planFor(noteIntent)!,
        ))?.status,
        FfmAssistantActionPlanStatus.completed,
      );

      final changed = (await GetRecurringTransactions(database)(
        AppContext.householdId,
      )).single;
      expect(changed.name, 'Internet Rumah');
      expect(changed.note, 'tagihan prioritas');
      expect(changed.amount, 350000);
      expect(changed.startDate, now);

      final archiveIntent = await interpreter.interpret(
        'nonaktifkan transaksi berkala internet rumah',
      );
      expect(
        archiveIntent.type,
        FfmAssistantIntentType.archiveRecurringTransaction,
      );
      final archivePlan = FfmAssistantActionPlanner(now: () => now)
          .planFor(archiveIntent)!;
      expect(
        archivePlan.steps.map((step) => step.capabilityId),
        containsAll(<String>[
          'draft.recurring_transaction_archive',
          'mutate.archive',
          'verify.recurring_transaction_mutation',
        ]),
      );
      expect(
        (await execute(archivePlan))?.status,
        FfmAssistantActionPlanStatus.completed,
      );
      expect(
        await GetRecurringTransactions(database)(AppContext.householdId),
        isEmpty,
      );
      final archived = await database
          .select(database.recurringTransactions)
          .getSingle();
      expect(archived.isActive, isFalse);
      expect(await database.select(database.transactions).get(), isEmpty);
      expect(
        await database.select(database.recurringTransactionRuns).get(),
        isEmpty,
      );
    },
  );

  test('target ambigu hanya meminta klarifikasi tanpa write', () async {
    await CreateRecurringTransaction(database)(
      householdId: AppContext.householdId,
      name: 'Internet Kantor',
      type: 'expense',
      amount: 400000,
      startDate: now,
      periodType: 'monthly',
      calcMode: 'fixed',
    );
    final intent = await interpreter.interpret(
      'arsipkan transaksi berkala internet',
    );
    expect(intent.type, FfmAssistantIntentType.archiveRecurringTransaction);
    expect(intent.clarification, isNotNull);
    expect(
      await GetRecurringTransactions(database)(AppContext.householdId),
      hasLength(2),
    );
    expect(await database.select(database.transactions).get(), isEmpty);
    expect(
      await database.select(database.recurringTransactionRuns).get(),
      isEmpty,
    );
  });
}
