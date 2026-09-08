import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/features/assistant/domain/ffm_assistant_form_prefill.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/transaction/data/services/receipt_import_models.dart';

void main() {
  test('mapper transaksi hanya mengirim nilai prefill yang aman', () {
    final prefill = FfmAssistantFormPrefillMapper.fromDraft(
      FfmAssistantDraft(
        kind: FfmAssistantDraftKind.expense,
        createdAt: DateTime(2026, 8, 28),
        amount: 50000,
        fromAccountName: 'Tunai',
        categoryName: 'Makan',
        note: 'Makan siang',
        date: DateTime(2026, 8, 28),
      ),
    );

    expect(prefill.target, FfmAssistantDestination.transactions);
    expect(prefill.values['amount'], '50000');
    expect(prefill.values['fromAccountName'], 'Tunai');
    expect(prefill.values.containsKey('token'), isFalse);
    expect(prefill.isReady, isTrue);
  });

  test('mapper transfer yang kurang rekening tujuan meminta perbaikan', () {
    final prefill = FfmAssistantFormPrefillMapper.fromDraft(
      FfmAssistantDraft(
        kind: FfmAssistantDraftKind.transfer,
        createdAt: DateTime(2026, 8, 28),
        amount: 50000,
        fromAccountName: 'Tunai',
      ),
    );

    expect(prefill.target, FfmAssistantDestination.transactions);
    expect(prefill.missingFields, contains('rekening tujuan'));
    expect(prefill.isReady, isFalse);
  });

  test('mapper anggaran dengan nominal dan kategori', () {
    final prefill = FfmAssistantFormPrefillMapper.fromDraft(
      FfmAssistantDraft(
        kind: FfmAssistantDraftKind.budget,
        createdAt: DateTime(2026, 8, 28),
        amount: 500000,
        categoryName: 'Makan',
      ),
    );

    expect(prefill.target, FfmAssistantDestination.budget);
    expect(prefill.values['amount'], '500000');
    expect(prefill.values['categoryName'], 'Makan');
    expect(prefill.isReady, isTrue);
  });

  test('mapper anggaran tanpa nominal meminta perbaikan', () {
    final prefill = FfmAssistantFormPrefillMapper.fromDraft(
      FfmAssistantDraft(
        kind: FfmAssistantDraftKind.budget,
        createdAt: DateTime(2026, 8, 28),
        categoryName: 'Makan',
      ),
    );

    expect(prefill.target, FfmAssistantDestination.budget);
    expect(prefill.missingFields, contains('nominal'));
    expect(prefill.isReady, isFalse);
  });

  test('mapper master data dengan nama dan tipe', () {
    final prefill = FfmAssistantFormPrefillMapper.fromDraft(
      FfmAssistantDraft(
        kind: FfmAssistantDraftKind.masterData,
        createdAt: DateTime(2026, 8, 28),
        title: 'BCA',
        categoryName: 'rekening',
      ),
    );

    expect(prefill.target, FfmAssistantDestination.masterData);
    expect(prefill.values['title'], 'BCA');
    expect(prefill.values['categoryName'], 'rekening');
  });

  test('mapper master data tanpa nama meminta perbaikan', () {
    final prefill = FfmAssistantFormPrefillMapper.fromDraft(
      FfmAssistantDraft(
        kind: FfmAssistantDraftKind.masterData,
        createdAt: DateTime(2026, 8, 28),
        categoryName: 'rekening',
      ),
    );

    expect(prefill.target, FfmAssistantDestination.masterData);
    expect(prefill.missingFields, contains('nama'));
    expect(prefill.isReady, isFalse);
  });

  test('prefill check mengidentifikasi field yang hilang', () {
    final prefill = FfmAssistantFormPrefillMapper.fromDraft(
      FfmAssistantDraft(
        kind: FfmAssistantDraftKind.expense,
        createdAt: DateTime(2026, 8, 28),
      ),
    );

    expect(prefill.missingFields, isNotEmpty);
    expect(prefill.missingFields, contains('nominal'));
  });

  test('prefill check mengidentifikasi warning', () {
    final prefill = FfmAssistantFormPrefillMapper.fromDraft(
      FfmAssistantDraft(
        kind: FfmAssistantDraftKind.transfer,
        createdAt: DateTime(2026, 8, 28),
        amount: 50000,
        fromAccountName: 'Tunai',
        toAccountName: 'Tunai',
      ),
    );

    expect(prefill.warnings, isNotEmpty);
  });

  test('prefill values tidak mengandung field sensitif', () {
    final prefill = FfmAssistantFormPrefillMapper.fromDraft(
      FfmAssistantDraft(
        kind: FfmAssistantDraftKind.expense,
        createdAt: DateTime(2026, 8, 28),
        amount: 50000,
        fromAccountName: 'Tunai',
        categoryName: 'Makan',
      ),
    );

    expect(prefill.values.containsKey('token'), isFalse);
    expect(prefill.values.containsKey('pin'), isFalse);
    expect(prefill.values.containsKey('password'), isFalse);
    expect(prefill.values.containsKey('secret'), isFalse);
  });

  test('prefill mempertahankan rincian item belanja nota dan nomor struk', () {
    final prefill = FfmAssistantFormPrefillMapper.fromDraft(
      FfmAssistantDraft(
        kind: FfmAssistantDraftKind.expense,
        createdAt: DateTime(2026, 8, 28),
        amount: 85000,
        fromAccountName: 'BCA',
        categoryName: 'Dapur',
        receiptNumber: 'STRUK-999',
        receiptPaidAmount: 100000,
        receiptChangeAmount: 15000,
        items: const [
          ReceiptOcrItem(
            name: 'Minyak Goreng 2L',
            price: 35000,
            quantity: 1,
            unit: 'PCS',
          ),
          ReceiptOcrItem(
            name: 'Beras 5kg',
            price: 50000,
            quantity: 1,
            unit: 'SAK',
          ),
        ],
      ),
    );

    expect(prefill.values['receiptNumber'], 'STRUK-999');
    expect(prefill.values['receiptPaidAmount'], '100000');
    expect(prefill.values['receiptChangeAmount'], '15000');
    expect(prefill.values['itemsJson'], isNotNull);
    expect(prefill.values['itemsJson'], contains('Minyak Goreng 2L'));
    expect(prefill.values['itemsJson'], contains('Beras 5kg'));
  });
}

