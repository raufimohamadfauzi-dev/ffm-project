import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/features/transaction/data/services/receipt_import_service.dart';

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

  test(
    'prompt LLM eksternal mendukung foto dan satu atau banyak transaksi',
    () {
      final prompt = ReceiptImportService.buildExternalLlmBatchPrompt();

      expect(prompt, contains('ffm-transaction-batch-v1'));
      expect(prompt, contains('Balas HANYA dengan JSON valid'));
      expect(prompt, contains('foto nota'));
      expect(prompt, contains('Satu nota berarti satu transaksi'));
      expect(prompt, contains('transfer'));
      expect(prompt, contains('items'));
      expect(prompt, contains('unit_price'));
    },
  );

  test('JSON nota di dalam code fence tetap bisa diimpor', () {
    final result = ReceiptImportService.parseJson('''
```json
{
  "format": "ffm-receipt-draft-v1",
  "receipt": {
    "merchant": "Warung",
    "total": 12000,
    "items": [{"name": "Nasi", "quantity": 1, "amount": 12000}]
  }
}
```
''');

    expect(result.merchant, 'Warung');
    expect(result.items.single.name, 'Nasi');
  });

  test('template JSON kosong memakai schema FFM dan bisa diimpor', () {
    final template = ReceiptImportService.templateJson();
    final result = ReceiptImportService.parseJson(template);

    expect(template, contains('ffm-receipt-draft-v1'));
    expect(template, contains('unit_price'));
    expect(result.items, hasLength(1));
    expect(result.items.single.name, 'Nama barang');
  });

  test('JSON batch membaca banyak transaksi dan rincian item', () {
    final transactions = List.generate(
      10,
      (index) => {
        'type': 'expense',
        'date': '2026-08-20',
        'amount': (index + 1) * 10000,
        'merchant': 'Toko ${index + 1}',
        'items': [
          {
            'name': 'Barang ${index + 1}',
            'quantity': 2,
            'unit_price': 5000,
            'amount': 10000,
          },
        ],
      },
    );
    final result = ReceiptImportService.parseBatchJson(
      jsonEncode({
        'format': 'ffm-transaction-batch-v1',
        'transactions': transactions,
      }),
    );

    expect(result.entries, hasLength(10));
    expect(result.entries.first.items.single.name, 'Barang 1');
    expect(result.entries.first.items.single.calculatedTotal, 10000);
    expect(result.entries.last.amount, 100000);
    expect(result.warnings, isEmpty);
  });

  test('JSON batch membawa petunjuk pos anggaran dari LLM', () {
    final result = ReceiptImportService.parseBatchJson(
      jsonEncode({
        'format': 'ffm-transaction-batch-v1',
        'transactions': [
          {
            'type': 'expense',
            'date': '2026-08-20',
            'amount': 35000,
            'budget_name': 'Belanja pasar',
            'budget_id': 'budget-pasar',
            'category_id': 'cat-belanja',
          },
        ],
      }),
    );

    expect(result.entries.single.budgetName, 'Belanja pasar');
    expect(result.entries.single.budgetId, 'budget-pasar');
    expect(result.entries.single.categoryId, 'cat-belanja');
  });

  test('template JSON batch bisa disalin dan diimpor', () {
    final template = ReceiptImportService.templateBatchJson();
    final result = ReceiptImportService.parseBatchJson(template);

    expect(template, contains('ffm-transaction-batch-v1'));
    expect(result.entries, hasLength(1));
    expect(result.entries.single.items, hasLength(1));
  });

  test('JSON mutasi bank membaca pemasukan, pengeluaran, transfer, dan saldo akhir', () {
    final result = ReceiptImportService.parseBatchJson(
      jsonEncode({
        'format': 'ffm-bank-statement-v1',
        'statement': {
          'account_name': 'SeaBank',
          'account_id': 'account-seabank',
          'opening_balance': 1000000,
          'closing_balance': 650000,
          'period_start': '2026-08-01',
          'period_end': '2026-08-03',
        },
        'mutations': [
          {
            'type': 'income',
            'date': '2026-08-01',
            'amount': 1000000,
            'description': 'Panen pepaya',
          },
          {
            'type': 'expense',
            'date': '2026-08-02',
            'amount': 250000,
            'description': 'Bayar listrik',
          },
          {
            'type': 'transfer',
            'date': '2026-08-03',
            'amount': 100000,
            'from_account_id': 'account-seabank',
            'to_account_id': 'account-gopay',
          },
        ],
      }),
    );

    expect(result.isBankStatement, isTrue);
    expect(result.statementAccountName, 'SeaBank');
    expect(result.closingBalance, 650000);
    expect(result.entries, hasLength(3));
    expect(result.entries[0].type, 'income');
    expect(result.entries[1].type, 'expense');
    expect(result.entries[2].type, 'transfer');
    expect(result.entries[2].fromAccountId, 'account-seabank');
    expect(result.entries[2].toAccountId, 'account-gopay');
    expect(result.warnings, isEmpty);
  });

  test('importer terpadu mendeteksi JSON nota berpagar sebagai satu transaksi', () {
    final result = ReceiptImportService.parseBatchJson('''
    ```json
    {
      "format": "ffm-receipt-draft-v1",
      "receipt": {
        "merchant": "Warung",
        "total": 12000,
        "items": [{"name": "Nasi", "quantity": 1, "amount": 12000}]
      }
    }
    ```
    ''');

    expect(result.entries, hasLength(1));
    expect(result.entries.single.amount, 12000);
    expect(result.entries.single.items.single.name, 'Nasi');
  });
}
