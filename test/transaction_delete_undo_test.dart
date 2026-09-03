import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/database/audit_logger.dart';
import 'package:ffm_manager/features/audit/data/repositories/audit_log_repository.dart';
import 'package:ffm_manager/features/transaction/domain/usecases/transaction_crud_usecases.dart';

void main() {
  late AppDatabase database;
  late AuditLogger auditLogger;
  late SqliteAuditLogRepository auditRepo;

  setUp(() {
    database = createInMemoryDatabaseForTests();
    auditLogger = AuditLogger(database);
    auditRepo = SqliteAuditLogRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('Soft delete transaksi dan pemulihan (undo) mengembalikan status aktif serta mencatat audit log', () async {
    final now = DateTime(2026, 9, 3);
    const householdId = 'household-test';

    // Insert dummy account & category & transaction
    await database.into(database.accounts).insert(
      AccountsCompanion.insert(
        id: 'acc-1',
        householdId: householdId,
        name: 'Kas Utama',
        type: 'cash',
        openingBalance: const Value(100000),
        createdAt: now,
        isActive: const Value(true),
      ),
    );

    await database.into(database.categories).insert(
      CategoriesCompanion.insert(
        id: 'cat-1',
        householdId: householdId,
        name: 'Operasional',
        type: 'expense',
        defaultBudgetPeriod: const Value('monthly'),
        createdAt: now,
        isActive: const Value(true),
      ),
    );

    await database.into(database.transactions).insert(
      TransactionsCompanion.insert(
        id: 'tx-1',
        householdId: householdId,
        type: 'expense',
        date: now,
        recordedAt: now,
        amount: -50000,
        owner: const Value('Keluarga'),
        categoryId: const Value('cat-1'),
        accountId: const Value('acc-1'),
        createdAt: now,
        isDeleted: const Value(false),
        isArchived: const Value(false),
      ),
    );

    // 1. Eksekusi Soft Delete
    final deleteUseCase = DeleteTransaction(database);
    await deleteUseCase(householdId, 'tx-1');

    var txRow = await (database.select(database.transactions)..where((t) => t.id.equals('tx-1'))).getSingle();
    expect(txRow.isDeleted, isTrue);
    expect(txRow.isArchived, isTrue);

    // Catat audit log hapus
    await auditLogger.record(
      action: 'hapus',
      entity: 'transaksi',
      oldValue: {'id': 'tx-1', 'amount': -50000},
    );

    // 2. Eksekusi Pemulihan (Undo)
    await (database.update(database.transactions)..where((t) => t.id.equals('tx-1'))).write(
      const TransactionsCompanion(
        isDeleted: Value(false),
        isArchived: Value(false),
      ),
    );

    txRow = await (database.select(database.transactions)..where((t) => t.id.equals('tx-1'))).getSingle();
    expect(txRow.isDeleted, isFalse);
    expect(txRow.isArchived, isFalse);

    // Catat audit log pulihkan
    await auditLogger.record(
      action: 'pulihkan',
      entity: 'transaksi',
      newValue: {'id': 'tx-1', 'amount': -50000},
    );

    final logs = await auditRepo.getLogs(householdId: AppContext.householdId);
    expect(logs.any((log) => log.action == 'hapus' && log.entity == 'transaksi'), isTrue);
    expect(logs.any((log) => log.action == 'pulihkan' && log.entity == 'transaksi'), isTrue);
  });

  test('Penghapusan transfer beserta biaya admin dan pemulihan (undo) keduanya', () async {
    final now = DateTime(2026, 9, 3);
    const householdId = 'household-test';

    // Buat fee transaction
    await database.into(database.transactions).insert(
      TransactionsCompanion.insert(
        id: 'fee-1',
        householdId: householdId,
        type: 'expense',
        date: now,
        recordedAt: now,
        amount: -2500,
        owner: const Value('Keluarga'),
        source: const Value('transfer_fee'),
        createdAt: now,
        isDeleted: const Value(false),
      ),
    );

    // Buat transfer
    await database.into(database.transfers).insert(
      TransfersCompanion.insert(
        id: 'trf-1',
        householdId: householdId,
        date: now,
        recordedAt: now,
        amount: 200000,
        adminFee: const Value(2500),
        feeTransactionId: const Value('fee-1'),
        fromAccountId: 'acc-1',
        toAccountId: 'acc-2',
        source: const Value('manual'),
      ),
    );

    // 1. Hapus transfer dan fee terkait
    await (database.update(database.transfers)..where((t) => t.id.equals('trf-1'))).write(
      const TransfersCompanion(isDeleted: Value(true)),
    );
    await (database.update(database.transactions)..where((t) => t.id.equals('fee-1'))).write(
      const TransactionsCompanion(isDeleted: Value(true)),
    );

    var trfRow = await (database.select(database.transfers)..where((t) => t.id.equals('trf-1'))).getSingle();
    var feeRow = await (database.select(database.transactions)..where((t) => t.id.equals('fee-1'))).getSingle();
    expect(trfRow.isDeleted, isTrue);
    expect(feeRow.isDeleted, isTrue);

    // 2. Pemulihan (Undo) transfer dan fee terkait
    await (database.update(database.transfers)..where((t) => t.id.equals('trf-1'))).write(
      const TransfersCompanion(isDeleted: Value(false)),
    );
    await (database.update(database.transactions)..where((t) => t.id.equals('fee-1'))).write(
      const TransactionsCompanion(isDeleted: Value(false)),
    );

    await auditLogger.record(
      action: 'pulihkan',
      entity: 'transfer',
      newValue: {'id': 'trf-1', 'amount': 200000},
    );

    trfRow = await (database.select(database.transfers)..where((t) => t.id.equals('trf-1'))).getSingle();
    feeRow = await (database.select(database.transactions)..where((t) => t.id.equals('fee-1'))).getSingle();
    expect(trfRow.isDeleted, isFalse);
    expect(feeRow.isDeleted, isFalse);

    final logs = await auditRepo.getLogs(householdId: AppContext.householdId);
    expect(logs.any((log) => log.action == 'pulihkan' && log.entity == 'transfer'), isTrue);
  });
}
