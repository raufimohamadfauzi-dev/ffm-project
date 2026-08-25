import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/ffm_personal_context.dart';
import 'ffm_assistant_chat_history_repository.dart';

/// Manager untuk working context yang terintegrasi dengan chat history.
///
/// Working context menyimpan state percakapan aktif yang digunakan untuk
/// mempertahankan referensi antar-turn percakapan.
///
/// Context dipersist ke SharedPreferences supaya survive restart app.
class FfmWorkingContextManager {
  FfmWorkingContextManager({
    required FfmAssistantChatHistoryRepository chatHistoryRepository,
    SharedPreferences? preferences,
  })  : _chatHistoryRepository = chatHistoryRepository,
        _preferences = preferences;

  static const _persistenceKey = 'ffm_working_context_v1';

  final FfmAssistantChatHistoryRepository _chatHistoryRepository;
  final SharedPreferences? _preferences;
  FfmWorkingContext _currentContext = const FfmWorkingContext();
  bool _loaded = false;

  FfmWorkingContext get currentContext => _currentContext;

  /// Load persisted context dari SharedPreferences.
  Future<void> loadPersisted() async {
    if (_loaded) return;
    final prefs = _preferences ?? await SharedPreferences.getInstance();
    final raw = prefs.getString(_persistenceKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          final loaded = FfmWorkingContext.fromJson(decoded);
          if (!loaded.isExpired) {
            _currentContext = loaded;
          }
        }
      } on FormatException {
        // Ignore corrupt data
      }
    }
    _loaded = true;
  }

  /// Save current context ke SharedPreferences.
  Future<void> _persist() async {
    final prefs = _preferences ?? await SharedPreferences.getInstance();
    await prefs.setString(
      _persistenceKey,
      jsonEncode(_currentContext.toJson()),
    );
  }

  /// Update working context setelah percakapan turn
  Future<FfmWorkingContext> updateAfterTurn({
    required String userQuery,
    required String? assistantResponse,
    required Map<String, String> extractedEntities,
  }) async {
    final autoExtracted = _extractSimpleEntities(userQuery);
    final merged = {
      ...autoExtracted,
      ...extractedEntities,
    };

    _currentContext = FfmWorkingContext(
      lastUserIntent: merged['intent'] ?? _currentContext.lastUserIntent,
      lastReferencedEntity: merged['entity'] ?? _currentContext.lastReferencedEntity,
      currentTopic: merged['topic'] ?? _currentContext.currentTopic,
      currentPeriod: merged['period'] ?? _currentContext.currentPeriod,
      currentGoal: merged['goal'] ?? _currentContext.currentGoal,
      pendingClarification: null,
      lastActionResult: assistantResponse != null ? 'assistant_response_ready' : null,
      lastUpdatedAt: DateTime.now(),
    );

    await _persist();
    return _currentContext;
  }

  /// Extract working context dari chat history terakhir
  Future<FfmWorkingContext> rebuildFromHistory() async {
    await loadPersisted();

    if (!_currentContext.isExpired && _currentContext.lastUpdatedAt != null) {
      return _currentContext;
    }

    final entries = await _chatHistoryRepository.load();

    if (entries.isEmpty) {
      _currentContext = const FfmWorkingContext();
      await _persist();
      return _currentContext;
    }

    final recentEntries = entries.length > 10
        ? entries.sublist(entries.length - 10)
        : entries;

    for (final entry in recentEntries.reversed) {
      if (entry.isUser) {
        final entities = _extractSimpleEntities(entry.text);

        _currentContext = FfmWorkingContext(
          lastUserIntent: entities['intent'] ?? _currentContext.lastUserIntent,
          lastReferencedEntity: entities['entity'] ?? _currentContext.lastReferencedEntity,
          currentTopic: entities['topic'] ?? _currentContext.currentTopic,
          currentPeriod: entities['period'] ?? _currentContext.currentPeriod,
          currentGoal: entities['goal'] ?? _currentContext.currentGoal,
          pendingClarification: null,
          lastActionResult: _currentContext.lastActionResult,
          lastUpdatedAt: DateTime.now(),
        );

        break;
      }
    }

    await _persist();
    return _currentContext;
  }

  /// Set specific context values manually
  Future<FfmWorkingContext> setContext({
    String? lastUserIntent,
    String? lastReferencedEntity,
    String? currentTopic,
    String? currentPeriod,
    String? currentGoal,
    String? pendingClarification,
  }) async {
    _currentContext = FfmWorkingContext(
      lastUserIntent: lastUserIntent ?? _currentContext.lastUserIntent,
      lastReferencedEntity: lastReferencedEntity ?? _currentContext.lastReferencedEntity,
      currentTopic: currentTopic ?? _currentContext.currentTopic,
      currentPeriod: currentPeriod ?? _currentContext.currentPeriod,
      currentGoal: currentGoal ?? _currentContext.currentGoal,
      pendingClarification: pendingClarification ?? _currentContext.pendingClarification,
      lastActionResult: _currentContext.lastActionResult,
      lastUpdatedAt: DateTime.now(),
    );

    await _persist();
    return _currentContext;
  }

  /// Clear working context
  Future<FfmWorkingContext> clear() async {
    _currentContext = const FfmWorkingContext();
    await _persist();
    return _currentContext;
  }

  /// Set pending clarification
  Future<FfmWorkingContext> setPendingClarification(String clarification) async {
    _currentContext = FfmWorkingContext(
      lastUserIntent: _currentContext.lastUserIntent,
      lastReferencedEntity: _currentContext.lastReferencedEntity,
      currentTopic: _currentContext.currentTopic,
      currentPeriod: _currentContext.currentPeriod,
      currentGoal: _currentContext.currentGoal,
      pendingClarification: clarification,
      lastActionResult: _currentContext.lastActionResult,
      lastUpdatedAt: DateTime.now(),
    );

    await _persist();
    return _currentContext;
  }

  bool get hasPendingClarification => _currentContext.pendingClarification != null;

  Map<String, dynamic> get summary => {
    'lastUserIntent': _currentContext.lastUserIntent,
    'lastReferencedEntity': _currentContext.lastReferencedEntity,
    'currentTopic': _currentContext.currentTopic,
    'currentPeriod': _currentContext.currentPeriod,
    'currentGoal': _currentContext.currentGoal,
    'pendingClarification': _currentContext.pendingClarification,
    'hasLastActionResult': _currentContext.lastActionResult != null,
    'lastUpdatedAt': _currentContext.lastUpdatedAt?.toIso8601String(),
  };

  // Private helper methods

  Map<String, String> _extractSimpleEntities(String query) {
    final lowerQuery = query.toLowerCase();
    final entities = <String, String>{};

    if (lowerQuery.contains('pengeluaran') || lowerQuery.contains('belanja')) {
      entities['topic'] = 'spending';
    } else if (lowerQuery.contains('pemasukan') || lowerQuery.contains('gaji')) {
      entities['topic'] = 'income';
    } else if (lowerQuery.contains('tabungan') || lowerQuery.contains('nabung')) {
      entities['topic'] = 'savings';
    } else if (lowerQuery.contains('target')) {
      entities['topic'] = 'goals';
    } else if (lowerQuery.contains('hutang') || lowerQuery.contains('utang')) {
      entities['topic'] = 'liabilities';
    }

    if (lowerQuery.contains('bulan ini')) {
      entities['period'] = 'current_month';
    } else if (lowerQuery.contains('minggu ini')) {
      entities['period'] = 'current_week';
    } else if (lowerQuery.contains('kemarin')) {
      entities['period'] = 'yesterday';
    } else if (lowerQuery.contains('bulan lalu')) {
      entities['period'] = 'previous_month';
    }

    if (lowerQuery.contains('berapa') || lowerQuery.contains('jumlah')) {
      entities['intent'] = 'query_amount';
    } else if (lowerQuery.contains('aman') || lowerQuery.contains('boros')) {
      entities['intent'] = 'financial_analysis';
    } else if (lowerQuery.contains('buat') || lowerQuery.contains('tambah')) {
      entities['intent'] = 'create';
    } else if (lowerQuery.contains('lihat') || lowerQuery.contains('tampilkan')) {
      entities['intent'] = 'view';
    }

    if (lowerQuery.contains('makan') || lowerQuery.contains('makanan')) {
      entities['entity'] = 'food';
    } else if (lowerQuery.contains('transportasi') || lowerQuery.contains('bensin')) {
      entities['entity'] = 'transport';
    } else if (lowerQuery.contains('listrik') || lowerQuery.contains('air')) {
      entities['entity'] = 'utilities';
    }

    return entities;
  }
}
