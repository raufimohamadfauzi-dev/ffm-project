import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/asset/data/repositories/market_news_cache_repository.dart';
import 'package:ffm_manager/features/asset/data/services/market_news_radar_service.dart';
import 'package:ffm_manager/features/asset/domain/entities/market_news_models.dart';
import 'package:ffm_manager/features/asset/domain/usecases/asset_auto_valuation_service.dart';
import 'package:ffm_manager/features/assistant/data/autonomous_activity_repository.dart';
import 'package:ffm_manager/features/assistant/domain/entities/autonomous_activity_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GoldKarat & Valuation Tests', () {
    test('GoldKarat purity calculations match Indonesian gold standards', () {
      const price24K = 1400000; // Rp 1.400.000 / gram

      // 24K Batangan (100% purity)
      final val24 = GoldKarat.k24.calculateValue(
        weightGrams: 10,
        pricePerGram24K: price24K,
      );

      expect(val24, equals(14000000));

      // 18K Perhiasan Toko Emas (75% purity)
      final val18 = GoldKarat.k18.calculateValue(
        weightGrams: 10,
        pricePerGram24K: price24K,
      );
      expect(val18, equals(10500000)); // 14.000.000 * 0.75

      // 22K Emas Tua (91.67%)
      final val22 = GoldKarat.k22.calculateValue(
        weightGrams: 5,
        pricePerGram24K: price24K,
      );
      expect(val22, equals(((5 * price24K) * (22 / 24)).round()));

      // 16K (66.67%)
      final val16 = GoldKarat.k16.calculateValue(
        weightGrams: 3,
        pricePerGram24K: price24K,
      );
      expect(val16, equals(((3 * price24K) * (16 / 24)).round()));

      // 10K Emas Muda (41.67%)
      final val10 = GoldKarat.k10.calculateValue(
        weightGrams: 4,
        pricePerGram24K: price24K,
      );
      expect(val10, equals(((4 * price24K) * (10 / 24)).round()));
    });
  });

  group('MarketPriceSnapshot & News Models', () {
    test('MarketPriceSnapshot serialization round-trip', () {
      final original = MarketPriceSnapshot(
        goldPrice24K: 1450000,
        goldBuybackPrice: 1330000,
        usdRate: 16250.0,
        sgdRate: 12100.0,
        eurRate: 17300.0,
        sarRate: 4330.0,
        btcPrice: 1050000000.0,
        ethPrice: 42000000.0,
        usdtPrice: 16260.0,
        lastUpdated: DateTime(2026, 9, 4, 12, 0),
        isOfflineCache: false,
      );

      final json = original.toJson();
      final restored = MarketPriceSnapshot.fromJson(json);

      expect(restored.goldPerGram24K, equals(1450000));
      expect(restored.usdToIdr, equals(16250.0));
      expect(restored.sarToIdr, equals(4330.0));
      expect(restored.btcToIdr, equals(1050000000.0));
      expect(restored.isOfflineCache, isFalse);
    });

    test('NewsAlertItem serialization and 48-hour age check', () {
      final recent = NewsAlertItem(
        id: 'news-1',
        title: 'Harga Pupuk Subsidi Terjaga',
        snippet:
            'Kementan memastikan distribusi pupuk subsidi musim tanam aman.',
        sourceName: 'Antara Pertanian',
        url: 'https://example.com/news1',
        category: NewsCategory.agriculture,
        publishedAt: DateTime.now().subtract(const Duration(hours: 12)),
        isHighAlert: false,
      );

      final old = NewsAlertItem(
        id: 'news-2',
        title: 'Peringatan Banjir BMKG',
        snippet: 'Hujan lebat diprediksi terjadi 3 hari lalu.',
        sourceName: 'BMKG',
        url: 'https://example.com/news2',
        category: NewsCategory.weatherDisaster,
        publishedAt: DateTime.now().subtract(const Duration(hours: 50)),
        isHighAlert: true,
      );

      expect(
        recent.publishedAt.isBefore(
          DateTime.now().subtract(const Duration(hours: 48)),
        ),
        isFalse,
      );
      expect(
        old.publishedAt.isBefore(
          DateTime.now().subtract(const Duration(hours: 48)),
        ),
        isTrue,
      );

      final json = recent.toJson();
      final restored = NewsAlertItem.fromJson(json);
      expect(restored.title, equals('Harga Pupuk Subsidi Terjaga'));
      expect(restored.category, equals(NewsCategory.agriculture));
    });
  });

  group('MarketNewsCacheRepository Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Saves and retrieves price snapshot', () async {
      final repo = MarketNewsCacheRepository();
      final snapshot = MarketPriceSnapshot(
        goldPrice24K: 1480000,
        goldBuybackPrice: 1360000,
        usdRate: 16300.0,
        sgdRate: 12200.0,
        eurRate: 17400.0,
        sarRate: 4340.0,
        btcPrice: 1100000000.0,
        ethPrice: 45000000.0,
        usdtPrice: 16310.0,
        lastUpdated: DateTime.now(),
        isOfflineCache: false,
      );

      await repo.savePriceSnapshot(snapshot);
      final retrieved = await repo.getLatestPriceSnapshot();

      expect(retrieved.goldPerGram24K, equals(1480000));
      expect(retrieved.usdToIdr, equals(16300.0));
    });

    test(
      'Auto-prunes news items older than 48 hours without touching database',
      () async {
        final repo = MarketNewsCacheRepository();
        final now = DateTime.now();

        final items = <NewsAlertItem>[
          NewsAlertItem(
            id: 'fresh-1',
            title: 'Musim Panen Raya',
            snippet: 'Panen padi meningkat',
            sourceName: 'Distan',
            url: 'https://example.com/1',
            category: NewsCategory.agriculture,
            publishedAt: now.subtract(const Duration(hours: 5)),
            isHighAlert: false,
          ),
          NewsAlertItem(
            id: 'expired-1',
            title: 'Berita Lama 3 Hari Lalu',
            snippet: 'Sudah kedaluwarsa',
            sourceName: 'Media',
            url: 'https://example.com/2',
            category: NewsCategory.all,
            publishedAt: now.subtract(const Duration(hours: 72)),
            isHighAlert: false,
          ),
        ];

        await repo.saveNewsItems(items);
        final cached = await repo.getCachedNews();

        expect(cached.length, equals(1));
        expect(cached.first.id, equals('fresh-1'));
      },
    );

    test('Custom user alert keywords can be stored and retrieved', () async {
      final repo = MarketNewsCacheRepository();
      final initialKeywords = await repo.getUserAlertKeywords();
      expect(initialKeywords, contains('pupuk'));
      expect(initialKeywords, contains('banjir'));

      await repo.saveUserAlertKeywords(['kopi', 'gabah', 'longsor']);
      final updated = await repo.getUserAlertKeywords();
      expect(updated, equals(['kopi', 'gabah', 'longsor']));
    });

    test('Unknown publication date uses fetch time for cache retention', () async {
      final repo = MarketNewsCacheRepository();
      final item = NewsAlertItem(
        id: 'unknown-date-1',
        title: 'Berita terbaru tanpa tanggal',
        snippet: 'Diambil sekarang dari RSS',
        sourceName: 'Test',
        publishedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        fetchedAt: DateTime.now(),
        isPublishedAtKnown: false,
        category: NewsCategory.all,
      );

      await repo.saveNewsItems([item]);
      final cached = await repo.getCachedNews();

      expect(cached.single.id, equals('unknown-date-1'));
    });

    test('Refresh interval preference persists locally', () async {
      final repo = MarketNewsCacheRepository();

      expect(await repo.getRefreshIntervalMinutes(), equals(60));
      await repo.saveRefreshIntervalMinutes(240);

      expect(await repo.getRefreshIntervalMinutes(), equals(240));
    });
  });

  group('AssetAutoValuationService Database Tests', () {
    late AppDatabase db;
    late AssetAutoValuationService service;

    setUp(() {
      db = createInMemoryDatabaseForTests();
      service = AssetAutoValuationService(db);
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'Revalues gold assets based on parsed karat and weight in note or name',
      () async {
        final householdId = 'household-test';

        // Insert an asset with gold karat note: "[Emas 18K, 10g]"
        await db.assets.insertOne(
          AssetsCompanion.insert(
            id: 'asset-gold-1',
            householdId: householdId,
            name: 'Cincin Kawin',
            assetType: 'Logam Mulia',
            value: const drift.Value(5000000), // old valuation
            placement: const drift.Value('Brankas'),
            note: const drift.Value('[Emas 18K, 10g] Cincin mas kawin'),
            createdAt: DateTime.now(),
          ),
        );

        // Insert another asset with 24K batangan
        await db.assets.insertOne(
          AssetsCompanion.insert(
            id: 'asset-gold-2',
            householdId: householdId,
            name: 'Emas Antam 24K (5 gram)',
            assetType: 'Emas',
            value: const drift.Value(6000000), // old valuation
            placement: const drift.Value('Safe Deposit Box'),
            createdAt: DateTime.now(),
          ),
        );

        final snapshot = MarketPriceSnapshot(
          goldPrice24K: 1400000,
          goldBuybackPrice: 1300000,
          usdRate: 16000,
          sgdRate: 12000,
          eurRate: 17000,
          sarRate: 4300,
          btcPrice: 1000000000,
          ethPrice: 40000000,
          usdtPrice: 16000,
          lastUpdated: DateTime.now(),
        );

        final updatedCount = await service.revalueAllAssets(
          householdId,
          snapshot,
        );
        expect(updatedCount, equals(2));

        final updatedGold1 = await (db.select(
          db.assets,
        )..where((a) => a.id.equals('asset-gold-1'))).getSingle();
        // 18K: 10 * 1.400.000 * (18/24) = 10.500.000
        expect(updatedGold1.value, equals(10500000));

        final updatedGold2 = await (db.select(
          db.assets,
        )..where((a) => a.id.equals('asset-gold-2'))).getSingle();
        // 24K: 5 * 1.400.000 * 1.0 = 7.000.000
        expect(updatedGold2.value, equals(7000000));
      },
    );

    test(
      'does not persist an estimated gold price without gold evidence',
      () async {
        const householdId = 'household-test';
        await db.assets.insertOne(
          AssetsCompanion.insert(
            id: 'asset-gold-unverified',
            householdId: householdId,
            name: 'Emas K18 5g',
            assetType: 'Emas',
            value: const drift.Value(9000000),
            placement: const drift.Value('Brankas'),
            createdAt: DateTime.now(),
          ),
        );
        final snapshot = MarketPriceSnapshot(
          goldPrice24K: 1500000,
          goldBuybackPrice: 1350000,
          usdRate: 16500,
          sgdRate: 12000,
          eurRate: 17000,
          sarRate: 4400,
          btcPrice: 1000000000,
          ethPrice: 40000000,
          usdtPrice: 16000,
          lastUpdated: DateTime.now(),
          verifiedInstruments: const {MarketInstrument.usd},
        );

        final result = await service.revalueAssets(
          db: db,
          snapshot: snapshot,
          householdId: householdId,
        );

        expect(result.revaluedCount, isZero);
        final asset = await (db.select(
          db.assets,
        )..where((a) => a.id.equals('asset-gold-unverified'))).getSingle();
        expect(asset.value, 9000000);
      },
    );

    test(
      'recognizes form K18 tags and rejects ambiguous foreign nominal tags',
      () async {
        const householdId = 'household-test';
        await db.assets.insertOne(
          AssetsCompanion.insert(
            id: 'asset-gold-k18',
            householdId: householdId,
            name: 'Cincin',
            assetType: 'Emas',
            value: const drift.Value(1),
            placement: const drift.Value('Brankas'),
            note: const drift.Value('[Emas K18, 5g]'),
            createdAt: DateTime.now(),
          ),
        );
        await db.assets.insertOne(
          AssetsCompanion.insert(
            id: 'asset-usd-ambiguous',
            householdId: householdId,
            name: 'Tabungan USD',
            assetType: 'Valas',
            value: const drift.Value(123),
            placement: const drift.Value('Brankas'),
            note: const drift.Value('[USD 1.000]'),
            createdAt: DateTime.now(),
          ),
        );
        final snapshot = MarketPriceSnapshot(
          goldPrice24K: 1400000,
          goldBuybackPrice: 1300000,
          usdRate: 16000,
          sgdRate: 12000,
          eurRate: 17000,
          sarRate: 4400,
          btcPrice: 1000000000,
          ethPrice: 40000000,
          usdtPrice: 16000,
          lastUpdated: DateTime.now(),
        );

        await service.revalueAssets(
          db: db,
          snapshot: snapshot,
          householdId: householdId,
        );

        final gold = await (db.select(
          db.assets,
        )..where((a) => a.id.equals('asset-gold-k18'))).getSingle();
        final usd = await (db.select(
          db.assets,
        )..where((a) => a.id.equals('asset-usd-ambiguous'))).getSingle();
        expect(gold.value, 5250000);
        expect(usd.value, 123);
      },
    );

    test(
      'Revalues forex assets (USD, SAR) based on current exchange rate',
      () async {
        final householdId = 'household-test';

        // Insert USD asset
        await db.assets.insertOne(
          AssetsCompanion.insert(
            id: 'asset-forex-1',
            householdId: householdId,
            name: 'Tabungan USD',
            assetType: 'Valas',
            value: const drift.Value(15000000),
            placement: const drift.Value('Rekening Valas'),
            note: const drift.Value('[USD 1000]'),
            createdAt: DateTime.now(),
          ),
        );

        // Insert SAR (Riyal) asset
        await db.assets.insertOne(
          AssetsCompanion.insert(
            id: 'asset-forex-2',
            householdId: householdId,
            name: 'Dana Haji Tunai Riyal',
            assetType: 'Valuta Asing',
            value: const drift.Value(2000000),
            placement: const drift.Value('Dompet Rumah'),
            note: const drift.Value('[SAR 500]'),
            createdAt: DateTime.now(),
          ),
        );

        final snapshot = MarketPriceSnapshot(
          goldPrice24K: 1400000,
          goldBuybackPrice: 1300000,
          usdRate: 16500.0,
          sgdRate: 12000.0,
          eurRate: 17000.0,
          sarRate: 4400.0,
          btcPrice: 1000000000,
          ethPrice: 40000000,
          usdtPrice: 16000,
          lastUpdated: DateTime.now(),
        );

        final count = await service.revalueAllAssets(householdId, snapshot);
        expect(count, equals(2));

        final usd = await (db.select(
          db.assets,
        )..where((a) => a.id.equals('asset-forex-1'))).getSingle();
        expect(usd.value, equals(16500000)); // 1000 * 16500

        final sar = await (db.select(
          db.assets,
        )..where((a) => a.id.equals('asset-forex-2'))).getSingle();
        expect(sar.value, equals(2200000)); // 500 * 4400
      },
    );

    test('Autonomous revaluation records activity into AutonomousActivityRepository', () async {
      final householdId = 'household-autonomous';
      final activityRepo = AutonomousActivityRepository(database: db);

      await db.assets.insertOne(
        AssetsCompanion.insert(
          id: 'asset-gold-auto',
          householdId: householdId,
          name: 'Emas Batangan 10 gram 24k',
          assetType: 'gold',
          value: const drift.Value(14000000),
          placement: const drift.Value('Brankas'),
          createdAt: DateTime.now(),
        ),
      );

      final snapshot = MarketPriceSnapshot(
        goldPrice24K: 1500000,
        goldBuybackPrice: 1350000,
        usdRate: 16500.0,
        sgdRate: 12000.0,
        eurRate: 17000.0,
        sarRate: 4400.0,
        btcPrice: 1000000000,
        ethPrice: 40000000,
        usdtPrice: 16000,
        lastUpdated: DateTime.now(),
      );

      final result = await service.revalueAndRecordAutonomously(
        db: db,
        snapshot: snapshot,
        householdId: householdId,
        activityRepository: activityRepo,
      );

      expect(result.revaluedCount, equals(1));
      expect(result.difference, equals(1000000)); // 15jt - 14jt

      final activities = await activityRepo.getRecentActivities(householdId);
      expect(activities, isNotEmpty);
      expect(
        activities.first.activityType,
        equals(AutonomousActivityType.assetRevaluation),
      );
      expect(activities.first.title, contains('1 Aset Diperbarui'));
    });
  });

  group('MarketNewsRadarService RSS and Division Guard Tests', () {
    test('parseRssFeed parses XML items correctly and categorizes them', () {
      const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>Antara News</title>
    <item>
      <title><![CDATA[BMKG Rilis Peringatan Hujan Lebat dan Angin Kencang]]></title>
      <description><![CDATA[Masyarakat diminta waspada cuaca ekstrem sepekan ke depan.]]></description>
      <link>https://antaranews.com/berita/123</link>
      <pubDate>Tue, 08 Sep 2026 10:00:00 GMT</pubDate>
    </item>
    <item>
      <title>Petani Sukabumi Panen Raya Padi dan Gabah Kering</title>
      <description>Harga gabah stabil dan pupuk bersubsidi mencukupi.</description>
      <link>https://antaranews.com/berita/124</link>
      <pubDate>Tue, 08 Sep 2026 08:00:00 GMT</pubDate>
    </item>
  </channel>
</rss>''';

      final items = MarketNewsRadarService.parseRssFeed(
        xml,
        defaultSource: 'Antara',
      );
      expect(items.length, equals(2));
      expect(
        items[0].title,
        equals('BMKG Rilis Peringatan Hujan Lebat dan Angin Kencang'),
      );
      expect(items[0].category, equals(NewsCategory.weatherDisaster));
      expect(
        items[1].title,
        equals('Petani Sukabumi Panen Raya Padi dan Gabah Kering'),
      );
      expect(items[1].category, equals(NewsCategory.agriculture));
    });

    test('categorizes tsunami, fire, and volcanic disaster terms', () {
      const xml = '''<rss><channel>
        <item><title>Peringatan tsunami dan gempa</title><description>Warga diminta evakuasi.</description><pubDate>Tue, 08 Sep 2026 10:00:00 GMT</pubDate></item>
        <item><title>Kebakaran hutan meluas</title><description>Petugas menangani karhutla.</description><pubDate>Tue, 08 Sep 2026 09:00:00 GMT</pubDate></item>
        <item><title>Gunung berapi erupsi</title><description>Status darurat dinaikkan.</description><pubDate>Tue, 08 Sep 2026 08:00:00 GMT</pubDate></item>
      </channel></rss>''';

      final items = MarketNewsRadarService.parseRssFeed(xml);

      expect(items, hasLength(3));
      expect(
        items.every((item) => item.category == NewsCategory.weatherDisaster),
        isTrue,
      );
    });

    test('parses official BMKG earthquake payload as disaster news', () {
      const payload = '''{"Infogempa":{"gempa":{"DateTime":"2026-09-09T01:04:26+00:00","Magnitude":"4.4","Kedalaman":"21 km","Wilayah":"20 km Timur Wanokaka","Potensi":"Tidak berpotensi tsunami"}}}''';

      final items = MarketNewsRadarService.parseBmkgEarthquake(payload);

      expect(items, hasLength(1));
      expect(items.single.sourceName, equals('BMKG Indonesia'));
      expect(items.single.category, equals(NewsCategory.weatherDisaster));
      expect(items.single.title, contains('M4.4'));
      expect(items.single.snippet, contains('21 km'));
    });

    test(
      'RSS without a valid publication date is not presented as current',
      () {
        const xml = '''<rss><channel><item>
        <title>Informasi pasar</title><description>Ringkasan</description>
        <pubDate>not-a-date</pubDate></item></channel></rss>''';

        final item = MarketNewsRadarService.parseRssFeed(xml).single;
        expect(item.isPublishedAtKnown, isFalse);
        expect(
          item.publishedAt,
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        );
      },
    );

    test('news relevance keeps core categories and matches user keywords locally', () {
      final finance = NewsAlertItem(
        id: 'finance-1',
        title: 'Perubahan suku bunga bank',
        snippet: 'Informasi ekonomi terbaru',
        sourceName: 'Test',
        publishedAt: DateTime(2026, 9, 9),
        category: NewsCategory.finance,
      );
      final general = NewsAlertItem(
        id: 'general-1',
        title: 'Harga pupuk untuk musim tanam',
        snippet: 'Ringkasan pasar pertanian',
        sourceName: 'Test',
        publishedAt: DateTime(2026, 9, 9),
        category: NewsCategory.all,
      );
      final unrelated = NewsAlertItem(
        id: 'general-2',
        title: 'Jadwal pertandingan akhir pekan',
        snippet: 'Berita olahraga',
        sourceName: 'Test',
        publishedAt: DateTime(2026, 9, 9),
        category: NewsCategory.all,
      );

      expect(
        MarketNewsRadarService.isRelevantForUser(
          finance,
          keywords: const ['kurs'],
        ),
        isTrue,
      );
      expect(
        MarketNewsRadarService.isRelevantForUser(
          general,
          keywords: const ['pupuk'],
        ),
        isTrue,
      );
      expect(
        MarketNewsRadarService.isRelevantForUser(
          unrelated,
          keywords: const ['pupuk'],
        ),
        isFalse,
      );
    });

    test(
      'offline fallback is explicitly marked and has a stable date',
      () async {
        final client = MockClient((_) async => http.Response('offline', 503));
        const service = MarketNewsRadarService();

        final first = await service.fetchCuratedNews(client: client);
        final second = await service.fetchCuratedNews(client: client);

        expect(first.every((item) => item.isFallback), isTrue);
        expect(
          first.map((item) => item.publishedAt),
          second.map((item) => item.publishedAt),
        );
      },
    );

    test(
      'Forex rate division guards against zero or missing exchange rates',
      () async {
        final mockClient = MockClient((request) async {
          if (request.url.toString().contains('open.er-api.com')) {
            return http.Response(
              jsonEncode({
                'rates': {
                  'IDR': 16000.0,
                  'SGD': 0, // Zero rate
                  'EUR': -1.0, // Negative rate
                },
              }),
              200,
            );
          }
          return http.Response('{}', 404);
        });

        const radarService = MarketNewsRadarService();
        final prices = await radarService.fetchMarketPrices(client: mockClient);

        // SgdRate and EurRate should remain default fallback and not throw Infinity or error
        expect(prices.usdRate, equals(16000.0));
        expect(prices.sgdRate.isFinite, isTrue);
        expect(prices.eurRate.isFinite, isTrue);
        expect(prices.sgdRate, equals(11950.0)); // Fallback maintained
        expect(prices.eurRate, equals(16920.0)); // Fallback maintained
      },
    );
  });
}
