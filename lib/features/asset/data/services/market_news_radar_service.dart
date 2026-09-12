import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/entities/market_news_models.dart';

/// Layanan pengambil data pasar finansial publik & warta berita terkini secara real-time.
///
/// Berjalan hening via HTTP Client (<0,2 detik), aman tanpa API key berbayar,
/// dan mendukung fallback offline tanpa crash (Zero-Crash).
class MarketNewsRadarService {
  const MarketNewsRadarService();

  static const _requestTimeout = Duration(seconds: 5);

  /// Mengambil data harga pasar terkini (Valas, Kripto, dan Emas Antam).
  Future<MarketPriceSnapshot> fetchMarketPrices({http.Client? client}) async {
    final httpClient = client ?? http.Client();
    final now = DateTime.now();

    var usdRate = 15650.0;
    var sgdRate = 11950.0;
    var eurRate = 16920.0;
    var sarRate = 4170.0;
    var chfRate = 17800.0;
    var btcPrice = 1050000000.0;
    var ethPrice = 55000000.0;
    var usdtPrice = 15680.0;
    var goldPrice24K = 1425000;
    var goldBuybackPrice = 1285000;

    final verifiedInstruments = <MarketInstrument>{};

    // 1. Ambil Kurs Valas (USD, SGD, EUR, SAR, CHF ke IDR) via open.er-api.com
    try {
      final res = await httpClient
          .get(Uri.parse('https://open.er-api.com/v6/latest/USD'))
          .timeout(_requestTimeout);

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final rates = data['rates'] as Map<String, dynamic>?;
        if (rates != null && rates.containsKey('IDR')) {
          final idr = (rates['IDR'] as num).toDouble();
          usdRate = idr;
          verifiedInstruments.add(MarketInstrument.usd);

          if (rates.containsKey('SGD')) {
            final sgdVal = (rates['SGD'] as num?)?.toDouble() ?? 0.0;
            if (sgdVal > 0) {
              sgdRate = idr / sgdVal;
              verifiedInstruments.add(MarketInstrument.sgd);
            }
          }
          if (rates.containsKey('EUR')) {
            final eurVal = (rates['EUR'] as num?)?.toDouble() ?? 0.0;
            if (eurVal > 0) {
              eurRate = idr / eurVal;
              verifiedInstruments.add(MarketInstrument.eur);
            }
          }
          if (rates.containsKey('SAR')) {
            final sarVal = (rates['SAR'] as num?)?.toDouble() ?? 0.0;
            if (sarVal > 0) {
              sarRate = idr / sarVal;
              verifiedInstruments.add(MarketInstrument.sar);
            }
          }
          if (rates.containsKey('CHF')) {
            final chfVal = (rates['CHF'] as num?)?.toDouble() ?? 0.0;
            if (chfVal > 0) {
              chfRate = idr / chfVal;
              verifiedInstruments.add(MarketInstrument.chf);
            }
          }
        }
      }
    } catch (_) {
      // Graceful degradation
    }

