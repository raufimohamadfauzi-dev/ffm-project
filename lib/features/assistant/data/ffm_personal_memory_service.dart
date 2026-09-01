import 'ffm_assistant_memory_repository.dart';
import 'ffm_assistant_draft_feedback_service.dart';
import '../domain/ffm_assistant_models.dart';

/// Kategori fakta yang diingat tentang pengguna.
enum FfmPersonalMemoryKind {
  /// Preferensi eksplisit yang disebutkan user dalam percakapan.
  preference,

  /// Kebiasaan yang terdeteksi dari pola kalimat chat.
  habitChat,

  /// Kebiasaan yang terdeteksi dari pola transaksi / aktivitas yang sudah diinput.
  habitData,
}

/// Satu fakta yang diketahui (atau akan diingat) tentang pengguna.
class FfmPersonalMemoryInsight {
  const FfmPersonalMemoryInsight({
    this.id,
    required this.kind,
    required this.key,
    required this.value,
    required this.humanLabel,
    this.sourceMessage,
    this.savedAt,
  });

  final String? id;
  final FfmPersonalMemoryKind kind;
  final String key;
  final String value;
  final String
  humanLabel; // Tampilan ramah, misal: "Tanggal gaji: 25 setiap bulan"
  final String? sourceMessage; // Kalimat user yang memicu deteksi
  final DateTime? savedAt;
}

/// Aturan regex sederhana untuk mendeteksi fakta pribadi dari kalimat user.
class _MemoryPattern {
  const _MemoryPattern({
    required this.kind,
    required this.key,
    required this.pattern,
    required this.labeler,
  });

  final FfmPersonalMemoryKind kind;
  final String key;
  final RegExp pattern;
  final String Function(RegExpMatch m) labeler;
}

/// Service Personal Memory Mode.
///
/// Hanya menyimpan data jika user secara eksplisit menyetujuinya
/// melalui nudge card konfirmasi di UI. Tidak ada penyimpanan diam-diam.
class FfmPersonalMemoryService {
  FfmPersonalMemoryService([
    this._memories,
    FfmAssistantDraftFeedbackService? feedbackService,
  ]) : feedbackService = feedbackService ?? FfmAssistantDraftFeedbackService();

  final FfmAssistantMemoryRepository? _memories;
  final FfmAssistantDraftFeedbackService feedbackService;

  static const _kindPrefix = 'personal_memory_';

