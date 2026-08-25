import '../domain/ffm_personal_context.dart';
import 'ffm_assistant_chat_history_repository.dart';

/// Manager untuk working context yang terintegrasi dengan chat history.
///
/// Working context menyimpan state percakapan aktif yang digunakan untuk
/// mempertahankan referensi antar-turn percakapan.
class FfmWorkingContextManager {
  FfmWorkingContextManager({
    required FfmAssistantChatHistoryRepository chatHistoryRepository,
  }) : _chatHistoryRepository = chatHistoryRepository;

  final FfmAssistantChatHistoryRepository _chatHistoryRepository;
  FfmWorkingContext _currentContext = const FfmWorkingContext();

  /// Get current working context
  FfmWorkingContext get currentContext => _currentContext;

  /// Update working context setelah percakapan turn
  FfmWorkingContext updateAfterTurn({
    required String userQuery,
    required String? assistantResponse,
    required Map<String, String> extractedEntities,
  }) {
    final entities = extractedEntities.isEmpty
        ? _extractSimpleEntities(userQuery)
        : extractedEntities;
    _currentContext = FfmWorkingContext(
      lastUserIntent: entities['intent'] ?? _currentContext.lastUserIntent,
      lastReferencedEntity:
          entities['entity'] ?? _currentContext.lastReferencedEntity,
      currentTopic: entities['topic'] ?? _currentContext.currentTopic,
      currentPeriod: entities['period'] ?? _currentContext.currentPeriod,
      currentGoal: entities['goal'] ?? _currentContext.currentGoal,
      pendingClarification: null, // Reset clarification setelah response
      // Jangan menyimpan isi respons yang dapat memuat rincian finansial.
      // Marker ini cukup untuk menjaga state percakapan tanpa menjadikannya
      // memori tahan lama atau prompt mentah pada turn berikutnya.
      lastActionResult: assistantResponse == null || assistantResponse.isEmpty
          ? _currentContext.lastActionResult
          : 'assistant_response_ready',
    );

    return _currentContext;
  }

  /// Extract working context dari chat history terakhir
  Future<FfmWorkingContext> rebuildFromHistory() async {
    final entries = await _chatHistoryRepository.load();

    if (entries.isEmpty) {
      _currentContext = const FfmWorkingContext();
      return _currentContext;
    }

    // Ambil beberapa entry terakhir untuk rebuild context
    final recentEntries = entries.length > 10
        ? entries.sublist(entries.length - 10)
        : entries;

    // Extract context dari entry terakhir
    for (final entry in recentEntries.reversed) {
      if (entry.isUser) {
        // Simple entity extraction dari user query
        final entities = _extractSimpleEntities(entry.text);

        _currentContext = FfmWorkingContext(
          lastUserIntent: entities['intent'] ?? _currentContext.lastUserIntent,
          lastReferencedEntity:
              entities['entity'] ?? _currentContext.lastReferencedEntity,
          currentTopic: entities['topic'] ?? _currentContext.currentTopic,
          currentPeriod: entities['period'] ?? _currentContext.currentPeriod,
          currentGoal: entities['goal'] ?? _currentContext.currentGoal,
          pendingClarification: null,
          lastActionResult: _currentContext.lastActionResult,
        );

        break; // Hanya ambil user query terakhir
      }
    }

    return _currentContext;
  }

  /// Set specific context values manually
  FfmWorkingContext setContext({
    String? lastUserIntent,
    String? lastReferencedEntity,
    String? currentTopic,
    String? currentPeriod,
    String? currentGoal,
    String? pendingClarification,
  }) {
    _currentContext = FfmWorkingContext(
      lastUserIntent: lastUserIntent ?? _currentContext.lastUserIntent,
      lastReferencedEntity:
          lastReferencedEntity ?? _currentContext.lastReferencedEntity,
      currentTopic: currentTopic ?? _currentContext.currentTopic,
      currentPeriod: currentPeriod ?? _currentContext.currentPeriod,
      currentGoal: currentGoal ?? _currentContext.currentGoal,
      pendingClarification:
          pendingClarification ?? _currentContext.pendingClarification,
      lastActionResult: _currentContext.lastActionResult,
    );

    return _currentContext;
  }

  /// Clear working context (reset ke initial state)
  FfmWorkingContext clear() {
    _currentContext = const FfmWorkingContext();
    return _currentContext;
  }

  /// Set pending clarification
  FfmWorkingContext setPendingClarification(String clarification) {
    _currentContext = FfmWorkingContext(
      lastUserIntent: _currentContext.lastUserIntent,
      lastReferencedEntity: _currentContext.lastReferencedEntity,
      currentTopic: _currentContext.currentTopic,
      currentPeriod: _currentContext.currentPeriod,
      currentGoal: _currentContext.currentGoal,
      pendingClarification: clarification,
      lastActionResult: _currentContext.lastActionResult,
    );

    return _currentContext;
  }

  /// Check apakah ada pending clarification
  bool get hasPendingClarification =>
      _currentContext.pendingClarification != null;

  /// Get working context summary untuk debugging
  Map<String, dynamic> get summary => {
    'lastUserIntent': _currentContext.lastUserIntent,
    'lastReferencedEntity': _currentContext.lastReferencedEntity,
    'currentTopic': _currentContext.currentTopic,
    'currentPeriod': _currentContext.currentPeriod,
    'currentGoal': _currentContext.currentGoal,
    'pendingClarification': _currentContext.pendingClarification,
    'hasLastActionResult': _currentContext.lastActionResult != null,
  };

  // Private helper methods

  Map<String, String> _extractSimpleEntities(String query) {
    final lowerQuery = query.toLowerCase();
    final entities = <String, String>{};

    // Topic detection
    if (lowerQuery.contains('pengeluaran') || lowerQuery.contains('belanja')) {
      entities['topic'] = 'spending';
    } else if (lowerQuery.contains('pemasukan') ||
        lowerQuery.contains('gaji')) {
      entities['topic'] = 'income';
    } else if (lowerQuery.contains('tabungan') ||
        lowerQuery.contains('nabung')) {
      entities['topic'] = 'savings';
    }

    // Period detection
    if (lowerQuery.contains('bulan ini')) {
      entities['period'] = 'current_month';
    } else if (lowerQuery.contains('minggu ini')) {
      entities['period'] = 'current_week';
    }

    // Intent detection
    if (lowerQuery.contains('berapa') || lowerQuery.contains('jumlah')) {
      entities['intent'] = 'query_amount';
    } else if (lowerQuery.contains('aman') || lowerQuery.contains('boros')) {
      entities['intent'] = 'financial_analysis';
    }

    // Entity detection (simple)
    if (lowerQuery.contains('makan') || lowerQuery.contains('makanan')) {
      entities['entity'] = 'food';
    }

    return entities;
  }
}
