import 'dart:convert';

import 'receipt_ocr_service.dart';

class ReceiptImportException implements Exception {
  const ReceiptImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ReceiptImportService {
  const ReceiptImportService._();

  static const format = 'ffm-receipt-draft-v1';

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
