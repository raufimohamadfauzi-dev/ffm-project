import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/ffm_assistant_models.dart';

/// Menyimpan riwayat chat dasar secara lokal.
/// Intent/draft aktif tidak diserialisasikan karena harus kedaluwarsa bersama sesi.
class FfmAssistantChatHistoryRepository {
  FfmAssistantChatHistoryRepository({this._preferences});

  static const _key = 'ffm_assistant_chat_history_v1';
  static const maxEntries = 100;
  SharedPreferences? _preferences;

  Future<List<FfmAssistantChatEntry>> load() async {
    final preferences = await _prefs();
    final raw = preferences.getString(_key);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map(_decodeEntry)
          .whereType<FfmAssistantChatEntry>()
          .toList(growable: false);
    } on FormatException {
      return const [];
    }
  }

  Future<void> save(List<FfmAssistantChatEntry> entries) async {
    final preferences = await _prefs();
    final retained = entries.length <= maxEntries
        ? entries
        : entries.sublist(entries.length - maxEntries);
    await preferences.setString(
      _key,
      jsonEncode(retained.map(_encodeEntry).toList(growable: false)),
    );
  }

  Future<void> clear() async {
    final preferences = await _prefs();
    await preferences.remove(_key);
  }

  Future<List<Map<String, Object?>>> readRaw() async {
    final preferences = await _prefs();
    final raw = preferences.getString(_key);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((row) => Map<String, Object?>.from(row))
          .toList(growable: false);
    } on FormatException {
      return const [];
    }
  }

  Future<void> importRaw(List<Map<String, Object?>> rows) async {
    final preferences = await _prefs();
    await preferences.setString(_key, jsonEncode(rows));
  }

  Future<SharedPreferences> _prefs() async =>
      _preferences ??= await SharedPreferences.getInstance();

  Map<String, Object?> _encodeEntry(FfmAssistantChatEntry entry) => {
    'isUser': entry.isUser,
    'text': entry.text,
    'createdAt': (entry.createdAt ?? DateTime.now()).toIso8601String(),
  };

  FfmAssistantChatEntry? _decodeEntry(Map raw) {
    final isUser = raw['isUser'];
    final text = raw['text'];
    if (isUser is! bool || text is! String) return null;
    final createdAt = raw['createdAt'];
    final parsedDate = createdAt is String
        ? DateTime.tryParse(createdAt)
        : null;
    return FfmAssistantChatEntry(
      isUser: isUser,
      text: text,
      createdAt: parsedDate,
    );
  }
}
