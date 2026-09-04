
/// Hasil parsing notifikasi pembayaran dari bank/e-wallet Indonesia.
class ParsedPaymentNotification {
  const ParsedPaymentNotification({
    required this.amount,
    required this.merchantName,
    required this.sourceApp,
    required this.mutationType,
    this.suggestedCategory,
    this.rawTitle = '',
    this.rawBody = '',
    this.postTime,
  });

  /// Nominal pembayaran dalam Rupiah (selalu positif).
  final double amount;

  /// Nama merchant / penerima transfer yang diekstrak.
  final String merchantName;

  /// Package ID aplikasi sumber notifikasi (misal: `com.bca`).
  final String sourceApp;

  /// Jenis mutasi: `debit` (pengeluaran) atau `credit` (pemasukan).
  final PaymentMutationType mutationType;

  /// Saran kategori berdasarkan kata kunci merchant.
  final String? suggestedCategory;

  /// Judul notifikasi asli (untuk debug / audit).
  final String rawTitle;

  /// Isi notifikasi asli (untuk debug / audit).
  final String rawBody;

  /// Waktu notifikasi diterima (epoch milliseconds).
  final int? postTime;

  /// Nama bank/e-wallet yang dapat dibaca manusia berdasarkan [sourceApp].
  String get accountLabel => PaymentNotificationParser.labelFor(sourceApp);

  @override
  String toString() =>
      'ParsedPayment(amount=$amount, merchant=$merchantName, '
      'source=$sourceApp, type=$mutationType, category=$suggestedCategory)';
}

enum PaymentMutationType { debit, credit, unknown }

/// Parser notifikasi pembayaran 100% lokal (regex-based).
///
/// Semua pemrosesan dilakukan di dalam perangkat tanpa mengirim data ke cloud.
/// Mendukung format notifikasi dari: BCA, Mandiri, BRI, BNI, GoPay, OVO, DANA,
/// ShopeePay.
///
/// Prinsip keamanan:
/// - Hanya menangkap notifikasi keberhasilan pembayaran.
/// - Notifikasi OTP, login, dan keamanan difilter sebelum sampai ke sini
///   (oleh FfmNotificationListenerService di Kotlin).
/// - Hasilnya adalah `PaymentDraft` yang memerlukan konfirmasi pengguna sebelum
///   disimpan ke database.
class PaymentNotificationParser {
  PaymentNotificationParser._();

  // ---------------------------------------------------------------------------
  // Regex ekstraksi nominal uang Indonesia
  // ---------------------------------------------------------------------------

  /// Cocok dengan format: Rp 45.000 / Rp. 120.500 / IDR 50,000 / Rp45000
  /// Grup 1: angka dengan titik/koma sebagai pemisah ribuan.
  static final _amountRegex = RegExp(
    r'(?:Rp\.?\s*|IDR\s*)([\d.,]+)',
    caseSensitive: false,
  );

  // ---------------------------------------------------------------------------
  // Regex deteksi merchant / penerima berdasarkan pola kalimat
  // Catatan: Single-quote di raw string menggunakan variasi pola alternatif
  // ---------------------------------------------------------------------------

  static List<RegExp> get _merchantPatterns => [
    // "QRIS ke MERCHANT berhasil" / "QRIS di MERCHANT"
    RegExp(
      r'(?:QRIS|qris)\s+(?:ke|di|to)\s+([A-Z0-9][A-Z0-9 &\-\.]{1,48}?)(?=\s+berhasil|\s+sukses|\.|\s+via|\s+Rp|\s+sebesar|$)',
      caseSensitive: false,
    ),
    // "Transfer / uang masuk dari NAMA" — nama pengirim kredit
    RegExp(
      r'(?:dari|from)\s+([A-Z0-9][A-Z0-9 &\-\.]{1,48}?)(?=\s+sebesar|\s+berhasil|\s+sukses|\s+telah|\s+masuk|\s+Rp|\.|$)',
      caseSensitive: false,
    ),
    // "ke MERCHANT berhasil" — merchant sebelum kata berhasil/sukses (abaikan kata rekening/akun/saldo/dompet)
    RegExp(
      r'\bke\s+(?!(?:rekening|akun|dompet|saldo|kantong)\b)([A-Z][A-Z0-9 &\-\.]{1,48}?)(?=\s+berhasil|\s+sukses|\s+sebesar|\s+Rp|\s+via|\.|$)',
      caseSensitive: false,
    ),
    // "di MERCHANT berhasil" — merchant sebelum kata berhasil/sukses
    RegExp(
      r'\bdi\s+([A-Z][A-Z0-9 &\-\.]{1,48}?)(?=\s+berhasil|\s+sukses|\.|$)',
      caseSensitive: false,
    ),
    // "Pembayaran ke/di MERCHANT"
    RegExp(
      r'[Pp]embayaran\s+(?:ke|di)\s+([A-Z][A-Z0-9 &\-\.]{2,49})',
      caseSensitive: false,
    ),
    // "Transfer ke NAMA" — nama sebelum berhasil/Rp
    RegExp(
      r'[Tt]ransfer\s+(?:ke|to)\s+(?!(?:rekening|akun|dompet|saldo|kantong)\b)([A-Z][A-Z0-9 &\-\.]{1,48}?)(?=\s+berhasil|\s+sukses|\s+sebesar|\s+Rp|\.|$)',
      caseSensitive: false,
    ),
    // "Bayar MERCHANT" / "Membayar MERCHANT"
    RegExp(
      r'[Bb]ayar(?:an)?\s+([A-Z][A-Z0-9 &\-\.]{1,48}?)(?=\s+berhasil|\s+sukses|\s+sebesar|\s+Rp|\.|$)',
      caseSensitive: false,
    ),
    // GoPay: "Ke MERCHANT" (seluruh string)
    RegExp(
      r'^Ke\s+([A-Z][A-Z0-9 &\-\.]{2,49})$',
      caseSensitive: false,
    ),
    // OVO: "MERCHANT - berhasil dibayar" (tanda hubung ASCII)
    RegExp(
      r'^([A-Z][A-Z0-9 &\-\.]{2,49})\s*-\s*(?:berhasil|sukses)',
      caseSensitive: false,
    ),
  ];