  static final _patterns = <_MemoryPattern>[
    _MemoryPattern(
      kind: FfmPersonalMemoryKind.preference,
      key: 'payday',
      pattern: RegExp(
        r'gaji(?:an)?(?:\s*(?:ku|saya|kami))?\s+(?:tiap|setiap|per)?\s*tanggal\s+(\d{1,2})',
        caseSensitive: false,
      ),
      labeler: (m) => 'Tanggal gaji: ${m.group(1)} setiap bulan',
    ),
    _MemoryPattern(
      kind: FfmPersonalMemoryKind.preference,
      key: 'name',
      pattern: RegExp(
        r'(?:nama(?:\s*(?:ku|saya|gue))?|panggil(?:an)?(?:\s*(?:ku|saya|aku|gue))?)\s+(?:adalah\s+)?([A-Za-z]{2,20})',
        caseSensitive: false,
      ),
      labeler: (m) => 'Nama panggilanmu: ${m.group(1)}',
    ),
    _MemoryPattern(
      kind: FfmPersonalMemoryKind.preference,
      key: 'occupation',
      pattern: RegExp(
        r'(?:aku|saya|gue)\s+(?:adalah|seorang?|bekerja\s+sebagai|kerja\s+sebagai)\s+([\w\s]{3,30})',
        caseSensitive: false,
      ),
      labeler: (m) => 'Pekerjaan: ${m.group(1)?.trim()}',
    ),
    _MemoryPattern(
      kind: FfmPersonalMemoryKind.preference,
      key: 'hobby',
      pattern: RegExp(
        r'(?:hobi|kesenangan|suka)\s+(?:ku|saya|gue)?\s*(?:adalah|nya)?\s*([\w\s,]{2,40})',
        caseSensitive: false,
      ),
      labeler: (m) => 'Hobi: ${m.group(1)?.trim()}',
    ),
    _MemoryPattern(
      kind: FfmPersonalMemoryKind.preference,
      key: 'location',
      pattern: RegExp(
        r'(?:aku|saya|gue)\s+(?:tinggal|domisili|berdomisili)\s+(?:di|dalam)?\s*([\w\s]{3,30})',
        caseSensitive: false,
      ),
      labeler: (m) => 'Domisili: ${m.group(1)?.trim()}',
    ),
    _MemoryPattern(
      kind: FfmPersonalMemoryKind.preference,
      key: 'monthly_income',
      pattern: RegExp(
        r'(?:gaji|penghasilan|pendapatan)(?:\s*(?:ku|saya|gue))?\s+(?:perbulan|per\s*bulan|sebulan)?\s*(?:sekitar|kurang\s+lebih|about)?\s*([\d.,]+(?:\s*(?:juta|ribu|rb|jt))?)',
        caseSensitive: false,
      ),
      labeler: (m) => 'Penghasilan/bulan: ${m.group(1)?.trim()}',
    ),
    _MemoryPattern(
      kind: FfmPersonalMemoryKind.preference,
      key: 'spouse_name',
      pattern: RegExp(
        r'(?:istri|suami|pasangan)(?:\s*(?:ku|saya|gue))?\s+(?:nama(?:nya)?)?\s*(?:adalah\s+)?([A-Za-z]{2,20})',
        caseSensitive: false,
      ),
      labeler: (m) => 'Nama pasangan: ${m.group(1)}',
    ),
    _MemoryPattern(
      kind: FfmPersonalMemoryKind.preference,
      key: 'child_count',
      pattern: RegExp(
        r'(?:anak(?:ku|saya|gue)?)\s+(?:ada|berjumlah)\s+(\d+)',
        caseSensitive: false,
      ),
      labeler: (m) => 'Jumlah anak: ${m.group(1)}',
    ),
    _MemoryPattern(
      kind: FfmPersonalMemoryKind.preference,
      key: 'financial_goal',
      pattern: RegExp(
        r'(?:ingin|mau|目标|mimpi)\s+(?:beli|punya|membeli)\s+([\w\s]{3,30})',
        caseSensitive: false,
      ),
      labeler: (m) => 'Goal keuangan: ${m.group(1)?.trim()}',
    ),
    _MemoryPattern(
      kind: FfmPersonalMemoryKind.habitChat,
      key: 'savings_target',
      pattern: RegExp(
        r'(?:target|tujuan|mau)\s+(?:nabung|menabung|simpan)\s+([\d.,]+(?:\s*(?:juta|ribu|rb|jt))?)',
        caseSensitive: false,
      ),
      labeler: (m) => 'Target tabungan: ${m.group(1)?.trim()}',
    ),
    _MemoryPattern(
      kind: FfmPersonalMemoryKind.habitChat,
      key: 'budget_food',
      pattern: RegExp(
        r'(?:budget|anggaran|jatah)\s+(?:makan|makanan|pangan)\s+(?:perbulan|per bulan|sebulan)?\s*([\d.,]+(?:\s*(?:juta|ribu|rb|jt))?)',
        caseSensitive: false,
      ),
      labeler: (m) => 'Anggaran makan/bulan: ${m.group(1)?.trim()}',
    ),
    _MemoryPattern(
      kind: FfmPersonalMemoryKind.habitChat,
      key: 'family_members',
      pattern: RegExp(
        r'(?:keluarga(?:ku|saya)?|kami)\s+(?:ada|terdiri dari|berjumlah)\s+(\d+)\s+(?:orang|anggota)',
        caseSensitive: false,
      ),
      labeler: (m) => 'Jumlah anggota keluarga: ${m.group(1)} orang',
    ),
  ];

