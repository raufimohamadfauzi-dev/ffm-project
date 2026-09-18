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
    this.tokenUsage,
  });

  final bool ok;
  final String message;
  final ReceiptBatchImport? batch;
  final List<String> warnings;
  final Duration? latency;
  final String? model;
  final String? imagePath;
  final Map<String, dynamic>? tokenUsage;

  int get transactionCount => batch?.entries.length ?? 0;
}

class ReceiptScannerService {
  ReceiptScannerService({GeminiService? gemini})
    : _gemini = gemini ?? GeminiService();

  final GeminiService _gemini;

  static final _tokenCodeRegex = RegExp(
    r'(?<!\d)(\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4})(?!\d)',
  );

  static final _meterNumberRegex = RegExp(
    r'(?:idpel|id\s*pelanggan|meter|no\.?\s*meter|nomor\s*meteran?)\s*[:#-]?\s*(\d{11,12})',
    caseSensitive: false,
  );

  /// Bukti yang cukup kuat bahwa gambar adalah struk token PLN.
  /// Nomor panjang saja tidak pernah cukup karena bisa berupa invoice/ref.
  static bool isPlnTokenText(String text) {
    final lower = text.toLowerCase();
    final hasPlnMarker = RegExp(
      r'\b(pln|token\s+listrik|pulsa\s+listrik|voucher\s+listrik|listrik\s+prabayar)\b',
    ).hasMatch(lower);
    if (!hasPlnMarker) return false;

    final hasTokenCode = _tokenCodeRegex.hasMatch(text);
    final hasMeterNumber = _meterNumberRegex.hasMatch(text);
    final hasKwh = RegExp(
      r'\b\d+(?:[.,]\d+)?\s*kwh\b',
      caseSensitive: false,
    ).hasMatch(text);
    final hasPrepaidMarker = RegExp(
      r'\b(prabayar|token|stroom|stroom\s*token)\b',
      caseSensitive: false,
    ).hasMatch(lower);

    return hasTokenCode || (hasMeterNumber && hasKwh && hasPrepaidMarker);
  }

  /// Mengambil kode token PLN 20 digit yang sudah dinormalisasi.
  static String? extractPlnToken(String text) {
    final match = _tokenCodeRegex.firstMatch(text);
    final digits = match?.group(1)?.replaceAll(RegExp(r'\D'), '');
    return digits?.length == 20 ? digits : null;
  }

  /// Mengambil SEMUA kode token PLN 20 digit unik dalam teks. Dipakai untuk
  /// mendeteksi satu gambar yang berisi beberapa pembelian token (multi-IDPEL).
  static List<String> extractPlnTokens(String text) {
    final result = <String>[];
    final seen = <String>{};
    for (final match in _tokenCodeRegex.allMatches(text)) {
      final digits = match.group(1)!.replaceAll(RegExp(r'\D'), '');
      if (digits.length == 20 && seen.add(digits)) result.add(digits);
    }
    return result;
  }

  /// Mengambil nomor meter/IDPEL hanya dari label PLN yang jelas.
  static String? extractPlnMeterNumber(String text) {
    return _meterNumberRegex.firstMatch(text)?.group(1);
  }

  /// Mengambil SEMUA nomor meter/IDPEL unik pada teks. Berguna untuk deteksi
  /// struk dengan beberapa meteran (2 rumah dalam 1 gambar).
  static List<String> extractPlnMeters(String text) {
    final result = <String>[];
    final seen = <String>{};
    for (final match in _meterNumberRegex.allMatches(text)) {
      final value = match.group(1)!;
      if (seen.add(value)) result.add(value);
    }
    return result;
  }

