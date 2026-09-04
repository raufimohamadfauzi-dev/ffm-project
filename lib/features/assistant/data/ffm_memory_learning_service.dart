import 'dart:async';
import 'dart:math' as math;

import '../../../core/network/supabase_service.dart';
import '../domain/ffm_memory_candidate.dart';
import '../domain/ffm_memory_type.dart';
import 'ffm_assistant_memory_repository.dart';

/// Service untuk learning dan candidate extraction dari percakapan.
///
/// Phase 6 dari Personal Memory & Context Engine implementation.
class FfmMemoryLearningService {
  FfmMemoryLearningService({FfmAssistantMemoryRepository? memoryRepository}) {
    _memoryRepository = memoryRepository;
  }

  FfmAssistantMemoryRepository? _memoryRepository;
  final _supabase = SupabaseService();

  bool _isQuestionOrTransaction(String text) {
    final lower = text.trim().toLowerCase();
    if (lower.isEmpty) return true;
    if (lower.contains('?')) return true;

    // 1. Kata tanya / interogatif (baik di awal maupun di tengah kalimat)
    const questionWords = [
      'berapa', 'kapan', 'apakah', 'apatah', 'kenapa', 'mengapa',
      'bagaimana', 'gimana', 'siapa', 'dimana', 'di mana', 'ke mana', 'dari mana',
      'apa ya', 'apa sih', 'apa itu', 'ada apa', 'apa yang',
      'bisa apa', 'kamu siapa', 'bisa bantu apa', 'kamu asisten apa',
    ];
    if (questionWords.any((q) => lower.contains(q))) return true;

    // Perintah query berbasis awalan
    const prefixOnlyCommands = [
      'cek ', 'lihat ', 'tampilkan ', 'tunjukin ', 'tolong jelaskan', 'jelaskan ',
    ];
    if (prefixOnlyCommands.any((p) => lower.startsWith(p))) return true;

    // 2. Perintah transaksi finansial & aksi aplikasi / mutasi database
    const commandWords = [
      'catat', 'tulis', 'tambah', 'masukkan', 'input', 'transfer', 'kirim',
      'bayar', 'beli', 'membeli', 'top up', 'topup', 'tarik tunai', 'simpan transaksi',
      'hapus', 'ubah', 'ganti', 'edit', 'buka', 'navigasi', 'reset', 'ekspor',
      'backup', 'impor', 'sinkron', 'kunci', 'pin'
    ];
    if (commandWords.any((cmd) => lower.startsWith(cmd) || lower.contains(' $cmd '))) {
      return true;
    }

    // 3. Sapaan santai, konfirmasi & small talk
    const casualWords = [
      'halo', 'hallo', 'hai', 'hello', 'hei', 'hey', 'pagi', 'siang', 'sore', 'malam',
      'apa kabar', 'terima kasih', 'makasih', 'makasi', 'thanks', 'thx',
      'ok', 'oke', 'siap', 'sip', 'mantap', 'keren', 'bagus', 'biasa aja',
      'wkwk', 'haha', 'hehe'
    ];
    if (casualWords.any((c) => lower == c || lower.startsWith('$c ') || lower.endsWith(' $c'))) {
      return true;
    }

    return false;
  }

