/// Standar kadar kemurnian emas perhiasan dan batangan di Indonesia.
enum GoldKarat {
  /// 24 Karat (99.9% - Logam Mulia Batangan Antam / UBS / Pegadaian)
  k24(24, 1.0, '24K (Batangan 99.9%)'),

  /// 22 Karat (91.6% - Emas Tua)
  k22(22, 22 / 24, '22K (Emas Tua 91.6%)'),

  /// 18 Karat (75.0% - Standar Perhiasan Toko Emas)
  k18(18, 18 / 24, '18K (Perhiasan Toko 75%)'),

  /// 16 Karat (66.6%)
  k16(16, 16 / 24, '16K (66.6%)'),

  /// 10 Karat (41.6% - Emas Muda)
  k10(10, 10 / 24, '10K (Emas Muda 41.6%)');

  const GoldKarat(this.karatValue, this.purityFactor, this.label);

  final int karatValue;
  final double purityFactor;
  final String label;

  /// Menghitung taksiran nilai pasar emas dalam Rupiah secara deterministik.
  static int calculateValueStatic({
    required double weightGrams,
    required GoldKarat karat,
    required int goldPrice24K,
  }) {
    if (weightGrams <= 0 || goldPrice24K <= 0) return 0;
    return (weightGrams * goldPrice24K * karat.purityFactor).round();
  }

  /// Instance helper untuk menghitung taksiran nilai emas.
  int calculateValue({
    required double weightGrams,
    required int pricePerGram24K,
  }) {
    if (weightGrams <= 0 || pricePerGram24K <= 0) return 0;
    return (weightGrams * pricePerGram24K * purityFactor).round();
  }
}

/// Snapshot harga pasar terkini (Emas, Valas, dan Kripto).
class MarketPriceSnapshot {
  const MarketPriceSnapshot({
    required this.goldPrice24K,
    required this.goldBuybackPrice,
    required this.usdRate,
    required this.sgdRate,
    required this.eurRate,
    required this.sarRate,
    required this.btcPrice,
    required this.ethPrice,
    required this.usdtPrice,
    required this.lastUpdated,
    this.isOfflineCache = false,
  });

  /// Harga beli emas batangan 24K per gram (IDR).
  final int goldPrice24K;

  /// Harga jual kembali (buyback) emas batangan per gram (IDR).
  final int goldBuybackPrice;

  /// Kurs 1 USD ke IDR.
  final double usdRate;

  /// Kurs 1 SGD ke IDR.
  final double sgdRate;

  /// Kurs 1 EUR ke IDR.
  final double eurRate;

  /// Kurs 1 SAR (Riyal Arab Saudi) ke IDR (Tabungan Haji/Umrah).
  final double sarRate;

  /// Harga 1 Bitcoin (BTC) dalam IDR.
  final double btcPrice;

  /// Harga 1 Ethereum (ETH) dalam IDR.
  final double ethPrice;

  /// Harga 1 Tether (USDT) dalam IDR.
  final double usdtPrice;

  final DateTime lastUpdated;
  final bool isOfflineCache;

  /// Default harga pasar jika belum pernah tersambung ke web.
  factory MarketPriceSnapshot.initialFallback() => MarketPriceSnapshot(
        goldPrice24K: 1425000,
        goldBuybackPrice: 1285000,
        usdRate: 15650.0,
        sgdRate: 11950.0,
        eurRate: 16920.0,
        sarRate: 4170.0,
        btcPrice: 1050000000.0,
        ethPrice: 55000000.0,
        usdtPrice: 15680.0,
        lastUpdated: DateTime.now(),
        isOfflineCache: true,
      );

  Map<String, dynamic> toJson() => {
        'goldPrice24K': goldPrice24K,
        'goldBuybackPrice': goldBuybackPrice,
        'usdRate': usdRate,
        'sgdRate': sgdRate,
        'eurRate': eurRate,
        'sarRate': sarRate,
        'btcPrice': btcPrice,
        'ethPrice': ethPrice,
        'usdtPrice': usdtPrice,
        'lastUpdated': lastUpdated.toIso8601String(),
        'isOfflineCache': isOfflineCache,
      };