  // ---------------------------------------------------------------------------
  // Deteksi jenis mutasi (debit / kredit)
  // ---------------------------------------------------------------------------

  static final _debitKeywords = RegExp(
    r'\b(bayar|pembayaran|transfer|beli|belanja|tarik|keluar|debit|withdrawal|payment|purchase)\b',
    caseSensitive: false,
  );

  static final _creditKeywords = RegExp(
    r'\b(terima|masuk|top.?up|isi ulang|credit|menerima|diterima|incoming|receive)\b',
    caseSensitive: false,
  );

  // ---------------------------------------------------------------------------
  // Saran kategori berdasarkan kata kunci merchant
  // ---------------------------------------------------------------------------

  static const _categoryKeywords = <String, List<String>>{
    'Makanan & Minuman': [
      'kopi', 'coffee', 'cafe', 'resto', 'restoran', 'makan', 'warung',
      'nasi', 'bakso', 'mie', 'sushi', 'pizza', 'burger', 'ayam', 'seafood',
      'es krim', 'ice cream', 'boba', 'milk tea', 'starbucks', 'kfc', 'mcd',
      'mcdonalds', 'chatime', 'hokben', 'hokahoka', 'dunkin',
      'jco', 'j.co', 'kenangan', 'kopi kenangan', 'fore', 'excelso',
    ],
    'Belanja & Ritel': [
      'alfamart', 'indomaret', 'minimart', 'supermarket', 'hypermart',
      'carrefour', 'hero', 'giant', 'lottemart', 'ranch market',
      'tokopedia', 'shopee', 'lazada', 'blibli', 'bukalapak', 'zalora',
    ],
    'Transportasi': [
      'gojek', 'grab', 'ojek', 'taxi', 'taksi', 'bensin', 'bbm', 'spbu',
      'pertamina', 'shell', 'vivo', 'parkir', 'tol', 'transjakarta',
      'commuter', 'mrt', 'lrt', 'damri',
    ],
    'Kesehatan': [
      'apotek', 'apotik', 'farmasi', 'kimia farma', 'guardian', 'century',
      'rumah sakit', 'klinik', 'dokter', 'rs ', 'puskesmas', 'laboratorium',
    ],
    'Tagihan & Utilitas': [
      'pln', 'listrik', 'pdam', 'air', 'gas', 'telkom', 'indihome',
      'wifi', 'internet', 'pulsa', 'paket data', 'xl', 'indosat',
      'tri ', 'smartfren', 'telkomsel',
    ],
    'Hiburan': [
      'cgv', 'cinepolis', 'xxi', 'netflix', 'spotify', 'youtube',
      'disney', 'vidio', 'main', 'game', 'steam', 'ps store',
    ],
  };

  // ---------------------------------------------------------------------------
  // Label nama bank/e-wallet berdasarkan package ID
  // ---------------------------------------------------------------------------

  static const _appLabels = <String, String>{
    'com.bca': 'BCA Mobile',
    'com.bca.mybca': 'myBCA',
    'com.bankmandiri.livin': "Livin' Mandiri",
    'id.co.bri.brimo': 'BRImo',
    'id.bni.mobile': 'BNI Mobile',
    'id.co.bni.wondr': 'Wondr BNI',
    'com.seabank.id': 'SeaBank',
    'com.gojek.app': 'GoPay',
    'com.gopay.wallet': 'GoPay',
    'ovo.id': 'OVO',
    'id.dana': 'DANA',
    'com.shopee.id': 'ShopeePay',
  };

  // ---------------------------------------------------------------------------
  // API Publik
  // ---------------------------------------------------------------------------

