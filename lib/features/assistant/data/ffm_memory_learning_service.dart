import '../domain/ffm_memory_candidate.dart';
import '../domain/ffm_memory_type.dart';

/// Service untuk learning dan candidate extraction dari percakapan.
///
/// Phase 6 dari Personal Memory & Context Engine implementation.
class FfmMemoryLearningService {
  FfmMemoryLearningService();

  /// Extract memory candidates dari percakapan turn.
  ///
  /// Menggabungkan pattern-based extraction (existing) dengan SLM-based extraction (future).
  Future<List<FfmMemoryPromotionCandidate>> extractCandidates({
    required String userQuery,
    required String? assistantResponse,
    required List<FfmMemoryCandidate> usedMemories,
  }) async {
    final candidates = <FfmMemoryPromotionCandidate>[];

    // 1. Pattern-based extraction (simple placeholder)
    final patternCandidates = _extractPatternBased(userQuery);
    candidates.addAll(patternCandidates);

    // 2. Usage-based learning
    final usageCandidates = _extractUsageBased(usedMemories);
    candidates.addAll(usageCandidates);

    // 3. Correction-based learning
    if (assistantResponse != null) {
      final correctionCandidates = _extractCorrectionBased(userQuery, assistantResponse);
      candidates.addAll(correctionCandidates);
    }

    // 4. TODO: SLM-based extraction (future phase)
    // final slmCandidates = await _extractSLMBased(userQuery, assistantResponse);
    // candidates.addAll(slmCandidates);

    return candidates;
  }

  /// Validate candidates berdasarkan aturan spesifikasi
  List<FfmMemoryPromotionCandidate> validateCandidates(
    List<FfmMemoryPromotionCandidate> candidates,
  ) {
    return candidates.where((candidate) {
      // Basic validation
      if (!candidate.isValid) return false;

      // Sensitive data check
      if (candidate.isSensitive) return false;

      // Duplicate check
      if (_isDuplicate(candidate)) return false;

      // Contradiction check
      if (_hasContradiction(candidate)) return false;

      return true;
    }).toList();
  }

  /// Promote validated candidates menjadi persistent memory
  Future<List<FfmMemoryCandidate>> promoteCandidates({
    required List<FfmMemoryPromotionCandidate> candidates,
    required bool requireApproval,
  }) async {
    final promoted = <FfmMemoryCandidate>[];

    for (final candidate in candidates) {
      try {
        final memoryCandidate = await _promoteSingleCandidate(candidate, requireApproval);
        if (memoryCandidate != null) {
          promoted.add(memoryCandidate);
        }
      } catch (e) {
        // Log error tapi continue dengan candidate lain
        continue;
      }
    }

    return promoted;
  }

  /// Apply decay ke memory yang tidak sering digunakan
  Future<void> applyMemoryDecay() async {
    // TODO: Implement decay logic
    // - Update status untuk memory yang lama tidak digunakan
    // - Archive memory yang sudah stale
    // - Keep active goals dan important preferences
  }

  /// Track memory usage dan update importance
  Future<void> trackMemoryUsage(List<String> memoryIds) async {
    // TODO: Implement usage tracking
    // - Update lastUsedAt
    // - Increment useCount
    // - Recalculate importance berdasarkan usage pattern
  }

  // Private helper methods

  List<FfmMemoryPromotionCandidate> _extractPatternBased(String userQuery) {
    final candidates = <FfmMemoryPromotionCandidate>[];

    // Simple pattern extraction sebagai placeholder
    // TODO: Integrate dengan actual personal memory service
    final lowerQuery = userQuery.toLowerCase();
    
    // Extract simple patterns
    if (lowerQuery.contains('panggil saya') || lowerQuery.contains('nama saya')) {
      candidates.add(FfmMemoryPromotionCandidate(
        type: FfmMemoryType.identity,
        key: 'preferred_name',
        value: _extractName(userQuery),
        confidence: 0.7,
        reason: 'User menyebutkan nama panggilan',
        sourceId: userQuery,
        requiresApproval: true,
      ));
    }

    return candidates;
  }

