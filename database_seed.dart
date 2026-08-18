import 'package:drift/drift.dart';

import 'app_context.dart';
import 'app_database.dart';

class DatabaseSeed {
  const DatabaseSeed._();

  static Future<void> ensure(AppDatabase database, {String householdId = AppContext.householdId}) async {
    final now = DateTime.now();
    await database.into(database.households).insertOnConflictUpdate(
          HouseholdsCompanion.insert(
            id: householdId,
            name: 'Keluarga',
            createdAt: now,
            updatedAt: Value(now),
          ),
        );
    final existing = await (database.select(database.categories)..where((row) => row.householdId.equals(householdId))).get();
    if (existing.isNotEmpty) return;
    const defaults = <(String, String, String)>[
      ('category-income', 'Pemasukan lain-lain', 'income'),
      ('category-expense-food', 'Makan dan minum', 'expense'),
      ('category-expense-transport', 'Transportasi', 'expense'),
      ('category-expense-bills', 'Tagihan rumah', 'expense'),
    ];
    await database.batch((batch) {
      batch.insertAll(
        database.categories,
        defaults
            .map(
              (item) => CategoriesCompanion.insert(
                id: item.$1,
                householdId: householdId,
                name: item.$2,
                type: item.$3,
                createdAt: now,
              ),
            )
            .toList(),
      );
    });
  }
}
