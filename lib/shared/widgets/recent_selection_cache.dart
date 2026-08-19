import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Cache pilihan terakhir untuk mempercepat input tanpa mengubah data utama.
///
/// Cache ini hanya menyimpan ID/string pilihan pada perangkat. Nilai yang sudah
/// tidak ada di master data akan diabaikan oleh komponen pemanggil.
class RecentSelectionCache {
  RecentSelectionCache([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _keyPrefix = 'ffm_recent_selection_v1_';
  static const _maxItems = 5;

  Future<List<String>> read(String fieldKey) async {
    final raw = await _storage.read(key: _key(fieldKey));
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toSet()
          .take(_maxItems)
          .toList(growable: false);
    } catch (_) {
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
      if (kept.isEmpty) {
        await _storage.delete(key: _key(fieldKey));
      } else {
        await _storage.write(key: _key(fieldKey), value: jsonEncode(kept));
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
    await _storage.write(key: _key(fieldKey), value: jsonEncode(values));
  }

  Future<void> clear(String fieldKey) => _storage.delete(key: _key(fieldKey));

  String _key(String fieldKey) {
    final safeKey = fieldKey.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9_-]'),
      '_',
    );
    return '$_keyPrefix$safeKey';
  }
}

final recentSelectionCache = RecentSelectionCache();
