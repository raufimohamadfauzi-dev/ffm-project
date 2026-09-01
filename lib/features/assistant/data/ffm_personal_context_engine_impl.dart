import 'dart:math' as math;
import 'dart:math' show Random;

import '../../../core/database/app_database.dart'
    show AppDatabase, InteractionPattern;
import '../domain/ffm_personal_context_engine.dart';
import '../domain/ffm_personal_context.dart';
import '../domain/ffm_memory_candidate.dart';
import '../domain/ffm_memory_type.dart';
import '../domain/ffm_context_relevance.dart';
import '../domain/ffm_assistant_reasoning_context.dart';
import '../domain/ffm_assistant_models.dart';
import 'ffm_assistant_memory_repository.dart';
import 'ffm_memory_learning_service.dart';
import 'ffm_assistant_user_model_service.dart';
import 'ffm_personal_memory_service.dart';
import 'ffm_assistant_draft_feedback_service.dart';
import 'ffm_assistant_personalization_repository.dart';
import 'ffm_assistant_fuzzy_matcher.dart';
import 'ffm_assistant_typo_normalizer.dart';
import 'ffm_working_context_manager.dart';

/// Implementasi concrete dari Personal Context Engine.
///
/// Mengintegrasikan semua komponen memory yang sudah ada:
/// - FfmAssistantMemoryRepository
/// - FfmAssistantUserModelService
/// - FfmPersonalMemoryService
/// - FfmAssistantPersonalizationRepository
/// - FfmAssistantFuzzyMatcher
/// - FfmAssistantTypoNormalizer
class FfmPersonalContextEngineImpl implements FfmPersonalContextEngine {
  FfmPersonalContextEngineImpl({
    required AppDatabase database,
    FfmAssistantMemoryRepository? memoryRepository,
    FfmAssistantUserModelService? userModelService,
    FfmPersonalMemoryService? personalMemoryService,
    FfmAssistantDraftFeedbackService? draftFeedbackService,
    FfmAssistantPersonalizationRepository? personalizationRepository,
    FfmWorkingContextManager? workingContextManager,
  }) : _memoryRepository =
           memoryRepository ?? FfmAssistantMemoryRepository(database),
       _userModelService =
           userModelService ??
           FfmAssistantUserModelService(FfmAssistantMemoryRepository(database)),
       _personalMemoryService =
           personalMemoryService ??
           FfmPersonalMemoryService(
             FfmAssistantMemoryRepository(database),
             draftFeedbackService ?? FfmAssistantDraftFeedbackService(),
           ),
       _personalizationRepository =
           personalizationRepository ??
               FfmAssistantPersonalizationRepository(database) {
    _workingContextManager = workingContextManager;
  }

  final FfmAssistantMemoryRepository _memoryRepository;
  final FfmAssistantUserModelService _userModelService;
  final FfmPersonalMemoryService _personalMemoryService;
  final FfmAssistantPersonalizationRepository _personalizationRepository;
  FfmWorkingContextManager? _workingContextManager;
  final _random = Random();

  static const householdId = 'local-household';

  @override
  Future<FfmPersonalContext> buildContext({
    required String query,
    FfmAssistantReasoningContext? reasoningContext,
    FfmWorkingContext? previousWorkingContext,
    FfmContextBudget? budget,
  }) async {
    final contextBudget = budget ?? const FfmContextBudget();
    final now = DateTime.now();

    // Use working context manager if available, otherwise use provided context
    final workingContext =
        previousWorkingContext ??
        _workingContextManager?.currentContext ??
        const FfmWorkingContext();

    try {
      // Stage 1: Normalization
      final normalizedQuery = normalizeQuery(query);

      // Stage 2: Entity & Topic Extraction
      final extracted = extractEntitiesAndTopic(normalizedQuery);
      final detectedTopic = extracted['topic'] as String?;
      final detectedEntities =
          extracted['entities'] as Map<String, String>? ?? {};
      final detectedIntent = extracted['intent'] as String?;

      // Merge dengan working context untuk follow-up detection
      final mergedEntities = _mergeWithWorkingContext(
        detectedEntities,
        workingContext,
      );

      // Stage 3: Cheap Retrieval - ambil kandidat dari berbagai sumber
      final candidates = await _retrieveCandidates(
        normalizedQuery,
        detectedTopic,
        mergedEntities,
        reasoningContext,
        workingContext,
      );

      // Stage 4: Structured Filtering
      final filtered = _filterCandidates(
        candidates,
        detectedTopic,
        mergedEntities,
      );

      // Stage 5: Relevance Scoring
      final scored = _scoreCandidates(
        filtered,
        normalizedQuery,
        detectedTopic,
        mergedEntities,
        now,
      );

      // Stage 6: Deduplication
      final deduplicated = deduplicateMemories(memories: scored);

      // Stage 7: Conflict Resolution
      final resolved = _resolveConflicts(deduplicated);

      // Stage 8: Context Budget
      final budgeted = _applyBudget(resolved, contextBudget);

      // Stage 9: Context Pack - susun menjadi structured context
      final contextPack = _buildContextPack(
        budgeted,
        query,
        normalizedQuery,
        detectedTopic,
        mergedEntities,
        detectedIntent,
        reasoningContext,
        workingContext,
        now,
      );

      return contextPack;
    } catch (e) {
      // Fallback behavior sesuai spesifikasi
      return _buildFallbackContext(
        query,
        reasoningContext,
        workingContext,
        now,
      );
    }
  }