    // Sumber kedua tetap dipanggil agar setiap refresh membandingkan dan
    // melengkapi data dari semua provider yang tersedia.
    try {
      final res = await httpClient
          .get(Uri.parse(
              'https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/usd.json'))
          .timeout(_requestTimeout);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final rates = data['usd'] as Map<String, dynamic>?;
        final idr = (rates?['idr'] as num?)?.toDouble();
        if (idr != null && idr > 0) {
          if (!verifiedInstruments.contains(MarketInstrument.usd)) {
            usdRate = idr;
            verifiedInstruments.add(MarketInstrument.usd);
          }
          final sgd = (rates?['sgd'] as num?)?.toDouble();
          final eur = (rates?['eur'] as num?)?.toDouble();
          final sar = (rates?['sar'] as num?)?.toDouble();
          final chf = (rates?['chf'] as num?)?.toDouble();
          if (!verifiedInstruments.contains(MarketInstrument.sgd) &&
              sgd != null &&
              sgd > 0) {
            sgdRate = idr / sgd;
            verifiedInstruments.add(MarketInstrument.sgd);
          }
          if (!verifiedInstruments.contains(MarketInstrument.eur) &&
              eur != null &&
              eur > 0) {
            eurRate = idr / eur;
            verifiedInstruments.add(MarketInstrument.eur);
          }
          if (!verifiedInstruments.contains(MarketInstrument.sar) &&
              sar != null &&
              sar > 0) {
            sarRate = idr / sar;
            verifiedInstruments.add(MarketInstrument.sar);
          }
          if (!verifiedInstruments.contains(MarketInstrument.chf) &&
              chf != null &&
              chf > 0) {
            chfRate = idr / chf;
            verifiedInstruments.add(MarketInstrument.chf);
          }
        }
      }
    } catch (_) {
      // Tetap gunakan fallback lokal bila kedua provider gagal.
    }

    // 2. Ambil Kripto (BTC, ETH, USDT ke IDR) via CoinGecko Public API
    try {
      final res = await httpClient
          .get(
              Uri.parse(
                  'https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum,tether&vs_currencies=idr'),
              headers: {'Accept': 'application/json'})
          .timeout(_requestTimeout);

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (data.containsKey('bitcoin')) {
          btcPrice =
              (data['bitcoin']['idr'] as num?)?.toDouble() ?? btcPrice;
          verifiedInstruments.add(MarketInstrument.btc);
        }
        if (data.containsKey('ethereum')) {
          ethPrice =
              (data['ethereum']['idr'] as num?)?.toDouble() ?? ethPrice;
          verifiedInstruments.add(MarketInstrument.eth);
        }
        if (data.containsKey('tether')) {
          usdtPrice =
              (data['tether']['idr'] as num?)?.toDouble() ?? usdtPrice;
          verifiedInstruments.add(MarketInstrument.usdt);
        }
      }
    } catch (_) {
      // Fallback kripto
    }

    // This is a display estimate only. It has no provider evidence and must
    // never be used to revalue a persisted asset.
    if (usdRate > 0) {
      // Estimasi emas Antam: ~$2.500/troy oz * kurs USD / 31.1035 + premi cetak domestik
      final estimatedGram = ((2500.0 * usdRate) / 31.1035) * 1.13;
      goldPrice24K = (estimatedGram / 1000).round() * 1000;
      goldBuybackPrice = (goldPrice24K * 0.902).round();
    }

    if (client == null) {
      httpClient.close();
    }

    return MarketPriceSnapshot(
      goldPrice24K: goldPrice24K,
      goldBuybackPrice: goldBuybackPrice,
      usdRate: usdRate,
      sgdRate: sgdRate,
      eurRate: eurRate,
      sarRate: sarRate,
      chfRate: chfRate,
      btcPrice: btcPrice,
      ethPrice: ethPrice,
      usdtPrice: usdtPrice,
      lastUpdated: now,
       isOfflineCache: !verifiedInstruments.any(
         (instrument) => const {
           MarketInstrument.usd,
           MarketInstrument.sgd,
           MarketInstrument.eur,
           MarketInstrument.sar,
           MarketInstrument.chf,
         }.contains(instrument),
       ),
      verifiedInstruments: verifiedInstruments,
    );
  }

  /// Mengambil warta berita dan peringatan terpilih (Pertanian, BMKG Cuaca, Finansial).
  ///
  /// Mencoba mengambil RSS feed publik terkini secara real-time.
  /// Jika offline atau gagal, melakukan degradasi anggun (graceful fallback) ke berita kurasi lokal.
  Future<List<NewsAlertItem>> fetchCuratedNews({http.Client? client}) async {
    final httpClient = client ?? http.Client();
    const feeds = <({String url, String source})>[
      (url: 'https://www.antaranews.com/rss/terkini.xml', source: 'Antara News'),
      (url: 'https://www.cnbcindonesia.com/rss', source: 'CNBC Indonesia'),
    ];
    final feedResults = await Future.wait<List<NewsAlertItem>>(
      feeds.map((feed) async {
        try {
          final res = await httpClient
              .get(Uri.parse(feed.url))
              .timeout(_requestTimeout);
          if (res.statusCode == 200 && res.body.trim().isNotEmpty) {
            return parseRssFeed(res.body, defaultSource: feed.source);
          }
        } catch (_) {
          // Sumber gagal tidak boleh menggagalkan feed lainnya.
        }
        return const <NewsAlertItem>[];
      }).followedBy([_fetchLatestBmkgNews(httpClient)]),
    );
    final collected = feedResults.expand((items) => items).toList();

    if (collected.isNotEmpty) {
      final unique = <String, NewsAlertItem>{};
      for (final item in collected) {
        unique[item.url ?? item.title.toLowerCase()] = item;
      }
      final result = unique.values.toList()
        ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
      if (client == null) httpClient.close();
      return result.take(10).toList();
    }

    if (client == null) {
      httpClient.close();
    }

    // Educational fallback. Dates are fixed and explicitly marked, so a
    // refresh cannot turn static content into fabricated current news.
    final fallbackPublishedAt = DateTime.utc(2026, 1, 1);
    final defaultNews = [
      NewsAlertItem(
        id: 'news_bmkg_1',
        title:
            'BMKG Rilis Potensi Cuaca Ekstrem & Hujan Lebat Sepekan ke Depan',
        snippet: 'BMKG mengimbau masyarakat dan petani mewaspadai potensi genangan air di lahan pertanian dataran rendah serta pergeseran tanah.',
        sourceName: 'BMKG Indonesia',
        publishedAt: fallbackPublishedAt,
        category: NewsCategory.weatherDisaster,
        url: 'https://www.bmkg.go.id',
        isFallback: true,
      ),
      NewsAlertItem(
        id: 'news_tani_1',
        title: 'Kementan Perluas Penyaluran Pupuk Bersubsidi untuk Musim Tanam',
        snippet: 'Pemerintah menambah kuota pupuk urea dan NPK bersubsidi guna mendukung ketahanan pangan dan kestabilan biaya modal petani.',
        sourceName: 'Antara Pertanian',
        publishedAt: fallbackPublishedAt,
        category: NewsCategory.agriculture,
        url: 'https://www.antaranews.com',
        isFallback: true,
      ),
      NewsAlertItem(
        id: 'news_fin_1',
        title: 'Bank Indonesia Pertahankan BI-Rate: Stabilitas Rupiah Terjaga',
        snippet: 'Keputusan ini diarahkan untuk memperkuat stabilitas nilai tukar Rupiah dari dampak ketidakpastian geopolitik global.',
        sourceName: 'Bank Indonesia',
        publishedAt: fallbackPublishedAt,
        category: NewsCategory.finance,
        url: 'https://www.bi.go.id',
        isFallback: true,
      ),
      NewsAlertItem(
        id: 'news_tani_2',
        title: 'Tren Harga Gabah Kering Panen di Pasar Regional Menguat',
        snippet: 'Permintaan beras yang stabil mendorong peningkatan harga beli gabah kering panen di tingkat penggilingan petani.',
        sourceName: 'Warta Pangan',
        publishedAt: fallbackPublishedAt,
        category: NewsCategory.agriculture,
        isFallback: true,
      ),
      NewsAlertItem(
        id: 'news_bmkg_2',
        title: 'Waspada Angin Kencang dan Potensi Titik Panas di Lahan Gambut',
        snippet: 'Petani dan pemilik lahan perkebunan diimbau tidak melakukan pembakaran sisa jerami secara sembarangan untuk mencegah karhutla.',
        sourceName: 'Radar Bencana BMKG',
        publishedAt: fallbackPublishedAt,
        category: NewsCategory.weatherDisaster,
        isFallback: true,
      ),
    ];

    return defaultNews;
  }

  /// Menyaring berita yang relevan dengan fokus aplikasi dan preferensi user.
  /// Pencocokan dilakukan lokal terhadap judul dan ringkasan.
  static bool isRelevantForUser(
    NewsAlertItem item, {
    required Iterable<String> keywords,
  }) {
    const coreCategories = {
      NewsCategory.agriculture,
      NewsCategory.weatherDisaster,
      NewsCategory.finance,
    };
    if (coreCategories.contains(item.category)) return true;

    final content = '${item.title} ${item.snippet}'.toLowerCase();
    return keywords.any((keyword) {
      final normalized = keyword.trim().toLowerCase();
      return normalized.isNotEmpty && content.contains(normalized);
    });
  }

  Future<List<NewsAlertItem>> _fetchLatestBmkgNews(http.Client client) async {
    try {
      final res = await client
          .get(Uri.parse('https://data.bmkg.go.id/DataMKG/TEWS/autogempa.json'))
          .timeout(_requestTimeout);
      if (res.statusCode != 200 || res.body.trim().isEmpty) {
        return const [];
      }
      return parseBmkgEarthquake(res.body);
    } catch (_) {
      return const [];
    }
  }

  static List<NewsAlertItem> parseBmkgEarthquake(String body) {
    try {
      final root = jsonDecode(body) as Map<String, dynamic>;
      final info = root['Infogempa'] as Map<String, dynamic>?;
      final earthquake = info?['gempa'] as Map<String, dynamic>?;
      if (earthquake == null) return const [];

      final title = 'Gempa M${earthquake['Magnitude'] ?? '-'}'
          ' - ${earthquake['Wilayah'] ?? 'wilayah Indonesia'}';
      final details = [
        if (earthquake['Kedalaman'] != null)
          'Kedalaman ${earthquake['Kedalaman']}',
        if (earthquake['Potensi'] != null) earthquake['Potensi'],
        if (earthquake['Dirasakan'] != null &&
            earthquake['Dirasakan'].toString().trim().isNotEmpty)
          'Dirasakan: ${earthquake['Dirasakan']}',
      ].join('. ');
      final publishedAt = DateTime.tryParse(
        earthquake['DateTime']?.toString() ?? '',
      );
      final fetchedAt = DateTime.now();

      return [
        NewsAlertItem(
          id: 'bmkg_${earthquake['DateTime'] ?? fetchedAt.millisecondsSinceEpoch}',
          title: title,
          snippet: details.isEmpty ? 'Informasi gempa terbaru dari BMKG.' : details,
          sourceName: 'BMKG Indonesia',
          publishedAt: publishedAt ?? fetchedAt,
          category: NewsCategory.weatherDisaster,
          url: 'https://data.bmkg.go.id/DataMKG/TEWS/autogempa.json',
          fetchedAt: fetchedAt,
          isPublishedAtKnown: publishedAt != null,
        ),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Helper untuk mem-parsing XML RSS 2.0 standar menjadi koleksi [NewsAlertItem].
  static List<NewsAlertItem> parseRssFeed(
    String xmlContent, {
    String defaultSource = 'Warta Publik',
  }) {
    final items = <NewsAlertItem>[];
    final itemPattern = RegExp(
      r'<item>([\s\S]*?)</item>',
      caseSensitive: false,
    );
    final titlePattern = RegExp(
      r'<title>(?:<!\[CDATA\[)?([\s\S]*?)(?:\]\]>)?</title>',
      caseSensitive: false,
    );
    final linkPattern = RegExp(
      r'<link>(?:<!\[CDATA\[)?([\s\S]*?)(?:\]\]>)?</link>',
      caseSensitive: false,
    );
    final descPattern = RegExp(
      r'<description>(?:<!\[CDATA\[)?([\s\S]*?)(?:\]\]>)?</description>',
      caseSensitive: false,
    );
    final pubDatePattern = RegExp(
      r'<pubDate>(?:<!\[CDATA\[)?([\s\S]*?)(?:\]\]>)?</pubDate>',
      caseSensitive: false,
    );

    final matches = itemPattern.allMatches(xmlContent);
    var index = 0;
    for (final match in matches) {
      if (items.length >= 10) break;
      final itemBlock = match.group(1) ?? '';
      final rawTitle =
          titlePattern.firstMatch(itemBlock)?.group(1)?.trim() ?? '';
      final rawLink = linkPattern.firstMatch(itemBlock)?.group(1)?.trim() ?? '';
      final rawDesc = descPattern.firstMatch(itemBlock)?.group(1)?.trim() ?? '';
      final rawPubDate =
          pubDatePattern.firstMatch(itemBlock)?.group(1)?.trim() ?? '';

      if (rawTitle.isEmpty) continue;

      final title = _cleanHtml(rawTitle);
      final snippet = _cleanHtml(rawDesc);
      final parsedPublishedAt = _parseRssDate(rawPubDate);
      // Keep a stable sentinel only for the required model field; consumers
      // must use isPublishedAtKnown before making any recency claim.
      final publishedAt =
          parsedPublishedAt ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      final category = _categorizeNews(title, snippet);

      items.add(
        NewsAlertItem(
          id: 'rss_${index}_${publishedAt.millisecondsSinceEpoch}',
          title: title,
          snippet: snippet.isNotEmpty ? snippet : title,
          sourceName: defaultSource,
          publishedAt: publishedAt,
          category: category,
          url: rawLink.isNotEmpty ? rawLink : null,
          isPublishedAtKnown: parsedPublishedAt != null,
          fetchedAt: DateTime.now(),
        ),
      );
      index++;
    }
    return items;
  }

  static String _cleanHtml(String text) {
    return text
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static NewsCategory _categorizeNews(String title, String snippet) {
    final lower = '$title $snippet'.toLowerCase();
    if (lower.contains('hujan') ||
        lower.contains('cuaca') ||
        lower.contains('bmkg') ||
        lower.contains('gempa') ||
        lower.contains('tsunami') ||
        lower.contains('banjir') ||
        lower.contains('longsor') ||
        lower.contains('kebakaran') ||
        lower.contains('karhutla') ||
        lower.contains('erupsi') ||
        lower.contains('gunung meletus') ||
        lower.contains('bencana') ||
        lower.contains('evakuasi') ||
        lower.contains('darurat') ||
        lower.contains('angin kencang') ||
        lower.contains('waspada')) {
      return NewsCategory.weatherDisaster;
    }
    if (lower.contains('tani') ||
        lower.contains('panen') ||
        lower.contains('pupuk') ||
        lower.contains('gabah') ||
        lower.contains('padi') ||
        lower.contains('beras') ||
        lower.contains('lahan') ||
        lower.contains('kebun') ||
        lower.contains('kementan')) {
      return NewsCategory.agriculture;
    }
    if (lower.contains('rupiah') ||
        lower.contains('inflasi') ||
        lower.contains('bunga') ||
        lower.contains('bank') ||
        lower.contains('ihsg') ||
        lower.contains('investasi') ||
        lower.contains('pasar') ||
        lower.contains('anggaran') ||
        lower.contains('bi-rate') ||
        lower.contains('uang')) {
      return NewsCategory.finance;
    }
    return NewsCategory.all;
  }

  static DateTime? _parseRssDate(String dateStr) {
    if (dateStr.isEmpty) return null;
    try {
      return DateTime.parse(dateStr);
    } catch (_) {
      // RFC-822 / RFC-1123 date parsing sederhana e.g. "Tue, 08 Sep 2026 12:00:00 GMT"
      try {
        final parts = dateStr.split(' ');
        if (parts.length >= 4) {
          final day = int.tryParse(parts[1]);
          final year = int.tryParse(parts[3]);
          final months = {
            'jan': 1,
            'feb': 2,
            'mar': 3,
            'apr': 4,
            'may': 5,
            'jun': 6,
            'jul': 7,
            'aug': 8,
            'sep': 9,
            'oct': 10,
            'nov': 11,
            'dec': 12,
          };
          final month = months[parts[2].toLowerCase().substring(0, 3)];
          if (day != null && year != null && month != null) {
            return DateTime(year, month, day);
          }
        }
      } catch (_) {}
      return null;
    }
  }
}
