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
    const defaults = <(String, String, String, String)>[
      ('seed-income-gaji', 'Gaji', 'income', 'none'),
      ('seed-income-usaha', 'Usaha', 'income', 'none'),
      ('seed-income-hadiah-bantuan', 'Hadiah & bantuan', 'income', 'none'),
      ('seed-expense-makan-minum', 'Makan & minum', 'expense', 'weekly'),
      ('seed-expense-belanja-rumah', 'Belanja rumah', 'expense', 'monthly'),
      ('seed-expense-belanja-pasar', 'Belanja pasar', 'expense', 'weekly'),
      ('seed-expense-transportasi', 'Transportasi', 'expense', 'weekly'),
      ('seed-expense-bbm-motor', 'BBM motor', 'expense', 'weekly'),
      ('seed-expense-bbm-mobil', 'BBM mobil', 'expense', 'weekly'),
      ('seed-expense-tagihan', 'Tagihan', 'expense', 'monthly'),
      ('seed-expense-tagihan-rumah', 'Tagihan rumah', 'expense', 'monthly'),
      ('seed-expense-listrik-air', 'Listrik & air', 'expense', 'monthly'),
      ('seed-expense-gas-lpg', 'Gas LPG', 'expense', 'monthly'),
      ('seed-expense-pulsa-internet', 'Pulsa & internet', 'expense', 'monthly'),
      ('seed-expense-beras', 'Beras', 'expense', 'monthly'),
      (
        'seed-expense-sabun-kebersihan',
        'Sabun & kebersihan',
        'expense',
        'monthly',
      ),
      ('seed-expense-kebutuhan-dapur', 'Kebutuhan dapur', 'expense', 'monthly'),
      ('seed-expense-kesehatan', 'Kesehatan', 'expense', 'monthly'),
      ('seed-expense-sandal-sepatu', 'Sandal & sepatu', 'expense', 'none'),
      ('seed-expense-pakaian', 'Pakaian', 'expense', 'none'),
      (
        'seed-expense-perlengkapan-rumah',
        'Perlengkapan rumah',
        'expense',
        'none',
      ),
      ('seed-expense-servis-kendaraan', 'Servis kendaraan', 'expense', 'none'),
      (
        'seed-expense-perawatan-kendaraan',
        'Perawatan kendaraan',
        'expense',
        'none',
      ),
      (
        'seed-expense-kebutuhan-sekolah',
        'Kebutuhan sekolah',
        'expense',
        'none',
      ),
      (
        'seed-expense-kebutuhan-musiman',
        'Kebutuhan musiman',
        'expense',
        'none',
      ),
      ('seed-expense-biaya-admin', 'Biaya admin', 'expense', 'none'),
      ('seed-expense-pertanian', 'Pertanian', 'expense', 'none'),
      ('seed-expense-lainnya', 'Lainnya', 'expense', 'none'),
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
                defaultBudgetPeriod: Value(item.$4),
                createdAt: now,
              ),
            )
            .toList(),
      );
    });
    for (final item in defaults) {
      if (item.$4 == 'none') continue;
      await (database.update(database.categories)..where(
            (row) =>
                row.householdId.equals(householdId) &
                row.id.equals(item.$1) &
                row.defaultBudgetPeriod.equals('none'),
          ))
          .write(CategoriesCompanion(defaultBudgetPeriod: Value(item.$4)));
    }
  }
}
