import 'dart:convert';

import 'receipt_ocr_service.dart';

class ReceiptImportException implements Exception {
  const ReceiptImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ReceiptBatchEntry {
  const ReceiptBatchEntry({
    required this.type,
    required this.date,
    required this.amount,
    required this.items,
    this.time,
    this.merchant,
    this.categoryId,
    this.accountId,
    this.partyName,
    this.note,
  });

  final String type;
  final DateTime? date;
  final String? time;
  final int? amount;
  final String? merchant;
  final String? categoryId;
  final String? accountId;
  final String? partyName;
  final String? note;
  final List<ReceiptOcrItem> items;
}

class ReceiptBatchImport {
  const ReceiptBatchImport({required this.entries, required this.warnings});

  final List<ReceiptBatchEntry> entries;
  final List<String> warnings;
}

class ReceiptImportService {
  const ReceiptImportService._();

  static const format = 'ffm-receipt-draft-v1';
  static const batchFormat = 'ffm-transaction-batch-v1';

  static ReceiptOcrResult parseJson(String rawJson, {String? imagePath}) {
    dynamic decoded;
    try {
      decoded = jsonDecode(rawJson);
    } on FormatException catch (error) {
      throw ReceiptImportException('JSON tidak valid: ${error.message}');
    }
    if (decoded is! Map) {
      throw const ReceiptImportException('Format JSON harus berupa objek.');
    }
    final root = Map<String, dynamic>.from(decoded);
    final rawReceipt = root['receipt'];
    final data = rawReceipt is Map
        ? Map<String, dynamic>.from(rawReceipt)
        : root;
    final declaredFormat = root['format']?.toString();
    if (declaredFormat != null &&
        declaredFormat.isNotEmpty &&
        declaredFormat != format) {
      throw ReceiptImportException(
        'Format $declaredFormat belum didukung. Pakai $format.',
      );
    }

    final warnings = <String>[];
    final itemValue = data['items'] ?? data['lines'];
    final items = <ReceiptOcrItem>[];
    if (itemValue is List) {
      for (var index = 0; index < itemValue.length; index++) {
        final raw = itemValue[index];
        if (raw is! Map) {
          warnings.add(
            'Baris item ke-${index + 1} dilewati karena bukan objek.',
          );
          continue;
        }
        final item = _parseItem(
          Map<String, dynamic>.from(raw),
          index,
          warnings,
        );
        if (item != null) items.add(item);
      }
    } else if (itemValue != null) {
      warnings.add('Field items harus berupa array.');
    }

    final result = ReceiptOcrResult(
      merchant: _text(data['merchant'] ?? data['toko']),
      total: _money(data['total'] ?? data['grand_total']),
      date: _date(data['date'] ?? data['tanggal']),
      time: _text(data['time'] ?? data['waktu']),
      paidAmount: _money(data['paid_amount'] ?? data['bayar']),
      changeAmount: _money(data['change_amount'] ?? data['kembalian']),
      receiptNumber: _text(data['receipt_number'] ?? data['nomor_nota']),
      rawText: _text(data['raw_text'] ?? data['teks_asli']) ?? '',
      categoryId: _text(data['category_id']),
      imagePath: imagePath ?? _text(data['image_path']),
      items: items,
      warnings: warnings,
    );
    if (result.total == null && result.items.isEmpty) {
      throw const ReceiptImportException(
        'JSON belum memiliki total atau item nota yang bisa diimpor.',
      );
    }
    return result;
  }

