import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../../../core/network/gemini_service.dart';
import '../../transaction/data/services/receipt_import_service.dart';

/// Hasil pemindaian struk dengan foto levat Gemini vision.
class ReceiptScanOutcome {
  const ReceiptScanOutcome({
    required this.ok,
    required this.message,
    this.batch,
    this.warnings = const [],
    this.latency,
    this.model,
    this.imagePath,
  });

  final bool ok;
  final String message;
  final ReceiptBatchImport? batch;
  final List<String> warnings;
  final Duration? latency;
  final String? model;
  final String? imagePath;

  int get transactionCount => batch?.entries.length ?? 0;
}

class ReceiptScannerService {
  ReceiptScannerService({GeminiService? gemini})
      : _gemini = gemini ?? GeminiService();

  final GeminiService _gemini;

  /// Batas ukuran inline image yang dikirim tanpa diubah (10 MB).
  static const int _maxInlineBytes = 10 * 1024 * 1024;

  /// Dimensi maksimal sisi panjang hasil downscale.
  static const int _maxDimension = 1600;

  /// Memindai foto struk: downscale bila perlu, kirim ke Gemini vision,
  /// parse JSON secara deterministik, lalu validasi total vs rincian.
  Future<ReceiptScanOutcome> scanImage({
    required Uint8List bytes,
    String mimeType = 'image/jpeg',
    String? imagePath,
    String? apiKey,
    String? model,
  }) async {
    final prepared = await _prepareImage(bytes, mimeType);
    if (prepared == null) {
      return ReceiptScanOutcome(
        ok: false,
        message: 'Gambar struk tidak dapat dibaca. Pilih foto yang lebih jelas.',
      );
    }

    final prompt = ReceiptImportService.buildExternalLlmBatchPrompt();
    final imageInput = GeminiImageInput(
      base64Data: base64Encode(prepared.$1),
      mimeType: prepared.$2,
    );
    final result = await _gemini.chat(
      prompt: prompt,
      systemInstruction: _visionSystemInstruction,
      image: imageInput,
      apiKey: apiKey,
      model: model,
      maxOutputTokens: 2048,
    );
    if (!result.ok) {
      return ReceiptScanOutcome(
        ok: false,
        message: result.message,
        latency: result.latency,
        model: result.model,
        imagePath: imagePath,
      );
    }
    final text = result.text?.trim();
    if (text == null || text.isEmpty) {
      return ReceiptScanOutcome(
        ok: false,
        message: 'Struk sudah terlihat tapi isinya tidak terbaca. Coba ambil foto lebih dekat dan terang.',
        latency: result.latency,
        model: result.model,
        imagePath: imagePath,
      );
    }

    try {
      final batch = ReceiptImportService.parseBatchJson(text);
      final warnings = _crossValidate(batch);
      return ReceiptScanOutcome(
        ok: true,
        message: 'Struk terbaca, berikut rancangan transaksinya. Periksa sebelum disimpan.',
        batch: batch,
        warnings: warnings,
        latency: result.latency,
        model: result.model,
        imagePath: imagePath,
      );
    } on ReceiptImportException catch (error) {
      return ReceiptScanOutcome(
        ok: false,
        message: 'Struk terbaca tetapi hasilnya belum cocok: ${error.message}',
        latency: result.latency,
        model: result.model,
        imagePath: imagePath,
      );
    } on Object {
      return ReceiptScanOutcome(
        ok: false,
        message: 'Struk terbaca tetapi hasilnya tidak sesuai format. Coba lagi dengan foto lain.',
        latency: result.latency,
        model: result.model,
        imagePath: imagePath,
      );
    }
  }

  /// Validasi deterministik: total transaksi wajib sama dengan jumlah baris item.
  List<String> _crossValidate(ReceiptBatchImport batch) {
    final warnings = <String>[...batch.warnings];
    for (var index = 0; index < batch.entries.length; index++) {
      final entry = batch.entries[index];
      final items = entry.items;
      final amount = entry.amount;
      if (items.isEmpty || amount == null) continue;
      final itemsTotal = items.fold<int>(
        0,
        (sum, item) => sum + item.calculatedTotal,
      );
      if (itemsTotal != amount) {
        warnings.add(
          'Transaksi ${index + 1}: total Rp${_formatNumber(amount)} '
          'berbeda dengan jumlah baris Rp${_formatNumber(itemsTotal)}.',
        );
      }
    }
    return warnings;
  }

  /// Instruksi tambahan khusus foto struk.
  static const String _visionSystemInstruction = '''
Kamu menerima sebuah FOTO STRUK/NOTA/BUKTI PEMBAYARAN.

Perhatikan baik-baik gambar sebelum menulis JSON:
- Baca nomor, rincian barang, total, tanggal, nama toko dengan teliti sesuai teks di foto.
- Jangan menebak angka yang buram; jika sebuah angka tidak terbaca, gunakan null untuk field itu, bukan menebak.
- Struk pembelian TOKEN LISTRIK PLN: tulis sebagai satu transaksi expense; isi budget_name dengan pos anggaran listrik yang paling cocok (misalnya "Listrik") bila tersirat; masukkan visible token 20 digit dan IDPEL ke note bila terbaca. Total pembelian token adalah jumlah yang dibayar, bukan jumlah kWh.
- Struk isi ulang pulsa/kuota/data/saldo e-wallet: satu transaksi expense dengan merchant sesuai merek.
- Struk yang hanya berisi rincian (bukan pembelian, misal rekening tagihan) tetap satu transaksi expense.
- Jangan menggabungkan beberapa transaksi yang jelas terpisah menjadi satu.
- Aplikasi menampilkan semua hasil sebagai draft yang wajib diperiksa dan dikonfirmasi.''';

  /// Menyiapkan bytes image; menurunkan resolusi bila melebihi kapasitas inline.
  Future<(Uint8List, String)?> _prepareImage(
    Uint8List bytes,
    String mimeType,
  ) async {
    if (bytes.lengthInBytes <= _maxInlineBytes) {
      return (bytes, mimeType);
    }
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        final resized = await _resize(image, _maxDimension);
        final byteData = await resized.toByteData(
          format: ui.ImageByteFormat.png,
        );
        resized.dispose();
        if (byteData == null) return null;
        return (byteData.buffer.asUint8List(), 'image/png');
      } finally {
        image.dispose();
      }
    } on Object {
      return (bytes, mimeType);
    }
  }

  Future<ui.Image> _resize(ui.Image source, int maxDimension) async {
    final width = source.width;
    final height = source.height;
    final longest = math.max(width, height);
    if (longest <= maxDimension) return source;
    final scale = maxDimension / longest;
    final targetWidth = math.max(1, (width * scale).round());
    final targetHeight = math.max(1, (height * scale).round());
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.scale(scale);
    canvas.drawImage(source, ui.Offset.zero, ui.Paint());
    final picture = recorder.endRecording();
    final resized = await picture.toImage(targetWidth, targetHeight);
    picture.dispose();
    return resized;
  }

  static String _formatNumber(int value) =>
      value.toString().replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (_) => '.',
      );
}