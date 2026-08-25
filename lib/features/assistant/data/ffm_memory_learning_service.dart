import 'dart:math' as math;

import '../domain/ffm_memory_candidate.dart';
import '../domain/ffm_memory_type.dart';
import 'ffm_assistant_memory_repository.dart';

/// Service untuk learning dan candidate extraction dari percakapan.
///
/// Phase 6 dari Personal Memory & Context Engine implementation.
class FfmMemoryLearningService {
  FfmMemoryLearningService({
    FfmAssistantMemoryRepository? memoryRepository,
  }) : _memoryRepository = memoryRepository;

  final FfmAssistantMemoryRepository? _memoryRepository;

  /// Extract memory candidates dari percakapan turn.
  Future<List<FfmMemoryPromotionCandidate>> extractCandidates({
    required String userQuery,
    required String? assistantResponse,
    required List<FfmMemoryCandidate> usedMemories,
  }) async {
    final candidates = <FfmMemoryPromotionCandidate>[];

    // 1. Pattern-based extraction
    final patternCandidates = _extractPatternBased(userQuery);
    candidates.addAll(patternCandidates);

    // 2. Usage-based learning
    final usageCandidates = _extractUsageBased(usedMemories);
    candidates.addAll(usageCandidates);

    // 3. Correction-based learning
    final correctionCandidates = _extractCorrectionBased(userQuery, assistantResponse);
    candidates.addAll(correctionCandidates);

    // 4. Frequency-based extraction
    final frequencyCandidates = _extractFrequencyPatterns(userQuery);
    candidates.addAll(frequencyCandidates);

    return candidates;
  }

  /// Validate candidates berdasarkan aturan spesifikasi
  List<FfmMemoryPromotionCandidate> validateCandidates(
    List<FfmMemoryPromotionCandidate> candidates,
    List<FfmMemoryCandidate> existingMemories,
  ) {
    return candidates.where((candidate) {
      if (!candidate.isValid) return false;
      if (candidate.isSensitive) return false;
      if (_isDuplicate(candidate, existingMemories)) return false;
      if (_hasContradiction(candidate, existingMemories)) return false;
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
      } catch (_) {
        continue;
      }
    }

    return promoted;
  }

  /// Apply decay ke memory yang tidak sering digunakan.
  ///
  /// Memory dengan `useCount` rendah dan usia tua akan di-decay.
  /// Goal yang sudah completed tidak di-decay.
  Future<void> applyMemoryDecay({
    required FfmAssistantMemoryRepository repository,
    Duration maxAge = const Duration(days: 180),
    int minUseCount = 2,
  }) async {
    final repo = _memoryRepository ?? repository;
    final allMemories = await repo.readAll();
    final now = DateTime.now();

    for (final memory in allMemories) {
      final age = now.difference(memory.createdAt);
      if (age < maxAge) continue;

      final useCount = (memory.metadata['useCount'] as num?)?.toInt() ?? 0;
      if (useCount >= minUseCount) continue;

      final importance = (memory.metadata['importance'] as num?)?.toDouble() ?? 0.5;
      if (importance >= 0.8) continue;

      final decayFactor = 1.0 - (age.inDays / (maxAge.inDays * 2)).clamp(0.0, 0.5);
      final newImportance = (importance * decayFactor).clamp(0.1, 1.0);

      if (newImportance < 0.2) {
        await repo.archive(memory.id);
      }
    }
  }

  /// Track memory usage dan update importance.
  Future<void> trackMemoryUsage(
    List<String> memoryIds, {
    required FfmAssistantMemoryRepository repository,
  }) async {
    if (memoryIds.isEmpty) return;
    final allMemories = await repository.readAll();

    for (final memoryId in memoryIds) {
      final match = allMemories.where((m) => m.id == memoryId);
      if (match.isEmpty) continue;
      final memory = match.first;

      final currentCount = (memory.metadata['useCount'] as num?)?.toInt() ?? 0;
      final newCount = currentCount + 1;
      final currentImportance = (memory.metadata['importance'] as num?)?.toDouble() ?? 0.5;
      final usageBoost = (newCount / 10).clamp(0.0, 0.3);
      final newImportance = (currentImportance + usageBoost).clamp(0.0, 1.0);

      await repository.save(
        id: memory.id,
        kind: memory.kind,
        triggerText: memory.triggerText,
        valueText: memory.valueText,
        metadata: {
          ...memory.metadata,
          'useCount': newCount,
          'importance': newImportance,
          'lastUsedAt': DateTime.now().toIso8601String(),
        },
        source: memory.source,
      );
    }
  }

