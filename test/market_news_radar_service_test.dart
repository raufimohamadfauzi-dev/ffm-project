import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/asset/data/repositories/market_news_cache_repository.dart';
import 'package:ffm_manager/features/asset/domain/entities/market_news_models.dart';
import 'package:ffm_manager/features/asset/domain/usecases/asset_auto_valuation_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GoldKarat & Valuation Tests', () {
    test('GoldKarat purity calculations match Indonesian gold standards', () {
      const price24K = 1400000; // Rp 1.400.000 / gram

      // 24K Batangan (100% purity)
      final val24 = GoldKarat.k24.calculateValue(weightGrams: 10, pricePerGram24K: price24K);
      expect(val24, equals(14000000));

      // 18K Perhiasan Toko Emas (75% purity)
      final val18 = GoldKarat.k18.calculateValue(weightGrams: 10, pricePerGram24K: price24K);
      expect(val18, equals(10500000)); // 14.000.000 * 0.75

      // 22K Emas Tua (91.67%)
      final val22 = GoldKarat.k22.calculateValue(weightGrams: 5, pricePerGram24K: price24K);
      expect(val22, equals(((5 * price24K) * (22 / 24)).round()));

      // 16K (66.67%)
      final val16 = GoldKarat.k16.calculateValue(weightGrams: 3, pricePerGram24K: price24K);
      expect(val16, equals(((3 * price24K) * (16 / 24)).round()));

      // 10K Emas Muda (41.67%)
      final val10 = GoldKarat.k10.calculateValue(weightGrams: 4, pricePerGram24K: price24K);
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
        snippet: 'Kementan memastikan distribusi pupuk subsidi musim tanam aman.',
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

      expect(recent.publishedAt.isBefore(DateTime.now().subtract(const Duration(hours: 48))), isFalse);
      expect(old.publishedAt.isBefore(DateTime.now().subtract(const Duration(hours: 48))), isTrue);

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

    test('Auto-prunes news items older than 48 hours without touching database', () async {
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
    });

    test('Custom user alert keywords can be stored and retrieved', () async {
      final repo = MarketNewsCacheRepository();
      final initialKeywords = await repo.getUserAlertKeywords();
      expect(initialKeywords, contains('pupuk'));
      expect(initialKeywords, contains('banjir'));

      await repo.saveUserAlertKeywords(['kopi', 'gabah', 'longsor']);
      final updated = await repo.getUserAlertKeywords();
      expect(updated, equals(['kopi', 'gabah', 'longsor']));
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

    test('Revalues gold assets based on parsed karat and weight in note or name', () async {
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

      final updatedCount = await service.revalueAllAssets(householdId, snapshot);
      expect(updatedCount, equals(2));

      final updatedGold1 = await (db.select(db.assets)..where((a) => a.id.equals('asset-gold-1'))).getSingle();
      // 18K: 10 * 1.400.000 * (18/24) = 10.500.000
      expect(updatedGold1.value, equals(10500000));

      final updatedGold2 = await (db.select(db.assets)..where((a) => a.id.equals('asset-gold-2'))).getSingle();
      // 24K: 5 * 1.400.000 * 1.0 = 7.000.000
      expect(updatedGold2.value, equals(7000000));
    });

    test('Revalues forex assets (USD, SAR) based on current exchange rate', () async {
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

      final usd = await (db.select(db.assets)..where((a) => a.id.equals('asset-forex-1'))).getSingle();
      expect(usd.value, equals(16500000)); // 1000 * 16500

      final sar = await (db.select(db.assets)..where((a) => a.id.equals('asset-forex-2'))).getSingle();
      expect(sar.value, equals(2200000)); // 500 * 4400
    });
  });
}