  static ReceiptBatchImport parseBatchJson(String rawJson) {
    dynamic decoded;
    try {
      decoded = jsonDecode(rawJson);
    } on FormatException catch (error) {
      throw ReceiptImportException('JSON tidak valid: ${error.message}');
    }
    if (decoded is! Map) {
      throw const ReceiptImportException('JSON batch harus berupa objek.');
    }
    final root = Map<String, dynamic>.from(decoded);
    final declaredFormat = root['format']?.toString();
    if (declaredFormat != null &&
        declaredFormat.isNotEmpty &&
        declaredFormat != batchFormat &&
        declaredFormat != format) {
      throw ReceiptImportException(
        'Format $declaredFormat belum didukung. Pakai $batchFormat.',
      );
    }
    final rawTransactions = root['transactions'];
    if (rawTransactions is! List) {
      final receipt = parseJson(rawJson);
      return ReceiptBatchImport(
        entries: [
          ReceiptBatchEntry(
            type: 'expense',
            date: receipt.date,
            time: receipt.time,
            amount: receipt.total ?? receipt.itemsTotal,
            merchant: receipt.merchant,
            categoryId: receipt.categoryId,
            note: receipt.rawText.trim().isEmpty ? null : receipt.rawText,
            items: receipt.items,
          ),
        ],
        warnings: receipt.validationWarnings,
      );
    }

    final warnings = <String>[];
    final entries = <ReceiptBatchEntry>[];
    for (var index = 0; index < rawTransactions.length; index++) {
      final raw = rawTransactions[index];
      if (raw is! Map) {
        warnings.add('Transaksi ke-${index + 1} dilewati karena bukan objek.');
        continue;
      }
      final data = Map<String, dynamic>.from(raw);
      final typeValue = _text(data['type'] ?? data['jenis'])?.toLowerCase();
      if (typeValue != 'income' && typeValue != 'expense') {
        warnings.add(
          'Transaksi ke-${index + 1} harus memiliki type income atau expense.',
        );
        continue;
      }
      final items = <ReceiptOcrItem>[];
      final rawItems = data['items'] ?? data['lines'];
      if (rawItems is List) {
        for (var itemIndex = 0; itemIndex < rawItems.length; itemIndex++) {
          final item = rawItems[itemIndex];
          if (item is! Map) {
            warnings.add(
              'Transaksi ke-${index + 1}, item ke-${itemIndex + 1} dilewati karena bukan objek.',
            );
            continue;
          }
          final parsed = _parseItem(
            Map<String, dynamic>.from(item),
            itemIndex,
            warnings,
          );
          if (parsed != null) items.add(parsed);
        }
      } else if (data['name'] != null || data['nama'] != null) {
        final parsed = _parseItem(data, 0, warnings);
        if (parsed != null) items.add(parsed);
      }
      final amount =
          _money(data['amount'] ?? data['total']) ??
          (items.isEmpty
              ? null
              : items.fold<int>(0, (sum, item) => sum + item.calculatedTotal));
      if (amount == null || amount <= 0) {
        warnings.add('Transaksi ke-${index + 1} belum memiliki nominal valid.');
      }
      entries.add(
        ReceiptBatchEntry(
          type: typeValue!,
          date: _date(data['date'] ?? data['tanggal']),
          time: _text(data['time'] ?? data['waktu']),
          amount: amount,
          merchant: _text(data['merchant'] ?? data['toko']),
          categoryId: _text(data['category_id']),
          accountId: _text(data['account_id'] ?? data['rekening_id']),
          partyName: _text(
            data['party_name'] ?? data['sumber'] ?? data['dipakai_oleh'],
          ),
          note: _text(data['note'] ?? data['catatan']),
          items: items,
        ),
      );
    }
    if (entries.isEmpty) {
      throw const ReceiptImportException(
        'Belum ada transaksi batch yang bisa diimpor.',
      );
    }
    return ReceiptBatchImport(entries: entries, warnings: warnings);
  }

  static Map<String, dynamic> templateBatchMap() => {
    'format': batchFormat,
    'transactions': [
      {
        'type': 'expense',
        'date': null,
        'time': null,
        'merchant': null,
        'category_id': null,
        'account_id': null,
        'party_name': null,
        'note': '',
        'amount': 0,
        'items': [
          {
            'name': 'Nama barang atau rincian',
            'quantity': 1,
            'unit': 'PCS',
            'unit_price': 0,
            'amount': 0,
          },
        ],
      },
    ],
  };

  static String templateBatchJson() =>
      const JsonEncoder.withIndent('  ').convert(templateBatchMap());

  static String buildGeminiBatchPrompt() =>
      '''Kamu membantu menyiapkan batch transaksi untuk aplikasi Family Finance Manager (FFM).

Balas HANYA dengan JSON valid tanpa markdown atau komentar. Gunakan format persis:
${templateBatchJson()}

Aturan:
- `transactions` berisi satu objek untuk setiap transaksi atau nota yang ingin dicatat.
- `type` hanya boleh `income` atau `expense`.
- `amount`, `unit_price`, dan `items.amount` harus berupa angka integer rupiah tanpa titik, koma, atau simbol Rp.
- Satu transaksi boleh memiliki banyak item pada `items`.
- Jangan menggabungkan beberapa transaksi berbeda menjadi satu objek.
- Jika data tidak terbaca, gunakan null; jangan menebak.
- FFM akan menampilkan semua hasil sebagai draft yang wajib diedit dan dikonfirmasi.''';

  static Map<String, dynamic> toMap(ReceiptOcrResult result) => {
    'format': format,
    'receipt': {
      'merchant': result.merchant,
      'receipt_number': result.receiptNumber,
      'date': result.date?.toIso8601String(),
      'time': result.time,
      'total': result.total,
      'paid_amount': result.paidAmount,
      'change_amount': result.changeAmount,
      'raw_text': result.rawText,
      'items': result.items
          .map(
            (item) => {
              'name': item.name,
              'quantity': item.quantity,
              'unit': item.unit,
              'unit_price': item.price,
              'amount': item.calculatedTotal,
            },
          )
          .toList(),
    },
  };