  @override
  FfmWorkingContext updateWorkingContext({
    required FfmWorkingContext current,
    required String userQuery,
    required String? assistantResponse,
    Map<String, String>? extractedEntities,
  }) {
    // Update working context berdasarkan percakapan terakhir
    final entities =
        extractedEntities ??
        extractEntitiesAndTopic(userQuery)['entities']
            as Map<String, String>? ??
        {};

    final updatedContext = FfmWorkingContext(
      lastUserIntent: entities['intent'] ?? current.lastUserIntent,
      lastReferencedEntity: entities['entity'] ?? current.lastReferencedEntity,
      currentTopic: entities['topic'] ?? current.currentTopic,
      currentPeriod: entities['period'] ?? current.currentPeriod,
      currentGoal: entities['goal'] ?? current.currentGoal,
      pendingClarification: null, // Reset clarification setelah response
      lastActionResult: assistantResponse,
    );

    // Update manager jika available
    _workingContextManager?.setContext(
      lastUserIntent: updatedContext.lastUserIntent,
      lastReferencedEntity: updatedContext.lastReferencedEntity,
      currentTopic: updatedContext.currentTopic,
      currentPeriod: updatedContext.currentPeriod,
      currentGoal: updatedContext.currentGoal,
    );

    return updatedContext;
  }

  @override
  Future<List<FfmMemoryPromotionCandidate>> extractMemoryCandidates({
    required String userQuery,
    required String? assistantResponse,
    required List<FfmMemoryCandidate> usedMemories,
  }) async {
    // Extract candidates dari personal memory service
    final insight = _personalMemoryService.extractFromMessage(userQuery);

    final candidates = <FfmMemoryPromotionCandidate>[];

    if (insight != null) {
      // Convert insight ke promotion candidate
      final memoryType = _convertInsightKindToMemoryType(insight.kind);
      candidates.add(
        FfmMemoryPromotionCandidate(
          type: memoryType,
          key: insight.key,
          value: insight.value,
          confidence: 0.8, // Default confidence untuk pattern-detected
          reason: insight.humanLabel,
          sourceId: insight.sourceMessage,
          requiresApproval: true,
        ),
      );
    }

    // TODO: Di fase berikutnya, tambahkan SLM-based extraction
    return candidates;
  }

  @override
  Future<List<FfmMemoryCandidate>> promoteCandidates({
    required List<FfmMemoryPromotionCandidate> candidates,
    required bool requireApproval,
  }) async {
    final promoted = <FfmMemoryCandidate>[];

    for (final candidate in candidates) {
      // Validasi candidate
      if (!candidate.isValid) continue;

      // Kontrak memori personal mewajibkan persetujuan eksplisit. Engine ini
      // tidak memiliki UI persetujuan, maka ia tidak boleh mempersistenkan
      // kandidat yang menunggu user meskipun data kandidat tampak aman.
      if (requireApproval && candidate.requiresApproval) continue;

      // Cek sensitive data
      if (candidate.isSensitive) continue;

      // Convert ke FfmMemoryCandidate
      final memoryCandidate = FfmMemoryCandidate(
        id: 'memory-${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(10000)}',
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
        importance: 0.5, // Default importance
      );

      // Simpan ke repository yang sesuai
      await _saveCandidateToRepository(memoryCandidate, candidate);

      promoted.add(memoryCandidate);
    }

    return promoted;
  }

  @override
  Future<void> updateMemoryUsage({required List<String> memoryIds}) async {
    if (memoryIds.isEmpty) return;
    await FfmMemoryLearningService().trackMemoryUsage(
      memoryIds.toSet().toList(),
      repository: _memoryRepository,
    );
    // Add a new line here
  }

  @override
  FfmConflictResolution resolveConflict({
    required List<FfmMemoryCandidate> conflictingMemories,
  }) {
    if (conflictingMemories.length < 2) {
      return FfmConflictResolution(
        resolved: true,
        selectedCandidate: conflictingMemories.isNotEmpty
            ? conflictingMemories.first
            : null,
        rejectedCandidates: const [],
      );
    }

    // Sort berdasarkan evidence strength
    final sorted = List<FfmMemoryCandidate>.from(conflictingMemories)
      ..sort((a, b) => _compareEvidenceStrength(a.evidence, b.evidence));

    final strongest = sorted.first;
    final secondStrongest = sorted.length > 1 ? sorted[1] : null;

    // Cek apakah conflict dapat diselesaikan dengan confidence yang cukup tinggi
    if (strongest.evidence.confidence >= 0.9 &&
        (secondStrongest == null ||
            strongest.evidence.confidence -
                    secondStrongest.evidence.confidence >=
                0.2)) {
      return FfmConflictResolution(
        resolved: true,
        selectedCandidate: strongest,
        rejectedCandidates: sorted.skip(1).toList(),
      );
    }

    // Conflict tidak dapat diselesaikan otomatis
    return FfmConflictResolution(
      resolved: false,
      selectedCandidate: null,
      rejectedCandidates: sorted,
      requiresClarification: true,
      clarificationMessage: _buildConflictClarification(sorted),
    );
  }

