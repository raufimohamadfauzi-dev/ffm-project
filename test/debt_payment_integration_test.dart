import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/liability/domain/entities/liability_entity.dart';
import 'package:ffm_manager/features/liability/domain/usecases/liability_crud_usecases.dart';
import 'package:ffm_manager/features/liability/domain/usecases/process_debt_payment.dart';
import 'package:ffm_manager/features/receivable/domain/entities/receivable_entity.dart';
import 'package:ffm_manager/features/receivable/domain/usecases/receivable_crud_usecases.dart';

void main() {
  late AppDatabase db;
  late ProcessDebtPayment processPayment;

  const householdId = 'hh-payment-test';
  const accountId = 'acc-bca-test';

  setUp(() async {
    db = createInMemoryDatabaseForTests();
    processPayment = ProcessDebtPayment(db);

    // Seed account
    await db.into(db.accounts).insert(
          AccountsCompanion.insert(
            id: accountId,
            householdId: householdId,
            name: 'BCA Utama',
            type: 'bank',
            openingBalance: const Value(5000000),
            isActive: const Value(true),
            isArchived: const Value(false),
            createdAt: DateTime(2026, 1, 1),
          ),
        );
  });

  tearDown(() => db.close());

  group('ProcessDebtPayment Integration Tests', () {
    test('pembayaran sebagian hutang memotong sisa saldo dan mencatat transaksi kas expense', () async {
      final now = DateTime(2026, 9, 3);
      final saveLiability = SaveLiability(db);
      final getLiabilities = GetLiabilities(db);

      // Seed hutang 1.000.000, sisa 1.000.000
      await saveLiability(
        LiabilityEntity(
          id: 'liab-1',
          householdId: householdId,
          name: 'Hutang Laptop',
          originalAmount: 1000000,
          remainingBalance: 1000000,
          monthlyInstallment: 250000,
          startDate: now,
          dueDate: now.add(const Duration(days: 30)),
          updatedAt: now,
        ),
      );

      // Bayar 250.000
      final newRemaining = await processPayment(
        householdId: householdId,
        targetId: 'liab-1',
        targetName: 'Hutang Laptop',
        isLiability: true,
        amount: 250000,
        date: now,
        accountId: accountId,
        note: 'Cicilan 1 Laptop',
        recordCashTransaction: true,
      );

      expect(newRemaining, 750000);

      // Verifikasi sisa saldo di database
      final liabilities = await getLiabilities(householdId);
      final updated = liabilities.firstWhere((l) => l.id == 'liab-1');
      expect(updated.remainingBalance, 750000);

      // Verifikasi transaksi kas tercatat sebagai expense
      final txs = await (db.select(db.transactions)
            ..where((t) => t.householdId.equals(householdId)))
          .get();
      expect(txs.length, 1);
      final tx = txs.first;
      expect(tx.type, 'expense');
      expect(tx.amount, -250000);
      expect(tx.source, 'liability_payment');
      expect(tx.sourceId, 'liab-1');
      expect(tx.note, 'Cicilan 1 Laptop');
    });

    test('pelunasan penuh hutang membuat sisa saldo menjadi 0', () async {
      final now = DateTime(2026, 9, 3);
      final saveLiability = SaveLiability(db);
      final getLiabilities = GetLiabilities(db);

      await saveLiability(
        LiabilityEntity(
          id: 'liab-lunas',
          householdId: householdId,
          name: 'Hutang Teman',
          originalAmount: 500000,
          remainingBalance: 500000,
          monthlyInstallment: 500000,
          startDate: now,
          dueDate: now.add(const Duration(days: 10)),
          updatedAt: now,
        ),
      );

      // Bayar 500.000 (lunas)
      final newRemaining = await processPayment(
        householdId: householdId,
        targetId: 'liab-lunas',
        targetName: 'Hutang Teman',
        isLiability: true,
        amount: 500000,
        date: now,
        accountId: accountId,
        recordCashTransaction: true,
      );

      expect(newRemaining, 0);

      final liabilities = await getLiabilities(householdId);
      final updated = liabilities.firstWhere((l) => l.id == 'liab-lunas');
      expect(updated.remainingBalance, 0);
    });

    test('penerimaan sebagian piutang memotong sisa dan mencatat pemasukan kas income', () async {
      final now = DateTime(2026, 9, 3);
      final saveReceivable = SaveReceivable(db);
      final getReceivables = GetReceivables(db);

      await saveReceivable(
        ReceivableEntity(
          id: 'rec-1',
          householdId: householdId,
          name: 'Pinjaman Budi',
          originalAmount: 2000000,
          remainingBalance: 2000000,
          monthlyInstallment: 500000,
          startDate: now,
          dueDate: now.add(const Duration(days: 60)),
          updatedAt: now,
        ),
      );

      // Budi bayar 500.000
      final newRemaining = await processPayment(
        householdId: householdId,
        targetId: 'rec-1',
        targetName: 'Pinjaman Budi',
        isLiability: false,
        amount: 500000,
        date: now,
        accountId: accountId,
        note: 'Penerimaan dari Budi',
        recordCashTransaction: true,
      );

      expect(newRemaining, 1500000);

      final receivables = await getReceivables(householdId);
      final updated = receivables.firstWhere((r) => r.id == 'rec-1');
      expect(updated.remainingBalance, 1500000);

      final txs = await (db.select(db.transactions)
            ..where((t) => t.householdId.equals(householdId)))
          .get();
      expect(txs.length, 1);
      final tx = txs.first;
      expect(tx.type, 'income');
      expect(tx.amount, 500000);
      expect(tx.source, 'receivable_payment');
      expect(tx.sourceId, 'rec-1');
    });

    test('menolak pembayaran yang melebihi sisa saldo', () async {
      final now = DateTime(2026, 9, 3);
      await SaveLiability(db)(
        LiabilityEntity(
          id: 'liab-over',
          householdId: householdId,
          name: 'Hutang Kecil',
          originalAmount: 100000,
          remainingBalance: 100000,
          monthlyInstallment: 100000,
          startDate: now,
          dueDate: now.add(const Duration(days: 5)),
          updatedAt: now,
        ),
      );

      expect(
        () => processPayment(
          householdId: householdId,
          targetId: 'liab-over',
          targetName: 'Hutang Kecil',
          isLiability: true,
          amount: 150000, // Melebihi 100.000
          date: now,
          accountId: accountId,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('pembayaran tanpa mutasi kas tidak mencatat ke tabel transactions', () async {
      final now = DateTime(2026, 9, 3);
      await SaveLiability(db)(
        LiabilityEntity(
          id: 'liab-no-cash',
          householdId: householdId,
          name: 'Hutang Barang',
          originalAmount: 300000,
          remainingBalance: 300000,
          monthlyInstallment: 100000,
          startDate: now,
          dueDate: now.add(const Duration(days: 15)),
          updatedAt: now,
        ),
      );

      final newRemaining = await processPayment(
        householdId: householdId,
        targetId: 'liab-no-cash',
        targetName: 'Hutang Barang',
        isLiability: true,
        amount: 100000,
        date: now,
        recordCashTransaction: false,
      );

      expect(newRemaining, 200000);

      final txs = await (db.select(db.transactions)
            ..where((t) => t.householdId.equals(householdId)))
          .get();
      expect(txs.isEmpty, true);
    });
  });
}
