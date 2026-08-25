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
import 'package:ffm_manager/features/settings/data/category_repository.dart';

void main() {
  final now = DateTime(2026, 8, 25);
  late AppDatabase database;
  late CategoryRepository categories;
  late FfmAssistantInterpreter interpreter;

  setUp(() async {
    database = createInMemoryDatabaseForTests();
    categories = CategoryRepository(
      database,
      AuditLogger(database),
      clock: () => now,
    );
    interpreter = FfmAssistantInterpreter(database, clock: () => now);
    await categories.create(
      id: 'cat-makan',
      householdId: AppContext.householdId,
      name: 'Makan Harian',
      type: 'expense',
      defaultBudgetPeriod: 'monthly',
    );
    await database
        .into(database.transactions)
        .insert(
          TransactionsCompanion.insert(
            id: 'historic-expense',
            householdId: AppContext.householdId,
            type: 'expense',
            amount: 25000,
            date: now,
            recordedAt: now,
            categoryId: const Value('cat-makan'),
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

  Future<String?> historicCategoryId() async =>
      (await database.select(database.transactions).getSingle()).categoryId;

  Future<Category> targetCategory() async =>
      (await categories.get(AppContext.householdId, 'cat-makan'))!;

  test('draft Kategori tidak menulis nama atau relasi transaksi', () async {
    final intent = await interpreter.interpret(
      'ubah kategori makan harian jadi Konsumsi Harian',
    );
    expect(intent.type, FfmAssistantIntentType.updateCategory);
    expect(intent.draft?.kind, FfmAssistantDraftKind.categoryUpdate);
    expect((await targetCategory()).name, 'Makan Harian');
    expect(await historicCategoryId(), 'cat-makan');

    final plan = FfmAssistantActionPlanner(now: () => now).planFor(intent)!;
    expect(
      plan.steps.map((step) => step.capabilityId),
      containsAll(<String>[
        'draft.category_update',
        'mutate.update',
        'verify.category_mutation',
      ]),
    );
  });

  test(
    'update nama menjaga type, parent, periode, dan kategori historis',
    () async {
      final intent = await interpreter.interpret(
        'ubah kategori makan harian jadi Konsumsi Harian',
      );
      expect(
        (await execute(
          FfmAssistantActionPlanner(now: () => now).planFor(intent)!,
        ))?.status,
        FfmAssistantActionPlanStatus.completed,
      );
      final changed = await targetCategory();
      expect(changed.id, 'cat-makan');
      expect(changed.name, 'konsumsi harian');
      expect(changed.type, 'expense');
      expect(changed.parentId, isNull);
      expect(changed.defaultBudgetPeriod, 'monthly');
      expect(await historicCategoryId(), 'cat-makan');
    },
  );

  test(
    'target kategori ambigu hanya meminta klarifikasi tanpa write',
    () async {
      await categories.create(
        id: 'cat-makan-luar',
        householdId: AppContext.householdId,
        name: 'Makan Luar',
        type: 'expense',
        defaultBudgetPeriod: 'monthly',
      );
      final intent = await interpreter.interpret('arsipkan kategori makan');
      expect(intent.type, FfmAssistantIntentType.archiveCategory);
      expect(intent.clarification, isNotNull);
      final scenarioCategories = (await categories.readActive(
        AppContext.householdId,
      )).where((row) => row.id.startsWith('cat-makan')).toList();
      expect(scenarioCategories, hasLength(2));
      expect(await historicCategoryId(), 'cat-makan');
    },
  );

  test(
    'arsip Agent ditolak ketika kategori masih menjadi induk aktif',
    () async {
      await categories.create(
        id: 'cat-makan-jajan',
        householdId: AppContext.householdId,
        name: 'Jajan',
        type: 'expense',
        parentId: 'cat-makan',
        defaultBudgetPeriod: 'monthly',
      );
      final intent = await interpreter.interpret(
        'arsipkan kategori makan harian',
      );
      final plan = FfmAssistantActionPlanner(now: () => now).planFor(intent)!;
      expect(
        (await execute(plan))?.status,
        FfmAssistantActionPlanStatus.failed,
      );
      expect(
        (await categories.get(AppContext.householdId, 'cat-makan'))?.isActive,
        isTrue,
      );
      expect(await historicCategoryId(), 'cat-makan');
    },
  );

  test(
    'guard arsip mendeteksi transaksi berkala, target, dan anggaran aktif',
    () async {
      await database
          .into(database.recurringTransactions)
          .insert(
            RecurringTransactionsCompanion.insert(
              id: 'rec-makan',
              householdId: AppContext.householdId,
              name: 'Belanja Mingguan',
              type: 'expense',
              amount: 100000,
              categoryId: const Value('cat-makan'),
              startDate: now,
              createdAt: now,
            ),
          );
      expect(
        await categories.archiveBlockReason(
          householdId: AppContext.householdId,
          id: 'cat-makan',
        ),
        contains('transaksi berkala aktif'),
      );
      await (database.delete(
        database.recurringTransactions,
      )..where((row) => row.id.equals('rec-makan'))).go();

      await database
          .into(database.goals)
          .insert(
            GoalsCompanion.insert(
              id: 'goal-makan',
              householdId: AppContext.householdId,
              name: 'Dana Makan',
              targetAmount: 1000000,
              categoryId: const Value('cat-makan'),
              createdAt: now,
            ),
          );
      expect(
        await categories.archiveBlockReason(
          householdId: AppContext.householdId,
          id: 'cat-makan',
        ),
        contains('Target Keuangan aktif'),
      );
      await (database.delete(
        database.goals,
      )..where((row) => row.id.equals('goal-makan'))).go();

      await database
          .into(database.envelopeBudgets)
          .insert(
            EnvelopeBudgetsCompanion.insert(
              id: 'budget-makan',
              householdId: AppContext.householdId,
              name: 'Amplop Makan',
              categoryIdsJson: const Value('["cat-makan"]'),
              startDate: now,
              endDate: now.add(const Duration(days: 30)),
              createdAt: now,
            ),
          );
      expect(
        await categories.archiveBlockReason(
          householdId: AppContext.householdId,
          id: 'cat-makan',
        ),
        contains('Anggaran aktif'),
      );
    },
  );

  test('arsip tanpa dependensi aktif bersifat lunak dan diaudit', () async {
    await (database.delete(
      database.transactions,
    )..where((row) => row.id.equals('historic-expense'))).go();
    final intent = await interpreter.interpret(
      'arsipkan kategori makan harian',
    );
    final plan = FfmAssistantActionPlanner(now: () => now).planFor(intent)!;
    expect(
      (await execute(plan))?.status,
      FfmAssistantActionPlanStatus.completed,
    );
    final archived = await categories.get(AppContext.householdId, 'cat-makan');
    expect(archived?.isActive, isFalse);
    expect(archived?.type, 'expense');
    expect(archived?.defaultBudgetPeriod, 'monthly');
    final audits = await database
        .customSelect(
          'SELECT action FROM audit_logs WHERE entity = ?',
          variables: [Variable<String>('category')],
        )
        .get();
    expect(
      audits.map((row) => row.read<String>('action')),
      contains('archive'),
    );
  });
}
