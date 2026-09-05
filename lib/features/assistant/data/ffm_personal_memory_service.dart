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
  ]) : feedbackService = feedbackService ?? FfmAssistantDraftFeedbackService() {
    if (this.feedbackService.onRuleLearned == null && _memories != null) {
      this.feedbackService.onRuleLearned = ({
        required String key,
        required String value,
        required String label,
      }) async {
        await learnCorrectionRule(
          key: key,
          value: value,
          humanLabel: label,
        );
      };
    }
  }

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
        r'(?:hobi|kegemaran)\s+(?:ku|saya|gue)?\s*(?:adalah|nya)?\s*([\w\s,]{2,40})',
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
        r'(?:target|tujuan|rencana|mimpi)\s+(?:keuangan|finansial|hidup)?\s*(?:ku|saya|kami)?\s+(?:adalah\s+)?(?:ingin\s+|mau\s+)?(?:beli|punya|membeli|mencapai)\s+([\w\s]{3,30})',
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
    _MemoryPattern(
      kind: FfmPersonalMemoryKind.preference,
      key: 'agriculture_field',
      pattern: RegExp(
        r'(?:lahan|tanah|sawah|ladang|kebun)(?:\s*(?:ku|saya|kami))?\s+(?:luas(?:nya)?\s+)?(?:ada|sekitar|seluas)?\s*([\d.,]+\s*(?:hektar|ha|meter|m2|ubin|bata|ru))',
        caseSensitive: false,
      ),
      labeler: (m) => 'Luas lahan tani/kebun: ${m.group(1)?.trim()}',
    ),
    _MemoryPattern(
      kind: FfmPersonalMemoryKind.preference,
      key: 'commodity',
      pattern: RegExp(
        r'(?:tanam|budidaya|komoditas|kebun|sawah|panen|usaha)\s+(?:nya\s+)?(padi|jagung|kopi|cengkeh|sawit|sayur(?:an)?|cabai|cabe|bawang|singkong|ubi|kakao|cokelat|teh|buah|melon|semangka|tomat|ikan|lele|ayam|bebek|kambing|sapi)',
        caseSensitive: false,
      ),
      labeler: (m) => 'Komoditas tani/usaha: ${m.group(1)?.trim()}',
    ),
    _MemoryPattern(
      kind: FfmPersonalMemoryKind.preference,
      key: 'harvest_target',
      pattern: RegExp(
        r'(?:panen|estimasi\s+panen|jadwal\s+panen|perkiraan\s+panen)(?:\s*(?:ku|saya|kami))?\s+(?:sekitar|pada|bulan|tanggal|tgl)?\s*([\w\s\d]{3,25})',
        caseSensitive: false,
      ),
      labeler: (m) => 'Perkiraan panen: ${m.group(1)?.trim()}',
    ),
    _MemoryPattern(
      kind: FfmPersonalMemoryKind.habitData,
      key: 'electricity_meter',
      pattern: RegExp(
        r'(?:nomor|no)?\s*(?:meteran|meter|id\s*pelanggan|idpel|token)\s*(?:pln|listrik)?\s*(?:rumah|ladang|sawah|toko|ruko|kontrakan)?\s*(?:adalah|:)?\s*(\d{11,12})',
        caseSensitive: false,
      ),
      labeler: (m) => 'Nomor Meteran PLN: ${m.group(1)?.trim()}',
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

  static bool _isQuestionOrTransaction(String text) {
    final lower = text.trim().toLowerCase();
    if (lower.isEmpty) return true;
    if (lower.contains('?')) return true;

    // 1. Kata tanya / interogatif
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

    // 2. Perintah transaksi finansial & aksi aplikasi
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

  /// Menganalisis satu kalimat user dan mengembalikan insight jika ada pola yang cocok.
  /// Mengembalikan null jika tidak ada fakta baru yang terdeteksi.
  FfmPersonalMemoryInsight? extractFromMessage(String userMessage) {
    final text = userMessage.trim();
    if (text.isEmpty) return null;
    if (_isQuestionOrTransaction(text)) return null;

    const stopWords = {
      'unknown', 'null', 'undefined', 'siapa', 'apa', 'dia', 'kamu',
      'anda', 'saya', 'aku', 'gue', 'kami', 'kita', 'mereka', 'tahu',
      'belum', 'ada', 'tidak', 'bukan', 'adalah', 'bisa', 'dong', 'ya',
      'nih', 'deh', 'aja', 'saja', 'toko', 'warung', 'rekening',
      'kategori', 'uang', 'saldo', 'gaji', 'belanja', 'makan', 'minum',
      'hari', 'bulan', 'nama', 'panggil', 'seorang', 'orang',
    };

    for (final rule in _patterns) {
      final match = rule.pattern.firstMatch(text);
      if (match != null) {
        final rawVal = match.group(1)?.trim() ?? text;
        if (rule.key == 'name' && stopWords.contains(rawVal.toLowerCase())) {
          continue;
        }
        return FfmPersonalMemoryInsight(
          kind: rule.kind,
          key: rule.key,
          value: rawVal,
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
  /// Memori dideduplikasi berdasarkan key (mengambil versi paling baru) dan
  /// dibatasi maksimal [maxItems] (default 8) agar prompt LLM tetap ringkas & fokus.
  Future<String> buildContext({String? query, int maxItems = 8}) async {
    final all = await readAll();
    if (all.isEmpty) return '';

    // 1. Deduplikasi berdasarkan key (mengambil entri unik teranyar)
    final uniqueMap = <String, FfmPersonalMemoryInsight>{};
    for (final m in all) {
      if (!uniqueMap.containsKey(m.key)) {
        uniqueMap[m.key] = m;
      }
    }

    var list = uniqueMap.values.toList();

    // 2. Jika ada query, prioritaskan memori yang cocok kata kunci
    if (query != null && query.trim().isNotEmpty) {
      final q = query.toLowerCase();
      list.sort((a, b) {
        final aScore = (a.key.toLowerCase().contains(q) ? 2 : 0) +
            (a.humanLabel.toLowerCase().contains(q) ? 1 : 0);
        final bScore = (b.key.toLowerCase().contains(q) ? 2 : 0) +
            (b.humanLabel.toLowerCase().contains(q) ? 1 : 0);
        return bScore.compareTo(aScore);
      });
    }

    // 3. Batasi hanya [maxItems] agar LLM tidak kebanjiran konteks
    final bounded = list.take(maxItems);
    return bounded.map((i) => '• ${i.humanLabel}').join('\n');
  }

  /// Belajar otonom dari koreksi draft pengguna (Modul 3A).
  /// Menyimpan aturan personal otomatis agar transaksi/tindakan serupa berikutnya tepat.
  Future<FfmPersonalMemoryInsight?> learnCorrectionRule({
    required String key,
    required String value,
    required String humanLabel,
    String? sourceMessage,
  }) async {
    final memories = _memories;
    if (memories == null) return null;
    final record = await memories.save(
      kind: _kindKebab(FfmPersonalMemoryKind.habitData),
      triggerText: key,
      valueText: value,
      source: 'draft-correction-learning',
      metadata: {
        'scope': 'personal-memory',
        'humanLabel': humanLabel,
        'approved': true,
        'isLearnedRule': true,
        'sourceMessage': ?sourceMessage,
      },
    );
    return FfmPersonalMemoryInsight(
      id: record.id,
      kind: FfmPersonalMemoryKind.habitData,
      key: record.triggerText,
      value: record.valueText,
      humanLabel: humanLabel,
      sourceMessage: sourceMessage,
      savedAt: record.createdAt,
    );
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