  /// Parse notifikasi dan kembalikan hasil ekstraksi, atau `null` jika
  /// notifikasi ini bukan notifikasi pembayaran yang valid.
  static ParsedPaymentNotification? parse({
    required String packageName,
    required String title,
    required String body,
    int? postTime,
  }) {
    final combined = '$title $body';

    // 1. Ekstrak nominal — wajib ada, jika tidak ada berarti bukan notif pembayaran
    final amount = _extractAmount(combined);
    if (amount == null || amount <= 0) return null;

    // 2. Deteksi jenis mutasi
    final mutationType = _detectMutationType(combined);

    // 3. Ekstrak nama merchant / penerima
    final merchantName = _extractMerchant(title, body);

    // 4. Saran kategori
    final suggestedCategory = merchantName.isNotEmpty
        ? _suggestCategory(merchantName)
        : null;

    return ParsedPaymentNotification(
      amount: amount,
      merchantName: merchantName,
      sourceApp: packageName,
      mutationType: mutationType,
      suggestedCategory: suggestedCategory,
      rawTitle: title,
      rawBody: body,
      postTime: postTime,
    );
  }

  /// Kembalikan label nama bank/e-wallet dari package ID.
  static String labelFor(String packageName) =>
      _appLabels[packageName] ?? packageName;

  // ---------------------------------------------------------------------------
  // Implementasi internal
  // ---------------------------------------------------------------------------

  static double? _extractAmount(String text) {
    final match = _amountRegex.firstMatch(text);
    if (match == null) return null;
    final raw = match.group(1) ?? '';
    // Normalisasi format angka:
    // - Indonesia: 1.234.567 atau 1.234,50 (titik=ribuan, koma=desimal)
    // - Internasional (IDR): 50,000 atau 1,234,567 (koma=ribuan)
    // Aturan: jika koma ada DAN digit setelah koma persis 3 => koma adalah ribuan
    String normalized;
    if (raw.contains(',')) {
      final commaIdx = raw.lastIndexOf(',');
      final afterComma = raw.substring(commaIdx + 1);
      if (afterComma.length == 3 && !afterComma.contains('.')) {
        // Koma sebagai pemisah ribuan (format internasional seperti IDR 50,000)
        normalized = raw.replaceAll(',', '').replaceAll('.', '');
      } else {
        // Koma sebagai pemisah desimal Indonesia (Rp 1.234,50)
        normalized = raw.replaceAll('.', '').replaceAll(',', '.');
      }
    } else {
      // Tidak ada koma: titik adalah pemisah ribuan
      normalized = raw.replaceAll('.', '');
    }
    return double.tryParse(normalized);
  }

  static PaymentMutationType _detectMutationType(String text) {
    final lower = text.toLowerCase();
    // Cek frasa kredit spesifik (misal: "transfer masuk", "menerima transfer", "dana masuk", "top-up")
    final explicitCredit = RegExp(
      r'\b(transfer masuk|dana masuk|uang masuk|menerima transfer|terima transfer|diterima dari|masuk ke|transfer dari|top.?up)\b',
      caseSensitive: false,
    );
    if (explicitCredit.hasMatch(lower)) return PaymentMutationType.credit;

    // Cek frasa debit spesifik (misal: "transfer ke", "transfer keluar", "pembayaran ke", "bayar di")
    final explicitDebit = RegExp(
      r'\b(transfer (?:ke|to)|transfer keluar|pembayaran|bayar|pembelian|beli|tarik)\b',
      caseSensitive: false,
    );
    if (explicitDebit.hasMatch(lower)) return PaymentMutationType.debit;

    final hasDebit = _debitKeywords.hasMatch(text);
    final hasCredit = _creditKeywords.hasMatch(text);
    if (hasCredit && !hasDebit) return PaymentMutationType.credit;
    if (hasDebit && !hasCredit) return PaymentMutationType.debit;
    // Default ke debit jika tidak dapat ditentukan (lebih aman untuk pencatatan)
    return PaymentMutationType.debit;
  }

  static String _extractMerchant(String title, String body) {
    final patterns = _merchantPatterns;
    // Coba ekstrak dari body terlebih dahulu (lebih informatif)
    for (final pattern in patterns) {
      final match = pattern.firstMatch(body);
      if (match != null) {
        final merchant = (match.group(1) ?? '').trim();
        if (merchant.length >= 2) return _cleanMerchant(merchant);
      }
    }
    // Fallback ke judul
    for (final pattern in patterns) {
      final match = pattern.firstMatch(title);
      if (match != null) {
        final merchant = (match.group(1) ?? '').trim();
        if (merchant.length >= 2) return _cleanMerchant(merchant);
      }
    }
    return '';
  }

  static String _cleanMerchant(String raw) {
    return raw
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp('[""""]'), '')
        .trim()
        .toUpperCase();
  }

  static String? _suggestCategory(String merchantName) {
    final lower = merchantName.toLowerCase();
    for (final entry in _categoryKeywords.entries) {
      for (final keyword in entry.value) {
        if (lower.contains(keyword)) return entry.key;
      }
    }
    return null;
  }
}
