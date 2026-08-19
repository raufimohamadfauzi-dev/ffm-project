import 'package:drift/drift.dart';

import 'app_context.dart';
import 'app_database.dart';

class DatabaseSeed {
  const DatabaseSeed._();

  static Future<void> ensure(
    AppDatabase database, {
    String householdId = AppContext.householdId,
  }) async {
    final now = DateTime.now();
    await database
        .into(database.households)
        .insertOnConflictUpdate(
          HouseholdsCompanion.insert(
            id: householdId,
            name: 'Keluarga',
            createdAt: now,
            updatedAt: Value(now),
          ),
        );
    final existing = await (database.select(
      database.categories,
    )..where((row) => row.householdId.equals(householdId))).get();
    final existingKeys = existing
        .map((row) => '${row.type}:${row.name.trim().toLowerCase()}')
        .toSet();
    const defaults = <(String, String, String)>[
      ('seed-income-gaji', 'Gaji', 'income'),
      ('seed-income-usaha', 'Usaha', 'income'),
      ('seed-income-hadiah-bantuan', 'Hadiah & bantuan', 'income'),
      ('seed-expense-makan-minum', 'Makan & minum', 'expense'),
      ('seed-expense-belanja-rumah', 'Belanja rumah', 'expense'),
      ('seed-expense-transportasi', 'Transportasi', 'expense'),
      ('seed-expense-tagihan', 'Tagihan', 'expense'),
      ('seed-expense-kesehatan', 'Kesehatan', 'expense'),
      ('seed-expense-biaya-admin', 'Biaya admin', 'expense'),
    ];
    final missing = defaults.where((item) {
      final key = '${item.$3}:${item.$2.toLowerCase()}';
      return !existingKeys.contains(key);
    });
    await database.batch((batch) {
      batch.insertAll(
        database.categories,
        missing
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
