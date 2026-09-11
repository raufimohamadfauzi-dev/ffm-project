import 'ffm_assistant_memory_repository.dart';

/// Service untuk mengelola koreksi mandiri pengguna terhadap jawaban asisten.
///
/// Menyimpan koreksi permanen ke tabel `assistant_memories` lokal (scope: user-correction)
/// dan menyusun konteks aturan/koreksi terverifikasi agar asisten tidak mengulangi kesalahan.
class FfmAssistantCorrectionService {
  const FfmAssistantCorrectionService(this._repository);

  final FfmAssistantMemoryRepository _repository;

  static const String kindCorrection = 'correction';

  /// Menyimpan koreksi pengguna terhadap jawaban asisten.
  Future<FfmAssistantMemoryRecord> saveCorrection({
    required String userQuestion,
    required String correctedText,
    String? originalResponse,
    String? topic,
  }) async {
    final cleanQuestion = userQuestion.trim();
    final cleanCorrection = correctedText.trim();
    if (cleanQuestion.isEmpty || cleanCorrection.isEmpty) {
      throw ArgumentError('Pertanyaan dan teks koreksi tidak boleh kosong.');
    }

    return await _repository.save(
      kind: kindCorrection,
      triggerText: cleanQuestion,
      valueText: cleanCorrection,
      source: 'user_correction',
      metadata: {
        'scope': 'user-correction',
        'approved': true,
        if (originalResponse != null && originalResponse.trim().isNotEmpty)
          'original_response': originalResponse.trim(),
        if (topic != null && topic.trim().isNotEmpty)
          'topic': topic.trim(),
      },
    );
  }

  /// Membaca semua koreksi aktif dari pengguna.
  Future<List<FfmAssistantMemoryRecord>> getActiveCorrections() async {
    return await _repository.readActive(kind: kindCorrection);
  }

  /// Membangun konteks koreksi yang siap diinjeksikan ke prompt asisten/LLM.
  Future<String> buildCorrectionsContext({
    String? query,
    int maxItems = 5,
  }) async {
    final all = await getActiveCorrections();
    if (all.isEmpty) return '';

    var filtered = all;
    if (query != null && query.trim().isNotEmpty) {
      final q = query.trim().toLowerCase();
      final matches = all.where((c) {
        final trigger = c.triggerText.toLowerCase();
        final val = c.valueText.toLowerCase();
        final topic = (c.metadata['topic'] as String?)?.toLowerCase() ?? '';
        return trigger.contains(q) ||
            q.contains(trigger) ||
            val.contains(q) ||
            topic.contains(q);
      }).toList();

      if (matches.isNotEmpty) {
        filtered = matches;
      }
    }

    final bounded = filtered.take(maxItems);
    final lines = bounded.map((c) {
      return '• Jika membahas "${c.triggerText}": fakta/aturan yang benar dari pengguna adalah "${c.valueText}". Wajib ikuti aturan ini dan jangan mengulangi jawaban keliru.';
    }).toList();

    return 'KOREKSI & ATURAN PENGGUNA TERVERIFIKASI (Wajib dipatuhi asisten):\n${lines.join('\n')}';
  }

  /// Mengarsipkan (menghapus) koreksi berdasarkan ID record.
  Future<void> archiveCorrection(String id) async {
    await _repository.archive(id);
  }
}