  /// Mendapatkan context lengkap untuk LLM termasuk draft feedback
  Map<String, dynamic> getEnhancedContextForLLM(
    FfmAssistantDraft? activeDraft,
  ) {
    final baseContext = <String, dynamic>{};

    // Tambahkan feedback draft
    final draftFeedback = feedbackService.getFeedbackMessageForLLM();
    if (draftFeedback.isNotEmpty) {
      baseContext['draftFeedback'] = draftFeedback;
    }

    // Tambahkan context draft aktif
    if (activeDraft != null) {
      baseContext.addAll(feedbackService.getDraftContextForLLM(activeDraft));
    }

    return baseContext;
  }

  /// Menganalisis satu kalimat user dan mengembalikan insight jika ada pola yang cocok.
  /// Mengembalikan null jika tidak ada fakta baru yang terdeteksi.
  FfmPersonalMemoryInsight? extractFromMessage(String userMessage) {
    final text = userMessage.trim();
    if (text.isEmpty) return null;

    for (final rule in _patterns) {
      final match = rule.pattern.firstMatch(text);
      if (match != null) {
        return FfmPersonalMemoryInsight(
          kind: rule.kind,
          key: rule.key,
          value: match.group(1)?.trim() ?? text,
          humanLabel: rule.labeler(match),
          sourceMessage: text,
        );
      }
    }
    return null;
  }

  /// Menyimpan insight ke tabel assistant_memories SETELAH user menyetujuinya.
  Future<FfmPersonalMemoryInsight> saveApproved(
    FfmPersonalMemoryInsight insight,
  ) async {
    final memories = _memories;
    if (memories == null) return insight;
    final record = await memories.save(
      kind: _kindKebab(insight.kind),
      triggerText: insight.key,
      valueText: insight.value,
      source: insight.kind == FfmPersonalMemoryKind.habitData
          ? 'activity-scan'
          : 'chat-detected',
      metadata: {
        'scope': 'personal-memory',
        'humanLabel': insight.humanLabel,
        'approved': true,
        if (insight.sourceMessage != null)
          'sourceMessage': insight.sourceMessage,
      },
    );
    return FfmPersonalMemoryInsight(
      id: record.id,
      kind: insight.kind,
      key: record.triggerText,
      value: record.valueText,
      humanLabel: insight.humanLabel,
      sourceMessage: insight.sourceMessage,
      savedAt: record.createdAt,
    );
  }

  /// Membaca semua memori pribadi yang sudah disetujui user.
  Future<List<FfmPersonalMemoryInsight>> readAll() async {
    final memories = _memories;
    if (memories == null) return const [];
    final records = await memories.readActive();
    return records
        .where((r) => r.metadata['scope'] == 'personal-memory')
        .where((r) => r.metadata['approved'] != false)
        .map((r) {
          final kindStr = r.kind;
          final kind = _kindFromString(kindStr);
          return FfmPersonalMemoryInsight(
            id: r.id,
            kind: kind,
            key: r.triggerText,
            value: r.valueText,
            humanLabel:
                (r.metadata['humanLabel'] as String?) ??
                '${r.triggerText}: ${r.valueText}',
            sourceMessage: r.metadata['sourceMessage'] as String?,
            savedAt: r.createdAt,
          );
        })
        .toList();
  }

  /// Membangun string konteks memori yang bisa diinjeksikan ke prompt interpreter.
  Future<String> buildContext() async {
    final all = await readAll();
    if (all.isEmpty) return '';
    return all.map((i) => '• ${i.humanLabel}').join('\n');
  }

  /// Menghapus satu memori berdasarkan ID.
  Future<void> forget(String id) async {
    await _memories?.archive(id);
  }

  static String _kindKebab(FfmPersonalMemoryKind kind) => switch (kind) {
    FfmPersonalMemoryKind.preference => '${_kindPrefix}preference',
    FfmPersonalMemoryKind.habitChat => '${_kindPrefix}habit_chat',
    FfmPersonalMemoryKind.habitData => '${_kindPrefix}habit_data',
  };

  static FfmPersonalMemoryKind _kindFromString(String kind) {
    if (kind.contains('preference')) return FfmPersonalMemoryKind.preference;
    if (kind.contains('habit_data')) return FfmPersonalMemoryKind.habitData;
    return FfmPersonalMemoryKind.habitChat;
  }
}
