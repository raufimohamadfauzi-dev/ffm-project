/// Controlled retrieval catalog for Gemini and local assistant reasoning.
/// This is a planning/index layer only: it never executes SQL or mutations.
class FfmAssistantKnowledgeIndex {
  const FfmAssistantKnowledgeIndex._();

  static const policyName = 'ffm-knowledge-index-v1';

  static const _entries = <_KnowledgeIndexEntry>[
    _KnowledgeIndexEntry('onboarding', 'Status onboarding dan langkah berikutnya', _IndexScope.guidance),
    _KnowledgeIndexEntry('summary', 'Ringkasan saldo dan arus kas', _IndexScope.financial),
    _KnowledgeIndexEntry('transactions', 'Transaksi dan analisis historis terbatas', _IndexScope.financial),
    _KnowledgeIndexEntry('budget', 'Anggaran dan pemakaian pos', _IndexScope.financial),
    _KnowledgeIndexEntry('goals', 'Target keuangan dan progres', _IndexScope.financial),
    _KnowledgeIndexEntry('liabilities', 'Hutang, piutang, dan cicilan', _IndexScope.financial),
    _KnowledgeIndexEntry('activity', 'Aktivitas, tugas, dan jadwal', _IndexScope.activity),
    _KnowledgeIndexEntry('reminders', 'Pengingat dan alarm', _IndexScope.activity),
    _KnowledgeIndexEntry('profile', 'Profil keluarga dan personalisasi', _IndexScope.profile),
    _KnowledgeIndexEntry('diagnostics', 'Error teknis dan Asisten Log', _IndexScope.diagnostics),
    _KnowledgeIndexEntry('memory', 'Memory yang sudah disetujui user', _IndexScope.profile),
    _KnowledgeIndexEntry('calendar', 'Tanggal lokal dan kalender Hijriah', _IndexScope.calendar),
  ];

  static FfmAssistantKnowledgeIndexPlan planForRequest(String request) {
    final normalized = request.toLowerCase();
    final selected = <_KnowledgeIndexEntry>[];

    void add(String id) {
      final entry = _entries.firstWhere((item) => item.id == id);
      if (!selected.contains(entry)) selected.add(entry);
    }

    if (RegExp(r'\b(onboarding|mulai|langkah|harus saya lakukan|isi apa|berikutnya)\b').hasMatch(normalized)) {
      add('onboarding');
      add('profile');
      add('summary');
    }
    if (RegExp(r'\b(transaksi|pengeluaran|pemasukan|saldo|ringkasan|analisis|tahun lalu|bulan lalu|historis)\b').hasMatch(normalized)) {
      add('summary');
      add('transactions');
    }
    if (RegExp(r'\b(anggaran|budget)\b').hasMatch(normalized)) add('budget');
    if (RegExp(r'\b(target|goal|tujuan)\b').hasMatch(normalized)) add('goals');
    if (RegExp(r'\b(hutang|utang|piutang|cicilan|pinjaman)\b').hasMatch(normalized)) add('liabilities');
    if (RegExp(r'\b(aktivitas|kegiatan|tugas|jadwal|agenda)\b').hasMatch(normalized)) add('activity');
    if (RegExp(r'\b(pengingat|alarm|ingatkan|reminder)\b').hasMatch(normalized)) add('reminders');
    if (RegExp(r'\b(profil|keluarga|suami|istri|pasangan|nama)\b').hasMatch(normalized)) add('profile');
    if (RegExp(r'\b(error|masalah|bug|asisten log|diagnostik)\b').hasMatch(normalized)) add('diagnostics');
    if (RegExp(r'\b(memory|ingatanku|pernah saya ajarkan)\b').hasMatch(normalized)) add('memory');
    if (RegExp(r'\b(hari|tanggal|kalender|hijriah|rabu|kamis|jumat)\b').hasMatch(normalized)) add('calendar');

    if (selected.isEmpty) {
      add('onboarding');
      add('summary');
    }

    return FfmAssistantKnowledgeIndexPlan(
      request: request,
      sourceIds: selected.map((entry) => entry.id).toList(growable: false),
      sourceLabels: selected.map((entry) => entry.label).toList(growable: false),
    );
  }
}

class FfmAssistantKnowledgeIndexPlan {
  const FfmAssistantKnowledgeIndexPlan({
    required this.request,
    required this.sourceIds,
    required this.sourceLabels,
  });

  final String request;
  final List<String> sourceIds;
  final List<String> sourceLabels;

  String toBoundedPrompt() =>
      'KNOWLEDGE INDEX PLAN (${FfmAssistantKnowledgeIndex.policyName}): '
      'sources=${sourceIds.join(', ')}. '
      'Pilih hanya source terdaftar dan gunakan fakta lokal terverifikasi. '
      'Index ini read-only; tidak memberi akses SQL atau mutasi.';
}

enum _IndexScope { guidance, financial, activity, profile, diagnostics, calendar }

class _KnowledgeIndexEntry {
  const _KnowledgeIndexEntry(this.id, this.label, this.scope);

  final String id;
  final String label;
  final _IndexScope scope;
}
