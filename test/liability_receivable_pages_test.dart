import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/di/injection.dart';
import 'package:ffm_manager/features/liability/domain/entities/liability_entity.dart';
import 'package:ffm_manager/features/liability/domain/usecases/liability_crud_usecases.dart';
import 'package:ffm_manager/features/liability/presentation/pages/liability_detail_page.dart';
import 'package:ffm_manager/features/liability/presentation/pages/liability_pages.dart';
import 'package:ffm_manager/features/receivable/domain/entities/receivable_entity.dart';
import 'package:ffm_manager/features/receivable/domain/usecases/receivable_crud_usecases.dart';
import 'package:ffm_manager/features/receivable/presentation/pages/receivable_pages.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = createInMemoryDatabaseForTests();
    await configureDependencies(database: db);
  });

  tearDown(() async {
    await db.close();
    await getIt.reset();
  });

  testWidgets('LiabilityListPage menampilkan 7 tab klasifikasi dan kotak pencarian', (tester) async {
    final now = DateTime(2026, 9, 3);
    await SaveLiability(db)(
      LiabilityEntity(
        id: 'liab-tab-test',
        householdId: AppContext.householdId,
        name: 'Cicilan Mobil',
        originalAmount: 50000000,
        remainingBalance: 40000000,
        monthlyInstallment: 2000000,
        startDate: now,
        dueDate: now.add(const Duration(days: 45)), // > 30 hari
        updatedAt: now,
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: LiabilityListPage(),
      ),
    );
    await tester.pumpAndSettle();

    // Verifikasi ada 7 tab
    expect(find.textContaining('Semua'), findsOneWidget);
    expect(find.textContaining('Aktif'), findsOneWidget);
    expect(find.textContaining('Terlambat'), findsOneWidget);
    expect(find.textContaining('0-7 hari'), findsOneWidget);
    expect(find.textContaining('8-30 hari'), findsOneWidget);
    expect(find.textContaining('> 30 hari'), findsOneWidget);
    expect(find.textContaining('Lunas'), findsOneWidget);

    // Verifikasi ada kotak pencarian
    expect(find.byType(TextField), findsOneWidget);

    // Verifikasi item tampil
    expect(find.text('Cicilan Mobil'), findsOneWidget);
  });

  testWidgets('ReceivableListPage menampilkan 7 tab klasifikasi dan kotak pencarian', (tester) async {
    final now = DateTime(2026, 9, 3);
    await SaveReceivable(db)(
      ReceivableEntity(
        id: 'rec-tab-test',
        householdId: AppContext.householdId,
        name: 'Piutang Mitra',
        originalAmount: 10000000,
        remainingBalance: 5000000,
        monthlyInstallment: 1000000,
        startDate: now,
        dueDate: now.add(const Duration(days: 15)), // 8-30 hari
        updatedAt: now,
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: ReceivableListPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Semua'), findsOneWidget);
    expect(find.textContaining('Aktif'), findsOneWidget);
    expect(find.textContaining('Terlambat'), findsOneWidget);
    expect(find.textContaining('0-7 hari'), findsOneWidget);
    expect(find.descendant(of: find.byType(TabBar), matching: find.textContaining('8-30 hari')), findsOneWidget);
    expect(find.textContaining('> 30 hari'), findsOneWidget);
    expect(find.textContaining('Lunas'), findsOneWidget);

    expect(find.text('Piutang Mitra'), findsOneWidget);
  });

  testWidgets('LiabilityDetailPage menampilkan tombol Catat Pembayaran Hutang dan riwayat', (tester) async {
    final now = DateTime(2026, 9, 3);
    final liability = LiabilityEntity(
      id: 'liab-detail-test',
      householdId: AppContext.householdId,
      name: 'Hutang Bank',
      originalAmount: 10000000,
      remainingBalance: 7500000,
      monthlyInstallment: 500000,
      startDate: now,
      dueDate: now.add(const Duration(days: 20)),
      updatedAt: now,
      note: 'Cicilan rumah',
    );

    await SaveLiability(db)(liability);

    await tester.pumpWidget(
      MaterialApp(
        home: LiabilityDetailPage(liability: liability),
      ),
    );
    await tester.pumpAndSettle();

    // Verifikasi tombol pembayaran ada
    expect(find.text('Catat Pembayaran Hutang'), findsOneWidget);
    expect(find.text('Cicilan rumah'), findsOneWidget);

    // Scroll untuk memeriksa riwayat
    await tester.scrollUntilVisible(
      find.text('Riwayat Pembayaran Kas'),
      300,
    );
    expect(find.text('Riwayat Pembayaran Kas'), findsOneWidget);
  });

  testWidgets('ReceivableDetailPage menampilkan tombol Terima Pembayaran Piutang dan riwayat', (tester) async {
    final now = DateTime(2026, 9, 3);
    final receivable = ReceivableEntity(
      id: 'rec-detail-test',
      householdId: AppContext.householdId,
      name: 'Pinjaman Kerabat',
      originalAmount: 3000000,
      remainingBalance: 2000000,
      monthlyInstallment: 500000,
      startDate: now,
      dueDate: now.add(const Duration(days: 10)),
      updatedAt: now,
      note: 'Pinjaman modal usaha',
    );

    await SaveReceivable(db)(receivable);

    await tester.pumpWidget(
      MaterialApp(
        home: ReceivableDetailPage(receivable: receivable),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Terima Pembayaran Piutang'), findsOneWidget);
    expect(find.text('Pinjaman modal usaha'), findsOneWidget);

    // Scroll untuk memeriksa riwayat
    await tester.scrollUntilVisible(
      find.text('Riwayat Penerimaan Kas'),
      300,
    );
    expect(find.text('Riwayat Penerimaan Kas'), findsOneWidget);
  });
}
