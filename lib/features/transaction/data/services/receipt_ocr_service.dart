import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class ReceiptOcrItem {
  const ReceiptOcrItem({
    required this.name,
    required this.price,
    this.quantity = 1,
    this.unit,
    this.lineTotal,
  });

  final String name;

  /// Harga satuan. Jika nota hanya menulis jumlah baris, harga satuan
  /// dihitung dari jumlah baris dibagi kuantitas.
  final int price;
  final double quantity;
  final String? unit;
  final int? lineTotal;

  int get calculatedTotal => lineTotal ?? (price * quantity).round();
}

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
        'Total item Rp${_formatReceiptNumber(itemsTotal)} berbeda dengan total nota Rp${_formatReceiptNumber(total!)}.',
      );
    }
    if (paidAmount != null && total != null && paidAmount! < total!) {
      result.add('Nominal bayar lebih kecil daripada total nota.');
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

enum ReceiptOcrDiagnosticCode {
  imageNotSelected,
  imageUnreadable,
  nativeFailed,
  emptyText,
  itemsNotRecognized,
  success,
}

class ReceiptOcrDiagnostic {
  const ReceiptOcrDiagnostic({
    required this.code,
    required this.title,
    required this.message,
    this.itemCount = 0,
  });

  final ReceiptOcrDiagnosticCode code;
  final String title;
  final String message;
  final int itemCount;

  bool get isSuccess => code == ReceiptOcrDiagnosticCode.success;

  factory ReceiptOcrDiagnostic.fromResult(ReceiptOcrResult result) {
    if (result.rawText.trim().isEmpty) {
      return const ReceiptOcrDiagnostic(
        code: ReceiptOcrDiagnosticCode.emptyText,
        title: 'Teks nota belum terbaca',
        message: 'OCR sudah berjalan, tetapi tidak menemukan tulisan. Coba foto lebih terang, rata, dan dekatkan ke nota.',
      );
    }
    if (result.items.isEmpty) {
      return const ReceiptOcrDiagnostic(
        code: ReceiptOcrDiagnosticCode.itemsNotRecognized,
        title: 'Item nota belum dikenali',
        message: 'Teks sudah terbaca, tetapi format itemnya belum dikenali. Buka teks mentah atau tambahkan item manual.',
      );
    }
    return ReceiptOcrDiagnostic(
      code: ReceiptOcrDiagnosticCode.success,
      title: 'OCR selesai',
      message:
          'Berhasil membaca ${result.items.length} item. Cek dan edit draft sebelum disimpan.',
      itemCount: result.items.length,
    );
  }

  factory ReceiptOcrDiagnostic.fromFailure(Object error) {
    if (error is ReceiptOcrException) {
      return ReceiptOcrDiagnostic(
        code: error.code,
        title: error.title,
        message: error.message,
      );
    }
    return const ReceiptOcrDiagnostic(
      code: ReceiptOcrDiagnosticCode.nativeFailed,
      title: 'OCR offline gagal dijalankan',
      message: 'Mesin OCR Latin sudah tersedia di APK, tetapi belum berhasil membaca gambar ini. Pastikan foto nota jelas, gambar bisa dibuka, dan izin kamera sudah aktif, lalu coba lagi.',
    );
  }

  static const imageNotSelected = ReceiptOcrDiagnostic(
    code: ReceiptOcrDiagnosticCode.imageNotSelected,
    title: 'Belum ada gambar',
    message: 'Tidak ada foto yang dipilih. Pilih foto nota dulu untuk mulai membaca.',
  );

  static const imageUnreadable = ReceiptOcrDiagnostic(
    code: ReceiptOcrDiagnosticCode.imageUnreadable,
    title: 'Gambar tidak bisa dibuka',
    message: 'File foto tidak ditemukan atau rusak. Pilih ulang foto JPG/PNG yang masih bisa dibuka di galeri.',
  );
}

class ReceiptOcrException implements Exception {
  const ReceiptOcrException({
    required this.code,
    required this.title,
    required this.message,
    this.cause,
  });

  final ReceiptOcrDiagnosticCode code;
  final String title;
  final String message;
  final Object? cause;

  @override
  String toString() => 'ReceiptOcrException($code): $message';
}

class ReceiptOcrService {
  Future<ReceiptOcrResult> recognize(String imagePath) async {
    if (imagePath.trim().isEmpty) {
      throw const ReceiptOcrException(
        code: ReceiptOcrDiagnosticCode.imageNotSelected,
        title: 'Belum ada gambar',
        message: 'Tidak ada foto yang dipilih. Pilih foto nota dulu untuk mulai membaca.',
      );
    }

    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final input = InputImage.fromFilePath(imagePath);
      final recognized = await recognizer.processImage(input);
      return parseText(recognized.text, imagePath: imagePath);
    } catch (error) {
      throw ReceiptOcrException(
        code: ReceiptOcrDiagnosticCode.nativeFailed,
        title: 'OCR offline gagal dijalankan',
        message: 'Mesin OCR Latin sudah tersedia di APK, tetapi belum berhasil membaca gambar ini. Pastikan foto nota jelas, gambar bisa dibuka, dan izin kamera sudah aktif, lalu coba lagi.',
        cause: error,
      );
    } finally {
      await recognizer.close();
    }
  }

  ReceiptOcrResult parseText(String rawText, {String? imagePath}) {
    final lines = rawText
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (lines.isEmpty) {
      return ReceiptOcrResult(
        rawText: rawText,
        imagePath: imagePath,
        warnings: const ['Teks nota kosong atau belum terbaca.'],
      );
    }

    String? merchant;
    String? receiptNumber;
    DateTime? date;
    String? time;
    int? total;
    int? paid;
    int? change;
    final items = <ReceiptOcrItem>[];
    final warnings = <String>[];

    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final lower = line.toLowerCase();
      if (merchant == null && _looksLikeMerchant(line, index)) {
        merchant = _cleanLabel(line);
      }
      final dateMatch = RegExp(r'(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})')
          .firstMatch(line);
      if (dateMatch != null) {
        date = _parseDate(dateMatch);
      }
      final timeMatch = RegExp(r'\b(\d{1,2}:\d{2}(?::\d{2})?)\b')
          .firstMatch(line);
      if (timeMatch != null) time = timeMatch.group(1);
      final receiptMatch = RegExp(
        r'\b(?:no|nomor|struk|trx|nota)\s*[:#-]?\s*([A-Z0-9/-]+)',
        caseSensitive: false,
      ).firstMatch(line);
      if (receiptMatch != null) receiptNumber = receiptMatch.group(1);

      if (RegExp(r'\btotal\b', caseSensitive: false).hasMatch(lower)) {
        final number = _lastMoney(line);
        if (number != null) total = number;
      } else if (RegExp(
        r'\bbayar\b|\bpaid\b',
        caseSensitive: false,
      ).hasMatch(lower)) {
        final number = _lastMoney(line);
        if (number != null) paid = number;
      } else if (RegExp(
        r'\bkembali\b|\bchange\b',
        caseSensitive: false,
      ).hasMatch(lower)) {
        final number = _lastMoney(line);
        if (number != null) change = number;
      }

      final inline = _parseInlineItem(line);
      if (inline != null) {
        items.add(inline);
        continue;
      }
      if (_isHeaderOrFooter(line)) continue;
      if (index + 1 < lines.length && _looksLikeItemName(line)) {
        final next = _parseQuantityMoneyLine(lines[index + 1]);
        if (next != null) {
          items.add(
            ReceiptOcrItem(
              name: _cleanLabel(line),
              price: next.unitPrice,
              quantity: next.quantity,
              unit: next.unit,
              lineTotal: next.lineTotal,
            ),
          );
          index++;
        }
      }
    }

    if (merchant == null && lines.isNotEmpty) {
      merchant = _cleanLabel(lines.first);
    }
    if (items.isEmpty)
      warnings.add('Item nota belum terbaca. Tambahkan manual.');
    if (total == null && items.isNotEmpty) total = _sumItems(items);
    if (total == null) warnings.add('Total nota belum terbaca.');

    return ReceiptOcrResult(
      merchant: merchant,
      total: total,
      date: date,
      time: time,
      paidAmount: paid,
      changeAmount: change,
      receiptNumber: receiptNumber,
      rawText: rawText,
      imagePath: imagePath,
      items: items,
      warnings: warnings,
    );
  }

  bool _looksLikeMerchant(String line, int index) {
    if (index > 3) return false;
    final lower = line.toLowerCase();
    if (_isHeaderOrFooter(line) ||
        lower.contains('jl.') ||
        lower.contains('jalan')) {
      return false;
    }
    return RegExp(r'[a-zA-Z]{3,}').hasMatch(line) &&
        !_containsMoney(line) &&
        !RegExp(r'\d{1,2}[/-]\d{1,2}[/-]\d{2,4}').hasMatch(line);
  }

  bool _looksLikeItemName(String line) {
    if (_isHeaderOrFooter(line) || _containsMoney(line)) return false;
    if (line.length < 2 || !RegExp(r'[A-Za-zÀ-ÿ]{2,}').hasMatch(line))
      return false;
    final lower = line.toLowerCase();
    return !lower.contains('alamat') &&
        !lower.contains('kasir') &&
        !lower.contains('operator') &&
        !lower.contains('nomor') &&
        !lower.contains('total') &&
        !lower.contains('bayar') &&
        !lower.contains('kembali');
  }

  bool _isHeaderOrFooter(String line) {
    final lower = line.toLowerCase();
    return lower.contains('total') ||
        lower.contains('bayar') ||
        lower.contains('kembali') ||
        lower.contains('terima kasih') ||
        lower.contains('barang yg sudah') ||
        lower.contains('barang yang sudah') ||
        lower.contains('kasir') ||
        lower == 'opr';
  }

  ReceiptOcrItem? _parseInlineItem(String line) {
    final match = RegExp(
      r'^(.+?)\s*[:\-]\s*(\d+(?:[.,]\d+)?)\s*([A-Za-z]+)?\s*[-:]\s*(?:Rp\s*)?([0-9.,]+)\s*$',
      caseSensitive: false,
    ).firstMatch(line);
    if (match == null) return null;
    final quantity = _parseQuantity(match.group(2)!);
    final lineTotal = _parseMoney(match.group(4)!);
    if (lineTotal == null || quantity <= 0) return null;
    return ReceiptOcrItem(
      name: _cleanLabel(match.group(1)!),
      price: (lineTotal / quantity).round(),
      quantity: quantity,
      unit: match.group(3),
      lineTotal: lineTotal,
    );
  }

  _QuantityMoney? _parseQuantityMoneyLine(String line) {
    final numbers = RegExp(r'(\d+(?:[.,]\d+)?)').allMatches(line).toList();
    if (numbers.length < 2) return null;
    final quantity = _parseQuantity(numbers.first.group(1)!);
    final monies = RegExp(r'([0-9][0-9.,]*)').allMatches(line).toList();
    if (monies.length < 2 || quantity <= 0) return null;
    final unitPrice = _parseMoney(monies[monies.length - 2].group(1)!);
    final lineTotal = _parseMoney(monies.last.group(1)!);
    if (unitPrice == null || lineTotal == null) return null;
    final unitMatch = RegExp(r'\d+(?:[.,]\d+)?\s*([A-Za-z]+)').firstMatch(line);
    return _QuantityMoney(
      quantity: quantity,
      unit: unitMatch?.group(1),
      unitPrice: unitPrice,
      lineTotal: lineTotal,
    );
  }

  int? _lastMoney(String line) {
    final matches = RegExp(
      r'(?:Rp\s*)?([0-9][0-9.,]*)',
      caseSensitive: false,
    ).allMatches(line).toList();
    if (matches.isEmpty) return null;
    return _parseMoney(matches.last.group(1)!);
  }

  int? _parseMoney(String value) {
    var clean = value.replaceAll(RegExp(r'[^0-9,.]'), '');
    if (clean.isEmpty) return null;
    if (clean.contains('.') && clean.contains(',')) {
      clean = clean.replaceAll('.', '').replaceAll(',', '');
    } else if (clean.contains('.') || clean.contains(',')) {
      final separator = clean.contains('.') ? '.' : ',';
      final parts = clean.split(separator);
      if (parts.length == 2 && parts.last.length == 3) {
        clean = parts.join();
      } else {
        clean = parts.first;
      }
    }
    return int.tryParse(clean);
  }

  double _parseQuantity(String value) {
    final normalized = value.replaceAll(',', '.');
    return double.tryParse(normalized) ?? 1;
  }

  DateTime? _parseDate(RegExpMatch match) {
    final day = int.tryParse(match.group(1)!);
    final month = int.tryParse(match.group(2)!);
    var year = int.tryParse(match.group(3)!);
    if (day == null || month == null || year == null) return null;
    if (year < 100) year += 2000;
    try {
      return DateTime(year, month, day);
    } catch (_) {
      return null;
    }
  }

  int _sumItems(List<ReceiptOcrItem> values) =>
      values.fold<int>(0, (sum, item) => sum + item.calculatedTotal);

  bool _containsMoney(String value) => RegExp(r'\d[\d.,]{2,}').hasMatch(value);

  String _cleanLabel(String value) => value
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^[\s:.-]+|[\s:.-]+$'), '')
      .trim();
}

String _formatReceiptNumber(int value) => value.toString().replaceAllMapped(
  RegExp(r'\B(?=(\d{3})+(?!\d))'),
  (_) => '.',
);

class _QuantityMoney {
  const _QuantityMoney({
    required this.quantity,
    required this.unit,
    required this.unitPrice,
    required this.lineTotal,
  });

  final double quantity;
  final String? unit;
  final int unitPrice;
  final int lineTotal;
}
