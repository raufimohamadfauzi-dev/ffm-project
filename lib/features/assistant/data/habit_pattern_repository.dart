import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Repository untuk mengelola preferensi pengabaian dan penundaan (snooze)
/// saran pola transaksi rutin dari Asisten FFM.
class HabitPatternRepository {
  HabitPatternRepository();

  static const _keyIgnoredPrefix = 'ffm_habit_patterns_ignored_';
  static const _keySnoozedPrefix = 'ffm_habit_patterns_snoozed_';

  SharedPreferences? _cachedPrefs;

  Future<SharedPreferences> _prefs() async =>
      _cachedPrefs ??= await SharedPreferences.getInstance();

  String _getIgnoredKey(String householdId) => '$_keyIgnoredPrefix$householdId';
  String _getSnoozedKey(String householdId) => '$_keySnoozedPrefix$householdId';

  /// Memeriksa apakah suatu pola sedang disembunyikan (baik karena dimatikan permanen
  /// maupun karena ditunda/snoozed minggu ini).
  Future<bool> isPatternSuppressed(
    String householdId,
    String patternId, {
    DateTime? now,
  }) async {
    final current = now ?? DateTime.now();

    // 1. Cek apakah masuk daftar dimatikan permanen
    final ignored = await getIgnoredPatternIds(householdId);
    if (ignored.contains(patternId)) return true;

    // 2. Cek apakah masih dalam masa tunda (snooze)
    final snoozedMap = await _getSnoozedMap(householdId);
    final snoozedUntilStr = snoozedMap[patternId];
    if (snoozedUntilStr != null) {
      final until = DateTime.tryParse(snoozedUntilStr);
      if (until != null && current.isBefore(until)) {
        return true;
      }
    }

    return false;
  }

  /// Menunda saran pola ini selama [duration] (default 7 hari untuk "Lewati Minggu Ini").
  Future<void> snoozePattern(
    String householdId,
    String patternId, {
    Duration duration = const Duration(days: 7),
    DateTime? now,
  }) async {
    final current = now ?? DateTime.now();
    final until = current.add(duration);
    final snoozedMap = await _getSnoozedMap(householdId);
    snoozedMap[patternId] = until.toIso8601String();

    final prefs = await _prefs();
    await prefs.setString(_getSnoozedKey(householdId), jsonEncode(snoozedMap));
  }

  /// Mematikan saran pola ini sehingga tidak muncul lagi ("Matikan Kebiasaan").
  Future<void> ignorePattern(String householdId, String patternId) async {
    final ignored = await getIgnoredPatternIds(householdId);
    ignored.add(patternId);

    final prefs = await _prefs();
    await prefs.setString(
      _getIgnoredKey(householdId),
      jsonEncode(ignored.toList()),
    );
  }

  /// Mengaktifkan kembali saran pola yang sebelumnya dimatikan.
  Future<void> unignorePattern(String householdId, String patternId) async {
    final ignored = await getIgnoredPatternIds(householdId);
    ignored.remove(patternId);

    final prefs = await _prefs();
    await prefs.setString(
      _getIgnoredKey(householdId),
      jsonEncode(ignored.toList()),
    );
  }

  /// Mengambil semua ID pola yang dimatikan.
  Future<Set<String>> getIgnoredPatternIds(String householdId) async {
    final prefs = await _prefs();
    final raw = prefs.getString(_getIgnoredKey(householdId));
    if (raw == null || raw.isEmpty) return {};

    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => e.toString()).toSet();
    } catch (_) {
      return {};
    }
  }

  /// Menghapus semua preferensi tunda dan ignore untuk household ini (misal saat reset).
  Future<void> clearAll(String householdId) async {
    final prefs = await _prefs();
    await prefs.remove(_getIgnoredKey(householdId));
    await prefs.remove(_getSnoozedKey(householdId));
  }

  Future<Map<String, String>> _getSnoozedMap(String householdId) async {
    final prefs = await _prefs();
    final raw = prefs.getString(_getSnoozedKey(householdId));
    if (raw == null || raw.isEmpty) return {};

    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return {};
    }
  }
}
