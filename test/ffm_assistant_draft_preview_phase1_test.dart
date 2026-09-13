import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/assistant/presentation/widgets/chat/ffm_assistant_draft_preview.dart';
import 'package:ffm_manager/features/transaction/data/services/receipt_import_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpPreview(WidgetTester tester, FfmAssistantDraft draft) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: FfmAssistantDraftPreview(draft: draft),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Buka rincian lengkap draf'));
    await tester.pumpAndSettle();
  }

  testWidgets('preview pemasukan memakai field canonical', (tester) async {
    await pumpPreview(
      tester,
      FfmAssistantDraft(
        kind: FfmAssistantDraftKind.income,
        createdAt: DateTime(2026, 9, 13),
        amount: 5000000,
        toAccountName: 'BCA',
        categoryName: 'Gaji',
        partyName: 'PT Maju',
        merchantName: 'Payroll',
        date: DateTime(2026, 9, 12),
        tags: 'bulanan, kantor',
        source: 'payroll',
        sourceId: 'PAY-09',
        formValues: const {'jaminanPalsu': 'jangan tampil'},
      ),
    );

    expect(find.text('Pemasukan'), findsOneWidget);
    expect(find.text('Rp5.000.000'), findsWidgets);
    expect(find.text('BCA'), findsOneWidget);
    expect(find.text('Gaji'), findsOneWidget);
    expect(find.text('PT Maju'), findsOneWidget);
    expect(find.text('Payroll'), findsOneWidget);
    expect(find.text('12/09/2026'), findsOneWidget);
    expect(find.text('bulanan, kantor'), findsOneWidget);
    expect(find.text('payroll'), findsOneWidget);
    expect(find.text('PAY-09'), findsOneWidget);
    expect(find.text('jaminanPalsu'), findsNothing);
    expect(find.text('jangan tampil'), findsNothing);
  });

  testWidgets('preview pengeluaran kompleks merinci receipt canonical', (
    tester,
  ) async {
    await pumpPreview(
      tester,
      FfmAssistantDraft(
        kind: FfmAssistantDraftKind.expense,
        createdAt: DateTime(2026, 9, 13),
        amount: 107500,
        fromAccountName: 'Kas',
        categoryName: 'Belanja',
        merchantName: 'Pasar Baru',
        partyName: 'Ibu',
        date: DateTime(2026, 9, 13),
        tags: 'dapur',
        items: const [
          ReceiptOcrItem(name: 'Beras', price: 50000, quantity: 2, unit: 'kg'),
        ],
        tax: 10000,
        discount: 2500,
        receiptPaidAmount: 110000,
        receiptChangeAmount: 2500,
        receiptNumber: 'N-100',
        receiptRawText: 'TOTAL 107500',
        attachmentPaths: const [r'C:\receipt\nota.jpg'],
        source: 'assistant',
      ),
    );

    expect(find.text('Pengeluaran'), findsOneWidget);
    expect(
      find.text('Beras · 2.0 x Rp50.000 = Rp100.000 · kg'),
      findsOneWidget,
    );
    expect(find.text('Subtotal item'), findsOneWidget);
    expect(find.text('Rp100.000'), findsOneWidget);
    expect(find.text('Rp10.000'), findsOneWidget);
    expect(find.text('Rp2.500'), findsWidgets);
    expect(find.text('Rp110.000'), findsOneWidget);
    expect(find.text('N-100'), findsOneWidget);
    expect(find.text('TOTAL 107500'), findsOneWidget);
    expect(find.text('nota.jpg'), findsOneWidget);
  });

  testWidgets('preview transfer memperlihatkan asal tujuan dan fee', (
    tester,
  ) async {
    await pumpPreview(
      tester,
      FfmAssistantDraft(
        kind: FfmAssistantDraftKind.transfer,
        createdAt: DateTime(2026, 9, 13),
        amount: 300000,
        fromAccountName: 'BCA',
        toAccountName: 'Jago',
        adminFee: 2500,
        date: DateTime(2026, 9, 11),
        source: 'assistant',
      ),
    );

    expect(find.text('Transfer Dana'), findsOneWidget);
    expect(find.text('BCA'), findsWidgets);
    expect(find.text('Jago'), findsOneWidget);
    expect(find.text('Rp300.000'), findsWidgets);
    expect(find.text('Biaya Admin'), findsOneWidget);
    expect(find.text('Rp2.500'), findsOneWidget);
    expect(find.text('11/09/2026'), findsOneWidget);
  });
}
