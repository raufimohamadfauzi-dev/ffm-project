import 'package:drift/drift.dart' hide isNotNull, isNull;
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
import 'package:ffm_manager/features/assistant/data/ffm_assistant_proposal_json_service.dart';
import 'package:ffm_manager/features/budget/data/budget_repository.dart';

void main() {
  final now = DateTime(2026, 8, 25, 9);
  late AppDatabase database;
  late BudgetRepository budgets;
  late FfmAssistantInterpreter interpreter;

  setUp(() async {
    database = createInMemoryDatabaseForTests();
    budgets = BudgetRepository(
      database,
      AuditLogger(database),
      clock: () => now,
    );
    interpreter = FfmAssistantInterpreter(database, clock: () => now);
    await database
        .into(database.categories)
        .insert(
          CategoriesCompanion.insert(
            id: 'category-food',
            householdId: AppContext.householdId,
            name: 'Makan',
            type: 'expense',
            createdAt: now,
          ),
        );
    await database
        .into(database.envelopeBudgets)
        .insert(
          EnvelopeBudgetsCompanion.insert(
            id: 'budget-food',
            householdId: AppContext.householdId,
            categoryId: const Value('category-food'),
            categoryIdsJson: const Value('["category-food"]'),
            name: 'Makan',
            month: const Value('2026-08'),
            allocated: const Value(1000000),
            periodType: const Value('monthly'),
            startDate: DateTime(2026, 8, 1),
            endDate: DateTime(2026, 8, 31),
            rollover: const Value(100000),
            createdAt: now,
            updatedAt: Value(now),
          ),
        );
  });

  test(
    'create budget draft menyimpan field canonical dan berhasil diverifikasi',
    () async {
      final adapters = FfmAssistantCapabilityAdapterRegistry(
        database: database,
        householdId: AppContext.householdId,
        clock: () => now,
      );
      const save = FfmAssistantActionStep(
        id: 'save-budget-create',
        capabilityId: 'mutate.save_draft',
        parameters: {
          'kind': 'budget',
          'title': 'Makan Baru',
          'category': 'Makan',
          'amount': 750000,
          'periodType': 'monthly',
          'date': '2026-08-01T00:00:00.000',
          'endDate': '2026-08-31T23:59:59.000',
          'alertPercent': 75,
          'rollover': 125000,
          'note': 'Khusus makan keluarga',
          '_idempotencyKey': 'budget-create-regression',
        },
      );
      const verify = FfmAssistantActionStep(
        id: 'verify-budget-create',
        capabilityId: 'verify.budget_mutation',
        parameters: {
          'kind': 'budget',
          'title': 'Makan Baru',
          'amount': 750000,
          'periodType': 'monthly',
          'date': '2026-08-01T00:00:00.000',
          'endDate': '2026-08-31T23:59:59.000',
          'alertPercent': 75,
          'rollover': 125000,
          'note': 'Khusus makan keluarga',
          '_idempotencyKey': 'budget-create-regression',
        },
      );

      final saved = await adapters.handlers['mutate.save_draft']!(save);
      final verified = await adapters.handlers['verify.budget_mutation']!(
        verify,
      );
      final rows = await database.select(database.envelopeBudgets).get();
      final created = rows.singleWhere((row) => row.name == 'Makan Baru');

      expect(saved.isSuccess, isTrue);
      expect(verified.isSuccess, isTrue);
      expect(created.allocated, 750000);
      expect(created.categoryId, 'category-food');
      expect(created.periodType, 'monthly');
      expect(created.startDate, DateTime(2026, 8, 1));
      expect(created.endDate, DateTime(2026, 8, 31, 23, 59, 59));
      expect(created.alertPercent, 75);
      expect(created.rollover, 125000);
      expect(created.note, 'Khusus makan keluarga');

      final retry = await adapters.handlers['mutate.save_draft']!(save);
      expect(retry.isSuccess, isTrue);
      final changedPayload = FfmAssistantActionStep(
        id: 'save-budget-create-different',
        capabilityId: 'mutate.save_draft',
        parameters: {...save.parameters, 'rollover': 200000},
      );
      final rejected = await adapters.handlers['mutate.save_draft']!(
        changedPayload,
      );
      expect(rejected.isSuccess, isFalse);
    },
  );

  test(
    'snapshot anggaran memakai pemakaian, transfer, status, dan filter',
    () async {
      await database
          .into(database.transactions)
          .insert(
            TransactionsCompanion.insert(
              id: 'food-expense',
              householdId: AppContext.householdId,
              type: 'expense',
              amount: -800000,
              date: now,
              recordedAt: now,
              categoryId: const Value('category-food'),
              createdAt: now,
            ),
          );
      await database
          .into(database.envelopeTransfers)
          .insert(
            EnvelopeTransfersCompanion.insert(
              id: 'food-transfer-out',
              householdId: AppContext.householdId,
              fromEnvelopeId: 'budget-food',
              toEnvelopeId: 'another-budget',
              amount: 100000,
              createdAt: now,
            ),
          );
      await database
          .into(database.envelopeBudgets)
          .insert(
            EnvelopeBudgetsCompanion.insert(
              id: 'future-budget',
              householdId: AppContext.householdId,
              name: 'Masa Depan',
              allocated: const Value(500000),
              periodType: const Value('monthly'),
              startDate: DateTime(2026, 9, 1),
              endDate: DateTime(2026, 9, 30),
              createdAt: now,
            ),
          );

      final snapshots = await budgets.readSnapshots(
        householdId: AppContext.householdId,
        now: now,
        periodType: 'monthly',
        categoryId: 'category-food',
      );

      expect(snapshots, hasLength(1));
      final snapshot = snapshots.single;
      expect(snapshot.spent, 800000);
      expect(snapshot.available, 1000000);
      expect(snapshot.remaining, 200000);
      expect(snapshot.progress, closeTo(.8, 1e-9));
      expect(snapshot.status, 'Mendekati batas');
    },
  );

  test('read.budget menampilkan posisi terkini yang terfilter', () async {
    await database
        .into(database.transactions)
        .insert(
          TransactionsCompanion.insert(
            id: 'food-expense',
            householdId: AppContext.householdId,
            type: 'expense',
            amount: -250000,
            date: now,
            recordedAt: now,
            categoryId: const Value('category-food'),
            createdAt: now,
          ),
        );
    final adapters = FfmAssistantCapabilityAdapterRegistry(
      database: database,
      householdId: AppContext.householdId,
      clock: () => now,
    );

    final result = await adapters.handlers['read.budget']!(
      const FfmAssistantActionStep(
        id: 'read-food-budget',
        capabilityId: 'read.budget',
        parameters: {'period': 'monthly', 'category': 'Makan'},
      ),
    );

    expect(result.isSuccess, isTrue);
    expect(result.message, contains('Makan: batas Rp1.000.000'));
    expect(result.message, contains('pakai Rp250.000'));
    expect(result.message, contains('sisa Rp850.000'));
    expect(result.message, contains('23%, Aman'));
  });

  test('perintah Agent anggaran sesuai kebiasaan memberi proposal batch tanpa mutasi', () async {
    for (final entry in <(String, DateTime, int)>[
      ('habit-june', DateTime(2026, 6, 5), -420000),
      ('habit-july', DateTime(2026, 7, 5), -510000),
    ]) {
      await database
          .into(database.transactions)
          .insert(
            TransactionsCompanion.insert(
              id: entry.$1,
              householdId: AppContext.householdId,
              type: 'expense',
              amount: entry.$3,
              date: entry.$2,
              recordedAt: entry.$2,
              categoryId: const Value('category-food'),
              createdAt: entry.$2,
            ),
          );
    }
    final before = (await (database.select(
      database.envelopeBudgets,
    )..where((row) => row.id.equals('budget-food'))).getSingle()).allocated;

    final intent = await interpreter.interpret(
      'tolong atur anggaran bulanan dan mingguan sesuai kebiasaan saya',
    );

    expect(intent.type, FfmAssistantIntentType.budgetHabitAnalysis);
    expect(intent.destination, FfmAssistantDestination.budget);
    expect(intent.draft, isNull);
    expect(intent.response, contains('proposal 2 pos'));
    expect(intent.response, contains('belum ada anggaran yang dibuat'));
    final plan =
        intent.pluginMetadata?['budgetHabitActionPlan']
            as FfmAssistantActionPlan;
    expect(plan.isComposite, isTrue);
    expect(plan.requiresConfirmation, isTrue);
    expect(
      plan.steps.map((step) => step.capabilityId),
      containsAllInOrder(<String>[
        'read.budget',
        'draft.budget',
        'mutate.save_draft',
        'verify.saved_draft',
        'draft.budget',
        'mutate.save_draft',
        'verify.saved_draft',
      ]),
    );
    expect(plan.steps[1].parameters['periodType'], 'monthly');
    expect(plan.steps[4].parameters['periodType'], 'weekly');
    expect(
      (await (database.select(
        database.envelopeBudgets,
      )..where((row) => row.id.equals('budget-food'))).getSingle()).allocated,
      before,
    );
  });

  test(
    'analisis kebiasaan anggaran tidak menyiapkan proposal atau plan',
    () async {
      for (final entry in <(String, DateTime, int)>[
        ('analysis-june', DateTime(2026, 6, 5), -420000),
        ('analysis-july', DateTime(2026, 7, 5), -510000),
      ]) {
        await database
            .into(database.transactions)
            .insert(
              TransactionsCompanion.insert(
                id: entry.$1,
                householdId: AppContext.householdId,
                type: 'expense',
                amount: entry.$3,
                date: entry.$2,
                recordedAt: entry.$2,
                categoryId: const Value('category-food'),
                createdAt: entry.$2,
              ),
            );
      }

      final intent = await interpreter.interpret(
        'analisis anggaran sesuai kebiasaan saya, jangan ubah',
      );

      expect(intent.type, FfmAssistantIntentType.budgetHabitAnalysis);
      expect(intent.draft, isNull);
      expect(intent.pluginMetadata, isNull);
      expect(intent.response, contains('hanya analisis'));
    },
  );

  test(
    'note Budget mengalir dari JSON ke draft, plan, executor, dan verifier',
    () async {
      final parsed = FfmAssistantProposalJsonService.parse(
        '{"formatVersion":"ffm-assistant-proposal-v1",'
        '"proposal":{"type":"budget","title":"Makan Baru",'
        '"amount":750000,"periodType":"monthly",'
        '"startDate":"2026-08-01T00:00:00.000",'
        '"endDate":"2026-08-31T23:59:59.000",'
        '"categoryIds":["category-food"],"note":"Catatan anggaran"}}',
        createdAt: now,
      );
      expect(parsed.error, isNull);
      final draft = parsed.draft!;
      final plan = const FfmAssistantActionPlanner().planFor(
        FfmAssistantIntent(
          rawText: 'buat anggaran',
          normalizedText: 'buat anggaran',
          type: FfmAssistantIntentType.createBudget,
          draft: draft,
        ),
      )!;
      final save = plan.steps.singleWhere((step) => step.id == 'save');
      expect(save.parameters['note'], 'Catatan anggaran');
    },
  );

  tearDown(() => database.close());

  Future<void> addBudget({
    String id = 'budget-food',
    String name = 'Makan',
    String categoryId = 'category-food',
    String categoryIdsJson = '["category-food"]',
    int allocated = 1000000,
    String periodType = 'monthly',
  }) => database
      .into(database.envelopeBudgets)
      .insert(
        EnvelopeBudgetsCompanion.insert(
          id: id,
          householdId: AppContext.householdId,
          categoryId: Value(categoryId),
          categoryIdsJson: Value(categoryIdsJson),
          name: name,
          month: const Value('2026-08'),
          allocated: Value(allocated),
          periodType: Value(periodType),
          startDate: DateTime(2026, 8, 1),
          endDate: DateTime(2026, 8, 31),
          rollover: const Value(100000),
          createdAt: now,
          updatedAt: Value(now),
        ),
      );

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

  Future<EnvelopeBudget> budget(String id) async =>
      (await budgets.get(AppContext.householdId, id))!;

  Future<void> addExpense({
    String id = 'expense-food',
    String categoryId = 'category-food',
    int amount = -300000,
    bool archived = false,
  }) => database
      .into(database.transactions)
      .insert(
        TransactionsCompanion.insert(
          id: id,
          householdId: AppContext.householdId,
          type: 'expense',
          amount: amount,
          date: now,
          recordedAt: now,
          categoryId: Value(categoryId),
          isArchived: Value(archived),
          createdAt: now,
        ),
      );

  Future<void> addTransfer({
    required String id,
    required String from,
    required String to,
  }) => database
      .into(database.envelopeTransfers)
      .insert(
        EnvelopeTransfersCompanion.insert(
          id: id,
          householdId: AppContext.householdId,
          fromEnvelopeId: from,
          toEnvelopeId: to,
          amount: 100000,
          createdAt: now,
        ),
      );

  test('draft Anggaran hanya membuat preview dan plan allowlisted', () async {
    final before = await budget('budget-food');
    final intent = await interpreter.interpret(
      'ubah batas anggaran makan jadi 800 ribu',
    );

    expect(intent.type, FfmAssistantIntentType.updateBudget);
    expect(intent.draft?.kind, FfmAssistantDraftKind.budgetUpdate);
    expect((await budget('budget-food')).allocated, before.allocated);
    final plan = FfmAssistantActionPlanner(now: () => now).planFor(intent)!;
    expect(
      plan.steps.map((step) => step.capabilityId),
      containsAll(<String>[
        'draft.budget_update',
        'mutate.update',
        'verify.budget_mutation',
      ]),
    );
  });

  test('update batas menjaga field terlindungi dan menghitung sisa', () async {
    await addExpense();
    final before = await budget('budget-food');
    final intent = await interpreter.interpret(
      'ubah batas anggaran makan jadi 800 ribu',
    );
    expect(
      (await execute(
        FfmAssistantActionPlanner(now: () => now).planFor(intent)!,
      ))?.status,
      FfmAssistantActionPlanStatus.completed,
    );
    final after = await budget('budget-food');
    final snapshot = await budgets.snapshot(
      householdId: AppContext.householdId,
      id: after.id,
    );
    expect(after.allocated, 800000);
    expect(after.id, before.id);
    expect(after.name, before.name);
    expect(after.categoryId, before.categoryId);
    expect(after.categoryIdsJson, before.categoryIdsJson);
    expect(after.periodType, before.periodType);
    expect(after.startDate, before.startDate);
    expect(after.endDate, before.endDate);
    expect(after.rollover, before.rollover);
    expect(after.alertPercent, before.alertPercent);
    expect(after.isActive, isTrue);
    expect(snapshot?.remaining, 600000);
  });

  test('update batas ditolak bila sisa pascaubah menjadi negatif', () async {
    await addExpense(amount: -950000);
    final intent = await interpreter.interpret(
      'ubah batas anggaran makan jadi 800 ribu',
    );
    final plan = FfmAssistantActionPlanner(now: () => now).planFor(intent)!;
    expect((await execute(plan))?.status, FfmAssistantActionPlanStatus.failed);
    expect((await budget('budget-food')).allocated, 1000000);
  });

  test(
    'target Anggaran ambigu atau terlalu pendek tidak memilih pos',
    () async {
      await addBudget(id: 'budget-food-extra', name: 'Makan Rumah');
      final ambiguous = await interpreter.interpret('arsipkan anggaran makan');
      final short = await interpreter.interpret('arsipkan anggaran ma');
      expect(ambiguous.clarification, isNotNull);
      expect(short.clarification, isNotNull);
      expect((await budget('budget-food')).isActive, isTrue);
    },
  );

  test(
    'arsip Anggaran ditolak untuk transfer dan transaksi historis',
    () async {
      await addTransfer(id: 'transfer-out', from: 'budget-food', to: 'other');
      expect(
        await budgets.archiveBlockReason(
          householdId: AppContext.householdId,
          id: 'budget-food',
        ),
        contains('transfer'),
      );
      var intent = await interpreter.interpret('arsipkan anggaran makan');
      expect(
        (await execute(
          FfmAssistantActionPlanner(now: () => now).planFor(intent)!,
        ))?.status,
        FfmAssistantActionPlanStatus.failed,
      );

      await database.delete(database.envelopeTransfers).go();
      await addExpense(archived: true);
      intent = await interpreter.interpret('arsipkan anggaran makan');
      expect(
        (await execute(
          FfmAssistantActionPlanner(now: () => now).planFor(intent)!,
        ))?.status,
        FfmAssistantActionPlanStatus.failed,
      );
      expect((await budget('budget-food')).isActive, isTrue);
    },
  );

  test('arsip Anggaran tanpa jejak bersifat lunak, diaudit, dan tanpa catatan baru', () async {
    final transactionsBefore = await database
        .select(database.transactions)
        .get();
    final transfersBefore = await database
        .select(database.envelopeTransfers)
        .get();
    final intent = await interpreter.interpret('arsipkan anggaran makan');
    expect(
      (await execute(
        FfmAssistantActionPlanner(now: () => now).planFor(intent)!,
      ))?.status,
      FfmAssistantActionPlanStatus.completed,
    );
    final archived = await budget('budget-food');
    expect(archived.isActive, isFalse);
    expect(archived.allocated, 1000000);
    expect(archived.rollover, 100000);
    expect(
      (await database.select(database.transactions).get()).length,
      transactionsBefore.length,
    );
    expect(
      (await database.select(database.envelopeTransfers).get()).length,
      transfersBefore.length,
    );
    final audits = await database
        .customSelect(
          'SELECT action FROM audit_logs WHERE entity = ?',
          variables: [Variable<String>('budget')],
        )
        .get();
    expect(
      audits.map((row) => row.read<String>('action')),
      contains('archive'),
    );
  });
}
