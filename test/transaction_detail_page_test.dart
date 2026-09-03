import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/transaction/domain/entities/transaction_entity.dart';
import 'package:ffm_manager/features/transaction/presentation/pages/transaction_detail_page.dart';

void main() {
  Widget buildTestWidget({
    required TransactionWithItems entry,
    String? categoryLabel,
    String? accountLabel,
    String? merchantLabel,
    VoidCallback? onEdit,
    VoidCallback? onDelete,
  }) {
    return MaterialApp(
      home: TransactionDetailPage(
        entry: entry,
        categoryLabel: categoryLabel,
        accountLabel: accountLabel,
        merchantLabel: merchantLabel,
        onEdit: onEdit,
        onDelete: onDelete,
      ),
    );
  }

  testWidgets('TransactionDetailPage merender rincian transaksi lengkap dan item belanja dengan subtotal', (tester) async {
    final now = DateTime(2026, 9, 3, 14, 30);
    final entry = TransactionWithItems(
      transaction: Transaction(
        id: 'tx-detail-1',
        householdId: 'house-1',
        type: 'expense',
        categoryId: 'cat-1',
        accountId: 'acc-1',
        merchantId: 'merch-1',
        amount: -150000,
        date: now,
        recordedAt: now,
        createdAt: now,
        receiptNumber: 'NOTA-9988',
        receiptPaidAmount: 200000,
        receiptChangeAmount: 50000,
        source: 'ocr',
        location: 'Jl. Merdeka No. 1',
        partyName: 'Istri',
        note: 'Belanja persediaan dapur mingguan',
        receiptRawText: 'SUPERMARKET ABC\nTOTAL: 150.000\nTUNAI: 200.000\nKEMBALI: 50.000',
        isArchived: false,
        isDeleted: false,
      ),
      items: [
        TransactionItem(
          id: 'item-1',
          transactionId: 'tx-detail-1',
          itemName: 'Minyak Goreng 2L',
          qty: 2,
          unit: 'pouch',
          price: 35000,
          amount: 70000,
          createdAt: now,
        ),
        TransactionItem(
          id: 'item-2',
          transactionId: 'tx-detail-1',
          itemName: 'Beras Pandan Wangi 5kg',
          qty: 1,
          unit: 'karung',
          price: 80000,
          amount: 80000,
          createdAt: now,
        ),
      ],
      tags: const ['dapur', 'bulanan'],
    );

    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      buildTestWidget(
        entry: entry,
        categoryLabel: 'Kebutuhan Dapur',
        accountLabel: 'BCA Utama',
        merchantLabel: 'Supermarket ABC',
      ),
    );
    await tester.pumpAndSettle();

    // Verifikasi Header & Detail Pokok
    expect(find.text('Detail transaksi'), findsOneWidget);
    expect(find.text('Uang keluar'), findsOneWidget);
    expect(find.text('Kebutuhan Dapur'), findsOneWidget);
    expect(find.text('BCA Utama'), findsOneWidget);
    expect(find.text('Supermarket ABC'), findsOneWidget);
    expect(find.text('NOTA-9988'), findsOneWidget);
    expect(find.text('Rp 200000'), findsOneWidget);
    expect(find.text('Rp 50000'), findsOneWidget);
    expect(find.text('Jl. Merdeka No. 1'), findsOneWidget);
    expect(find.text('Belanja persediaan dapur mingguan'), findsOneWidget);

    // Verifikasi Rincian Item Belanja & Subtotal
    expect(find.text('Rincian belanja'), findsOneWidget);
    expect(find.text('2 item'), findsOneWidget);
    expect(find.text('Minyak Goreng 2L'), findsOneWidget);
    expect(find.text('Jumlah: 2.0 pouch · Harga satuan: Rp 35000'), findsOneWidget);
    expect(find.text('Beras Pandan Wangi 5kg'), findsOneWidget);
    expect(find.text('Jumlah: 1.0 karung · Harga satuan: Rp 80000'), findsOneWidget);
    expect(find.text('Subtotal Item'), findsOneWidget);

    // Verifikasi Tags & OCR Text
    expect(find.text('dapur, bulanan'), findsOneWidget);
    expect(find.text('Teks Mentah Nota / OCR'), findsOneWidget);

    // Verifikasi Tombol Edit & Hapus
    expect(find.byIcon(Icons.edit_outlined), findsWidgets);
    expect(find.byIcon(Icons.delete_outline), findsWidgets);
  });

  testWidgets('Tombol Edit dan Hapus memicu callback dengan tepat', (tester) async {
    final now = DateTime(2026, 9, 3);
    final entry = TransactionWithItems(
      transaction: Transaction(
        id: 'tx-detail-2',
        householdId: 'house-1',
        type: 'income',
        amount: 5000000,
        date: now,
        recordedAt: now,
        createdAt: now,
        isArchived: false,
        isDeleted: false,
      ),
    );

    var editTriggered = false;
    var deleteTriggered = false;

    await tester.pumpWidget(
      buildTestWidget(
        entry: entry,
        onEdit: () => editTriggered = true,
        onDelete: () => deleteTriggered = true,
      ),
    );
    await tester.pumpAndSettle();

    // Klik Edit di Bottom Button
    final editButton = find.widgetWithText(FilledButton, 'Edit');
    expect(editButton, findsOneWidget);
    await tester.tap(editButton);
    await tester.pumpAndSettle();
    expect(editTriggered, isTrue);

    // Klik Hapus di Bottom Button
    final deleteButton = find.widgetWithText(OutlinedButton, 'Hapus');
    expect(deleteButton, findsOneWidget);
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();

    // Dialog konfirmasi muncul
    expect(find.text('Hapus transaksi?'), findsOneWidget);
    final confirmButton = find.widgetWithText(FilledButton, 'Hapus');
    await tester.tap(confirmButton);
    await tester.pumpAndSettle();
    expect(deleteTriggered, isTrue);
  });
}
