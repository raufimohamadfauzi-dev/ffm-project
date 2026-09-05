import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/ffm_assistant_models.dart';

/// Menyimpan riwayat chat dasar secara lokal.
/// Intent/draft aktif tidak diserialisasikan karena harus kedaluwarsa bersama sesi.
class FfmAssistantChatConversation {
  const FfmAssistantChatConversation({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.entries,
  });

  final String id;
  final String title;
  final DateTime updatedAt;
  final List<FfmAssistantChatEntry> entries;
}

class FfmAssistantChatHistoryRepository {
  FfmAssistantChatHistoryRepository({this._preferences});

  static const _key = 'ffm_assistant_chat_history_v1';
  static const _conversationsKey = 'ffm_assistant_chat_conversations_v1';
  static const maxConversations = 30;
  static const maxEntries = 100;
  SharedPreferences? _preferences;

  String newConversationId() => _newConversationId();

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
    await preferences.remove(_conversationsKey);
  }

  Future<List<FfmAssistantChatConversation>> loadConversations() async {
    final preferences = await _prefs();
    final raw = preferences.getString(_conversationsKey);
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded
              .whereType<Map>()
              .map(_decodeConversation)
              .whereType<FfmAssistantChatConversation>()
              .toList(growable: false);
        }
      } on FormatException {
        // Fall through to the v1 migration below.
      }
    }

    final legacy = await load();
    if (legacy.isEmpty) return const [];
    final migrated = FfmAssistantChatConversation(
      id: _newConversationId(),
      title: _titleFor(legacy),
      updatedAt: DateTime.now(),
      entries: legacy,
    );
    await preferences.setString(
      _conversationsKey,
      jsonEncode([_encodeConversation(migrated)]),
    );
    await preferences.remove(_key);
    return [migrated];
  }

  Future<void> saveConversation(
    FfmAssistantChatConversation conversation,
  ) async {
    final conversations = await loadConversations();
    final updated = [
      for (final item in conversations)
        if (item.id != conversation.id) item,
      conversation,
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final retained = updated.take(maxConversations).toList(growable: false);
    final preferences = await _prefs();
    await preferences.setString(
      _conversationsKey,
      jsonEncode(retained.map(_encodeConversation).toList(growable: false)),
    );
    await preferences.remove(_key);
  }

  Future<void> deleteConversation(String id) async {
    final remaining = (await loadConversations())
        .where((conversation) => conversation.id != id)
        .toList(growable: false);
    final preferences = await _prefs();
    if (remaining.isEmpty) {
      await preferences.remove(_conversationsKey);
    } else {
      await preferences.setString(
        _conversationsKey,
        jsonEncode(remaining.map(_encodeConversation).toList(growable: false)),
      );
    }
  }

  Future<List<Map<String, Object?>>> readConversationsRaw() async {
    final conversations = await loadConversations();
    return conversations
        .map(_encodeConversation)
        .map((row) => Map<String, Object?>.from(row))
        .toList(growable: false);
  }

  Future<void> importConversationsRaw(List<Map<String, Object?>> rows) async {
    final imported = rows
        .map(_decodeConversation)
        .whereType<FfmAssistantChatConversation>()
        .toList(growable: false);
    if (imported.isEmpty) return;
    final existing = await loadConversations();
    final merged = <String, FfmAssistantChatConversation>{
      for (final item in existing) item.id: item,
    };
    for (final item in imported) {
      final current = merged[item.id];
      if (current == null) {
        merged[item.id] = item;
        continue;
      }
      final entries = [...current.entries];
      for (final entry in item.entries) {
        if (!entries.any(
          (candidate) =>
              candidate.isUser == entry.isUser &&
              candidate.text == entry.text &&
              candidate.createdAt == entry.createdAt,
        )) {
          entries.add(entry);
        }
      }
      merged[item.id] = FfmAssistantChatConversation(
        id: item.id,
        title: current.title,
        updatedAt: item.updatedAt.isAfter(current.updatedAt)
            ? item.updatedAt
            : current.updatedAt,
        entries: entries,
      );
    }
    final preferences = await _prefs();
    final retained = merged.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await preferences.setString(
      _conversationsKey,
      jsonEncode(
        retained
            .take(maxConversations)
            .map(_encodeConversation)
            .toList(growable: false),
      ),
    );
    await preferences.remove(_key);
  }

  Future<List<Map<String, Object?>>> readRaw() async {
    final preferences = await _prefs();
    final raw = preferences.getString(_key);
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded
              .whereType<Map>()
              .map((row) => Map<String, Object?>.from(row))
              .toList(growable: false);
        }
      } on FormatException {
        return const [];
      }
    }
    final conversations = await loadConversations();
    return conversations
        .expand((conversation) => conversation.entries.map(_encodeEntry))
        .map((row) => Map<String, Object?>.from(row))
        .toList(growable: false);
  }

  Future<void> importRaw(List<Map<String, Object?>> rows) async {
    final conversations = await loadConversations();
    if (conversations.isNotEmpty) {
      final current = conversations.first;
      final existing = current.entries.map(_encodeEntry).toList();
      final merged = [...existing];
      for (final row in rows) {
        final isDuplicate = existing.any(
          (item) =>
              item['isUser'] == row['isUser'] &&
              item['text'] == row['text'] &&
              item['createdAt'] == row['createdAt'],
        );
        if (!isDuplicate) merged.add(row);
      }
      await saveConversation(
        FfmAssistantChatConversation(
          id: current.id,
          title: current.title,
          updatedAt: DateTime.now(),
          entries: merged
              .map((row) => _decodeEntry(row))
              .whereType<FfmAssistantChatEntry>()
              .toList(growable: false),
        ),
      );
      return;
    }
    final existing = await readRaw();
    final merged = [...existing];
    for (final row in rows) {
      final isDuplicate = existing.any(
        (item) =>
            item['isUser'] == row['isUser'] &&
            item['text'] == row['text'] &&
            item['createdAt'] == row['createdAt'],
      );
      if (!isDuplicate) merged.add(row);
    }
    final preferences = await _prefs();
    await preferences.setString(_key, jsonEncode(merged));
  }

  String _newConversationId() =>
      'chat-${DateTime.now().microsecondsSinceEpoch}';

  String _titleFor(List<FfmAssistantChatEntry> entries) {
    final firstUser = entries.firstWhere(
      (entry) => entry.isUser && entry.text.trim().isNotEmpty,
      orElse: () => entries.first,
    );
    final text = firstUser.text.trim();
    if (text.isEmpty) return 'Percakapan baru';
    return text.length > fortyFive
        ? '${text.substring(0, fortyFive)}...'
        : text;
  }

  static const fortyFive = 45;

  Map<String, Object?> _encodeConversation(
    FfmAssistantChatConversation conversation,
  ) => {
    'id': conversation.id,
    'title': conversation.title,
    'updatedAt': conversation.updatedAt.toIso8601String(),
    'entries': conversation.entries.map(_encodeEntry).toList(growable: false),
  };

  FfmAssistantChatConversation? _decodeConversation(Map raw) {
    final id = raw['id'];
    final title = raw['title'];
    final updatedAt = raw['updatedAt'];
    final entries = raw['entries'];
    final parsedUpdatedAt = updatedAt is String
        ? DateTime.tryParse(updatedAt)
        : null;
    if (id is! String ||
        title is! String ||
        parsedUpdatedAt == null ||
        entries is! List) {
      return null;
    }
    return FfmAssistantChatConversation(
      id: id,
      title: title,
      updatedAt: parsedUpdatedAt,
      entries: entries
          .whereType<Map>()
          .map(_decodeEntry)
          .whereType<FfmAssistantChatEntry>()
          .toList(growable: false),
    );
  }

  Future<SharedPreferences> _prefs() async =>
      _preferences ??= await SharedPreferences.getInstance();

  Map<String, Object?> _encodeEntry(FfmAssistantChatEntry entry) => {
    'isUser': entry.isUser,
    'text': entry.text,
    'createdAt': (entry.createdAt ?? DateTime.now()).toIso8601String(),
    'verifiedFacts': entry.verifiedFacts,
    'analysisResults': entry.analysisResults,
    'feedbackType': entry.feedbackType,
    'feedbackCategory': entry.feedbackCategory,
    'sentAt': entry.sentAt?.toIso8601String(),
    'receivedAt': entry.receivedAt?.toIso8601String(),
    'modelUsed': entry.modelUsed,
    'absorbedMemory': entry.absorbedMemory,
  };

  FfmAssistantChatEntry? _decodeEntry(Map raw) {
    final isUser = raw['isUser'];
    final text = raw['text'];
    if (isUser is! bool || text is! String) return null;
    final createdAt = raw['createdAt'];
    final parsedDate = createdAt is String
        ? DateTime.tryParse(createdAt)
        : null;
    final sentAt = raw['sentAt'];
    final receivedAt = raw['receivedAt'];
    final modelUsed = raw['modelUsed'];
    final verifiedFacts = raw['verifiedFacts'];
    final analysisResults = raw['analysisResults'];
    final feedbackType = raw['feedbackType'];
    final feedbackCategory = raw['feedbackCategory'];
    final absorbedMemory = raw['absorbedMemory'];
    return FfmAssistantChatEntry(
      isUser: isUser,
      text: text,
      createdAt: parsedDate,
      sentAt: sentAt is String ? DateTime.tryParse(sentAt) : null,
      receivedAt: receivedAt is String
          ? DateTime.tryParse(receivedAt)
          : null,
      modelUsed: modelUsed is String && modelUsed.isNotEmpty
          ? modelUsed
          : null,
      verifiedFacts: verifiedFacts is String ? verifiedFacts : null,
      analysisResults: analysisResults is String ? analysisResults : null,
      feedbackType: feedbackType is String ? feedbackType : null,
      feedbackCategory: feedbackCategory is String ? feedbackCategory : null,
      absorbedMemory: absorbedMemory is String ? absorbedMemory : null,
    );
  }

  Future<void> updateEntryWithFeedback(
    int index,
    String feedbackType,
    String? feedbackCategory,
  ) async {
    final entries = await load();
    if (index >= 0 && index < entries.length) {
      final entry = entries[index];
      entries[index] = FfmAssistantChatEntry(
        isUser: entry.isUser,
        text: entry.text,
        intent: entry.intent,
        activityIntent: entry.activityIntent,
        understanding: entry.understanding,
        review: entry.review,
        filePath: entry.filePath,
        fileFormat: entry.fileFormat,
        processTrace: entry.processTrace,
        createdAt: entry.createdAt,
        verifiedFacts: entry.verifiedFacts,
        analysisResults: entry.analysisResults,
        feedbackType: feedbackType,
        feedbackCategory: feedbackCategory,
        sentAt: entry.sentAt,
        receivedAt: entry.receivedAt,
        modelUsed: entry.modelUsed,
      );
      await save(entries);
    }
  }
}
