import 'ffm_personal_context.dart';
import 'ffm_memory_candidate.dart';
import 'ffm_context_relevance.dart';
import 'ffm_assistant_reasoning_context.dart';
import 'ffm_memory_type.dart';

/// Personal Context Engine - Orchestrator untuk mengambil dan menyusun
/// konteks personal yang relevan untuk setiap query pengguna.
///
/// Sesuai spesifikasi FFM Personal Memory & Context Engine:
/// - Stage 1: Normalization
/// - Stage 2: Entity & Topic Extraction
/// - Stage 3: Cheap Retrieval
/// - Stage 4: Structured Filtering
/// - Stage 5: Relevance Scoring
/// - Stage 6: Deduplication
/// - Stage 7: Conflict Resolution
/// - Stage 8: Context Budget
/// - Stage 9: Context Pack
abstract class FfmPersonalContextEngine {
  /// Build personal context untuk query pengguna.
  ///
  /// Ini adalah method utama yang akan dipanggil sebelum response generation.
  /// Context Engine mengambil kandidat dari berbagai sumber, scoring, filtering,
  /// dan menyusunnya menjadi structured context pack.
  Future<FfmPersonalContext> buildContext({
    required String query,
    FfmAssistantReasoningContext? reasoningContext,
    FfmWorkingContext? previousWorkingContext,
    FfmContextBudget? budget,
  });

  /// Update working context setelah percakapan turn selesai.
  ///
  /// Ini digunakan untuk mempertahankan referensi antar-turn percakapan.
  FfmWorkingContext updateWorkingContext({
    required FfmWorkingContext current,
    required String userQuery,
    required String? assistantResponse,
    Map<String, String>? extractedEntities,
  });

  /// Extract memory candidates dari percakapan.
  ///
  /// Dihasilkan oleh SLM atau pattern extraction, tetapi harus melalui
  /// validasi dan approval sebelum menjadi persistent memory.
  Future<List<FfmMemoryPromotionCandidate>> extractMemoryCandidates({
    required String userQuery,
    required String? assistantResponse,
    required List<FfmMemoryCandidate> usedMemories,
  });

  /// Validate dan promosikan memory candidates menjadi persistent memory.
  ///
  /// Hanya candidate yang valid dan disetujui pengguna yang akan disimpan.
  Future<List<FfmMemoryCandidate>> promoteCandidates({
    required List<FfmMemoryPromotionCandidate> candidates,
    required bool requireApproval,
  });

  /// Update usage tracking untuk memory yang digunakan.
  ///
 /// Batch/debounced write untuk performance.
  Future<void> updateMemoryUsage({
    required List<String> memoryIds,
  });

  /// Conflict resolution untuk memory yang konflik.
  FfmConflictResolution resolveConflict({
    required List<FfmMemoryCandidate> conflictingMemories,
  });

  /// Deduplication untuk memory yang duplikat.
  List<FfmMemoryCandidate> deduplicateMemories({
    required List<FfmMemoryCandidate> memories,
  });

  /// Calculate recency score berdasarkan age dan memory type.
  double calculateRecencyScore({
    required DateTime memoryDate,
    required FfmMemoryType type,
    required DateTime now,
  });

  /// Normalize query input.
  String normalizeQuery(String query);

  /// Extract entities dan topic dari query.
  Map<String, dynamic> extractEntitiesAndTopic(String normalizedQuery);
}

/// Error yang mungkin terjadi saat context retrieval
class FfmContextEngineError implements Exception {
  const FfmContextEngineError({
    required this.message,
    this.code,
    this.details,
  });

  final String message;
  final String? code;
  final dynamic details;

  @override
  String toString() => 'FfmContextEngineError: $message${code != null ? " ($code)" : ""}';
}

/// Error codes untuk context engine
class FfmContextEngineErrorCode {
  static const String retrievalFailed = 'RETRIEVAL_FAILED';
  static const String scoringFailed = 'SCORING_FAILED';
  static const String conflictResolutionFailed = 'CONFLICT_RESOLUTION_FAILED';
  static const String normalizationFailed = 'NORMALIZATION_FAILED';
  static const String entityExtractionFailed = 'ENTITY_EXTRACTION_FAILED';
  static const String budgetExceeded = 'BUDGET_EXCEEDED';
  static const String validationFailed = 'VALIDATION_FAILED';
}
