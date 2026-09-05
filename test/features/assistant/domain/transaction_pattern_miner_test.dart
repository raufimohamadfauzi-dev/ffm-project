import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/domain/services/transaction_pattern_miner.dart';

void main() {
  group('TransactionPatternMiner', () {
    late AppDatabase db;
    late TransactionPatternMiner miner;
    const householdId = 'test-household-patterns';

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      miner = TransactionPatternMiner(db);

      // Seed category
      await db.into(db.categories).insert(
        CategoriesCompanion.insert(
          id: 'cat-kopi',
          householdId: householdId,
          name: 'Minuman',
          type: 'expense',
          createdAt: DateTime.now(),
        ),
      );

      // Seed merchant
      await db.into(db.merchants).insert(
        MerchantsCompanion.insert(
          id: 'merch-kopi',
          householdId: householdId,
          name: 'Kopi Kenangan',
          createdAt: DateTime.now(),
        ),
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('mines weekly recurring expense pattern successfully', () async {
      // Seed 3 transactions on Saturdays: 2026-08-15, 2026-08-22, 2026-08-29
      final sat1 = DateTime(2026, 8, 15, 14, 0); // Saturday
      final sat2 = DateTime(2026, 8, 22, 14, 30); // Saturday
      final sat3 = DateTime(2026, 8, 29, 15, 0); // Saturday

      for (var i = 0; i < 3; i++) {
        final date = [sat1, sat2, sat3][i];
        await db.into(db.transactions).insert(
          TransactionsCompanion.insert(
            id: 'tx-kopi-$i',
            householdId: householdId,
            type: 'expense',
            date: date,
            recordedAt: date,
            amount: 25000,
            categoryId: const drift.Value('cat-kopi'),
            merchantId: const drift.Value('merch-kopi'),
            createdAt: date,
            isDeleted: const drift.Value(false),
          ),
        );
      }

      // Reference date is Saturday 2026-09-05
      final refDate = DateTime(2026, 9, 5, 12, 0); // Saturday
      final patterns = await miner.minePatterns(
        householdId: householdId,
        referenceDate: refDate,
        lookbackDays: 60,
      );

      expect(patterns.isNotEmpty, isTrue);
      final pattern = patterns.first;
      expect(pattern.merchant, 'Kopi Kenangan');
      expect(pattern.categoryName, 'Minuman');
      expect(pattern.amount, 25000);
      expect(pattern.dayOfWeek, DateTime.saturday);
      expect(pattern.isDueToday, isTrue);
      expect(pattern.confidence, greaterThanOrEqualTo(0.8));
      expect(pattern.promptMessage, contains('Sabtu'));
      expect(pattern.promptMessage, contains('Rp 25.000'));
    });

    test('excludes transactions that belong to active recurring transactions', () async {
      // Seed an active recurring transaction for cat-kopi
      await db.into(db.recurringTransactions).insert(
        RecurringTransactionsCompanion.insert(
          id: 'rec-kopi',
          householdId: householdId,
          name: 'Kopi Kenangan Mingguan',
          type: 'expense',
          amount: 25000,
          startDate: DateTime(2026, 8, 1),
          categoryId: const drift.Value('cat-kopi'),
          isActive: const drift.Value(true),
          createdAt: DateTime.now(),
        ),
      );

      // Seed 3 transactions
      final sat1 = DateTime(2026, 8, 15, 14, 0);
      final sat2 = DateTime(2026, 8, 22, 14, 30);
      final sat3 = DateTime(2026, 8, 29, 15, 0);

      for (var i = 0; i < 3; i++) {
        final date = [sat1, sat2, sat3][i];
        await db.into(db.transactions).insert(
          TransactionsCompanion.insert(
            id: 'tx-kopi-rec-$i',
            householdId: householdId,
            type: 'expense',
            date: date,
            recordedAt: date,
            amount: 25000,
            categoryId: const drift.Value('cat-kopi'),
            createdAt: date,
            isDeleted: const drift.Value(false),
          ),
        );
      }

      final patterns = await miner.minePatterns(
        householdId: householdId,
        referenceDate: DateTime(2026, 9, 5),
        lookbackDays: 60,
      );

      expect(patterns.isEmpty, isTrue);
    });

    test('marks isDueToday as false when weekday does not match', () async {
      final sat1 = DateTime(2026, 8, 15, 14, 0);
      final sat2 = DateTime(2026, 8, 22, 14, 30);
      final sat3 = DateTime(2026, 8, 29, 15, 0);

      for (var i = 0; i < 3; i++) {
        final date = [sat1, sat2, sat3][i];
        await db.into(db.transactions).insert(
          TransactionsCompanion.insert(
            id: 'tx-kopi-weekday-$i',
            householdId: householdId,
            type: 'expense',
            date: date,
            recordedAt: date,
            amount: 25000,
            merchantId: const drift.Value('merch-kopi'),
            createdAt: date,
            isDeleted: const drift.Value(false),
          ),
        );
      }

      // Reference date is Sunday 2026-09-06
      final sundayRef = DateTime(2026, 9, 6, 12, 0);
      final patterns = await miner.minePatterns(
        householdId: householdId,
        referenceDate: sundayRef,
        lookbackDays: 60,
      );

      expect(patterns.isNotEmpty, isTrue);
      expect(patterns.first.dayOfWeek, DateTime.saturday);
      expect(patterns.first.isDueToday, isFalse);
    });
  });
}
