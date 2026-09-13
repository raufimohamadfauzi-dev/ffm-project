import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_capability_adapters.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_plan.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_planner.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_capability_executor.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/goal/domain/entities/goal_entity.dart';
import 'package:ffm_manager/features/goal/domain/usecases/goal_crud_usecases.dart';
import 'package:drift/drift.dart' hide Column, isNull;

void main() {
  final now = DateTime(2026, 8, 24, 9);
  late AppDatabase database;
  late FfmAssistantInterpreter interpreter;

  setUp(() async {
    database = createInMemoryDatabaseForTests();
    interpreter = FfmAssistantInterpreter(database, clock: () => now);
    await SaveGoal(database)(
      GoalEntity(
        id: 'goal-emergency',
        householdId: AppContext.householdId,
        name: 'Dana darurat',
        targetAmount: 5000000,
        currentAmount: 1000000,
             targetDate: DateTime(2026, 12, 31),
             note: 'Dana untuk kondisi darurat',
             createdAt: now,
      ),
    );
  });

  tearDown(() async {
    await database.close();
  });

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

  test(
    'ubah target menghasilkan draft tanpa write sebelum konfirmasi',
    () async {
      final intent = await interpreter.interpret(
        'ubah target dana darurat jadi 6000000',
      );

      expect(intent.type, FfmAssistantIntentType.updateGoal);
      expect(intent.destination, FfmAssistantDestination.goals);
      expect(intent.draft?.kind, FfmAssistantDraftKind.goalUpdate);
      expect(intent.draft?.amount, 6000000);
      expect(intent.draft?.formValues['targetId'], 'goal-emergency');
      expect(intent.needsConfirmation, isTrue);
      final goal = await GetGoal(database)(
        AppContext.householdId,
        'goal-emergency',
      );
      expect(goal?.targetAmount, 5000000);
    },
  );

  test('target ambigu tidak dipilih secara diam-diam', () async {
    await SaveGoal(database)(
      GoalEntity(
        id: 'goal-emergency-home',
        householdId: AppContext.householdId,
        name: 'Dana darurat rumah',
        targetAmount: 3000000,
        currentAmount: 0,
        targetDate: DateTime(2026, 11, 1),
        createdAt: now,
      ),
    );

    final intent = await interpreter.interpret('arsip target dana darurat');

    expect(intent.type, FfmAssistantIntentType.archiveGoal);
    expect(intent.draft, isNull);
    expect(intent.clarification, contains('menemukan 2 target'));
  });

  test(
    'ubah target melewati preview, konfirmasi, audit, dan verifikasi',
    () async {
      final intent = await interpreter.interpret(
        'ubah target dana darurat jadi 6000000',
      );
      final plan = FfmAssistantActionPlanner(now: () => now).planFor(intent)!;

      final completed = await executeConfirmed(plan);

      expect(completed?.status, FfmAssistantActionPlanStatus.completed);
      expect(
        completed?.steps.map((step) => step.capabilityId),
        equals([
          'read.goals',
          'navigate.goals',
          'draft.goal_update',
          'mutate.update',
          'verify.goal_mutation',
        ]),
      );
      final goal = await GetGoal(database)(
        AppContext.householdId,
        'goal-emergency',
      );
      expect(goal?.targetAmount, 6000000);
      expect(goal?.currentAmount, 1000000);
      final logs = await database
          .customSelect('SELECT action, entity FROM audit_logs')
          .get();
      expect(logs.last.read<String>('action'), 'simpan target');
      expect(logs.last.read<String>('entity'), 'goal');
    },
  );

  test(
    'arsip target mempertahankan progres dan menonaktifkan target',
    () async {
      final intent = await interpreter.interpret('arsip target dana darurat');
      final plan = FfmAssistantActionPlanner(now: () => now).planFor(intent)!;

      final completed = await executeConfirmed(plan);

      expect(completed?.status, FfmAssistantActionPlanStatus.completed);
      final goal = await GetGoal(database)(
        AppContext.householdId,
        'goal-emergency',
      );
      expect(goal?.isActive, isFalse);
      expect(goal?.currentAmount, 1000000);
    },
  );

  test('target baru tidak boleh lebih kecil dari progres tersimpan', () async {
    final intent = await interpreter.interpret(
      'ubah target dana darurat jadi 500000',
    );
    final plan = FfmAssistantActionPlanner(now: () => now).planFor(intent)!;

    final completed = await executeConfirmed(plan);

    expect(completed?.status, FfmAssistantActionPlanStatus.failed);
    final goal = await GetGoal(database)(
      AppContext.householdId,
      'goal-emergency',
    );
    expect(goal?.targetAmount, 5000000);
  });

  test('setor target atomik menolak saldo rekening yang tidak cukup', () async {
    await database
        .into(database.accounts)
        .insert(
          AccountsCompanion.insert(
            id: 'goal-cash',
            householdId: AppContext.householdId,
            name: 'Tunai Goal',
            type: 'cash',
            openingBalance: const Value(10000),
            createdAt: now,
          ),
        );
    final adapters = FfmAssistantCapabilityAdapterRegistry(
      database: database,
      householdId: AppContext.householdId,
      clock: () => now,
    );
    final result = await adapters.handlers['mutate.save_draft']!(
      const FfmAssistantActionStep(
        id: 'save',
        capabilityId: 'mutate.save_draft',
        parameters: {
          'kind': 'goal_deposit',
          'goal': 'Dana darurat',
          'accountId': 'goal-cash',
          'amount': 20000,
          'date': '2026-08-23T08:00:00.000',
          '_idempotencyKey': 'goal-insufficient',
        },
      ),
    );
    expect(result.isSuccess, isFalse);
    expect(await database.select(database.transactions).get(), isEmpty);
    expect(
      (await GetGoal(database)(
        AppContext.householdId,
        'goal-emergency',
      ))!.currentAmount,
      1000000,
    );
  });

  test('setor target menolak target yang hilang atau ambigu', () async {
    final adapters = FfmAssistantCapabilityAdapterRegistry(
      database: database,
      householdId: AppContext.householdId,
      clock: () => now,
    );
    Future<FfmAssistantCapabilityExecutionResult> save(String goal) =>
        adapters.handlers['mutate.save_draft']!(
          FfmAssistantActionStep(
            id: 'save',
            capabilityId: 'mutate.save_draft',
            parameters: {
              'kind': 'goal_deposit',
              'goal': goal,
              'amount': 1000,
              'fromAccount': 'Tunai',
              'date': now.toIso8601String(),
              '_idempotencyKey': 'goal-$goal',
            },
          ),
        );
    expect((await save('Tidak Ada')).isSuccess, isFalse);
    await SaveGoal(database)(
      GoalEntity(
        id: 'goal-emergency-copy',
        householdId: AppContext.householdId,
        name: 'Dana darurat',
        targetAmount: 5000000,
        currentAmount: 0,
        targetDate: DateTime(2026, 12, 31),
        createdAt: now,
      ),
    );
    expect((await save('Dana darurat')).isSuccess, isFalse);
  });

  test('retry identik idempotent dan payload berbeda ditolak', () async {
    await database
        .into(database.accounts)
        .insert(
          AccountsCompanion.insert(
            id: 'goal-cash',
            householdId: AppContext.householdId,
            name: 'Tunai Goal',
            type: 'cash',
            openingBalance: const Value(1000000),
            createdAt: now,
          ),
        );
    final adapters = FfmAssistantCapabilityAdapterRegistry(
      database: database,
      householdId: AppContext.householdId,
      clock: () => now,
    );
    FfmAssistantActionStep step(int amount) => FfmAssistantActionStep(
      id: 'save',
      capabilityId: 'mutate.save_draft',
      parameters: {
        'kind': 'goal_deposit',
        'goalId': 'goal-emergency',
        'goal': 'Dana darurat',
        'accountId': 'goal-cash',
        'amount': amount,
        'date': '2026-08-22T08:00:00.000',
        '_idempotencyKey': 'goal-retry',
      },
    );
    expect(
      (await adapters.handlers['mutate.save_draft']!(step(50000))).isSuccess,
      isTrue,
    );
    expect(
      (await adapters.handlers['mutate.save_draft']!(step(50000))).message,
      contains('alreadyApplied'),
    );
    expect(
      (await adapters.handlers['mutate.save_draft']!(step(60000))).isSuccess,
      isFalse,
    );
    expect(await database.select(database.transactions).get(), hasLength(1));
  });

  test(
    'create goal menyimpan row kanonis dan verifier membaca kembali',
    () async {
      final adapters = FfmAssistantCapabilityAdapterRegistry(
        database: database,
        householdId: AppContext.householdId,
        clock: () => now,
      );
      const key = 'goal-create-acceptance';
      final step = FfmAssistantActionStep(
        id: 'save',
        capabilityId: 'mutate.save_draft',
        parameters: {
          'kind': 'goal',
          'title': 'Renovasi rumah',
          'amount': 12000000,
           'date': '2027-01-15T00:00:00.000',
           'note': 'Renovasi bertahap',
           '_idempotencyKey': key,
        },
      );
      expect(
        (await adapters.handlers['mutate.save_draft']!(step)).isSuccess,
        isTrue,
      );
      final verify = await adapters.handlers['verify.goal_mutation']!(step);
      expect(verify.isSuccess, isTrue);
      final row = await (database.select(
        database.goals,
      )..where((item) => item.name.equals('Renovasi rumah'))).getSingle();
      expect(row.householdId, AppContext.householdId);
      expect(row.targetAmount, 12000000);
      expect(row.targetDate, DateTime(2027, 1, 15));
      expect(row.note, 'Renovasi bertahap');
    },
  );

  test(
    'deposit dan usage menjaga tanggal, akun, progres, serta readback',
    () async {
      await database
          .into(database.accounts)
          .insert(
            AccountsCompanion.insert(
              id: 'goal-wallet',
              householdId: AppContext.householdId,
              name: 'Dompet Goal',
              type: 'cash',
              openingBalance: const Value(1000000),
              createdAt: now,
            ),
          );
      final adapters = FfmAssistantCapabilityAdapterRegistry(
        database: database,
        householdId: AppContext.householdId,
        clock: () => now,
      );

      Future<FfmAssistantCapabilityExecutionResult> save(
        String kind,
        int amount,
        String key,
      ) => adapters.handlers['mutate.save_draft']!(
        FfmAssistantActionStep(
          id: key,
          capabilityId: 'mutate.save_draft',
          parameters: {
            'kind': kind,
            'goalId': 'goal-emergency',
            'goal': 'Dana darurat',
            'accountId': 'goal-wallet',
            'amount': amount,
            'date': '2026-08-22T08:00:00.000',
            '_idempotencyKey': key,
          },
        ),
      );

      expect(
        (await save('goal_deposit', 50000, 'goal-deposit-readback')).isSuccess,
        isTrue,
      );
      expect(
        (await save('goal_usage', 20000, 'goal-usage-readback')).isSuccess,
        isTrue,
      );
      final goal = await GetGoal(database)(
        AppContext.householdId,
        'goal-emergency',
      );
      expect(goal?.currentAmount, 1030000);
      final transactions = await (database.select(
        database.transactions,
      )..where((row) => row.goalId.equals('goal-emergency'))).get();
      expect(transactions, hasLength(2));
      expect(
        transactions.every((row) => row.amount == -row.amount.abs()),
        isTrue,
      );
      expect(
        transactions.every((row) => row.accountId == 'goal-wallet'),
        isTrue,
      );
      expect(
        transactions.every((row) => row.date == DateTime(2026, 8, 22, 8)),
        isTrue,
      );
    },
  );

  test('goal idempotency key lintas household ditolak tanpa write', () async {
    final otherAdapters = FfmAssistantCapabilityAdapterRegistry(
      database: database,
      householdId: 'other-household',
      clock: () => now,
    );
    final first = await otherAdapters.handlers['mutate.save_draft']!(
      const FfmAssistantActionStep(
        id: 'save',
        capabilityId: 'mutate.save_draft',
        parameters: {
          'kind': 'goal',
          'title': 'Target lain',
          'amount': 1000,
          'date': '2026-08-22T00:00:00.000',
          '_idempotencyKey': 'goal-create-acceptance',
        },
      ),
    );
    expect(first.isSuccess, isTrue);
    final result =
        await FfmAssistantCapabilityAdapterRegistry(
          database: database,
          householdId: AppContext.householdId,
          clock: () => now,
        ).handlers['mutate.save_draft']!(
          const FfmAssistantActionStep(
            id: 'save',
            capabilityId: 'mutate.save_draft',
            parameters: {
              'kind': 'goal',
              'title': 'Target lokal',
              'amount': 2000,
              'date': '2026-08-22T00:00:00.000',
              '_idempotencyKey': 'goal-create-acceptance',
            },
          ),
        );
    expect(result.isSuccess, isFalse);
  });
}
