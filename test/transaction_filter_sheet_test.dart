import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/transaction/presentation/widgets/transaction_filter_sheet.dart';

void main() {
  final now = DateTime(2026, 9, 3);
  final accounts = [
    Account(
      id: 'acc-1',
      householdId: 'h-1',
      name: 'BCA Utama',
      type: 'bank',
      openingBalance: 1000000,
      createdAt: now,
      isActive: true,
      isArchived: false,
    ),
  ];
  final List<Category> categories = [
    Category(
      id: 'cat-1',
      householdId: 'h-1',
      name: 'Makanan',
      type: 'expense',
      defaultBudgetPeriod: 'monthly',
      createdAt: now,
      isActive: true,
    ),
  ];
  final List<Merchant> merchants = [
    Merchant(
      id: 'm-1',
      householdId: 'h-1',
      name: 'Warung Bu Siti',
      createdAt: now,
      isActive: true,
    ),
  ];
  final owners = ['Suami', 'Istri'];

  Widget buildLauncher({
    required void Function(TransactionFilter) onResult,
    String typeFilter = 'Semua',
    bool currentMonthOnly = false,
    String? accountId,
    String? categoryId,
    String? merchantId,
    String? owner,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              final result = await showModalBottomSheet<TransactionFilter>(
                context: context,
                builder: (_) => TransactionFilterSheet(
                  typeFilter: typeFilter,
                  currentMonthOnly: currentMonthOnly,
                  accounts: accounts,
                  categories: categories,
                  merchants: merchants,
                  owners: owners,
                  accountId: accountId,
                  categoryId: categoryId,
                  merchantId: merchantId,
                  owner: owner,
                ),
              );
              if (result != null) onResult(result);
            },
            child: const Text('Buka'),
          ),
        ),
      ),
    );
  }

  testWidgets('menerapkan jenis transaksi dari sheet filter', (tester) async {
    TransactionFilter? result;
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(buildLauncher(onResult: (value) => result = value));

    await tester.tap(find.text('Buka'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pemasukan'));
    await tester.tap(find.text('Terapkan'));
    await tester.pumpAndSettle();

    expect(result?.typeFilter, 'Pemasukan');
    expect(result?.currentMonthOnly, isFalse);
  });

  testWidgets('menerapkan filter merchant dan pemilik dari dropdown', (tester) async {
    TransactionFilter? result;
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(buildLauncher(onResult: (value) => result = value));

    await tester.tap(find.text('Buka'));
    await tester.pumpAndSettle();

    // Pilih Merchant
    await tester.tap(find.text('Semua toko / merchant'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Warung Bu Siti').last);
    await tester.pumpAndSettle();

    // Pilih Pemilik
    await tester.tap(find.text('Semua anggota'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Istri').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Terapkan'));
    await tester.pumpAndSettle();

    expect(result?.merchantId, 'm-1');
    expect(result?.owner, 'Istri');
  });

  testWidgets('reset mengembalikan filter default termasuk merchant dan owner', (tester) async {
    TransactionFilter? result;
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      buildLauncher(
        onResult: (value) => result = value,
        typeFilter: 'Pengeluaran',
        currentMonthOnly: true,
        merchantId: 'm-1',
        owner: 'Istri',
      ),
    );

    await tester.tap(find.text('Buka'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();

    expect(result?.typeFilter, 'Semua');
    expect(result?.currentMonthOnly, isFalse);
    expect(result?.accountId, isNull);
    expect(result?.categoryId, isNull);
    expect(result?.merchantId, isNull);
    expect(result?.owner, isNull);
  });
}