  @override
  List<FfmMemoryCandidate> deduplicateMemories({
    required List<FfmMemoryCandidate> memories,
  }) {
    final seen = <String>{};
    final unique = <FfmMemoryCandidate>[];

    for (final memory in memories) {
      final canonicalKey = '${memory.type.name}:${memory.key}:${memory.value}';

      if (!seen.contains(canonicalKey)) {
        seen.add(canonicalKey);
        unique.add(memory);
      }
    }

    return unique;
  }

  @override
  double calculateRecencyScore({
    required DateTime memoryDate,
    required FfmMemoryType type,
    required DateTime now,
  }) {
    final ageDays = now.difference(memoryDate).inDays;

    // Half-life berbeda per tipe memory sesuai spesifikasi
    final halfLifeDays = switch (type) {
      FfmMemoryType.identity => 365 * 2, // Sangat lambat
      FfmMemoryType.preference => 365, // Lambat
      FfmMemoryType.goal =>
        memoryDate.month == now.month ? 30 : 90, // Based on status
      FfmMemoryType.habit => 90, // Sedang
      FfmMemoryType.episodic => 60, // Sedang/cepat
      FfmMemoryType.working => 7, // Sangat cepat
      FfmMemoryType.explicitFact => 180,
      FfmMemoryType.behavioralPattern => 120,
      FfmMemoryType.correction => 365,
      FfmMemoryType.assistantRecommendation => 90,
    };

    // Exponential decay formula
    return math.exp(-ageDays / halfLifeDays);
  }

  @override
  String normalizeQuery(String query) {
    // Gunakan typo normalizer yang sudah ada
    final normalized = FfmAssistantTypoNormalizer.correct(query);

    // Apply aliases dari memory repository (synchronous untuk sekarang)
    // TODO: Make this async if needed
    return normalized;
  }

  @override
  Map<String, dynamic> extractEntitiesAndTopic(String normalizedQuery) {
    final lowerQuery = normalizedQuery.toLowerCase();

    // Simple entity extraction - bisa ditingkatkan di fase berikutnya
    final entities = <String, String>{};

    // Topic detection
    String? topic;
    if (lowerQuery.contains('pengeluaran') ||
        lowerQuery.contains('belanja') ||
        lowerQuery.contains('makan')) {
      topic = 'spending';
    } else if (lowerQuery.contains('pemasukan') ||
        lowerQuery.contains('gaji') ||
        lowerQuery.contains('income')) {
      topic = 'income';
    } else if (lowerQuery.contains('tabungan') ||
        lowerQuery.contains('nabung') ||
        lowerQuery.contains('target')) {
      topic = 'savings';
    } else if (lowerQuery.contains('budget') ||
        lowerQuery.contains('anggaran')) {
      topic = 'budget';
    }

    // Entity detection
    if (lowerQuery.contains('bulan ini')) {
      entities['period'] = 'current_month';
    } else if (lowerQuery.contains('minggu ini')) {
      entities['period'] = 'current_week';
    } else if (lowerQuery.contains('bulan lalu')) {
      entities['period'] = 'previous_month';
    }

    // Intent detection
    String? intent;
    if (lowerQuery.contains('berapa') || lowerQuery.contains('jumlah')) {
      intent = 'query_amount';
    } else if (lowerQuery.contains('aman') ||
        lowerQuery.contains('boros') ||
        lowerQuery.contains('kebanyakan')) {
      intent = 'financial_analysis';
    } else if (lowerQuery.contains('ingat') ||
        lowerQuery.contains('apa') ||
        lowerQuery.contains('siapa')) {
      intent = 'query_fact';
    }

    return {'topic': topic, 'entities': entities, 'intent': intent};
  }

  // Private helper methods

  Map<String, String> _mergeWithWorkingContext(
    Map<String, String> detectedEntities,
    FfmWorkingContext workingContext,
  ) {
    final merged = Map<String, String>.from(detectedEntities);

    // Jika detected entities tidak mengandung entity tertentu, gunakan dari working context
    if (!merged.containsKey('topic') && workingContext.currentTopic != null) {
      merged['topic'] = workingContext.currentTopic!;
    }
    if (!merged.containsKey('entity') &&
        workingContext.lastReferencedEntity != null) {
      merged['entity'] = workingContext.lastReferencedEntity!;
    }
    if (!merged.containsKey('period') && workingContext.currentPeriod != null) {
      merged['period'] = workingContext.currentPeriod!;
    }
    if (!merged.containsKey('goal') && workingContext.currentGoal != null) {
      merged['goal'] = workingContext.currentGoal!;
    }

    return merged;
  }

