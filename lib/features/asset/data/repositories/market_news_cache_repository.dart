import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/market_news_models.dart';

/// Repository penyimpanan cache sementara untuk data harga pasar & warta berita.
///
/// TIDAK menyimpan ke database utama SQLite transaksi agar database tetap steril,
/// ringan, dan terbebas dari arsip teks berita lama.
class MarketNewsCacheRepository {
  MarketNewsCacheRepository();

  static const _keyPriceSnapshot = 'ffm_market_price_snapshot';
  static const _keyNewsList = 'ffm_cached_news_items';
  static const _keyFilterKeywords = 'ffm_news_filter_keywords';
  static const _keyFilterCategories = 'ffm_news_filter_categories';

  static const _newsRetention = Duration(hours: 48);

  SharedPreferences? _cachedPrefs;

  Future<SharedPreferences> _prefs() async =>
      _cachedPrefs ??= await SharedPreferences.getInstance();

  // ---------------------------------------------------------------------------
  // Harga Pasar Snapshot
  // ---------------------------------------------------------------------------

  Future<MarketPriceSnapshot> getLatestPriceSnapshot() async {
    final prefs = await _prefs();
    final raw = prefs.getString(_keyPriceSnapshot);
    if (raw == null || raw.isEmpty) {
      return MarketPriceSnapshot.initialFallback();
    }

    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return MarketPriceSnapshot.fromJson(map);
    } catch (_) {
      return MarketPriceSnapshot.initialFallback();
    }
  }

  Future<void> savePriceSnapshot(MarketPriceSnapshot snapshot) async {
    final prefs = await _prefs();
    await prefs.setString(_keyPriceSnapshot, jsonEncode(snapshot.toJson()));
  }

  // ---------------------------------------------------------------------------
  // Berita & Peringatan Terpilih (Retention 48 Jam)
  // ---------------------------------------------------------------------------

  Future<List<NewsAlertItem>> getCachedNews() async {
    final prefs = await _prefs();
    final raw = prefs.getString(_keyNewsList);
    if (raw == null || raw.isEmpty) return [];

    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final now = DateTime.now();

      // Prune berita yang lebih lama dari 48 jam
      return list
          .map((e) => NewsAlertItem.fromJson(e as Map<String, dynamic>))
          .where((n) => now.difference(n.publishedAt) <= _newsRetention)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveCachedNews(List<NewsAlertItem> news) async {
    final prefs = await _prefs();
    final now = DateTime.now();

    // Hanya simpan warta yang masih dalam jendela retensi 48 jam
    final validNews =
        news.where((n) => now.difference(n.publishedAt) <= _newsRetention).toList();

    await prefs.setString(
      _keyNewsList,
      jsonEncode(validNews.map((n) => n.toJson()).toList()),
    );
  }

  // ---------------------------------------------------------------------------
  // Preferensi Filter Pengguna
  // ---------------------------------------------------------------------------

  Future<List<String>> getFilterKeywords() async {
    final prefs = await _prefs();
    return prefs.getStringList(_keyFilterKeywords) ?? [];
  }

  Future<void> saveFilterKeywords(List<String> keywords) async {
    final prefs = await _prefs();
    await prefs.setStringList(_keyFilterKeywords, keywords);
  }

  Future<List<NewsCategory>> getSelectedCategories() async {
    final prefs = await _prefs();
    final raw = prefs.getStringList(_keyFilterCategories);
    if (raw == null || raw.isEmpty) {
      return [NewsCategory.all];
    }
    return raw
        .map((name) => NewsCategory.values.firstWhere(
              (c) => c.name == name,
              orElse: () => NewsCategory.all,
            ))
        .toList();
  }

  Future<void> saveSelectedCategories(List<NewsCategory> categories) async {
    final prefs = await _prefs();
    await prefs.setStringList(
      _keyFilterCategories,
      categories.map((c) => c.name).toList(),
    );
  }

  // Alias methods
  Future<void> saveNewsItems(List<NewsAlertItem> news) => saveCachedNews(news);
  Future<void> saveUserAlertKeywords(List<String> keywords) => saveFilterKeywords(keywords);
  Future<List<String>> getUserAlertKeywords() async {
    final list = await getFilterKeywords();
    if (list.isEmpty) {
      return ['pupuk', 'banjir', 'kurs', 'kebakaran'];
    }
    return list;
  }
}
