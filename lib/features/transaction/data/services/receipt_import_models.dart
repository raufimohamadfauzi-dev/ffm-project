/// Model data impor nota berbasis JSON. Tidak membaca gambar atau menjalankan OCR.
class ReceiptOcrItem {
  const ReceiptOcrItem({
    required this.name,
    required this.price,
    this.quantity = 1,
    this.unit,
    this.lineTotal,
  });

  final String name;
  final int price;
  final double quantity;
  final String? unit;
  final int? lineTotal;

  int get calculatedTotal => lineTotal ?? (price * quantity).round();
}

/// Hasil impor yang masih berupa rancangan dan wajib diperiksa di form transaksi.
class ReceiptOcrResult {
  const ReceiptOcrResult({
    this.merchant,
    this.total,
    this.date,
    this.time,
    this.paidAmount,
    this.changeAmount,
    this.receiptNumber,
    this.rawText = '',
    this.categoryId,
    this.imagePath,
    this.items = const [],
    this.warnings = const [],
  });

  final String? merchant;
  final int? total;
  final DateTime? date;
  final String? time;
  final int? paidAmount;
  final int? changeAmount;
  final String? receiptNumber;
  final String rawText;
  final String? categoryId;
  final String? imagePath;
  final List<ReceiptOcrItem> items;
  final List<String> warnings;

  ReceiptOcrResult copyWith({
    String? merchant,
    int? total,
    DateTime? date,
    String? time,
    int? paidAmount,
    int? changeAmount,
    String? receiptNumber,
    String? rawText,
    String? categoryId,
    String? imagePath,
    List<ReceiptOcrItem>? items,
    List<String>? warnings,
  }) {
    return ReceiptOcrResult(
      merchant: merchant ?? this.merchant,
      total: total ?? this.total,
      date: date ?? this.date,
      time: time ?? this.time,
      paidAmount: paidAmount ?? this.paidAmount,
      changeAmount: changeAmount ?? this.changeAmount,
      receiptNumber: receiptNumber ?? this.receiptNumber,
      rawText: rawText ?? this.rawText,
      categoryId: categoryId ?? this.categoryId,
      imagePath: imagePath ?? this.imagePath,
      items: items ?? this.items,
      warnings: warnings ?? this.warnings,
    );
  }

  int get itemsTotal =>
      items.fold<int>(0, (sum, item) => sum + item.calculatedTotal);

  List<String> get validationWarnings {
    final result = <String>[...warnings];
    if (total != null && items.isNotEmpty && itemsTotal != total) {
      result.add(
        'Total item Rp${_formatReceiptNumber(itemsTotal)} berbeda dengan total JSON Rp${_formatReceiptNumber(total!)}.',
      );
    }
    if (paidAmount != null && total != null && paidAmount! < total!) {
      result.add('Nominal bayar lebih kecil daripada total.');
    }
    if (paidAmount != null && changeAmount != null && total != null) {
      final expected = paidAmount! - total!;
      if (expected != changeAmount) {
        result.add(
          'Nominal kembalian tidak sama dengan bayar dikurangi total.',
        );
      }
    }
    return result;
  }
}

String _formatReceiptNumber(int value) => value.toString().replaceAllMapped(
  RegExp(r'\B(?=(\d{3})+(?!\d))'),
  (_) => '.',
);