  Future<List<FfmMemoryCandidate>> _retrieveCandidates(
    String normalizedQuery,
    String? detectedTopic,
    Map<String, String> detectedEntities,
    FfmAssistantReasoningContext? reasoningContext,
    FfmWorkingContext workingContext,
  ) async {
    final candidates = <FfmMemoryCandidate>[];

    // 1. Dari user model service
    final userModelEntries = await _userModelService.readApproved();
    for (final entry in userModelEntries) {
      candidates.add(_convertUserModelEntryToCandidate(entry));
    }

    // 2. Dari personal memory service
    final personalMemories = await _personalMemoryService.readAll();
    for (final memory in personalMemories) {
      candidates.add(_convertPersonalMemoryToCandidate(memory));
    }

    // 3. Dari memory repository (untuk answer, alias, dll)
    final allMemories = await _memoryRepository.readActive();
    for (final memory in allMemories) {
      if (memory.kind != 'user' &&
          !memory.kind.startsWith('user_') &&
          !memory.kind.startsWith('personal_memory_')) {
        candidates.add(_convertMemoryRecordToCandidate(memory));
      }
    }

    // 4. Dari personalization patterns
    try {
      final patterns = await _personalizationRepository.getAllPatterns(
        householdId,
      );
      for (final pattern in patterns) {
        final patternObj = _convertInteractionPatternToPattern(pattern);
        if (patternObj.isStrong) {
          candidates.add(_convertPatternToCandidate(patternObj));
        }
      }
    } catch (e) {
      // Ignore if patterns table doesn't exist yet
    }

    return candidates;
  }

  List<FfmMemoryCandidate> _filterCandidates(
    List<FfmMemoryCandidate> candidates,
    String? detectedTopic,
    Map<String, String> detectedEntities,
  ) {
    // Filter berdasarkan konteks - priority ke current period, active goals, dll
    return candidates.where((candidate) {
      // Filter berdasarkan status
      if (!candidate.isValid) return false;

      // Filter berdasarkan topic relevance (simple implementation)
      if (detectedTopic != null) {
        final keyLower = candidate.key.toLowerCase();

        if (detectedTopic == 'spending' &&
            (keyLower.contains('makan') ||
                keyLower.contains('budget') ||
                keyLower.contains('pengeluaran'))) {
          return true;
        }
        if (detectedTopic == 'savings' &&
            (keyLower.contains('tabungan') ||
                keyLower.contains('target') ||
                keyLower.contains('nabung'))) {
          return true;
        }
      }

      // Default: include jika tidak ada filter spesifik
      return true;
    }).toList();
  }

  List<FfmMemoryCandidate> _scoreCandidates(
    List<FfmMemoryCandidate> candidates,
    String normalizedQuery,
    String? detectedTopic,
    Map<String, String> detectedEntities,
    DateTime now,
  ) {
    return candidates.map((candidate) {
      // Calculate individual scores
      final relevanceScore = _calculateLexicalRelevance(
        candidate,
        normalizedQuery,
      );
      final topicScore = _calculateTopicRelevance(candidate, detectedTopic);
      final entityScore = _calculateEntityRelevance(
        candidate,
        detectedEntities,
      );
      final recencyScore = calculateRecencyScore(
        memoryDate: candidate.evidence.createdAt,
        type: candidate.type,
        now: now,
      );

      // Build relevance score object
      final relevance = FfmContextRelevanceScore(
        semanticOrLexicalMatch: relevanceScore,
        topicMatch: topicScore,
        entityMatch: entityScore,
        recency: recencyScore,
        importance: candidate.importance,
        confidence: candidate.evidence.confidence,
        goalRelevance: _calculateGoalRelevance(candidate, detectedEntities),
        usageFrequency: _calculateUsageFrequency(candidate),
      );

      // Calculate final score
      final finalScore = relevance.calculateFinalScore();

      return candidate.withScores(
        relevance: relevanceScore,
        recency: recencyScore,
        finalVal: finalScore,
      );
    }).toList();
  }

  List<FfmMemoryCandidate> _resolveConflicts(
    List<FfmMemoryCandidate> candidates,
  ) {
    // Group by type and key untuk detect conflicts
    final groups = <String, List<FfmMemoryCandidate>>{};

    for (final candidate in candidates) {
      final key = '${candidate.type.name}:${candidate.key}';
      groups.putIfAbsent(key, () => []).add(candidate);
    }

    final resolved = <FfmMemoryCandidate>[];

    for (final group in groups.values) {
      if (group.length == 1) {
        resolved.add(group.first);
      } else {
        // Resolve conflict
        final resolution = resolveConflict(conflictingMemories: group);
        if (resolution.resolved && resolution.selectedCandidate != null) {
          resolved.add(resolution.selectedCandidate!);
        }
        // Jika tidak resolved, skip semua atau handle clarification
      }
    }

    return resolved;
  }

