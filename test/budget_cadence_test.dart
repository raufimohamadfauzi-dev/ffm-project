import 'package:drift/drift.dart' hide Column;
import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/database/database_seed.dart';

void main() {
  test(
    'seed kebutuhan memberi saran cadence tanpa membuat target atau transaksi',
    () async {
      final database = createInMemoryDatabaseForTests();
      addTearDown(database.close);

      final categories = await database.select(database.categories).get();
      final byName = {
        for (final category in categories) category.name: category,
      };

      expect(byName['Makan & minum']!.defaultBudgetPeriod, 'weekly');
      expect(byName['Warung Sawah']!.type, 'expense');
      expect(byName['Warung Sawah']!.defaultBudgetPeriod, 'weekly');
      expect(byName['BBM motor']!.defaultBudgetPeriod, 'weekly');
      expect(byName['Beras']!.defaultBudgetPeriod, 'monthly');
      expect(byName['Sabun & kebersihan']!.defaultBudgetPeriod, 'monthly');
      expect(byName['Sandal & sepatu']!.defaultBudgetPeriod, 'none');
      expect(byName['Pakaian']!.defaultBudgetPeriod, 'none');
      expect(await database.select(database.envelopeBudgets).get(), isEmpty);
      expect(await database.select(database.transactions).get(), isEmpty);
      await DatabaseSeed.ensure(database);
      final merchants = await database.select(database.merchants).get();
      expect(merchants.any((merchant) => merchant.name == 'Warung Sawah'), isTrue);
    },
  );

  test(
    'DatabaseSeed idempoten dan memperbaiki cadence seed lama saja',
    () async {
      final database = createInMemoryDatabaseForTests();
      addTearDown(database.close);

      await (database.update(database.categories)
            ..where((row) => row.id.equals('seed-expense-beras')))
          .write(const CategoriesCompanion(defaultBudgetPeriod: Value('none')));
      await database
          .into(database.categories)
          .insert(
            CategoriesCompanion.insert(
              id: 'custom-beras',
              householdId: 'local-household',
              name: 'Beras',
              type: 'expense',
              defaultBudgetPeriod: const Value('none'),
              createdAt: DateTime.now(),
            ),
          );

      await DatabaseSeed.ensure(database);
      final afterFirst = await database.select(database.categories).get();
      await DatabaseSeed.ensure(database);
      final afterSecond = await database.select(database.categories).get();

      expect(afterSecond, hasLength(afterFirst.length));
      final beras = afterSecond.singleWhere(
        (row) => row.id == 'seed-expense-beras',
      );
      expect(beras.defaultBudgetPeriod, 'monthly');
      final customBeras = afterSecond.singleWhere(
        (row) => row.id == 'custom-beras',
      );
      expect(customBeras.defaultBudgetPeriod, 'none');
      expect(await database.select(database.envelopeBudgets).get(), isEmpty);
      expect(await database.select(database.transactions).get(), isEmpty);
    },
  );
}