  /// Extract memory candidates dari percakapan turn.
  Future<List<FfmMemoryPromotionCandidate>> extractCandidates({
    required String userQuery,
    required String? assistantResponse,
    required List<FfmMemoryCandidate> usedMemories,
  }) async {
    final candidates = <FfmMemoryPromotionCandidate>[];
    final isQueryNoise = _isQuestionOrTransaction(userQuery);

    // 1. Pattern-based extraction (hanya jika bukan pertanyaan atau mutasi transaksi kasual)
    if (!isQueryNoise) {
      final patternCandidates = _extractPatternBased(userQuery);
      candidates.addAll(patternCandidates);
    }

    // 2. Usage-based learning
    final usageCandidates = _extractUsageBased(usedMemories);
    candidates.addAll(usageCandidates);

    // 3. Correction-based learning
    final correctionCandidates = _extractCorrectionBased(
      userQuery,
      assistantResponse,
    );
    candidates.addAll(correctionCandidates);

    // 4. Frequency-based extraction (hanya jika bukan pertanyaan atau mutasi transaksi kasual)
    if (!isQueryNoise) {
      final specificValues = <String>{
        for (final candidate in candidates)
          if (candidate.type != FfmMemoryType.habit)
            candidate.value.trim().toLowerCase(),
      };
      final frequencyCandidates =
          _extractFrequencyPatterns(userQuery).where(
            (candidate) => !specificValues.contains(
              candidate.value.trim().toLowerCase(),
            ),
          );
      candidates.addAll(frequencyCandidates);
    }

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
        final memoryCandidate = await _promoteSingleCandidate(
          candidate,
          requireApproval,
        );
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

      final importance =
          (memory.metadata['importance'] as num?)?.toDouble() ?? 0.5;
      if (importance >= 0.8) continue;

      final decayFactor =
          1.0 - (age.inDays / (maxAge.inDays * 2)).clamp(0.0, 0.5);
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
      final currentImportance =
          (memory.metadata['importance'] as num?)?.toDouble() ?? 0.5;
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

    final extractedName = _extractName(userQuery);
    if (extractedName != null) {
      candidates.add(
        FfmMemoryPromotionCandidate(
          type: FfmMemoryType.identity,
          key: 'preferred_name',
          value: extractedName,
          confidence: 0.85,
          reason: 'User menyebutkan nama panggilan: $extractedName',
          sourceId: userQuery,
          requiresApproval: true,
        ),
      );
    }

    if (RegExp(
      r'gaji(?:an)?\s+(?:tiap|setiap|per)?\s*tanggal\s+\d+|gaji(?:an)?\s+tanggal\s+\d+\s+(?:tiap|setiap|per)?\s*bulan',
      caseSensitive: false,
    ).hasMatch(lowerQuery)) {
      candidates.add(
        FfmMemoryPromotionCandidate(
          type: FfmMemoryType.explicitFact,
          key: 'payday',
          value: userQuery,
          confidence: 0.85,
          reason: 'User menyebutkan jadwal gaji',
          sourceId: userQuery,
          requiresApproval: true,
        ),
      );
    }

    final foodMatch = RegExp(
      r'(?:budget|anggaran|jatah)\s+(?:makan|makanan)\s+(?:perbulan|sebulan|tiap\s+bulan)?\s*(?:sebesar|sebanyak|sekitar|adalah)?\s*([\d.,]+(?:\s*(?:juta|ribu|rb|jt))?)',
      caseSensitive: false,
    ).firstMatch(lowerQuery);
    if (foodMatch != null) {
      final amount = foodMatch.group(1)?.trim();
      if (amount != null && amount.isNotEmpty) {
        candidates.add(
          FfmMemoryPromotionCandidate(
            type: FfmMemoryType.explicitFact,
            key: 'budget_food',
            value: 'Anggaran makan: $amount',
            confidence: 0.8,
            reason: 'User menyebutkan anggaran makan $amount',
            sourceId: userQuery,
            requiresApproval: true,
          ),
        );
      }
    }

    final goalMatch = RegExp(
      r'(?:target\s+(?:nabung|menabung)|mau\s+nabung)\s+(?:sebesar|sebanyak|sekitar|adalah)?\s*([\d.,]+(?:\s*(?:juta|ribu|rb|jt))?|[\w\s]{3,35})',
      caseSensitive: false,
    ).firstMatch(lowerQuery);
    if (goalMatch != null) {
      final goal = goalMatch.group(1)?.trim();
      if (goal != null && goal.isNotEmpty && goal.length <= 40) {
        candidates.add(
          FfmMemoryPromotionCandidate(
            type: FfmMemoryType.goal,
            key: 'savings_target',
            value: goal,
            confidence: 0.8,
            reason: 'User menyebutkan target tabungan',
            sourceId: userQuery,
            requiresApproval: true,
          ),
        );
      }
    }

    return candidates;
  }

  String? _extractName(String query) {
    final clean = query.trim();
    final lower = clean.toLowerCase();

    // Jangan ekstrak jika berupa kalimat tanya atau sapaan semata
    if (lower.contains('siapa') ||
        lower.contains('?') ||
        lower.contains('tahu')) {
      return null;
    }

    final patterns = [
      RegExp(
        r'(?:panggil(?:\s*saya|\s*aku|\s*gue)?\s+(?:dengan\s+nama\s+|sebagai\s+)?)([A-Za-zÀ-ÿ]{2,25})',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:nama(?:\s*saya|\s*aku|\s*gue)?\s+(?:adalah\s+)?)([A-Za-zÀ-ÿ]{2,25})',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:namaku|panggilanku)\s+(?:adalah\s+)?([A-Za-zÀ-ÿ]{2,25})',
        caseSensitive: false,
      ),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(clean);
      if (match != null) {
        final rawName = match.group(1)?.trim();
        if (rawName == null || rawName.length < 2) continue;

        const stopWords = {
          'unknown', 'null', 'undefined', 'siapa', 'apa', 'dia', 'kamu',
          'anda', 'saya', 'aku', 'gue', 'kami', 'kita', 'mereka', 'tahu',
          'belum', 'ada', 'tidak', 'bukan', 'adalah', 'bisa', 'dong', 'ya',
          'nih', 'deh', 'aja', 'saja', 'toko', 'warung', 'rekening',
          'kategori', 'uang', 'saldo', 'gaji', 'belanja', 'makan', 'minum',
          'hari', 'bulan', 'nama', 'panggil', 'seorang', 'orang',
        };

        if (stopWords.contains(rawName.toLowerCase())) continue;

        return rawName[0].toUpperCase() + rawName.substring(1).toLowerCase();
      }
    }

