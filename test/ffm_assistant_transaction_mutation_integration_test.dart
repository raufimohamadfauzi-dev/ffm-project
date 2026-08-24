import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_capability_adapters.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_plan.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_planner.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_capability_executor.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/transaction/domain/usecases/transaction_crud_usecases.dart';

void main() {
  const householdId = 'local-household';
  final now = DateTime(2026, 8, 24, 9);
  late AppDatabase database;

  setUp(() async {
    database = createInMemoryDatabaseForTests();
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> seedTransaction({
    required String id,
    required int amount,
    String? note,
  }) => SaveTransaction(database)(
    TransactionEntity(
      id: id,
      householdId: householdId,
      date: now,
      amount: amount,
      owner: 'Keluarga',
      categoryId: null,
      note: note,
      recordedAt: now,
      updatedAt: now,
    ),
  );

  FfmAssistantIntent mutationIntent({
    required FfmAssistantDraftKind kind,
    required FfmAssistantIntentType type,
    required String targetId,
    int? amount,
  }) {
    final operation = switch (kind) {
      FfmAssistantDraftKind.transactionUpdate => 'update',
      FfmAssistantDraftKind.transactionArchive => 'archive',
      FfmAssistantDraftKind.transactionDelete => 'delete',
      _ => throw ArgumentError.value(kind, 'kind'),
    };
    return FfmAssistantIntent(
      rawText: '$operation transaksi',
      normalizedText: '$operation transaksi',
      type: type,
      destination: FfmAssistantDestination.transactions,
      draft: FfmAssistantDraft(
        kind: kind,
        createdAt: now,
        amount: amount,
        formValues: {'targetId': targetId, 'operation': operation},
      ),
    );
  }

  Future<FfmAssistantActionPlan?> executeConfirmed(
    FfmAssistantActionPlan plan,
  ) async {
    final controller = FfmAssistantActionPlanController(now: () => now)
      ..register(plan)
      ..markAwaitingConfirmation(plan.id)
      ..confirm(plan.id);
    final adapters = FfmAssistantCapabilityAdapterRegistry(
      database: database,
      householdId: householdId,
      clock: () => now,
    );
    return FfmAssistantCapabilityExecutor(
      controller: controller,
      handlers: adapters.handlers,
    ).execute(plan.id);
  }

  test('mutation transaksi diblokir bila belum dikonfirmasi', () async {
    await seedTransaction(id: 'coffee', amount: -15000, note: 'kopi');
    final plan = FfmAssistantActionPlanner(now: () => now).planFor(
      mutationIntent(
        kind: FfmAssistantDraftKind.transactionUpdate,
        type: FfmAssistantIntentType.updateTransaction,
        targetId: 'coffee',
        amount: 25000,
      ),
    )!;
    final controller = FfmAssistantActionPlanController(now: () => now)
      ..register(plan);
    final adapters = FfmAssistantCapabilityAdapterRegistry(
      database: database,
      householdId: householdId,
      clock: () => now,
    );
    final blocked = await FfmAssistantCapabilityExecutor(
      controller: controller,
      handlers: adapters.handlers,
    ).execute(plan.id);

    expect(blocked?.status, FfmAssistantActionPlanStatus.blocked);
    final row = await GetTransaction(database)(householdId, 'coffee');
    expect(row?.transaction.amount, -15000);
  });

  test(
    'update transaksi melewati preview, confirmation, verify, dan audit',
    () async {
      await seedTransaction(id: 'coffee', amount: -15000, note: 'kopi');
      final plan = FfmAssistantActionPlanner(now: () => now).planFor(
        mutationIntent(
          kind: FfmAssistantDraftKind.transactionUpdate,
          type: FfmAssistantIntentType.updateTransaction,
          targetId: 'coffee',
          amount: 25000,
        ),
      )!;
      final completed = await executeConfirmed(plan);

      expect(completed?.status, FfmAssistantActionPlanStatus.completed);
      expect(
      completed?.steps.map((step) => step.capabilityId),
      equals([
        'navigate.transactions',
        'draft.transaction_update',
        'mutate.update',
        'verify.transaction_mutation',
        ]),
      );
      final row = await GetTransaction(database)(householdId, 'coffee');
      expect(row?.transaction.amount, -25000);
      final logs = await database
          .customSelect('SELECT action, entity FROM audit_logs')
          .get();
      expect(logs.single.read<String>('action'), 'ubah');
      expect(logs.single.read<String>('entity'), 'transaksi');
    },
  );

  test(
    'archive transaksi mengubah state arsip dan dapat diverifikasi',
    () async {
      await seedTransaction(id: 'market', amount: -35000, note: 'pasar');
      final plan = FfmAssistantActionPlanner(now: () => now).planFor(
        mutationIntent(
          kind: FfmAssistantDraftKind.transactionArchive,
          type: FfmAssistantIntentType.archiveTransaction,
          targetId: 'market',
        ),
      )!;
      final completed = await executeConfirmed(plan);

      expect(completed?.status, FfmAssistantActionPlanStatus.completed);
      final row = await GetTransaction(database)(householdId, 'market');
      expect(row?.transaction.isArchived, isTrue);
      expect(row?.transaction.isDeleted, isFalse);
    },
  );

  test(
    'delete transaksi menghilangkan dari daftar aktif tanpa physical delete',
    () async {
      await seedTransaction(id: 'snack', amount: -12000, note: 'jajan');
      final plan = FfmAssistantActionPlanner(now: () => now).planFor(
        mutationIntent(
          kind: FfmAssistantDraftKind.transactionDelete,
          type: FfmAssistantIntentType.deleteTransaction,
          targetId: 'snack',
        ),
      )!;
      final completed = await executeConfirmed(plan);

      expect(completed?.status, FfmAssistantActionPlanStatus.completed);
      final row = await GetTransaction(database)(householdId, 'snack');
      expect(row?.transaction.isArchived, isTrue);
      expect(row?.transaction.isDeleted, isTrue);
      final active = await GetTransactions(database)(householdId);
      expect(active, isEmpty);
    },
  );
}