  static String toJson(ReceiptOcrResult result) =>
      const JsonEncoder.withIndent('  ').convert(toMap(result));

  static Map<String, dynamic> templateMap() => {
    'format': format,
    'receipt': {
      'merchant': null,
      'receipt_number': null,
      'date': null,
      'time': null,
      'total': 0,
      'paid_amount': null,
      'change_amount': null,
      'raw_text': '',
      'items': [
        {
          'name': 'Nama barang',
          'quantity': 1,
          'unit': 'PCS',
          'unit_price': 0,
          'amount': 0,
        },
      ],
    },
  };

  static String templateJson() =>
      const JsonEncoder.withIndent('  ').convert(templateMap());

  static String buildGeminiPrompt({required String rawText}) {
    final source = rawText.trim();
    return '''Kamu membantu menyiapkan draft nota untuk aplikasi Family Finance Manager (FFM).

Baca teks nota di bawah ini. Balas HANYA dengan JSON valid, tanpa markdown, tanpa komentar, dan gunakan format persis berikut:
{
  "format": "ffm-receipt-draft-v1",
  "receipt": {
    "merchant": "nama toko atau null",
    "receipt_number": "nomor nota atau null",
    "date": "YYYY-MM-DD atau null",
    "time": "HH:mm:ss atau null",
    "total": 0,
    "paid_amount": 0,
    "change_amount": 0,
    "raw_text": "teks nota asli",
    "items": [
      {"name": "nama barang", "quantity": 1, "unit": "PCS", "unit_price": 0, "amount": 0}
    ]
  }
}

Aturan penting:
- Nominal harus berupa angka integer rupiah tanpa titik, koma, atau simbol Rp.
- Jika data tidak terbaca, gunakan null; jangan menebak.
- `amount` adalah jumlah baris, sedangkan `unit_price` adalah harga satuan.
- Pertahankan kuantitas pecahan, misalnya 0.5.
- Jangan memasukkan total, bayar, atau kembalian sebagai item.
- Jangan mengubah nama barang yang terbaca.
- Aplikasi akan memvalidasi ulang jumlah item dan meminta pengguna mengedit sebelum menyimpan.

Teks nota:
---
$source
---''';
  }

  static ReceiptOcrItem? _parseItem(
    Map<String, dynamic> data,
    int index,
    List<String> warnings,
  ) {
    final name = _text(data['name'] ?? data['item'] ?? data['nama']);
    final quantity = _number(data['quantity'] ?? data['qty'] ?? data['jumlah']);
    final amount = _money(
      data['amount'] ?? data['line_total'] ?? data['total'],
    );
    final unitPrice = _money(
      data['unit_price'] ?? data['price'] ?? data['harga_satuan'],
    );
    if (name == null || name.trim().isEmpty) {
      warnings.add('Baris item ke-${index + 1} tidak memiliki nama.');
      return null;
    }
    final double safeQuantity = quantity == null || quantity <= 0
        ? 1.0
        : quantity;
    final safeAmount =
        amount ??
        (unitPrice == null ? null : (unitPrice * safeQuantity).round());
    if (safeAmount == null) {
      warnings.add('Nominal item "$name" belum terbaca.');
      return ReceiptOcrItem(
        name: name,
        price: unitPrice ?? 0,
        quantity: safeQuantity,
        unit: _text(data['unit'] ?? data['satuan']),
      );
    }
    final safePrice = unitPrice ?? (safeAmount / safeQuantity).round();
    return ReceiptOcrItem(
      name: name,
      price: safePrice,
      quantity: safeQuantity,
      unit: _text(data['unit'] ?? data['satuan']),
      lineTotal: safeAmount,
    );
  }

  static String? _text(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty || text.toLowerCase() == 'null') return null;
    return text;
  }

  static int? _money(dynamic value) {
    if (value == null || value is bool) return null;
    if (value is num) return value.round();
    var text = value.toString().trim();
    if (text.isEmpty) return null;
    text = text.replaceAll(RegExp(r'[^0-9,.]'), '');
    if (text.isEmpty) return null;
    if (text.contains('.') && text.contains(',')) {
      text = text.replaceAll('.', '').replaceAll(',', '');
    } else if (text.contains('.') || text.contains(',')) {
      final separator = text.contains('.') ? '.' : ',';
      final parts = text.split(separator);
      text = parts.length == 2 && parts.last.length < 3
          ? '${parts.first}.${parts.last}'
          : parts.join();
    }
    return double.tryParse(text)?.round();
  }

  static double? _number(dynamic value) {
    if (value == null || value is bool) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().replaceAll(',', '.'));
  }

  static DateTime? _date(dynamic value) {
    final text = _text(value);
    if (text == null) return null;
    return DateTime.tryParse(text);
  }
}