  factory MarketPriceSnapshot.fromJson(Map<String, dynamic> json) =>
      MarketPriceSnapshot(
        goldPrice24K: (json['goldPrice24K'] as num?)?.toInt() ?? 1425000,
        goldBuybackPrice:
            (json['goldBuybackPrice'] as num?)?.toInt() ?? 1285000,
        usdRate: (json['usdRate'] as num?)?.toDouble() ?? 15650.0,
        sgdRate: (json['sgdRate'] as num?)?.toDouble() ?? 11950.0,
        eurRate: (json['eurRate'] as num?)?.toDouble() ?? 16920.0,
        sarRate: (json['sarRate'] as num?)?.toDouble() ?? 4170.0,
        btcPrice: (json['btcPrice'] as num?)?.toDouble() ?? 1050000000.0,
        ethPrice: (json['ethPrice'] as num?)?.toDouble() ?? 55000000.0,
        usdtPrice: (json['usdtPrice'] as num?)?.toDouble() ?? 15680.0,
        lastUpdated: json['lastUpdated'] != null
            ? DateTime.tryParse(json['lastUpdated'] as String) ?? DateTime.now()
            : DateTime.now(),
        isOfflineCache: json['isOfflineCache'] as bool? ?? false,
      );

  // Convenience getters
  int get goldPerGram24K => goldPrice24K;
  int get goldPerGramBuyback => goldBuybackPrice;
  double get usdToIdr => usdRate;
  double get sgdToIdr => sgdRate;
  double get eurToIdr => eurRate;
  double get sarToIdr => sarRate;
  double get btcToIdr => btcPrice;
  double get ethToIdr => ethPrice;
  double get usdtToIdr => usdtPrice;
}

/// Kategori berita dan peringatan terpilih.
enum NewsCategory {
  all('Semua Kabar'),
  agriculture('🌾 Pertanian & Pangan'),
  weatherDisaster('⛈️ Cuaca & Bencana BMKG'),
  finance('💰 Finansial & Pasar');

  const NewsCategory(this.label);
  final String label;

  static const NewsCategory financial = finance;
  static const NewsCategory general = all;
}

/// Item artikel berita atau peringatan yang tersimpan sementara di cache.
///
/// TIDAK disimpan ke database utama agar database tetap steril dan ringan.
class NewsAlertItem {
  const NewsAlertItem({
    required this.id,
    required this.title,
    required this.snippet,
    required this.sourceName,
    required this.publishedAt,
    required this.category,
    this.url,
    bool? isHighAlert,
  }) : _explicitHighAlert = isHighAlert;

  final String id;
  final String title;
  final String snippet;
  final String sourceName;
  final DateTime publishedAt;
  final NewsCategory category;
  final String? url;
  final bool? _explicitHighAlert;

  // Convenience getters
  String get summary => snippet;
  String get source => sourceName;
  bool get isHighAlert =>
      _explicitHighAlert ??
      (category == NewsCategory.weatherDisaster ||
          title.toLowerCase().contains('waspada') ||
          title.toLowerCase().contains('peringatan') ||
          title.toLowerCase().contains('darurat') ||
          title.toLowerCase().contains('ekstrem'));

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'snippet': snippet,
        'sourceName': sourceName,
        'publishedAt': publishedAt.toIso8601String(),
        'category': category.name,
        'url': url,
        'isHighAlert': isHighAlert,
      };

  factory NewsAlertItem.fromJson(Map<String, dynamic> json) => NewsAlertItem(
        id: json['id'] as String,
        title: json['title'] as String,
        snippet: json['snippet'] as String? ?? '',
        sourceName: json['sourceName'] as String? ?? 'Warta Resmi',
        publishedAt: json['publishedAt'] != null
            ? DateTime.tryParse(json['publishedAt'] as String) ?? DateTime.now()
            : DateTime.now(),
        category: NewsCategory.values.firstWhere(
          (c) => c.name == json['category'],
          orElse: () => NewsCategory.all,
        ),
        url: json['url'] as String?,
        isHighAlert: json['isHighAlert'] as bool?,
      );
}