  List<FfmMemoryCandidate> _applyBudget(
    List<FfmMemoryCandidate> candidates,
    FfmContextBudget budget,
  ) {
    // Group by type dan apply budget per type
    final grouped = <FfmMemoryType, List<FfmMemoryCandidate>>{};

    for (final candidate in candidates) {
      grouped.putIfAbsent(candidate.type, () => []).add(candidate);
    }

    final result = <FfmMemoryCandidate>[];

    // Apply budget per type
    for (final entry in grouped.entries) {
      final type = entry.key;
      final typeCandidates = entry.value;

      // Sort by final score
      typeCandidates.sort((a, b) => b.finalScore.compareTo(a.finalScore));

      // Take based on budget
      final maxItems = switch (type) {
        FfmMemoryType.working => budget.workingMemoryMax,
        FfmMemoryType.identity => budget.personalFactsMax,
        FfmMemoryType.explicitFact => budget.personalFactsMax,
        FfmMemoryType.preference => budget.preferencesMax,
        FfmMemoryType.goal => budget.goalsMax,
        FfmMemoryType.behavioralPattern => budget.behaviorPatternsMax,
        FfmMemoryType.episodic => budget.episodesMax,
        FfmMemoryType.correction => budget.correctionsMax,
        FfmMemoryType.habit => budget.behaviorPatternsMax,
        FfmMemoryType.assistantRecommendation => budget.episodesMax,
      };

      result.addAll(typeCandidates.take(maxItems));
    }

    // Apply total budget
    result.sort((a, b) => b.finalScore.compareTo(a.finalScore));
    return result.take(budget.maxTotalItems).toList();
  }

  FfmPersonalContext _buildContextPack(
    List<FfmMemoryCandidate> candidates,
    String query,
    String normalizedQuery,
    String? detectedTopic,
    Map<String, String> detectedEntities,
    String? detectedIntent,
    FfmAssistantReasoningContext? reasoningContext,
    FfmWorkingContext workingContextParam,
    DateTime now,
  ) {
    // Group candidates by type
    final workingMemories = <FfmMemoryCandidate>[];
    final personalFacts = <FfmMemoryCandidate>[];
    final preferences = <FfmMemoryCandidate>[];
    final goals = <FfmMemoryCandidate>[];
    final behaviorPatterns = <FfmMemoryCandidate>[];
    final episodes = <FfmMemoryCandidate>[];
    final corrections = <FfmMemoryCandidate>[];

    for (final candidate in candidates) {
      switch (candidate.type) {
        case FfmMemoryType.working:
          workingMemories.add(candidate);
          break;
        case FfmMemoryType.identity:
        case FfmMemoryType.explicitFact:
          personalFacts.add(candidate);
          break;
        case FfmMemoryType.preference:
          preferences.add(candidate);
          break;
        case FfmMemoryType.goal:
          goals.add(candidate);
          break;
        case FfmMemoryType.behavioralPattern:
        case FfmMemoryType.habit:
          behaviorPatterns.add(candidate);
          break;
        case FfmMemoryType.episodic:
        case FfmMemoryType.assistantRecommendation:
          episodes.add(candidate);
          break;
        case FfmMemoryType.correction:
          corrections.add(candidate);
          break;
      }
    }

    // Build response preferences
    final responsePreferences = _buildResponsePreferences(preferences);

    // Build data context
    final dataContext = _buildDataContext(detectedEntities, reasoningContext);

    return FfmPersonalContext(
      query: query,
      normalizedQuery: normalizedQuery,
      detectedTopic: detectedTopic,
      detectedEntities: detectedEntities,
      detectedIntent: detectedIntent,
      workingContext: workingMemories,
      personalFacts: personalFacts,
      preferences: preferences,
      goals: goals,
      behaviorPatterns: behaviorPatterns,
      episodes: episodes,
      corrections: corrections,
      dataContext: dataContext,
      responsePreferences: responsePreferences,
      capturedAt: now,
      processingMetadata: {
        'total_candidates': candidates.length,
        'retrieval_time_ms': now.millisecondsSinceEpoch,
        'working_context': workingContextParam.toString(),
      },
    );
  }

  FfmPersonalContext _buildFallbackContext(
    String query,
    FfmAssistantReasoningContext? reasoningContext,
    FfmWorkingContext? previousWorkingContext,
    DateTime now,
  ) {
    return FfmPersonalContext(
      query: query,
      normalizedQuery: normalizeQuery(query),
      detectedTopic: null,
      detectedEntities: {},
      detectedIntent: null,
      workingContext: [],
      personalFacts: [],
      preferences: [],
      goals: [],
      behaviorPatterns: [],
      episodes: [],
      corrections: [],
      dataContext: FfmDataContext(
        period: previousWorkingContext?.currentPeriod,
      ),
      responsePreferences: const FfmResponsePreferences(),
      capturedAt: now,
      processingMetadata: {
        'fallback': true,
        'error': 'Context engine failed, using fallback',
      },
    );
  }

  // Helper conversion methods