  // --- Private helpers ---

  List<FfmMemoryPromotionCandidate> _extractPatternBased(String userQuery) {
    final candidates = <FfmMemoryPromotionCandidate>[];
    final lowerQuery = userQuery.toLowerCase();

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

    if (RegExp(r'gaji(?:an)?\s+(?:tiap|setiap|per)?\s*tanggal\s+\d+').hasMatch(lowerQuery)) {
      candidates.add(FfmMemoryPromotionCandidate(
        type: FfmMemoryType.explicitFact,
        key: 'payday',
        value: userQuery,
        confidence: 0.8,
        reason: 'User menyebutkan jadwal gaji',
        sourceId: userQuery,
        requiresApproval: true,
      ));
    }

    if (RegExp(r'(?:budget|anggaran|jatah)\s+(?:makan|makanan)').hasMatch(lowerQuery)) {
      candidates.add(FfmMemoryPromotionCandidate(
        type: FfmMemoryType.explicitFact,
        key: 'budget_food',
        value: userQuery,
        confidence: 0.75,
        reason: 'User menyebutkan anggaran makan',
        sourceId: userQuery,
        requiresApproval: true,
      ));
    }

    if (lowerQuery.contains('target nabung') || lowerQuery.contains('target menabung')) {
      candidates.add(FfmMemoryPromotionCandidate(
        type: FfmMemoryType.goal,
        key: 'savings_target',
        value: userQuery,
        confidence: 0.8,
        reason: 'User menyebutkan target tabungan',
        sourceId: userQuery,
        requiresApproval: true,
      ));
    }

    return candidates;
  }

  String _extractName(String query) {
    final words = query.split(' ');
    for (var i = 0; i < words.length; i++) {
      if (words[i].toLowerCase() == 'adalah' && i + 1 < words.length) {
        return words[i + 1];
      }
      if ((words[i].toLowerCase() == 'panggil' ||
              words[i].toLowerCase() == 'nama') &&
          i + 1 < words.length &&
          words[i + 1].toLowerCase() != 'saya' &&
          words[i + 1].toLowerCase() != 'ku') {
        return words[i + 1];
      }
    }
    return 'unknown';
  }

  List<FfmMemoryPromotionCandidate> _extractUsageBased(
    List<FfmMemoryCandidate> usedMemories,
  ) {
    final candidates = <FfmMemoryPromotionCandidate>[];
    if (usedMemories.length < 2) return candidates;

    final topicCounts = <String, int>{};
    for (final memory in usedMemories) {
      final topic = memory.type.name;
      topicCounts[topic] = (topicCounts[topic] ?? 0) + 1;
    }

    for (final entry in topicCounts.entries) {
      if (entry.value >= 3) {
        candidates.add(FfmMemoryPromotionCandidate(
          type: FfmMemoryType.behavioralPattern,
          key: 'frequent_topic_${entry.key}',
          value: entry.key,
          confidence: 0.6,
          reason: 'Topik ${entry.key} sering muncul dalam percakapan',
          sourceId: 'usage-analysis',
          requiresApproval: false,
        ));
      }
    }

    return candidates;
  }

  List<FfmMemoryPromotionCandidate> _extractCorrectionBased(
    String userQuery,
    String? assistantResponse,
  ) {
    final candidates = <FfmMemoryPromotionCandidate>[];
    if (assistantResponse == null) return candidates;

    final lowerQuery = userQuery.toLowerCase();
    final correctionPatterns = [
      RegExp(r'^(bukan|salah|tidak benar|keliru)', caseSensitive: false),
      RegExp(r'(?:harusnya|seharusnya|mestinya)\s+', caseSensitive: false),
      RegExp(r'(?:ubah|ganti|gantikan)\s+(?:jadi|ke|menjadi)\s+', caseSensitive: false),
    ];

    final isCorrection = correctionPatterns.any((p) => p.hasMatch(lowerQuery));

    if (isCorrection) {
      final key = _extractCorrectionKey(lowerQuery);
      final value = _extractCorrectionValue(lowerQuery);

      if (key.isNotEmpty && value.isNotEmpty) {
        candidates.add(FfmMemoryPromotionCandidate(
          type: FfmMemoryType.correction,
          key: key,
          value: value,
          confidence: 0.85,
          reason: 'User mengoreksi informasi',
          sourceId: userQuery,
          requiresApproval: true,
        ));
      }
    }

    return candidates;
  }