  String _extractName(String query) {
    // Simple name extraction as placeholder
    final words = query.split(' ');
    for (var i = 0; i < words.length; i++) {
      if (words[i].toLowerCase() == 'adalah' && i + 1 < words.length) {
        return words[i + 1];
      }
    }
    return 'unknown';
  }

  List<FfmMemoryPromotionCandidate> _extractUsageBased(
    List<FfmMemoryCandidate> usedMemories,
  ) {
    final candidates = <FfmMemoryPromotionCandidate>[];

    // Jika memory sering digunakan bersama-sama, mungkin ada pattern
    // Contoh: user selalu bertanya tentang makan setelah bertanya tentang gaji
    // Ini bisa menjadi episodic memory atau habit

    // TODO: Implement co-occurrence analysis
    // - Detect patterns dalam memory usage
    // - Create episodic memory untuk frequent co-occurrences
    // - Update importance berdasarkan usage frequency

    return candidates;
  }

  List<FfmMemoryPromotionCandidate> _extractCorrectionBased(
    String userQuery,
    String assistantResponse,
  ) {
    final candidates = <FfmMemoryPromotionCandidate>[];

    // Detect jika user mengoreksi assistant
    final correctionPatterns = [
      RegExp(r'salah|bukan|tidak|jangan', caseSensitive: false),
      RegExp(r'korrek|perbaiki|ubah', caseSensitive: false),
    ];

    final isCorrection = correctionPatterns.any((pattern) => pattern.hasMatch(userQuery));
    
    if (isCorrection) {
      // Extract correction context
      // Ini bisa menjadi correction memory dengan confidence tinggi
      // TODO: Implement correction extraction logic
    }

    return candidates;
  }

  Future<FfmMemoryCandidate?> _promoteSingleCandidate(
    FfmMemoryPromotionCandidate candidate,
    bool requireApproval,
  ) async {
    // Jika memerlukan approval dan belum di-approve, skip
    if (requireApproval && !candidate.requiresApproval) {
      return null;
    }

    // Convert ke memory candidate
    final memoryCandidate = FfmMemoryCandidate(
      id: 'memory-${DateTime.now().microsecondsSinceEpoch}',
      type: candidate.type,
      key: candidate.key,
      value: candidate.value,
      evidence: FfmMemoryEvidence(
        source: candidate.requiresApproval 
            ? FfmMemorySource.userExplicit 
            : FfmMemorySource.inferredPattern,
        sourceId: candidate.sourceId,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        confidence: candidate.confidence,
        approved: !candidate.requiresApproval,
      ),
      importance: _calculateInitialImportance(candidate),
    );

    // Simpan ke repository yang sesuai
    await _saveToRepository(memoryCandidate, candidate);

    return memoryCandidate;
  }

  Future<void> _saveToRepository(
    FfmMemoryCandidate memoryCandidate,
    FfmMemoryPromotionCandidate promotionCandidate,
  ) async {
    // Save logic sudah diimplementasikan di context engine
    // Reuse logic tersebut
    // TODO: Extract common save logic ke shared service
    // Placeholder: currently no-op
  }

  double _calculateInitialImportance(FfmMemoryPromotionCandidate candidate) {
    // Calculate importance berdasarkan tipe dan confidence
    switch (candidate.type) {
      case FfmMemoryType.goal:
        return 1.0; // Goals are very important
      case FfmMemoryType.identity:
        return 0.8; // Identity facts are important
      case FfmMemoryType.preference:
        return 0.6; // Preferences are moderately important
      case FfmMemoryType.correction:
        return 0.9; // Corrections are very important
      case FfmMemoryType.explicitFact:
        return 0.7; // Explicit facts are important
      default:
        return 0.5; // Default importance
    }
  }

  bool _isDuplicate(FfmMemoryPromotionCandidate candidate) {
    // Check apakah candidate sudah ada sebagai memory
    // TODO: Implement duplicate check dengan repository
    return false;
  }

  bool _hasContradiction(FfmMemoryPromotionCandidate candidate) {
    // Check apakah candidate contradict dengan existing memory
    // TODO: Implement contradiction check
    return false;
  }
}