  FfmMemoryCandidate _convertUserModelEntryToCandidate(
    FfmAssistantUserModelEntry entry,
  ) {
    return FfmMemoryCandidate(
      id: entry.id,
      type: _convertUserModelKindToMemoryType(entry.kind),
      key: entry.key,
      value: entry.value,
      evidence: FfmMemoryEvidence(
        source: entry.approved
            ? FfmMemorySource.userExplicit
            : FfmMemorySource.inferredPattern,
        createdAt: entry.updatedAt ?? DateTime.now(),
        updatedAt: entry.updatedAt ?? DateTime.now(),
        confidence: entry.confidence,
        approved: entry.approved,
      ),
      importance: 0.7,
    );
  }

  FfmMemoryCandidate _convertPersonalMemoryToCandidate(
    FfmPersonalMemoryInsight memory,
  ) {
    return FfmMemoryCandidate(
      id: memory.id ?? 'personal-${DateTime.now().microsecondsSinceEpoch}',
      type: _convertInsightKindToMemoryType(memory.kind),
      key: memory.key,
      value: memory.value,
      evidence: FfmMemoryEvidence(
        source: FfmMemorySource.userExplicit,
        createdAt: memory.savedAt ?? DateTime.now(),
        updatedAt: memory.savedAt ?? DateTime.now(),
        confidence: 1.0,
        approved: true,
      ),
      importance: 0.6,
      metadata: {'humanLabel': memory.humanLabel},
    );
  }

  FfmMemoryCandidate _convertMemoryRecordToCandidate(
    FfmAssistantMemoryRecord record,
  ) {
    return FfmMemoryCandidate(
      id: record.id,
      type: _convertRecordKindToMemoryType(record.kind),
      key: record.triggerText,
      value: record.valueText,
      evidence: FfmMemoryEvidence(
        source: _convertSourceToMemorySource(record.source),
        sourceId: record.id,
        createdAt: record.createdAt,
        updatedAt: record.updatedAt ?? record.createdAt,
        confidence: (record.metadata['confidence'] as num?)?.toDouble() ?? 0.5,
        approved: record.metadata['approved'] as bool? ?? true,
      ),
      importance: (record.metadata['importance'] as num?)?.toDouble() ?? 0.5,
      metadata: record.metadata,
    );
  }

  FfmMemoryCandidate _convertPatternToCandidate(
    FfmPersonalizationPattern pattern,
  ) {
    return FfmMemoryCandidate(
      id: 'pattern-${pattern.merchantName}-${pattern.fieldName}',
      type: FfmMemoryType.behavioralPattern,
      key: '${pattern.merchantName}_${pattern.fieldName}',
      value: pattern.mostCommonValue,
      evidence: FfmMemoryEvidence(
        source: FfmMemorySource.approvedPattern,
        createdAt: pattern.lastUpdated,
        updatedAt: pattern.lastUpdated,
        confidence: pattern.confidenceScore,
        approved: pattern.isStrong,
      ),
      importance: 0.4,
      metadata: {
        'merchantName': pattern.merchantName,
        'fieldName': pattern.fieldName,
        'sampleCount': pattern.sampleCount,
      },
    );
  }

  FfmPersonalizationPattern _convertInteractionPatternToPattern(
    InteractionPattern row,
  ) {
    return FfmPersonalizationPattern(
      merchantName: row.merchantName,
      fieldName: row.fieldName,
      mostCommonValue: row.mostCommonValue,
      confidenceScore: row.confidenceScore,
      sampleCount: row.sampleCount,
      lastUpdated: row.lastUpdated,
    );
  }

  FfmMemoryType _convertUserModelKindToMemoryType(String kind) {
    switch (kind.toLowerCase()) {
      case 'identity':
      case 'name':
      case 'occupation':
        return FfmMemoryType.identity;
      case 'preference':
        return FfmMemoryType.preference;
      default:
        return FfmMemoryType.explicitFact;
    }
  }

  FfmMemoryType _convertInsightKindToMemoryType(FfmPersonalMemoryKind kind) {
    switch (kind) {
      case FfmPersonalMemoryKind.preference:
        return FfmMemoryType.preference;
      case FfmPersonalMemoryKind.habitChat:
      case FfmPersonalMemoryKind.habitData:
        return FfmMemoryType.habit;
    }
  }

  FfmMemoryType _convertRecordKindToMemoryType(String kind) {
    switch (kind.toLowerCase()) {
      case 'identity':
      case 'name':
        return FfmMemoryType.identity;
      case 'preference':
        return FfmMemoryType.preference;
      case 'goal':
        return FfmMemoryType.goal;
      case 'answer':
        return FfmMemoryType.assistantRecommendation;
      case 'alias':
        return FfmMemoryType.preference;
      default:
        return FfmMemoryType.explicitFact;
    }
  }

  FfmMemorySource _convertSourceToMemorySource(String source) {
    switch (source.toLowerCase()) {
      case 'user':
      case 'user-approved':
        return FfmMemorySource.userExplicit;
      case 'chat-detected':
        return FfmMemorySource.conversation;
      case 'activity-scan':
        return FfmMemorySource.transactionPattern;
      case 'system':
        return FfmMemorySource.system;
      default:
        return FfmMemorySource.inferredPattern;
    }
  }

