import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/budget/data/budget_habit_analyzer.dart';

void main() {
  final now = DateTime(2026, 6, 15, 10);
  late AppDatabase database;
  late BudgetHabitAnalyzer analyzer;

  setUp(() async {
    database = createInMemoryDatabaseForTests();
    analyzer = BudgetHabitAnalyzer(database, clock: () => now);
    await _category(database, id: 'food', householdId: 'home', name: 'Makan');
    await _category(
      database,
      id: 'other-home',
      householdId: 'other',
      name: 'Lain',
    );
  });

  tearDown(() => database.close());

  test(
    'uses completed monthly medians, reports trend, and rounds up safely',
    () async {
      await _expense(
        database,
        id: 'jan',
        categoryId: 'food',
        date: DateTime(2026, 3, 2),
        amount: 100100,
      );
      await _expense(
        database,
        id: 'apr',
        categoryId: 'food',
        date: DateTime(2026, 4, 2),
        amount: 150000,
      );
      await _expense(
        database,
        id: 'may',
        categoryId: 'food',
        date: DateTime(2026, 5, 2),
        amount: 200000,
      );
      await _expense(
        database,
        id: 'outlier',
        categoryId: 'food',
        date: DateTime(2026, 5, 3),
        amount: 8000000,
      );
      await _expense(
        database,
        id: 'current',
        categoryId: 'food',
        date: DateTime(2026, 6, 1),
        amount: 9000000,
      );

      final result = await analyzer.analyze(householdId: 'home');

      expect(result.asOf, DateTime(2026, 6, 15));
      expect(result.recommendations, hasLength(1));
      final recommendation = result.recommendations.single;
      expect(recommendation.monthlyTotals, [100100, 150000, 8200000]);
      expect(recommendation.sampleCount, 3);
      expect(recommendation.medianMonthlySpend, 150000);
      expect(recommendation.recommendedMonthlyAmount, 150000);
      expect(recommendation.trend, BudgetHabitTrend.increasing);
    },
  );

  test('excludes other households, archived, deleted, transfer, income, and sparse categories', () async {
    await _expense(
      database,
      id: 'valid-1',
      categoryId: 'food',
      date: DateTime(2026, 3, 1),
      amount: 100001,
    );
    await _expense(
      database,
      id: 'valid-2',
      categoryId: 'food',
      date: DateTime(2026, 4, 1),
      amount: 100001,
    );
    await _expense(
      database,
      id: 'archived',
      categoryId: 'food',
      date: DateTime(2026, 5, 1),
      amount: 900000,
      isArchived: true,
    );
    await _expense(
      database,
      id: 'deleted',
      categoryId: 'food',
      date: DateTime(2026, 5, 2),
      amount: 900000,
      isDeleted: true,
    );
    await _expense(
      database,
      id: 'transfer',
      categoryId: 'food',
      date: DateTime(2026, 5, 3),
      amount: 900000,
      source: 'transfer',
    );
    await _expense(
      database,
      id: 'linked-transfer',
      categoryId: 'food',
      date: DateTime(2026, 5, 4),
      amount: 900000,
      transferId: 'transfer-1',
    );
    await _transaction(
      database,
      id: 'income',
      householdId: 'home',
      categoryId: 'food',
      date: DateTime(2026, 5, 5),
      amount: 900000,
      type: 'income',
    );
    await _transaction(
      database,
      id: 'other-household',
      householdId: 'other',
      categoryId: 'other-home',
      date: DateTime(2026, 3, 1),
      amount: 700000,
      type: 'expense',
    );

    final result = await analyzer.analyze(householdId: 'home');

    final recommendation = result.recommendations.single;
    expect(recommendation.monthlyTotals, [100001, 100001, 0]);
    expect(recommendation.sampleCount, 2);
    expect(recommendation.recommendedMonthlyAmount, 101000);
  });

  test(
    'requires 3 to 12 completed periods and at least two sampled months',
    () async {
      await _expense(
        database,
        id: 'one-off',
        categoryId: 'food',
        date: DateTime(2026, 5, 1),
        amount: 50000,
      );

      expect(
        (await analyzer.analyze(householdId: 'home')).recommendations,
        isEmpty,
      );
      await expectLater(
        analyzer.analyze(householdId: 'home', historicalPeriodCount: 2),
        throwsArgumentError,
      );
      await expectLater(
        analyzer.analyze(householdId: 'home', historicalPeriodCount: 13),
        throwsArgumentError,
      );
    },
  );
}

Future<void> _category(
  AppDatabase database, {
  required String id,
  required String householdId,
  required String name,
}) => database
    .into(database.categories)
    .insert(
      CategoriesCompanion.insert(
        id: id,
        householdId: householdId,
        name: name,
        type: 'expense',
        createdAt: DateTime(2026),
      ),
    );

Future<void> _expense(
  AppDatabase database, {
  required String id,
  required String categoryId,
  required DateTime date,
  required int amount,
  bool isArchived = false,
  bool isDeleted = false,
  String? source,
  String? transferId,
}) => _transaction(
  database,
  id: id,
  householdId: 'home',
  categoryId: categoryId,
  date: date,
  amount: amount,
  type: 'expense',
  isArchived: isArchived,
  isDeleted: isDeleted,
  source: source,
  transferId: transferId,
);

Future<void> _transaction(
  AppDatabase database, {
  required String id,
  required String householdId,
  required String categoryId,
  required DateTime date,
  required int amount,
  required String type,
  bool isArchived = false,
  bool isDeleted = false,
  String? source,
  String? transferId,
}) => database
    .into(database.transactions)
    .insert(
      TransactionsCompanion.insert(
        id: id,
        householdId: householdId,
        categoryId: Value(categoryId),
        amount: amount,
        type: type,
        date: date,
        recordedAt: date,
        source: Value(source),
        transferId: Value(transferId),
        isArchived: Value(isArchived),
        isDeleted: Value(isDeleted),
        createdAt: date,
      ),
    );