  static double? extractPlnKwh(String text) {
    final match = RegExp(
      r'(?:jumlah\s*)?(?:kwh|stroom)\s*[:#-]?\s*(\d+(?:[.,]\d+)?)|'
      r'(\d+(?:[.,]\d+)?)\s*kwh\b',
      caseSensitive: false,
    ).firstMatch(text);
    final raw = match?.group(1) ?? match?.group(2);
    final value = double.tryParse(raw?.replaceAll(',', '.') ?? '');
    return value != null && value > 0 ? value : null;
  }

  /// Membagi satu struk PLN multi-meter menjadi proposal utility per meter.
  static List<Map<String, dynamic>> expandPlnUtilityProposals(
    String text, {
    Map<String, dynamic>? baseProposal,
  }) {
    final tokens = extractPlnTokens(text);
    final meters = extractPlnMeters(text);
    final normalizedBase = Map<String, dynamic>.from(baseProposal ?? const {});

    final orderedTokens = tokens.isNotEmpty
        ? tokens
        : (normalizedBase['tokenCode']?.toString() == null
              ? <String>[]
              : [normalizedBase['tokenCode'].toString()]);
    final orderedMeters = meters.isNotEmpty
        ? meters
        : (normalizedBase['meterNumber']?.toString() == null
              ? <String>[]
              : [normalizedBase['meterNumber'].toString()]);

    if (orderedTokens.isEmpty && orderedMeters.isEmpty && normalizedBase.isEmpty) {
      return const <Map<String, dynamic>>[];
    }

    final totalItems = math.max(orderedTokens.length, orderedMeters.length);
    if (totalItems <= 1) {
      final proposal = <String, dynamic>{...normalizedBase};
      if (orderedTokens.isNotEmpty) {
        proposal['tokenCode'] = orderedTokens.first;
      }
      if (orderedMeters.isNotEmpty) {
        proposal['meterNumber'] = orderedMeters.first;
      }
      return [proposal];
    }

    final proposals = <Map<String, dynamic>>[];
    for (var index = 0; index < totalItems; index++) {
      final proposal = <String, dynamic>{...normalizedBase};
      final token = orderedTokens.length > index
          ? orderedTokens[index]
          : (orderedTokens.isNotEmpty ? orderedTokens.first : null);
      final meter = orderedMeters.length > index
          ? orderedMeters[index]
          : (orderedMeters.isNotEmpty ? orderedMeters.first : null);

      if (token != null) proposal['tokenCode'] = token;
      if (meter != null) proposal['meterNumber'] = meter;

      if (proposal['tokenCode'] != null || proposal['meterNumber'] != null) {
        proposals.add(proposal);
      }
    }

    return proposals;
  }

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
    String? userCaption,
    String? apiKey,
    String? model,
  }) async {
    final prepared = await _prepareImage(bytes, mimeType);
    if (prepared == null) {
      return ReceiptScanOutcome(
        ok: false,
        message:
            'Gambar struk tidak dapat dibaca. Pilih foto yang lebih jelas.',
      );
    }

    final basePrompt = ReceiptImportService.buildExternalLlmBatchPrompt();
    final prompt = (userCaption != null && userCaption.trim().isNotEmpty)
        ? '$basePrompt\n\nCatatan instruksi dari pengguna: "${userCaption.trim()}". Sesuaikan kategori, nama toko, atau rekening transaksi bila relevan.'
        : basePrompt;

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
    final tokenUsage = result.usageMetadata?.toJson();
    if (!result.ok) {
      return ReceiptScanOutcome(
        ok: false,
        message: result.message,
        latency: result.latency,
        model: result.model,
        imagePath: imagePath,
        tokenUsage: tokenUsage,
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
        tokenUsage: tokenUsage,
      );
    }

    try {
      final batch = ReceiptImportService.parseBatchJson(text);
      final reheatedBatch = await _retryMissingPlnMetadata(
        batch: batch,
        originalText: text,
        image: prepared,
        userCaption: userCaption,
        apiKey: apiKey,
        model: model,
      );
      final warnings = _crossValidate(reheatedBatch);
      return ReceiptScanOutcome(
        ok: true,
        message: 'Struk terbaca, berikut rancangan transaksinya. Periksa sebelum disimpan.',
        batch: reheatedBatch,
        warnings: warnings,
        latency: result.latency,
        model: result.model,
        imagePath: imagePath,
        tokenUsage: tokenUsage,
      );
    } on ReceiptImportException catch (error) {
      if (userCaption != null && userCaption.trim().isNotEmpty) {
        return askVisualQuestion(
          bytes: bytes,
          question: userCaption.trim(),
          mimeType: mimeType,
          imagePath: imagePath,
          apiKey: apiKey,
          model: model,
        );
      }
      return ReceiptScanOutcome(
        ok: false,
        message:
            'Struk terbaca tetapi hasilnya belum cocok: angka atau rinciannya kurang jelas (${error.message}). Coba foto lebih dekat dan terang, atau lengkapi lewat tombol Edit.',
        latency: result.latency,
        model: result.model,
        imagePath: imagePath,
        tokenUsage: tokenUsage,
      );
    } on Object catch (error) {
      if (userCaption != null && userCaption.trim().isNotEmpty) {
        return askVisualQuestion(
          bytes: bytes,
          question: userCaption.trim(),
          mimeType: mimeType,
          imagePath: imagePath,
          apiKey: apiKey,
          model: model,
        );
      }
      return ReceiptScanOutcome(
        ok: false,
        message: 'Format hasil baca struk tidak dapat diolah: $error',
        latency: result.latency,
        model: result.model,
        imagePath: imagePath,
        tokenUsage: tokenUsage,
      );
    }
  }

  /// Bertanya tentang gambar secara visual multimodal luas (non-struk atau pertanyaan analisis).
  Future<ReceiptScanOutcome> askVisualQuestion({
    required Uint8List bytes,
    required String question,
    String mimeType = 'image/jpeg',
    String? imagePath,
    String? apiKey,
    String? model,
  }) async {
    final prepared = await _prepareImage(bytes, mimeType);
    if (prepared == null) {
      return ReceiptScanOutcome(
        ok: false,
        message: 'Gambar tidak dapat dibaca. Pilih foto yang lebih jelas.',
      );
    }
    final imageInput = GeminiImageInput(
      base64Data: base64Encode(prepared.$1),
      mimeType: prepared.$2,
    );
    final result = await _gemini.chat(
      prompt: question,
      systemInstruction: '''
Kamu adalah Asisten Finansial Cerdas FFM (Family Finance Manager) berkemampuan visual multimodal.
Pengguna melampirkan foto/gambar/grafik dan mengajukan pertanyaan atau permintaan analisis.
Tugasmu:
1. Jawab pertanyaan pengguna dengan ramah, akurat, ringkas, dan jelas dalam Bahasa Indonesia.
2. Jelaskan apa yang terlihat di gambar jika relevan dengan pertanyaan keuangan, pengeluaran, barang, atau nota.
3. Berikan saran atau ringkasan yang bermanfaat bagi keuangan keluarga pengguna.
''',
      image: imageInput,
      apiKey: apiKey,
      model: model,
      maxOutputTokens: 2048,
    );
    final tokenUsage = result.usageMetadata?.toJson();
    return ReceiptScanOutcome(
      ok: result.ok,
      message: result.ok ? (result.text?.trim() ?? '') : result.message,
      latency: result.latency,
      model: result.model,
      imagePath: imagePath,
      tokenUsage: tokenUsage,
    );
  }

  Future<ReceiptBatchImport> _retryMissingPlnMetadata({
    required ReceiptBatchImport batch,
    required String originalText,
    required (Uint8List, String)? image,
    String? userCaption,
    String? apiKey,
    String? model,
  }) async {
    final needsRetry = batch.entries.any((entry) {
      final merchant = entry.merchant ?? '';
      final budget = entry.budgetName ?? '';
      final note = entry.note ?? '';
      final allText = [merchant, budget, note].join(' ');
      final lower = allText.toLowerCase();
      final looksLikePlnTokenReceipt =
          lower.contains('pln') &&
          (lower.contains('token listrik') ||
              lower.contains('pulsa listrik') ||
              lower.contains('meter') ||
              lower.contains('idpel') ||
              lower.contains('kwh'));
      if (!looksLikePlnTokenReceipt) return false;
      final token = extractPlnToken(note) ?? extractPlnToken(merchant) ?? extractPlnToken(budget);
      final kwh = extractPlnKwh(note) ?? extractPlnKwh(merchant) ?? extractPlnKwh(budget);
      return token == null || kwh == null;
    });
    if (!needsRetry) return batch;

    final retryPrompt = '''
Pada gambar struk ini, cari data PLN yang hilang dan lengkapi tanpa mengarang detail lain.
Format JSON yang harus dikembalikan:
{"token_code": "<20-digit code atau null>", "kwh": <angka atau null>}

Gunakan konteks berikut dari hasil OCR awal: $originalText
${userCaption != null && userCaption.trim().isNotEmpty ? 'Catatan pengguna: ${userCaption.trim()}\n' : ''}Jika data tidak ditemukan, tulis null.
''';

    final retryResult = await _gemini.chat(
      prompt: retryPrompt,
      systemInstruction: 'Kamu membantu melengkapi data struk PLN yang masih kosong. Jawab hanya JSON valid tanpa teks tambahan.',
      image: image == null ? null : GeminiImageInput(
        base64Data: base64Encode(image.$1),
        mimeType: image.$2,
      ),
      apiKey: apiKey,
      model: model,
      maxOutputTokens: 512,
    );
    if (!retryResult.ok || retryResult.text == null || retryResult.text!.trim().isEmpty) {
      return batch;
    }

    try {
      final decoded = jsonDecode(retryResult.text!);
      final payload = decoded is Map ? Map<String, dynamic>.from(decoded) : const {};
      final tokenCode = payload['token_code']?.toString();
      final rawKwh = payload['kwh'];
      final kwh = rawKwh == null ? null : double.tryParse(rawKwh.toString());
      if (tokenCode == null && kwh == null) return batch;

      final updatedEntries = <ReceiptBatchEntry>[];
      var didRetry = false;
      for (final entry in batch.entries) {
        final lower = '${entry.merchant ?? ''} ${entry.budgetName ?? ''} ${entry.note ?? ''}'.toLowerCase();
        final isPln = lower.contains('pln') || lower.contains('listrik') || lower.contains('token listrik');
        if (!isPln) {
          updatedEntries.add(entry);
          continue;
        }

        String note = entry.note ?? '';
        final token = extractPlnToken(note);
        final existingKwh = extractPlnKwh(note);
        if (token == null && tokenCode != null) {
          note = [note, 'Token: $tokenCode'].join(' ').trim();
        }
        if (existingKwh == null && kwh != null) {
          note = [note, 'KWH: ${kwh.toStringAsFixed(1)}'].join(' ').trim();
        }
        if (note != (entry.note ?? '')) {
          didRetry = true;
        }
        updatedEntries.add(entry.copyWith(note: note));
      }

      if (!didRetry) return batch;
      return ReceiptBatchImport(
        entries: updatedEntries,
        warnings: batch.warnings,
        isBankStatement: batch.isBankStatement,
        statementAccountId: batch.statementAccountId,
        statementAccountName: batch.statementAccountName,
        openingBalance: batch.openingBalance,
        closingBalance: batch.closingBalance,
        periodStart: batch.periodStart,
        periodEnd: batch.periodEnd,
        hadOcrRetry: true,
      );
    } on Object {
      return batch;
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
- PENTING TENTANG JUMLAH/TOTAL TRANSAKSI (amount/total):
  * Nilai "amount" atau "total" adalah TOTAL BELANJA / HARGA AKHIR YANG DIBAYAR (setelah diskon/pajak).
  * JANGAN gunakan uang tunai yang diserahkan pembeli (cash / tunai / bayar / paid_amount) sebagai total/amount transaksi jika ada uang kembalian (change / kembali).
  * Contoh: Total Belanja Rp75.000, Tunai/Bayar Rp100.000, Kembalian Rp25.000 -> maka amount adalah 75000, paid_amount adalah 100000, dan change_amount adalah 25000. JANGAN set amount menjadi 100000!
- Tentukan jenis transaksi (type):
  * Jika nota merupakan struk belanja, pembelian barang/jasa, atau tagihan: gunakan type "expense".
  * Jika nota merupakan faktur penjualan barang/jasa, kuitansi penerimaan pembayaran, bukti transfer masuk, atau nota uang masuk: gunakan type "income".
  * Jika bukti mutasi kirim uang / setor tunai antar-rekening: gunakan type "transfer".
- Struk pembelian TOKEN LISTRIK PLN: tulis sebagai satu transaksi expense; isi budget_name dengan "Listrik" atau pos anggaran utilitas yang cocok; masukkan nomor token 20 digit (format 5 blok: xxxx-xxxx-xxxx-xxxx-xxxx atau 20 angka) dan IDPEL / nomor meteran ke note dan items. Total pembelian token adalah jumlah yang dibayar (Rupiah), bukan kWh.
- PENTING UNTUK STRUK TOKEN LISTRIK BERGANDA: jika satu gambar berisi DUA atau lebih pembelian token (misal struk berisi 2 IDPEL/no.meteran BEDA, 2 kode token BEDA, dan 2 nominal BEDA), buatkan entries TERPISAH per pembelian — SATU entry per meteran/IDPEL. Jangan pernah menggabungkan nominal beberapa token menjadi satu amount, dan jangan campur token/meteran antar-entry. Setiap entry harus membawa IDPEL/no.meteran dan token miliknya sendiri (tulis di note/items entry tersebut).
- Struk pembelian BBM di SPBU (Pertamina/Shell/BP/dll): tulis sebagai transaksi expense dengan merchant nama SPBU; isi budget_name "Transportasi" atau "BBM"; tulis jenis BBM (Pertalite/Pertamax/Solar/Dexlite) dan jumlah liter ke note atau rincian items, serta plat nomor kendaraan bila terbaca.
- Struk isi ulang PULSA/KUOTA/DATA: satu transaksi expense dengan merchant sesuai merek provider.
- Struk TOP-UP SALDO E-WALLET (GoPay, OVO, Dana, ShopeePay, LinkAja, dll): gunakan type "transfer" karena ini adalah pemindahan saldo antar-rekening milik keluarga; from_account adalah rekening bank sumber (bila terbaca), to_account adalah e-wallet tujuan. Jika ada biaya admin top-up, catat ke admin_fee.
- Struk yang hanya berisi rincian (bukan pembelian, misal rekening tagihan) tetap satu transaksi expense.
- Jangan menggabungkan beberapa transaksi yang jelas terpisah menjadi satu.
- Aplikasi menampilkan semua hasil sebagai draft yang wajib diperiksa dan dikonfirmasi.''';

  /// Menyiapkan bytes image; menurunkan resolusi bila gambar terlalu besar
  /// (>10MB atau sisi terpanjang >1600px) untuk upload cepat & konsisten.
  Future<(Uint8List, String)?> _prepareImage(
    Uint8List bytes,
    String mimeType,
  ) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        final longest = math.max(image.width, image.height);
        final needsDownscale =
            bytes.lengthInBytes > _maxInlineBytes || longest > _maxDimension;
        if (!needsDownscale) {
          return (bytes, mimeType);
        }
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

  static String _formatNumber(int value) => value.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => '.',
  );
}