  String _extractCorrectionKey(String query) {
    final lower = query.toLowerCase();
    if (lower.contains('kategori')) return 'category';
    if (lower.contains('toko') || lower.contains('merchant')) return 'merchant';
    if (lower.contains('rekening') || lower.contains('akun')) return 'account';
    if (lower.contains('tag')) return 'tag';
    if (lower.contains('nominal') || lower.contains('jumlah')) return 'amount';
    return 'general';
  }

  String _extractCorrectionValue(String query) {
    final match = RegExp(r'(?:jadi|ke|menjadi)\s+(.+)', caseSensitive: false)
        .firstMatch(query);
    if (match != null) return match.group(1)?.trim() ?? '';
    return query;
  }

  List<FfmMemoryPromotionCandidate> _extractFrequencyPatterns(String userQuery) {
    final candidates = <FfmMemoryPromotionCandidate>[];
    final lower = userQuery.toLowerCase();

    final timePatterns = {
      RegExp(r'(?:setiap|tiap|per)\s+pagi'): 'morning_routine',
      RegExp(r'(?:setiap|tiap|per)\s+malam'): 'evening_routine',
      RegExp(r'(?:setiap|tiap|per)\s+bulan'): 'monthly_routine',
      RegExp(r'(?:setiap|tiap|per)\s+minggu'): 'weekly_routine',
      RegExp(r'(?:selalu|biasa(nya)?)\s+'): 'habitual_behavior',
    };

    for (final entry in timePatterns.entries) {
      if (entry.key.hasMatch(lower)) {
        candidates.add(FfmMemoryPromotionCandidate(
          type: FfmMemoryType.habit,
          key: entry.value,
          value: userQuery,
          confidence: 0.65,
          reason: 'Pola kebiasaan terdeteksi: ${entry.value}',
          sourceId: userQuery,
          requiresApproval: true,
        ));
        break;
      }
    }

    return candidates;
  }

  bool _isDuplicate(
    FfmMemoryPromotionCandidate candidate,
    List<FfmMemoryCandidate> existingMemories,
  ) {
    for (final existing in existingMemories) {
      if (existing.type == candidate.type &&
          existing.key.toLowerCase() == candidate.key.toLowerCase() &&
          existing.value.toLowerCase() == candidate.value.toLowerCase()) {
        return true;
      }
    }
    return false;
  }

  bool _hasContradiction(
    FfmMemoryPromotionCandidate candidate,
    List<FfmMemoryCandidate> existingMemories,
  ) {
    for (final existing in existingMemories) {
      if (existing.type == candidate.type &&
          existing.key.toLowerCase() == candidate.key.toLowerCase() &&
          existing.value.toLowerCase() != candidate.value.toLowerCase() &&
          existing.evidence.confidence >= candidate.confidence) {
        return true;
      }
    }
    return false;
  }

  Future<FfmMemoryCandidate?> _promoteSingleCandidate(
    FfmMemoryPromotionCandidate candidate,
    bool requireApproval,
  ) async {
    final memoryCandidate = FfmMemoryCandidate(
      id: 'memory-${DateTime.now().microsecondsSinceEpoch}-${math.Random().nextInt(10000)}',
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

    await _saveToRepository(memoryCandidate, candidate);
    return memoryCandidate;
  }

  Future<void> _saveToRepository(
    FfmMemoryCandidate memoryCandidate,
    FfmMemoryPromotionCandidate promotionCandidate,
  ) async {
    final repo = _memoryRepository;
    if (repo == null) return;

    await repo.save(
      kind: memoryCandidate.type.name,
      triggerText: memoryCandidate.key,
      valueText: memoryCandidate.value,
      source: promotionCandidate.sourceId ?? 'memory-learning-service',
      metadata: {
        'confidence': memoryCandidate.evidence.confidence,
        'approved': memoryCandidate.evidence.approved,
        'importance': memoryCandidate.importance,
        'useCount': 0,
        if (promotionCandidate.reason != null) 'reason': promotionCandidate.reason,
      },
    );
  }

  double _calculateInitialImportance(FfmMemoryPromotionCandidate candidate) {
    switch (candidate.type) {
      case FfmMemoryType.goal:
        return 1.0;
      case FfmMemoryType.identity:
        return 0.8;
      case FfmMemoryType.correction:
        return 0.9;
      case FfmMemoryType.explicitFact:
        return 0.7;
      case FfmMemoryType.preference:
        return 0.6;
      case FfmMemoryType.habit:
      case FfmMemoryType.behavioralPattern:
        return 0.5;
      default:
        return 0.4;
    }
  }
}
