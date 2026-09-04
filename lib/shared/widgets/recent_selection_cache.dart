import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Cache pilihan terakhir untuk mempercepat input tanpa mengubah data utama.
///
/// Cache ini menggunakan in-memory cache dengan persistensi [SharedPreferences]
/// agar pembacaan nilai berlangsung instan (0 ms) tanpa IPC ke Keystore.
class RecentSelectionCache {
  RecentSelectionCache([this._prefs]);

  SharedPreferences? _prefs;
  final Map<String, List<String>> _memoryCache = {};

  static const _keyPrefix = 'ffm_recent_selection_v1_';
  static const _maxItems = 5;

  Future<SharedPreferences> _getPrefs() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  Future<List<String>> read(String fieldKey) async {
    final cacheKey = _key(fieldKey);
    if (_memoryCache.containsKey(cacheKey)) {
      return _memoryCache[cacheKey]!;
    }
    final prefs = await _getPrefs();
    final raw = prefs.getString(cacheKey);
    if (raw == null || raw.trim().isEmpty) {
      _memoryCache[cacheKey] = const [];
      return const [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        _memoryCache[cacheKey] = const [];
        return const [];
      }
      final list = decoded
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toSet()
          .take(_maxItems)
          .toList(growable: false);
      _memoryCache[cacheKey] = list;
      return list;
    } catch (_) {
      _memoryCache[cacheKey] = const [];
      return const [];
    }
  }

  Future<List<String>> prune(
    String fieldKey,
    Iterable<String> validValues,
  ) async {
    final valid = validValues
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    final current = await read(fieldKey);
    final kept = current.where(valid.contains).toList(growable: false);
    if (kept.length != current.length) {
      final cacheKey = _key(fieldKey);
      _memoryCache[cacheKey] = kept;
      final prefs = await _getPrefs();
      if (kept.isEmpty) {
        await prefs.remove(cacheKey);
      } else {
        await prefs.setString(cacheKey, jsonEncode(kept));
      }
    }
    return kept;
  }

  Future<void> remember(String fieldKey, String value) async {
    final cleanValue = value.trim();
    if (cleanValue.isEmpty) return;
    final current = await read(fieldKey);
    final values = [
      cleanValue,
      ...current.where((item) => item != cleanValue),
    ].take(_maxItems).toList(growable: false);

    final cacheKey = _key(fieldKey);
    _memoryCache[cacheKey] = values;
    final prefs = await _getPrefs();
    await prefs.setString(cacheKey, jsonEncode(values));
  }

  Future<void> clear(String fieldKey) async {
    final cacheKey = _key(fieldKey);
    _memoryCache.remove(cacheKey);
    final prefs = await _getPrefs();
    await prefs.remove(cacheKey);
  }

  String _key(String fieldKey) {
    final safeKey = fieldKey.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9_-]'),
      '_',
    );
    return '$_keyPrefix$safeKey';
  }
}

final recentSelectionCache = RecentSelectionCache();
