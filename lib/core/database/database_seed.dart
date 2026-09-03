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
    await _seedCategories(database, householdId, now);
    await _seedMerchants(database, householdId, now);
    await _seedTags(database, householdId, now);
    await _seedAccounts(database, householdId, now);
    await _seedIncomeSources(database, householdId, now);
    await _seedGoals(database, householdId, now);
  }

  // ---------------------------------------------------------------------------
  // Kategori
  // ---------------------------------------------------------------------------

  static Future<void> _seedCategories(
    AppDatabase database,
    String householdId,
    DateTime now,
  ) async {
    final existing = await (database.select(
      database.categories,
    )..where((row) => row.householdId.equals(householdId))).get();
    final existingKeys = existing
        .map((row) => '${row.type}:${row.name.trim().toLowerCase()}')
        .toSet();

    const defaults = <(String, String, String, String)>[
      // --- Pengeluaran ---
      ('seed-expense-belanja-dapur', 'Belanja dapur', 'expense', 'weekly'),
      ('seed-expense-pajak-tanah', 'Pajak tanah', 'expense', 'none'),
      ('seed-expense-pajak-motor', 'Pajak motor', 'expense', 'none'),
      ('seed-expense-pajak-mobil', 'Pajak mobil', 'expense', 'none'),
      (
        'seed-expense-pupuk-obat-tanaman',
        'Pupuk & obat tanaman',
        'expense',
        'none',
      ),
      (
        'seed-expense-transportasi-bensin',
        'Transportasi / bensin',
        'expense',
        'weekly',
      ),
      ('seed-expense-listrik-air', 'Listrik & air', 'expense', 'monthly'),
      ('seed-expense-kesehatan', 'Kesehatan', 'expense', 'monthly'),
      ('seed-expense-pendidikan', 'Pendidikan', 'expense', 'none'),
      // --- Cadence warisan: ID sama dengan seed AppDatabase agar
      // ensure() dapat memperbaiki periode 'none' peninggalan versi lama.
      ('seed-expense-makan-minum', 'Makan & minum', 'expense', 'weekly'),
      ('seed-expense-belanja-rumah', 'Belanja rumah', 'expense', 'monthly'),
      ('seed-expense-belanja-pasar', 'Belanja pasar', 'expense', 'weekly'),
      ('seed-expense-transportasi', 'Transportasi', 'expense', 'weekly'),
      ('seed-expense-bbm-motor', 'BBM motor', 'expense', 'weekly'),
      ('seed-expense-bbm-mobil', 'BBM mobil', 'expense', 'weekly'),
      ('seed-expense-tagihan', 'Tagihan', 'expense', 'monthly'),
      ('seed-expense-tagihan-rumah', 'Tagihan rumah', 'expense', 'monthly'),
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
      // --- Pemasukan ---
      ('seed-income-hasil-panen', 'Hasil panen', 'income', 'none'),
      ('seed-income-cabe', 'Cabe', 'income', 'none'),
      ('seed-income-pepaya', 'Pepaya', 'income', 'none'),
      ('seed-income-padi', 'Padi', 'income', 'none'),
      ('seed-income-kasih-orang', 'Kasih orang', 'income', 'none'),
      ('seed-income-bansos', 'Bansos', 'income', 'none'),
      ('seed-income-ternak', 'Ternak', 'income', 'none'),
      // --- Aktivitas ---
      ('seed-activity-menanam', 'Menanam', 'activity', 'none'),
      ('seed-activity-menyiangi', 'Menyiangi', 'activity', 'none'),
      ('seed-activity-panen', 'Panen', 'activity', 'none'),
      ('seed-activity-ngopi', 'Ngopi', 'activity', 'none'),
      ('seed-activity-belajar', 'Belajar', 'activity', 'none'),
    ];

    final missing = defaults.where((item) {
      final key = '${item.$3}:${item.$2.toLowerCase()}';
      return !existingKeys.contains(key);
    });

    if (missing.isEmpty) return;

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

    // Atur defaultBudgetPeriod untuk kategori yang sudah ada tapi masih 'none'.
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

  // ---------------------------------------------------------------------------
  // Toko / Tempat
  // ---------------------------------------------------------------------------

  static Future<void> _seedMerchants(
    AppDatabase database,
    String householdId,
    DateTime now,
  ) async {
    final existing =
        await (database.select(database.merchants)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isActive.equals(true),
            ))
            .get();
    final existingNames = existing
        .map((row) => row.name.trim().toLowerCase())
        .toSet();

    const defaults = <(String, String)>[
      ('seed-merchant-sayur-segar', 'Sayur segar'),
      ('seed-merchant-pupuk-ciputri', 'Toko Pupuk Ciputri'),
      ('seed-merchant-pasar-singaparna', 'Pasar Singaparna'),
      ('seed-merchant-toko-beras-sukahaji', 'Toko beras sukahaji'),
      ('seed-merchant-pupuk-spa', 'Toko pupuk SPA'),
      ('seed-merchant-pupuk-ciputri-2', 'Toko pupuk Ciputri 2'),
    ];

    final missing = defaults.where(
      (item) => !existingNames.contains(item.$2.toLowerCase()),
    );

    if (missing.isEmpty) return;

    await database.batch((batch) {
      batch.insertAll(
        database.merchants,
        missing
            .map(
              (item) => MerchantsCompanion.insert(
                id: item.$1,
                householdId: householdId,
                name: item.$2,
                createdAt: now,
              ),
            )
            .toList(),
      );
    });
  }

  // ---------------------------------------------------------------------------
  // Tag
  // ---------------------------------------------------------------------------

  static Future<void> _seedTags(
    AppDatabase database,
    String householdId,
    DateTime now,
  ) async {
    final existing =
        await (database.select(database.tags)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isArchived.equals(false),
            ))
            .get();
    final existingNames = existing
        .map((row) => row.name.trim().toLowerCase())
        .toSet();

    const defaults = <(String, String)>[
      ('seed-tag-wajib', 'wajib'),
      ('seed-tag-pertanian', 'pertanian'),
      ('seed-tag-sekolah', 'sekolah'),
      ('seed-tag-mudik', 'mudik'),
      ('seed-tag-rutin', 'rutin'),
      ('seed-tag-bisa-ditunda', 'bisa ditunda'),
      ('seed-tag-darurat', 'darurat'),
    ];

    final missing = defaults.where(
      (item) => !existingNames.contains(item.$2.toLowerCase()),
    );

    if (missing.isEmpty) return;

    await database.batch((batch) {
      batch.insertAll(
        database.tags,
        missing
            .map(
              (item) => TagsCompanion.insert(
                id: item.$1,
                householdId: householdId,
                name: item.$2,
                createdAt: now,
              ),
            )
            .toList(),
      );
    });
  }

  // ---------------------------------------------------------------------------
  // Rekening
  // ---------------------------------------------------------------------------

  static Future<void> _seedAccounts(
    AppDatabase database,
    String householdId,
    DateTime now,
  ) async {
    final existing =
        await (database.select(database.accounts)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isArchived.equals(false),
            ))
            .get();
    final existingNames = existing
        .map((row) => row.name.trim().toLowerCase())
        .toSet();

    const defaults = <(String, String, String)>[
      ('seed-account-cash-rumah', 'Cash Rumah', 'cash'),
      ('seed-account-seabank', 'Seabank', 'bank'),
      ('seed-account-gopay', 'GoPay', 'ewallet'),
    ];

    final missing = defaults.where(
      (item) => !existingNames.contains(item.$2.toLowerCase()),
    );

    if (missing.isEmpty) return;

    await database.batch((batch) {
      batch.insertAll(
        database.accounts,
        missing
            .map(
              (item) => AccountsCompanion.insert(
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

  // ---------------------------------------------------------------------------
  // Sumber Pemasukan
  // ---------------------------------------------------------------------------

  static Future<void> _seedIncomeSources(
    AppDatabase database,
    String householdId,
    DateTime now,
  ) async {
    final existing =
        await (database.select(database.transactionParties)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.kind.equals('income_source') &
                  row.isArchived.equals(false),
            ))
            .get();
    final existingNames = existing
        .map((row) => row.name.trim().toLowerCase())
        .toSet();

    const defaults = <(String, String)>[
      ('seed-income-source-cabe', 'Cabe'),
      ('seed-income-source-pepaya', 'Pepaya'),
      ('seed-income-source-padi', 'Padi'),
      ('seed-income-source-kasih-orang', 'Kasih orang'),
      ('seed-income-source-bansos', 'Bansos'),
      ('seed-income-source-ternak', 'Ternak'),
    ];

    final missing = defaults.where(
      (item) => !existingNames.contains(item.$2.toLowerCase()),
    );

    if (missing.isEmpty) return;

    await database.batch((batch) {
      batch.insertAll(
        database.transactionParties,
        missing
            .map(
              (item) => TransactionPartiesCompanion.insert(
                id: item.$1,
                householdId: householdId,
                name: item.$2,
                role: const Value('Sumber pemasukan'),
                kind: const Value('income_source'),
                createdAt: now,
              ),
            )
            .toList(),
      );
    });
  }

  // ---------------------------------------------------------------------------
  // Target Keuangan
  // ---------------------------------------------------------------------------

  static Future<void> _seedGoals(
    AppDatabase database,
    String householdId,
    DateTime now,
  ) async {
    final existing =
        await (database.select(database.goals)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isActive.equals(true),
            ))
            .get();
    final existingNames = existing
        .map((row) => row.name.trim().toLowerCase())
        .toSet();

    final targetDate = DateTime(now.year + 1, now.month, now.day);

    const defaults = <(String, String, int)>[
      ('seed-goal-dana-darurat', 'Dana darurat', 10000000),
    ];

    final missing = defaults.where(
      (item) => !existingNames.contains(item.$2.toLowerCase()),
    );

    if (missing.isEmpty) return;

    await database.batch((batch) {
      batch.insertAll(
        database.goals,
        missing
            .map(
              (item) => GoalsCompanion.insert(
                id: item.$1,
                householdId: householdId,
                name: item.$2,
                targetAmount: item.$3,
                targetDate: Value(targetDate),
                createdAt: now,
              ),
            )
            .toList(),
      );
    });
  }
}
