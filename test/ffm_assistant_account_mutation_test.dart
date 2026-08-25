import 'package:drift/drift.dart' hide isNotNull;
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
import 'package:ffm_manager/features/recurring_transaction/domain/usecases/recurring_transaction_crud_usecases.dart';
import 'package:ffm_manager/features/settings/data/account_repository.dart';

void main() {
  final now = DateTime(2026, 8, 25, 9);
  late AppDatabase database;
  late AccountRepository accounts;
  late FfmAssistantInterpreter interpreter;

  setUp(() async {
    database = createInMemoryDatabaseForTests();
    accounts = AccountRepository(
      database,
      AuditLogger(database),
      clock: () => now,
    );
    interpreter = FfmAssistantInterpreter(database, clock: () => now);
    await accounts.create(
      id: 'account-bank-utama',
      householdId: AppContext.householdId,
      name: 'Bank Utama',
      type: 'bank',
      openingBalance: 100000,
    );
    await accounts.create(
      id: 'account-bank-tujuan',
      householdId: AppContext.householdId,
      name: 'Bank Tujuan',
      type: 'bank',
      openingBalance: 20000,
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

  Future<Account> account(String id) async =>
      (await accounts.get(AppContext.householdId, id))!;

  Future<void> insertTransactionReference(String accountId) => database
      .into(database.transactions)
      .insert(
        TransactionsCompanion.insert(
          id: 'transaction-$accountId',
          householdId: AppContext.householdId,
          type: 'income',
          amount: 25000,
          date: now,
          recordedAt: now,
          accountId: Value(accountId),
          createdAt: now,
        ),
      );

  Future<void> insertTransferReference({
    required String fromAccountId,
    required String toAccountId,
    required String id,
  }) => database
      .into(database.transfers)
      .insert(
        TransfersCompanion.insert(
          id: id,
          householdId: AppContext.householdId,
          fromAccountId: fromAccountId,
          toAccountId: toAccountId,
          amount: 10000,
          date: now,
          recordedAt: now,
        ),
      );

  Future<void> expectArchiveRejected(String id, String command) async {
    final intent = await interpreter.interpret(command);
    final plan = FfmAssistantActionPlanner(now: () => now).planFor(intent)!;
    expect((await execute(plan))?.status, FfmAssistantActionPlanStatus.failed);
    expect((await account(id)).isArchived, isFalse);
  }

  test(
    'draft Rekening tidak menulis saldo, nama, atau referensi finansial',
    () async {
      await insertTransactionReference('account-bank-utama');
      final before = await account('account-bank-utama');
      final transactionCount = await database
          .select(database.transactions)
          .get()
          .then((rows) => rows.length);

      final intent = await interpreter.interpret(
        'ubah rekening bank utama jadi Dana Harian',
      );

      expect(intent.type, FfmAssistantIntentType.updateAccount);
      expect(intent.draft?.kind, FfmAssistantDraftKind.accountUpdate);
      expect((await account('account-bank-utama')).name, before.name);
      expect((await account('account-bank-utama')).openingBalance, 100000);
      expect(
        await database
            .select(database.transactions)
            .get()
            .then((rows) => rows.length),
        transactionCount,
      );

      final plan = FfmAssistantActionPlanner(now: () => now).planFor(intent)!;
      expect(
        plan.steps.map((step) => step.capabilityId),
        containsAll(<String>[
          'draft.account_update',
          'mutate.update',
          'verify.account_mutation',
        ]),
      );
    },
  );

  test('update nama menjaga saldo buku dan semua field serta referensi terlindungi', () async {
    await insertTransactionReference('account-bank-utama');
    await insertTransferReference(
      id: 'transfer-out',
      fromAccountId: 'account-bank-utama',
      toAccountId: 'account-bank-tujuan',
    );
    final before = await account('account-bank-utama');
    final balanceBefore = await GetAccountBookBalance(database)(
      AppContext.householdId,
      before.id,
      asOf: now,
    );
    final intent = await interpreter.interpret(
      'ubah rekening bank utama jadi Dana Harian',
    );

    expect(
      (await execute(
        FfmAssistantActionPlanner(now: () => now).planFor(intent)!,
      ))?.status,
      FfmAssistantActionPlanStatus.completed,
    );

    final changed = await account('account-bank-utama');
    expect(changed.id, before.id);
    expect(changed.name, 'dana harian');
    expect(changed.type, before.type);
    expect(changed.openingBalance, before.openingBalance);
    expect(changed.isActive, before.isActive);
    expect(changed.isArchived, before.isArchived);
    expect(changed.createdAt, before.createdAt);
    expect(
      await GetAccountBookBalance(database)(
        AppContext.householdId,
        changed.id,
        asOf: now,
      ),
      balanceBefore,
    );
    expect(
      (await database.select(database.transactions).getSingle()).accountId,
      'account-bank-utama',
    );
    expect(
      (await database.select(database.transfers).getSingle()).fromAccountId,
      'account-bank-utama',
    );
  });

  test(
    'target Rekening ambigu hanya meminta klarifikasi tanpa write',
    () async {
      await accounts.create(
        id: 'account-bank-cadangan',
        householdId: AppContext.householdId,
        name: 'Bank Cadangan',
        type: 'bank',
        openingBalance: 0,
      );
      final intent = await interpreter.interpret('arsipkan rekening bank');
      expect(intent.type, FfmAssistantIntentType.archiveAccount);
      expect(intent.clarification, isNotNull);
      expect((await account('account-bank-utama')).isArchived, isFalse);
      expect((await account('account-bank-cadangan')).isArchived, isFalse);
    },
  );

  test(
    'target Rekening terlalu pendek meminta klarifikasi tanpa write',
    () async {
      final intent = await interpreter.interpret('arsipkan rekening ba');
      expect(intent.type, FfmAssistantIntentType.archiveAccount);
      expect(intent.clarification, isNotNull);
      expect((await account('account-bank-utama')).isArchived, isFalse);
      expect((await account('account-bank-tujuan')).isArchived, isFalse);
    },
  );

  test('arsip Rekening ditolak bila pernah dipakai transaksi', () async {
    await insertTransactionReference('account-bank-utama');
    expect(
      await accounts.archiveBlockReason(
        householdId: AppContext.householdId,
        id: 'account-bank-utama',
      ),
      contains('transaksi'),
    );
    await expectArchiveRejected(
      'account-bank-utama',
      'arsipkan rekening bank utama',
    );
  });

  test('arsip Rekening ditolak bila pernah menjadi asal transfer', () async {
    await insertTransferReference(
      id: 'transfer-from',
      fromAccountId: 'account-bank-utama',
      toAccountId: 'account-bank-tujuan',
    );
    expect(
      await accounts.archiveBlockReason(
        householdId: AppContext.householdId,
        id: 'account-bank-utama',
      ),
      contains('transfer'),
    );
    await expectArchiveRejected(
      'account-bank-utama',
      'arsipkan rekening bank utama',
    );
  });

  test('arsip Rekening ditolak bila pernah menjadi tujuan transfer', () async {
    await insertTransferReference(
      id: 'transfer-to',
      fromAccountId: 'account-bank-tujuan',
      toAccountId: 'account-bank-utama',
    );
    await expectArchiveRejected(
      'account-bank-utama',
      'arsipkan rekening bank utama',
    );
  });

  test(
    'arsip Rekening ditolak bila pernah dipakai transaksi berkala',
    () async {
      await database
          .into(database.recurringTransactions)
          .insert(
            RecurringTransactionsCompanion.insert(
              id: 'recurring-account',
              householdId: AppContext.householdId,
              name: 'Internet',
              type: 'expense',
              amount: 100000,
              accountId: const Value('account-bank-utama'),
              startDate: now,
              createdAt: now,
            ),
          );
      await expectArchiveRejected(
        'account-bank-utama',
        'arsipkan rekening bank utama',
      );
    },
  );

  test('arsip Rekening ditolak bila memiliki log rekonsiliasi', () async {
    await database
        .into(database.accountReconciliationLogs)
        .insert(
          AccountReconciliationLogsCompanion.insert(
            id: 'reconciliation-account',
            householdId: AppContext.householdId,
            accountId: 'account-bank-utama',
            bookBalance: 100000,
            actualBalance: 100000,
            difference: 0,
            checkedAt: now,
            createdAt: now,
          ),
        );
    await expectArchiveRejected(
      'account-bank-utama',
      'arsipkan rekening bank utama',
    );
  });

  test('arsip hanya untuk Rekening tanpa referensi, lunak, diaudit, dan terbaca kembali', () async {
    final beforeTransactions = await database
        .select(database.transactions)
        .get()
        .then((rows) => rows.length);
    final beforeTransfers = await database
        .select(database.transfers)
        .get()
        .then((rows) => rows.length);
    final intent = await interpreter.interpret('arsipkan rekening bank utama');

    expect(
      (await execute(
        FfmAssistantActionPlanner(now: () => now).planFor(intent)!,
      ))?.status,
      FfmAssistantActionPlanStatus.completed,
    );
    final archived = await account('account-bank-utama');
    expect(archived.isArchived, isTrue);
    expect(archived.name, 'Bank Utama');
    expect(archived.type, 'bank');
    expect(archived.openingBalance, 100000);
    expect(archived.isActive, isTrue);
    expect(
      await database
          .select(database.transactions)
          .get()
          .then((rows) => rows.length),
      beforeTransactions,
    );
    expect(
      await database
          .select(database.transfers)
          .get()
          .then((rows) => rows.length),
      beforeTransfers,
    );
    final audits = await database
        .customSelect(
          'SELECT action FROM audit_logs WHERE entity = ?',
          variables: [Variable<String>('account')],
        )
        .get();
    expect(
      audits.map((row) => row.read<String>('action')),
      contains('archive'),
    );
  });
}
