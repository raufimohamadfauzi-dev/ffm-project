class ReceiptOcrItem {
  const ReceiptOcrItem({
    required this.name,
    required this.price,
    this.quantity = 1,
  });

  final String name;
  final int price;
  final double quantity;
}

class ReceiptOcrResult {
  const ReceiptOcrResult({
    this.merchant,
    this.total,
    this.date,
    this.categoryId,
    this.imagePath,
    this.items = const [],
  });

  final String? merchant;
  final int? total;
  final DateTime? date;
  final String? categoryId;
  final String? imagePath;
  final List<ReceiptOcrItem> items;
}

class ReceiptOcrService {
  Future<ReceiptOcrResult> recognize(String imagePath) async =>
      ReceiptOcrResult(imagePath: imagePath);
}
