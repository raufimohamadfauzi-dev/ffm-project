import '../domain/ffm_personal_context.dart';
import '../domain/ffm_assistant_reasoning_context.dart';

/// Adapter untuk mengintegrasikan Personal Context Engine dengan reasoning layer.
///
/// Mengubah FfmPersonalContext menjadi format yang bisa digunakan oleh
/// FfmAssistantReasoningContext yang sudah ada.
class FfmContextAdapter {
  const FfmContextAdapter();

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
      approvedUserContext: approvedUserText,
      personalizationContext: personalizationText,
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
      final prefText = context.preferences
          .map((p) => '${p.key}=${p.value}')
          .join(', ');
      parts.add('Preferensi: $prefText');
    }

    // Add goals
    if (context.goals.isNotEmpty) {
      final goalText = context.goals
          .map((g) => '${g.key}: ${g.value}')
          .join(', ');
      parts.add('Tujuan aktif: $goalText');
    }

    // Add behavioral patterns
    if (context.behaviorPatterns.isNotEmpty) {
      final patternText = context.behaviorPatterns
          .take(3)
          .map((p) => '${p.key}=${p.value}')
          .join(', ');
      parts.add('Pola behavior: $patternText');
    }

    // Add corrections
    if (context.corrections.isNotEmpty) {
      final correctionText = context.corrections
          .take(2)
          .map((c) => '${c.key}=${c.value}')
          .join(', ');
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
      final factText = context.personalFacts
          .map((f) => '${f.key}=${f.value}')
          .join(', ');
      parts.add('Fakta personal: $factText');
    }

    // Add working context if relevant
    if (context.workingContext.isNotEmpty) {
      final workingText = context.workingContext
          .map((w) => '${w.key}=${w.value}')
          .join(', ');
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
  FfmResponsePreferences extractResponsePreferences(FfmPersonalContext context) {
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
      if (context.goals.any((g) => g.key.contains('tabungan') || g.key.contains('target'))) {
        enhancements.add('Pertimbangkan target tabungan user dalam analisis pengeluaran.');
      }
    }

    // Data context guidance
    if (context.dataContext.requiresFinancialSummary) {
      enhancements.add('Gunakan data finansial aktual sebagai sumber kebenaran.');
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
}
