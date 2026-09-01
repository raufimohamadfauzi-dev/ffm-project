import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_financial_snapshot_service.dart';
import 'package:ffm_manager/features/hijri/domain/hijri_calendar_service.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = createInMemoryDatabaseForTests();
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'accounts digest memakai opening_balance bukan balance dan terbatas 8',
    () async {
      final now = DateTime(2026, 8, 31);
      for (var i = 0; i < 10; i++) {
        await database
            .into(database.accounts)
            .insert(
              AccountsCompanion.insert(
                id: 'acc-$i',
                householdId: AppContext.householdId,
                name: 'Rek $i',
                type: 'bank',
                openingBalance: Value(100000 * i),
                createdAt: now,
              ),
            );
      }
      final service = FfmAssistantFinancialSnapshotService(
        database,
        HijriCalendarService(database),
      );
      final digest = await service.buildAccountsDigest(
        householdId: AppContext.householdId,
      );

      expect(digest, contains('opening_balance'));
      expect(
        digest,
        isNot(contains('|balance=')),
      ); // label lama tanpa prefix tidak boleh muncul
      expect(digest, contains('opening_balance = saldo awal'));
      // Hanya 8 dari 10 yang dirender
      expect(
        'Rek 9'.allMatches(digest).length,
        0,
      ); // Rek 9 harus terpotong karena limit 8 dan sort
      expect(digest, contains('… (+2 lebih)'));
    },
  );

  test(
    'budget digest memakai allocated bukan pemakaian dan terbatas',
    () async {
      final now = DateTime(2026, 8, 31);
      for (var i = 0; i < 9; i++) {
        await database
            .into(database.envelopeBudgets)
            .insert(
              EnvelopeBudgetsCompanion.insert(
                id: 'budget-$i',
                householdId: AppContext.householdId,
                name: 'Budget $i',
                allocated: const Value(500000),
                periodType: const Value('monthly'),
                startDate: now,
                endDate: now.add(const Duration(days: 30)),
                createdAt: now,
              ),
            );
      }
      final digest = await FfmAssistantFinancialSnapshotService(database)
          .buildBudgetDigest(householdId: AppContext.householdId, now: now);

      expect(digest, contains('allocated='));
      expect(digest, contains('batas alokasi, bukan pemakaian'));
      expect(digest, contains('Budget digest'));
      expect(digest, contains('… (+1 lebih)'));
      expect(digest, isNot(contains('posisi anggaran')));
    },
  );

  test('categories digest terbatas 16 dan sanitize newline', () async {
    final now = DateTime(2026, 8, 31);
    for (var i = 0; i < 20; i++) {
      await database
          .into(database.categories)
          .insert(
            CategoriesCompanion.insert(
              id: 'cat-$i',
              householdId: AppContext.householdId,
              name: i == 5 ? 'AAA Kategori\nBaru' : 'Kat $i',
              type: 'expense',
              createdAt: now,
            ),
          );
    }
    final digest = await FfmAssistantFinancialSnapshotService(database)
        .buildCategoriesDigest(householdId: AppContext.householdId);

    expect(digest, contains('Categories digest'));
    expect(digest, isNot(contains('\nBaru'))); // newline sanitized
    expect(digest, contains('AAA Kategori Baru'));
    expect(digest, contains('… (+'));
  });

  test('goals digest hanya target aktif dan terbatas 8', () async {
    final now = DateTime(2026, 8, 31);
    for (var i = 0; i < 5; i++) {
      await database
          .into(database.goals)
          .insert(
            GoalsCompanion.insert(
              id: 'goal-active-$i',
              householdId: AppContext.householdId,
              name: 'Goal $i',
              targetAmount: 1000000,
              createdAt: now,
              isActive: Value(true),
            ),
          );
    }
    await database
        .into(database.goals)
        .insert(
          GoalsCompanion.insert(
            id: 'goal-archived',
            householdId: AppContext.householdId,
            name: 'Goal Arsip',
            targetAmount: 999999,
            createdAt: now,
            isActive: const Value(false),
          ),
        );

    final digest = await FfmAssistantFinancialSnapshotService(database)
        .buildGoalsDigest(householdId: AppContext.householdId);

    expect(digest, contains('Goal 0'));
    expect(digest, isNot(contains('Goal Arsip')));
    expect(digest, contains('hanya target aktif'));
  });
}
