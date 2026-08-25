import '../domain/ffm_personal_context.dart';
import '../domain/ffm_assistant_reasoning_context.dart';

/// Adapter untuk mengintegrasikan Personal Context Engine dengan reasoning layer.
///
/// Mengubah FfmPersonalContext menjadi format yang bisa digunakan oleh
/// FfmAssistantReasoningContext yang sudah ada.
class FfmContextAdapter {
  const FfmContextAdapter();

  static const _maxApprovedContextCharacters = 700;
  static const _maxPersonalizationCharacters = 700;

  /// Update reasoning context dengan personal context
  FfmAssistantReasoningContext updateReasoningContext({
    required FfmAssistantReasoningContext originalContext,
    required FfmPersonalContext personalContext,
  }) {
    // Build personalization context string dari personal context
    final personalizationText = _buildPersonalizationText(personalContext);

    // Build approved user context string
    final approvedUserText = _buildApprovedUserContext(personalContext);

    return FfmAssistantReasoningContext(
      request: originalContext.request,
      capturedAt: originalContext.capturedAt,
      currentPage: originalContext.currentPage,
      pageSummary: originalContext.pageSummary,
      activeFilters: originalContext.activeFilters,
      capabilityIds: originalContext.capabilityIds,
      approvedUserContext: _mergeBounded(
        originalContext.approvedUserContext,
        approvedUserText,
        _maxApprovedContextCharacters,
      ),
      personalizationContext: _mergeBounded(
        originalContext.personalizationContext,
        personalizationText,
        _maxPersonalizationCharacters,
      ),
      modelReady: originalContext.modelReady,
      previousStepResults: originalContext.previousStepResults,
      recentTransactions: _shouldIncludeTransactions(personalContext)
          ? originalContext.recentTransactions
          : [],
    );
  }

  /// Build personalization context string untuk reasoning context
  String _buildPersonalizationText(FfmPersonalContext context) {
    final parts = <String>[];

    // Add preferences
    if (context.preferences.isNotEmpty) {
      final prefText = _candidateList(context.preferences, maxItems: 3);
      parts.add('Preferensi: $prefText');
    }

    // Add goals
    if (context.goals.isNotEmpty) {
      final goalText = _candidateList(context.goals, maxItems: 2);
      parts.add('Tujuan aktif: $goalText');
    }

    // Add behavioral patterns
    if (context.behaviorPatterns.isNotEmpty) {
      final patternText = _candidateList(context.behaviorPatterns, maxItems: 2);
      parts.add('Pola behavior: $patternText');
    }

    // Add corrections
    if (context.corrections.isNotEmpty) {
      final correctionText = _candidateList(context.corrections, maxItems: 2);
      parts.add('Koreksi user: $correctionText');
    }

    if (parts.isEmpty) return '';
    return parts.join(' | ');
  }

  /// Build approved user context string
  String _buildApprovedUserContext(FfmPersonalContext context) {
    final parts = <String>[];

    // Add personal facts
    if (context.personalFacts.isNotEmpty) {
      final factText = _candidateList(context.personalFacts, maxItems: 3);
      parts.add('Fakta personal: $factText');
    }

    // Add working context if relevant
    if (context.workingContext.isNotEmpty) {
      final workingText = _candidateList(context.workingContext, maxItems: 2);
      parts.add('Konteks percakapan: $workingText');
    }

    if (parts.isEmpty) return '';
    return parts.join(' | ');
  }

  /// Determine apakah perlu include transactions berdasarkan context
  bool _shouldIncludeTransactions(FfmPersonalContext context) {
    return context.dataContext.requiresRecentTransactions ||
        context.detectedEntities.containsKey('period') ||
        context.detectedTopic == 'spending' ||
        context.detectedTopic == 'income';
  }

  /// Extract response preferences dari personal context
  FfmResponsePreferences extractResponsePreferences(
    FfmPersonalContext context,
  ) {
    return context.responsePreferences;
  }

  /// Build prompt enhancement suggestions berdasarkan personal context
  List<String> buildPromptEnhancements(FfmPersonalContext context) {
    final enhancements = <String>[];

    // Response style
    if (context.responsePreferences.concise) {
      enhancements.add('Jawab secara singkat dan langsung ke poin.');
    }

    // Language
    if (context.responsePreferences.useIndonesian) {
      enhancements.add('Gunakan bahasa Indonesia yang natural.');
    }

    // Currency format
    if (context.responsePreferences.showRupiah) {
      enhancements.add('Tampilkan nominal dalam format Rupiah.');
    }

    // Topic-specific guidance
    if (context.detectedTopic == 'spending') {
      if (context.goals.any(
        (g) => g.key.contains('tabungan') || g.key.contains('target'),
      )) {
        enhancements.add(
          'Pertimbangkan target tabungan user dalam analisis pengeluaran.',
        );
      }
    }

    // Data context guidance
    if (context.dataContext.requiresFinancialSummary) {
      enhancements.add(
        'Gunakan data finansial aktual sebagai sumber kebenaran.',
      );
    }

    return enhancements;
  }

  /// Validate context sebelum digunakan
  bool validateContext(FfmPersonalContext context) {
    // Check untuk conflict resolution
    if (context.processingMetadata.containsKey('conflict_detected')) {
      return false;
    }

    // Check untuk sensitive data handling
    if (context.processingMetadata.containsKey('sensitive_data_blocked')) {
      return false;
    }

    return true;
  }

  /// Build error message jika context tidak valid
  String buildContextErrorMessage(FfmPersonalContext context) {
    if (context.processingMetadata.containsKey('conflict_detected')) {
      return 'Ditemukan konflik memory yang perlu diselesaikan.';
    }
    if (context.processingMetadata.containsKey('sensitive_data_blocked')) {
      return 'Data sensitif terdeteksi dan tidak dapat digunakan.';
    }
    return 'Context tidak valid untuk alasan yang tidak diketahui.';
  }

  String _candidateList(
    Iterable<dynamic> candidates, {
    required int maxItems,
  }) => candidates
      .take(maxItems)
      .map(
        (candidate) =>
            '${_clip(candidate.key, 48)}=${_clip(candidate.value, 96)}',
      )
      .join(', ');

  String _mergeBounded(String existing, String addition, int maxCharacters) {
    final combined = [
      if (existing.trim().isNotEmpty) existing.trim(),
      if (addition.trim().isNotEmpty) addition.trim(),
    ].join(' | ');
    return _clip(combined, maxCharacters);
  }

  String _clip(String value, int maxCharacters) {
    final normalized = value.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    if (normalized.length <= maxCharacters) return normalized;
    return '${normalized.substring(0, maxCharacters - 1)}…';
  }
}