  Future<void> _saveCandidateToRepository(
    FfmMemoryCandidate candidate,
    FfmMemoryPromotionCandidate promotionCandidate,
  ) async {
    // Save ke repository yang sesuai berdasarkan tipe
    switch (candidate.type) {
      case FfmMemoryType.identity:
      case FfmMemoryType.preference:
      case FfmMemoryType.explicitFact:
        await _userModelService.saveApproved(
          kind: candidate.type.name,
          key: candidate.key,
          value: candidate.value,
          confidence: candidate.evidence.confidence,
          source: promotionCandidate.sourceId ?? 'context-engine',
        );
        break;
      case FfmMemoryType.goal:
      case FfmMemoryType.habit:
        // Save via personal memory service
        final insight = FfmPersonalMemoryInsight(
          kind: FfmPersonalMemoryKind.habitChat,
          key: candidate.key,
          value: candidate.value,
          humanLabel:
              promotionCandidate.reason ??
              '${candidate.key}: ${candidate.value}',
          sourceMessage: promotionCandidate.sourceId,
        );
        await _personalMemoryService.saveApproved(insight);
        break;
      default:
        // Save via general memory repository
        await _memoryRepository.save(
          kind: candidate.type.name,
          triggerText: candidate.key,
          valueText: candidate.value,
          source: promotionCandidate.sourceId ?? 'context-engine',
          metadata: {
            'confidence': candidate.evidence.confidence,
            'approved': candidate.evidence.approved,
            'importance': candidate.importance,
          },
        );
    }
  }

  // Scoring helper methods

  double _calculateLexicalRelevance(
    FfmMemoryCandidate candidate,
    String query,
  ) {
    final keyLower = candidate.key.toLowerCase();
    final queryLower = query.toLowerCase();

    // Exact match
    if (keyLower == queryLower) return 1.0;

    // Contains match
    if (keyLower.contains(queryLower)) return 0.8;

    // Token overlap
    final queryTokens = queryLower
        .split(' ')
        .where((t) => t.isNotEmpty)
        .toSet();
    final keyTokens = keyLower.split(' ').where((t) => t.isNotEmpty).toSet();

    final keyOverlap = queryTokens.intersection(keyTokens);

    if (keyOverlap.isNotEmpty) {
      final overlap = keyOverlap.length;
      return (overlap / queryTokens.length).clamp(0.0, 0.6);
    }

    // Fuzzy match
    final similarity = FfmAssistantFuzzyMatcher.similarity(query, keyLower);
    if (similarity > 0.7) return similarity * 0.7;

    return 0.0;
  }

  double _calculateTopicRelevance(FfmMemoryCandidate candidate, String? topic) {
    if (topic == null) return 0.0;

    final keyLower = candidate.key.toLowerCase();
    final valueLower = candidate.value.toLowerCase();
    final topicLower = topic.toLowerCase();

    if (keyLower.contains(topicLower) || valueLower.contains(topicLower)) {
      return 0.8;
    }

    return 0.0;
  }

  double _calculateEntityRelevance(
    FfmMemoryCandidate candidate,
    Map<String, String> entities,
  ) {
    if (entities.isEmpty) return 0.0;

    double score = 0.0;
    final keyLower = candidate.key.toLowerCase();
    final valueLower = candidate.value.toLowerCase();

    for (final entity in entities.values) {
      if (keyLower.contains(entity.toLowerCase()) ||
          valueLower.contains(entity.toLowerCase())) {
        score += 0.3;
      }
    }

    return score.clamp(0.0, 1.0);
  }

  double _calculateGoalRelevance(
    FfmMemoryCandidate candidate,
    Map<String, String> entities,
  ) {
    // Boost jika candidate adalah goal dan entities mengandung goal-related terms
    if (candidate.type == FfmMemoryType.goal) {
      final entityValues = entities.values.join(' ').toLowerCase();
      if (entityValues.contains('target') ||
          entityValues.contains('tabungan') ||
          entityValues.contains('nabung')) {
        return 0.8;
      }
    }
    return 0.0;
  }

  double _calculateUsageFrequency(FfmMemoryCandidate candidate) {
    // Normalize usage count to 0-1 range
    // Assume 10+ uses is high frequency
    return (candidate.evidence.useCount / 10).clamp(0.0, 1.0);
  }

  int _compareEvidenceStrength(FfmMemoryEvidence a, FfmMemoryEvidence b) {
    // Priority: source > confidence > recency > approval
    final sourceComparison = _compareSourceStrength(a.source, b.source);
    if (sourceComparison != 0) return sourceComparison;

    final confidenceComparison = b.confidence.compareTo(a.confidence);
    if (confidenceComparison != 0) return confidenceComparison;

    final recencyComparison = b.updatedAt.compareTo(a.updatedAt);
    if (recencyComparison != 0) return recencyComparison;

    return (b.approved ? 1 : 0).compareTo(a.approved ? 1 : 0);
  }

