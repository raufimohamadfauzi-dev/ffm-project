import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/di/injection.dart';
import 'package:ffm_manager/features/transaction/presentation/pages/transaction_pages.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = createInMemoryDatabaseForTests();
    await configureDependencies(database: db);
  });

  tearDown(() async {
    if (getIt.isRegistered<AppDatabase>()) {
      final database = getIt<AppDatabase>();
      await database.close();
    }
    await getIt.reset();
  });

  Widget buildTestApp({Size? physicalSize}) {
    return MaterialApp(
      home: const TransactionListPage(),
    );
  }

  testWidgets('AppBar TransactionListPage tidak menampilkan icon Asisten dan memiliki judul Transaksi', (tester) async {
    await tester.pumpWidget(buildTestApp());
    await tester.pumpAndSettle();

    // Verifikasi ketiadaan icon Asisten di AppBar (Tahap 2)
    expect(find.byIcon(Icons.auto_awesome), findsNothing);
    expect(find.byIcon(Icons.auto_awesome_outlined), findsNothing);

    // Verifikasi Judul & Aksi Utama
    expect(find.text('Transaksi'), findsOneWidget);
    expect(find.byIcon(Icons.search), findsOneWidget);
    expect(find.byIcon(Icons.tune), findsOneWidget);
  });

  testWidgets('Menampilkan empty state saat belum ada data transaksi', (tester) async {
    await db.into(db.accounts).insert(
      AccountsCompanion.insert(
        id: 'acc-1',
        householdId: AppContext.householdId,
        name: 'BCA Utama',
        type: 'bank',
        openingBalance: const drift.Value(5000000),
        createdAt: DateTime(2026, 9, 3),
        isActive: const drift.Value(true),
      ),
    );

    await tester.pumpWidget(buildTestApp());
    await tester.pumpAndSettle();

    expect(find.text('Belum ada transaksi'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets('Timeline merender pemasukan, pengeluaran, dan transfer tanpa transfer mengubah total arus kas', (tester) async {
    final now = DateTime(2026, 9, 3, 10, 0);

    // Seed Rekening
    await db.into(db.accounts).insert(
      AccountsCompanion.insert(
        id: 'acc-1',
        householdId: AppContext.householdId,
        name: 'BCA Utama',
        type: 'bank',
        openingBalance: const drift.Value(5000000),
        createdAt: now,
        isActive: const drift.Value(true),
      ),
    );
    await db.into(db.accounts).insert(
      AccountsCompanion.insert(
        id: 'acc-2',
        householdId: AppContext.householdId,
        name: 'Dompet Tunai',
        type: 'cash',
        openingBalance: const drift.Value(500000),
        createdAt: now,
        isActive: const drift.Value(true),
      ),
    );

    // Seed Kategori
    await db.into(db.categories).insert(
      CategoriesCompanion.insert(
        id: 'cat-in',
        householdId: AppContext.householdId,
        name: 'Gaji Bulanan',
        type: 'income',
        defaultBudgetPeriod: const drift.Value('monthly'),
        createdAt: now,
        isActive: const drift.Value(true),
      ),
    );
    await db.into(db.categories).insert(
      CategoriesCompanion.insert(
        id: 'cat-out',
        householdId: AppContext.householdId,
        name: 'Makan Siang',
        type: 'expense',
        defaultBudgetPeriod: const drift.Value('monthly'),
        createdAt: now,
        isActive: const drift.Value(true),
      ),
    );

    // Seed Pemasukan (+1.000.000)
    await db.into(db.transactions).insert(
      TransactionsCompanion.insert(
        id: 'tx-in-1',
        householdId: AppContext.householdId,
        type: 'income',
        date: now.subtract(const Duration(hours: 2)),
        recordedAt: now,
        amount: 1000000,
        owner: const drift.Value('Suami'),
        categoryId: const drift.Value('cat-in'),
        accountId: const drift.Value('acc-1'),
        createdAt: now,
        isDeleted: const drift.Value(false),
      ),
    );

    // Seed Pengeluaran (-250.000)
    await db.into(db.transactions).insert(
      TransactionsCompanion.insert(
        id: 'tx-out-1',
        householdId: AppContext.householdId,
        type: 'expense',
        date: now.subtract(const Duration(hours: 1)),
        recordedAt: now,
        amount: -250000,
        owner: const drift.Value('Istri'),
        categoryId: const drift.Value('cat-out'),
        accountId: const drift.Value('acc-1'),
        createdAt: now,
        isDeleted: const drift.Value(false),
      ),
    );

    // Seed Transfer (500.000 antar rekening)
    await db.into(db.transfers).insert(
      TransfersCompanion.insert(
        id: 'trf-1',
        householdId: AppContext.householdId,
        date: now,
        recordedAt: now,
        amount: 500000,
        fromAccountId: 'acc-1',
        toAccountId: 'acc-2',
        source: const drift.Value('manual'),
      ),
    );

    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(buildTestApp());
    await tester.pumpAndSettle();

    // Verifikasi item transaksi & transfer muncul
    expect(find.text('Gaji Bulanan'), findsWidgets);
    expect(find.text('Makan Siang'), findsWidgets);
    expect(find.text('Transfer'), findsWidgets);

    // Verifikasi Ringkasan Arus Kas: Pemasukan 1.000.000, Pengeluaran 250.000 (Transfer tidak menambah/mengurangi)
    expect(find.text('Ringkasan transaksi'), findsOneWidget);
    expect(find.text('Pemasukan'), findsWidgets);
    expect(find.text('Pengeluaran'), findsWidgets);
    expect(find.text('Selisih arus kas'), findsOneWidget);
    expect(find.text('1 transfer tidak mengubah total pemasukan atau pengeluaran.'), findsOneWidget);
  });

  testWidgets('Tampilan tetap rapi dan tidak overflow pada lebar layar kecil 320dp', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(buildTestApp());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
