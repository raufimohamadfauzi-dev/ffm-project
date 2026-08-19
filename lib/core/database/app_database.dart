import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Households,
    Categories,
    Merchants,
    Tags,
    Accounts,
    TransactionParties,
    Transactions,
    TransactionItems,
    TransactionTags,
    Attachments,
    Transfers,
    EnvelopeBudgets,
    EnvelopeTransfers,
    Assets,
    Goals,
    Liabilities,
    Receivables,
    RecurringTransactions,
    RecurringTransactionRuns,
    AccountReconciliationLogs,
    HijriSettings,
    HijriMonthOverrides,
    HijriCorrectionLogs,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  factory AppDatabase.openDefault() => AppDatabase(_openConnection());

  @override
  int get schemaVersion => 25;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      await _seedInitialData();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      await m.createAll();
      if (from < 21) {
        await m.addColumn(tags, tags.isArchived);
      }
      if (from < 22) {
        await m.addColumn(transactions, transactions.receiptRawText);
        await m.addColumn(transactions, transactions.receiptNumber);
        await m.addColumn(transactions, transactions.receiptPaidAmount);
        await m.addColumn(transactions, transactions.receiptChangeAmount);
      }
      if (from < 23) {
        await m.addColumn(transactions, transactions.sourceId);
        await m.addColumn(transactions, transactions.recurringTransactionId);
        await m.addColumn(
          recurringTransactions,
          recurringTransactions.sourceId,
        );
        await m.addColumn(recurringTransactions, recurringTransactions.note);
      }
      if (from < 24) {
        await m.addColumn(
          recurringTransactions,
          recurringTransactions.ratePercent,
        );
        await m.addColumn(
          recurringTransactions,
          recurringTransactions.calcMode,
        );
        await m.createTable(accountReconciliationLogs);
      }
      if (from < 25) {
        await _seedInitialData();
      }
      if (from < 20) {
        await _seedInitialData();
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Future<void> _seedInitialData() async {
    final now = DateTime.now();
    await into(households).insertOnConflictUpdate(
      HouseholdsCompanion.insert(
        id: 'local-household',
        name: 'Keluarga',
        createdAt: now,
        updatedAt: Value(now),
      ),
    );
    const categories = <(String, String)>[
      ('Makan & minum', 'expense'),
      ('Belanja rumah', 'expense'),
      ('Transportasi', 'expense'),
      ('Tagihan', 'expense'),
      ('Kesehatan', 'expense'),
      ('Gaji', 'income'),
      ('Usaha', 'income'),
      ('Hadiah & bantuan', 'income'),
      ('Biaya admin', 'expense'),
    ];
    for (final (name, type) in categories) {
      await into(this.categories).insertOnConflictUpdate(
        CategoriesCompanion.insert(
          id: 'seed-${type}-${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}',
          householdId: 'local-household',
          name: name,
          type: type,
          createdAt: now,
        ),
      );
    }
  }
}

QueryExecutor _openConnection() {
  return LazyDatabase(() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File(p.join(directory.path, 'ffm.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}

AppDatabase createInMemoryDatabaseForTests() =>
    AppDatabase(NativeDatabase.memory());