  int _compareSourceStrength(FfmMemorySource a, FfmMemorySource b) {
    final strength = {
      FfmMemorySource.userCorrection: 5,
      FfmMemorySource.userExplicit: 4,
      FfmMemorySource.approvedPattern: 3,
      FfmMemorySource.inferredPattern: 2,
      FfmMemorySource.conversation: 1,
      FfmMemorySource.transactionPattern: 1,
      FfmMemorySource.goal: 3,
      FfmMemorySource.system: 0,
      FfmMemorySource.assistantRecommendation: 0,
    };

    return (strength[b] ?? 0).compareTo(strength[a] ?? 0);
  }

  String _buildConflictClarification(List<FfmMemoryCandidate> conflicting) {
    if (conflicting.isEmpty) return '';

    final buffer = StringBuffer('Ditemukan konflik memory untuk ');
    buffer.write(conflicting.first.key);
    buffer.write(': ');

    for (var i = 0; i < conflicting.length; i++) {
      if (i > 0) buffer.write(' vs ');
      buffer.write('"${conflicting[i].value}"');
    }

    buffer.write('. Mana yang harus saya gunakan?');
    return buffer.toString();
  }

  FfmResponsePreferences _buildResponsePreferences(
    List<FfmMemoryCandidate> preferences,
  ) {
    var concise = false;
    var useIndonesian = true;
    var showRupiah = true;
    final customStyle = <String, dynamic>{};

    for (final pref in preferences) {
      switch (pref.key.toLowerCase()) {
        case 'response_style':
          concise =
              pref.value.toLowerCase() == 'concise' ||
              pref.value.toLowerCase().contains('singkat');
          break;
        case 'language':
          useIndonesian = pref.value.toLowerCase().contains('indonesia');
          break;
        case 'currency_format':
          showRupiah = pref.value.toLowerCase().contains('rupiah');
          break;
        default:
          customStyle[pref.key] = pref.value;
      }
    }

    return FfmResponsePreferences(
      concise: concise,
      useIndonesian: useIndonesian,
      showRupiah: showRupiah,
      customStyle: customStyle,
    );
  }

  FfmDataContext _buildDataContext(
    Map<String, String> detectedEntities,
    FfmAssistantReasoningContext? reasoningContext,
  ) {
    // Extract data requirements dari reasoning context
    final evidenceScope = reasoningContext != null
        ? FfmAssistantReasoningEvidencePolicy.forRequest(
            reasoningContext.request,
          )
        : const FfmAssistantReasoningEvidenceScope(
            includeFinancialSummary: false,
            includeMasterData: false,
            includeRecentTransactions: false,
          );

    // Detect page-specific context
    final currentPage = reasoningContext?.currentPage;
    final pageBasedRequirements = _detectPageRequirements(currentPage);

    return FfmDataContext(
      period: detectedEntities['period'] ?? pageBasedRequirements['period'],
      requiresFinancialSummary:
          evidenceScope.includeFinancialSummary ||
          pageBasedRequirements['financial'] == true,
      requiresMasterData:
          evidenceScope.includeMasterData ||
          pageBasedRequirements['masterData'] == true,
      requiresRecentTransactions:
          evidenceScope.includeRecentTransactions ||
          detectedEntities['period'] != null ||
          pageBasedRequirements['recentTransactions'] == true,
      customRequests: _buildCustomDataRequests(detectedEntities, currentPage),
    );
  }

  Map<String, dynamic> _detectPageRequirements(
    FfmAssistantDestination? currentPage,
  ) {
    if (currentPage == null) return {};

    // Simplified page detection - can be expanded later
    final pageName = currentPage.name.toLowerCase();

    if (pageName.contains('budget') || pageName.contains('anggaran')) {
      return {'financial': true, 'masterData': true, 'period': 'current_month'};
    } else if (pageName.contains('transaksi') ||
        pageName.contains('transactions')) {
      return {'financial': true, 'recentTransactions': true};
    } else if (pageName.contains('target') || pageName.contains('goals')) {
      return {'financial': true};
    } else if (pageName.contains('analisa') || pageName.contains('analysis')) {
      return {'financial': true, 'recentTransactions': true};
    } else if (pageName.contains('ringkasan') || pageName.contains('summary')) {
      return {'financial': true, 'period': 'current_month'};
    }

    return {};
  }

  List<String> _buildCustomDataRequests(
    Map<String, String> detectedEntities,
    FfmAssistantDestination? currentPage,
  ) {
    final requests = <String>[];

    // Add entity-specific requests
    if (detectedEntities.containsKey('entity')) {
      final entity = detectedEntities['entity']!;
      if (entity.contains('makan') || entity.contains('food')) {
        requests.add('category_breakdown:food');
      }
    }

    // Add page-specific requests
    if (currentPage != null) {
      final pageName = currentPage.name.toLowerCase();
      if (pageName.contains('budget') || pageName.contains('anggaran')) {
        requests.add('active_budgets');
        requests.add('budget_variance');
      } else if (pageName.contains('target') || pageName.contains('goals')) {
        requests.add('active_goals');
        requests.add('goal_progress');
      }
    }

    return requests;
  }
}