    return null;
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
        candidates.add(
          FfmMemoryPromotionCandidate(
            type: FfmMemoryType.behavioralPattern,
            key: 'frequent_topic_${entry.key}',
            value: entry.key,
            confidence: 0.6,
            reason: 'Topik ${entry.key} sering muncul dalam percakapan',
            sourceId: 'usage-analysis',
            requiresApproval: true,
          ),
        );
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
      RegExp(
        r'(?:ubah|ganti|gantikan)\s+(?:jadi|ke|menjadi)\s+',
        caseSensitive: false,
      ),
    ];

    final isCorrection = correctionPatterns.any((p) => p.hasMatch(lowerQuery));

    if (isCorrection) {
      final key = _extractCorrectionKey(lowerQuery);
      final value = _extractCorrectionValue(lowerQuery);

      if (key.isNotEmpty && value.isNotEmpty) {
        candidates.add(
          FfmMemoryPromotionCandidate(
            type: FfmMemoryType.correction,
            key: key,
            value: value,
            confidence: 0.85,
            reason: 'User mengoreksi informasi',
            sourceId: userQuery,
            requiresApproval: true,
          ),
        );
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
    final match = RegExp(
      r'(?:jadi|ke|menjadi)\s+(.+)',
      caseSensitive: false,
    ).firstMatch(query);
    if (match != null) return match.group(1)?.trim() ?? '';
    return query;
  }

  List<FfmMemoryPromotionCandidate> _extractFrequencyPatterns(
    String userQuery,
  ) {
    final candidates = <FfmMemoryPromotionCandidate>[];
    final lower = userQuery.toLowerCase();

    // Hanya deteksi rutinitas jika user menyatakan rutinitas/jadwal eksplisit
    final timePatterns = {
      RegExp(r'(?:setiap|tiap|per)\s+pagi'): 'morning_routine',
      RegExp(r'(?:setiap|tiap|per)\s+malam'): 'evening_routine',
      RegExp(r'(?:setiap|tiap|per)\s+bulan'): 'monthly_routine',
      RegExp(r'(?:setiap|tiap|per)\s+minggu'): 'weekly_routine',
    };

    for (final entry in timePatterns.entries) {
      if (entry.key.hasMatch(lower)) {
        candidates.add(
          FfmMemoryPromotionCandidate(
            type: FfmMemoryType.habit,
            key: entry.value,
            value: userQuery,
            confidence: 0.65,
            reason: 'Pola kebiasaan terdeteksi: ${entry.value}',
            sourceId: userQuery,
            requiresApproval: true,
          ),
        );
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
        approved: !requireApproval && !candidate.requiresApproval,
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
      id: memoryCandidate.id,
      kind: memoryCandidate.type.name,
      triggerText: memoryCandidate.key,
      valueText: memoryCandidate.value,
      source: promotionCandidate.sourceId ?? 'memory-learning-service',
      metadata: {
        'confidence': memoryCandidate.evidence.confidence,
        'approved': memoryCandidate.evidence.approved,
        'importance': memoryCandidate.importance,
        'useCount': 0,
        if (promotionCandidate.reason != null)
          'reason': promotionCandidate.reason,
      },
    );

    // Sync to Cloud if approved. This is best-effort: local memory promotion
    // must remain successful when secure storage or the optional cloud service
    // is unavailable (for example, during offline startup or local tests).
    if (memoryCandidate.evidence.approved) {
      unawaited(_syncApprovedMemory(memoryCandidate));
    }
  }

  Future<void> _syncApprovedMemory(FfmMemoryCandidate memory) async {
    try {
      await _supabase.saveMemory(
        content: '${memory.key}: ${memory.value}',
        category: memory.type.name,
        metadata: {'importance': memory.importance, 'source': 'auto-sync'},
      );
    } on Object {
      // Cloud sync must never make the local learning pipeline fail.
    }
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
