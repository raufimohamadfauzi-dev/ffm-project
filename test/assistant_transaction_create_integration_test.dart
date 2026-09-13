import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_capability_adapters.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_plan.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_planner.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_capability_executor.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/transaction/data/services/receipt_import_models.dart';

void main() {
  const householdId = 'local-household';
  final now = DateTime(2026, 8, 24, 9);
  late AppDatabase database;

  setUp(() async {
    database = createInMemoryDatabaseForTests();
    await database
        .into(database.accounts)
        .insert(
          AccountsCompanion.insert(
            id: 'cash',
            householdId: householdId,
            name: 'Kas',
            type: 'cash',
            openingBalance: const Value(1000000),
            createdAt: now,
          ),
        );
    await database
        .into(database.accounts)
        .insert(
          AccountsCompanion.insert(
            id: 'bank',
            householdId: householdId,
            name: 'Bank',
            type: 'bank',
            openingBalance: const Value(100000),
            createdAt: now,
          ),
        );
    await database
        .into(database.categories)
        .insert(
          CategoriesCompanion.insert(
            id: 'salary',
            householdId: householdId,
            name: 'Gaji Kantor',
            type: 'income',
            createdAt: now,
          ),
        );
    await database
        .into(database.merchants)
        .insert(
          MerchantsCompanion.insert(
            id: 'market',
            householdId: householdId,
            name: 'Pasar Induk',
            createdAt: now,
          ),
        );
    await database
        .into(database.tags)
        .insert(
          TagsCompanion.insert(
            id: 'household',
            householdId: householdId,
            name: 'Rumah Tangga',
            createdAt: now,
          ),
        );
    await database
        .into(database.categories)
        .insert(
          CategoriesCompanion.insert(
            id: 'food',
            householdId: householdId,
            name: 'Makan',
            type: 'expense',
            createdAt: now,
          ),
        );
  });

  tearDown(() => database.close());

  Future<FfmAssistantActionPlan?> execute(FfmAssistantDraft draft) async {
    final intent = FfmAssistantIntent(
      rawText: 'buat transaksi',
      normalizedText: 'buat transaksi',
      type: switch (draft.kind) {
        FfmAssistantDraftKind.income => FfmAssistantIntentType.createIncome,
        FfmAssistantDraftKind.expense => FfmAssistantIntentType.createExpense,
        FfmAssistantDraftKind.transfer => FfmAssistantIntentType.createTransfer,
        _ => FfmAssistantIntentType.unknown,
      },
      destination: FfmAssistantDestination.transactions,
      draft: draft,
    );
    final plan = FfmAssistantActionPlanner(now: () => now).planFor(intent)!;
    final controller = FfmAssistantActionPlanController(now: () => now)
      ..register(plan)
      ..markAwaitingConfirmation(plan.id)
      ..confirm(plan.id);
    final registry = FfmAssistantCapabilityAdapterRegistry(
      database: database,
      householdId: householdId,
      clock: () => now,
    );
    return FfmAssistantCapabilityExecutor(
      controller: controller,
      handlers: registry.handlers,
    ).execute(plan.id);
  }

  test(
    'create income menyimpan field canonical dan verifier readback',
    () async {
      final completed = await execute(
        FfmAssistantDraft(
          kind: FfmAssistantDraftKind.income,
          createdAt: now,
          amount: 5000000,
          toAccountName: 'Kas',
          categoryName: 'Gaji Kantor',
          partyName: 'Kantor',
          location: 'Jakarta',
          date: now.subtract(const Duration(days: 1)),
          source: 'payroll',
          sourceId: 'p-1',
          recurringTransactionId: 'salary-rule',
          linkedActivityId: 'work-session',
          note: 'Gaji Agustus',
        ),
      );

      expect(completed?.status, FfmAssistantActionPlanStatus.completed);
      final row = (await database.select(database.transactions).get());
      expect(row.single.amount, 5000000);
      expect(row.single.type, 'income');
      expect(row.single.source, 'payroll');
      expect(row.single.sourceId, 'p-1');
      expect(row.single.recurringTransactionId, 'salary-rule');
      expect(row.single.linkedActivityId, 'work-session');
      expect(row.single.accountId, 'cash');
      expect(row.single.categoryId, 'salary');
      expect(row.single.partyName, 'Kantor');
      expect(row.single.location, 'Jakarta');
      expect(row.single.note, 'Gaji Agustus');
      expect(row.single.date, now.subtract(const Duration(days: 1)));
    },
  );

  test('create simple expense menyimpan kategori dan tag', () async {
    final completed = await execute(
      FfmAssistantDraft(
        kind: FfmAssistantDraftKind.expense,
        createdAt: now,
        amount: 25000,
        fromAccountName: 'Kas',
        categoryName: 'Makan',
        merchantName: 'Pasar Induk',
        tags: 'Rumah Tangga',
      ),
    );

    expect(completed?.status, FfmAssistantActionPlanStatus.completed);
    expect(
      (await database.select(database.transactions).get()).single.amount,
      -25000,
    );
    expect((await database.select(database.transactionTags).get()).length, 1);
    final row = (await database.select(database.transactions).get()).single;
    expect(row.accountId, 'cash');
    expect(row.categoryId, 'food');
    expect(row.merchantId, 'market');
  });

  test(
    'create complex expense memvalidasi receipt, item, dan attachment',
    () async {
      final completed = await execute(
        FfmAssistantDraft(
          kind: FfmAssistantDraftKind.expense,
          createdAt: now,
          amount: 107500,
          fromAccountName: 'Kas',
          categoryName: 'Makan',
          merchantName: 'Pasar Induk',
          tags: 'Rumah Tangga, Nota',
          newTags: 'Nota',
          items: const [
            ReceiptOcrItem(name: 'Belanja', price: 100000, quantity: 1),
          ],
          tax: 10000,
          discount: 2500,
          receiptPaidAmount: 110000,
          receiptChangeAmount: 2500,
          receiptNumber: 'N-1',
          receiptRawText: 'BELANJA 100000 PAJAK 10000 DISKON 2500',
          attachmentPaths: ['/receipt/n-1.jpg'],
        ),
      );

      expect(completed?.status, FfmAssistantActionPlanStatus.completed);
      expect(
        (await database.select(database.transactionItems).get()).single.amount,
        100000,
      );
      expect(
        (await database.select(database.attachments).get()).single.path,
        '/receipt/n-1.jpg',
      );
      expect(
        (await database.select(database.transactions).get())
            .single
            .receiptPaidAmount,
        110000,
      );
      final transaction =
          (await database.select(database.transactions).get()).single;
      expect(transaction.receiptChangeAmount, 2500);
      expect(transaction.tax, 10000);
      expect(transaction.discount, 2500);
      expect(transaction.receiptNumber, 'N-1');
      expect(transaction.receiptRawText, contains('PAJAK'));
      expect(
        await database.select(database.transactionTags).get(),
        hasLength(2),
      );
    },
  );

  test(
    'create transfer menyimpan tanggal, fee, dan retry idempotent',
    () async {
      final draft = FfmAssistantDraft(
        kind: FfmAssistantDraftKind.transfer,
        createdAt: now,
        amount: 300000,
        adminFee: 5000,
        fromAccountName: 'Kas',
        toAccountName: 'Bank',
        date: now.subtract(const Duration(days: 2)),
        note: 'Setor bank',
        source: 'assistant_test',
      );
      final first = await execute(draft);
      final second = await execute(draft);

      expect(first?.status, FfmAssistantActionPlanStatus.completed);
      expect(second?.status, FfmAssistantActionPlanStatus.completed);
      expect((await database.select(database.transfers).get()).length, 1);
      final transfer = (await database.select(database.transfers).get()).single;
      expect(transfer.amount, 300000);
      expect(transfer.adminFee, 5000);
      expect(transfer.fromAccountId, 'cash');
      expect(transfer.toAccountId, 'bank');
      expect(transfer.source, 'assistant_test');
      expect(transfer.note, 'Setor bank');
      expect(transfer.date, now.subtract(const Duration(days: 2)));
      final fee = (await database.select(database.transactions).get()).single;
      expect(fee.id, transfer.feeTransactionId);
      expect(fee.amount, -5000);
      expect(fee.accountId, 'cash');
      final feeCategory = await (database.select(
        database.categories,
      )..where((category) => category.id.equals(fee.categoryId!))).getSingle();
      expect(feeCategory.name, 'Biaya admin');
      expect(fee.source, 'transfer_fee');
      expect(fee.date, transfer.date);

      final registry = FfmAssistantCapabilityAdapterRegistry(
        database: database,
        householdId: householdId,
        clock: () => now,
      );
      final mutationStep = first!.steps.firstWhere(
        (step) => step.capabilityId == 'mutate.save_draft',
      );
      final conflict = await registry.handlers['mutate.save_draft']!(
        FfmAssistantActionStep(
          id: 'transfer-conflict',
          capabilityId: 'mutate.save_draft',
          parameters: {...mutationStep.parameters, 'note': 'Payload berbeda'},
        ),
      );
      expect(conflict.isSuccess, isFalse);
      expect(conflict.message, contains('isi berbeda'));
      expect(await database.select(database.transfers).get(), hasLength(1));

      await (database.update(database.transactions)
            ..where((row) => row.id.equals(fee.id)))
          .write(const TransactionsCompanion(amount: Value(-4000)));
      final verifyStep = first.steps.firstWhere(
        (step) => step.capabilityId == 'verify.saved_draft',
      );
      final verification = await registry.handlers['verify.saved_draft']!(
        verifyStep,
      );
      expect(verification.isSuccess, isFalse);
    },
  );

  test('item invalid ditolak seluruhnya tanpa write parsial', () async {
    final registry = FfmAssistantCapabilityAdapterRegistry(
      database: database,
      householdId: householdId,
      clock: () => now,
    );
    final result = await registry.handlers['mutate.save_draft']!(
      const FfmAssistantActionStep(
        id: 'invalid-item',
        capabilityId: 'mutate.save_draft',
        parameters: {
          'kind': 'expense',
          'amount': 10000,
          'fromAccount': 'Kas',
          'itemsJson': '[{"name":"Valid","price":10000,"qty":1},{"name":"","price":0,"qty":1}]',
          '_idempotencyKey': 'invalid-item-key',
        },
      ),
    );

    expect(result.isSuccess, isFalse);
    expect(await database.select(database.transactions).get(), isEmpty);
    expect(await database.select(database.transactionItems).get(), isEmpty);
  });

  test('idempotency menolak payload berbeda dengan key sama', () async {
    final registry = FfmAssistantCapabilityAdapterRegistry(
      database: database,
      householdId: householdId,
      clock: () => now,
    );
    const base = {
      'kind': 'expense',
      'amount': 10000,
      'fromAccount': 'Kas',
      'category': 'Makan',
      'note': 'Kopi',
      '_idempotencyKey': 'same-key',
    };
    final first = await registry.handlers['mutate.save_draft']!(
      const FfmAssistantActionStep(
        id: 'first',
        capabilityId: 'mutate.save_draft',
        parameters: base,
      ),
    );
    final retry = await registry.handlers['mutate.save_draft']!(
      const FfmAssistantActionStep(
        id: 'retry',
        capabilityId: 'mutate.save_draft',
        parameters: base,
      ),
    );
    final conflict = await registry.handlers['mutate.save_draft']!(
      const FfmAssistantActionStep(
        id: 'conflict',
        capabilityId: 'mutate.save_draft',
        parameters: {
          'kind': 'expense',
          'amount': 10000,
          'fromAccount': 'Kas',
          'category': 'Makan',
          'note': 'Teh',
          '_idempotencyKey': 'same-key',
        },
      ),
    );

    expect(first.isSuccess, isTrue);
    expect(retry.isSuccess, isTrue);
    expect(retry.message, contains('alreadyApplied'));
    expect(conflict.isSuccess, isFalse);
    expect(conflict.message, contains('isi berbeda'));
    expect(await database.select(database.transactions).get(), hasLength(1));
  });

  test(
    'transfer menolak rekening sama dan saldo kurang termasuk fee',
    () async {
      final registry = FfmAssistantCapabilityAdapterRegistry(
        database: database,
        householdId: householdId,
        clock: () => now,
      );
      final sameAccount = await registry.handlers['mutate.save_draft']!(
        const FfmAssistantActionStep(
          id: 'same-account',
          capabilityId: 'mutate.save_draft',
          parameters: {
            'kind': 'transfer',
            'amount': 10000,
            'fromAccount': 'Kas',
            'toAccount': 'Kas',
            '_idempotencyKey': 'same-account',
          },
        ),
      );
      final insufficient = await registry.handlers['mutate.save_draft']!(
        const FfmAssistantActionStep(
          id: 'insufficient',
          capabilityId: 'mutate.save_draft',
          parameters: {
            'kind': 'transfer',
            'amount': 99000,
            'adminFee': 2000,
            'fromAccount': 'Bank',
            'toAccount': 'Kas',
            '_idempotencyKey': 'insufficient',
          },
        ),
      );

      expect(sameAccount.isSuccess, isFalse);
      expect(insufficient.isSuccess, isFalse);
      expect(insufficient.message, contains('Saldo'));
      expect(await database.select(database.transfers).get(), isEmpty);
    },
  );
}
