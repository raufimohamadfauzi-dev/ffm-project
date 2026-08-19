import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/features/transaction/data/services/receipt_import_service.dart';
import 'package:ffm_manager/features/transaction/data/services/receipt_ocr_service.dart';

void main() {
  test('impor JSON nota membaca item, nominal, dan pecahan', () {
    const json = '''
{
  "format": "ffm-receipt-draft-v1",
  "receipt": {
    "merchant": "Sayur Segar",
    "date": "2026-08-16",
    "time": "11:04:32",
    "total": 10500,
    "paid_amount": 20500,
    "change_amount": 10000,
    "raw_text": "Indomilk Kids Coklat 1 PCS 3.500 3.500",
    "items": [
      {"name": "Indomilk Kids Coklat", "quantity": 1, "unit": "PCS", "unit_price": 3500, "amount": 3500},
      {"name": "Mie Sakura", "quantity": 3, "unit": "PCS", "unit_price": 2000, "amount": 6000},
      {"name": "Sosin", "quantity": 0.5, "unit": "IKA", "unit_price": 2000, "amount": 1000}
    ]
  }
}
''';

    final result = ReceiptImportService.parseJson(json);

    expect(result.merchant, 'Sayur Segar');
    expect(result.total, 10500);
    expect(result.paidAmount, 20500);
    expect(result.changeAmount, 10000);
    expect(result.items, hasLength(3));
    expect(result.items[1].quantity, 3);
    expect(result.items[1].calculatedTotal, 6000);
    expect(result.items[2].quantity, 0.5);
    expect(result.items[2].calculatedTotal, 1000);
    expect(result.itemsTotal, 10500);
    expect(result.validationWarnings, isEmpty);
  });

  test('teks manual nota dapat membaca item dan total', () {
    final result = ReceiptOcrService().parseText('''
Sayur Segar
Indomilk Kids Coklat
1 PCS 3,500 3,500
Mie Sakura
3 PCS 2,000 6,000
Sosin
.5 IKA 2,000 1,000
ITEM : 4.5 Total : 10,500
Bayar : 20,500
Kembali : 10,000
''');

    expect(result.items, isNotEmpty);
    expect(result.total, 10500);
    expect(result.paidAmount, 20500);
    expect(result.changeAmount, 10000);
  });

  test('ekspor JSON mempertahankan total baris dan kuantitas nota', () {
    const sourceJson = '''
{
  "format": "ffm-receipt-draft-v1",
  "receipt": {
    "merchant": "Sayur Segar",
    "total": 7000,
    "items": [
      {"name": "Mie Sakura", "quantity": 3, "unit": "PCS", "unit_price": 2000, "amount": 6000},
      {"name": "Sosin", "quantity": 0.5, "unit": "IKA", "unit_price": 2000, "amount": 1000}
    ]
  }
}
''';
    final result = ReceiptImportService.parseJson(sourceJson);
    final json = ReceiptImportService.toJson(result);
    final imported = ReceiptImportService.parseJson(json);

    expect(imported.items, hasLength(2));
    expect(imported.items[0].quantity, 3);
    expect(imported.items[0].calculatedTotal, 6000);
    expect(imported.items[1].quantity, 0.5);
    expect(imported.items[1].calculatedTotal, 1000);
    expect(imported.itemsTotal, 7000);
  });

  test('prompt Gemini meminta JSON tanpa mengaktifkan koneksi aplikasi', () {
    final prompt = ReceiptImportService.buildGeminiPrompt(
      rawText: 'Mie Sakura 3 PCS 2.000 6.000',
    );

    expect(prompt, contains('ffm-receipt-draft-v1'));
    expect(prompt, contains('Balas HANYA dengan JSON valid'));
    expect(prompt, contains('Mie Sakura'));
  });
}
