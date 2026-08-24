import 'ffm_assistant_models.dart';

class FfmAssistantKnowledgeEntry {
  const FfmAssistantKnowledgeEntry({
    required this.id,
    required this.title,
    required this.content,
    this.tags = const <String>[],
  });

  final String id;
  final String title;
  final String content;
  final List<String> tags;

  String get searchableText =>
      '$title $content ${tags.join(' ')}'.toLowerCase();
}

/// Sumber pengetahuan runtime yang bounded untuk orchestrator dan prompt SLM.
/// Registry ini menjelaskan aplikasi dan kontraknya, bukan menyalin isi database.
class FfmAssistantRuntimeKnowledgeRegistry {
  static const formatVersion = 'ffm-runtime-knowledge-v2';

  static const databaseTables = <String>[
    'households',
    'categories',
    'merchants',
    'tags',
    'accounts',
    'transaction_parties',
    'transactions',
    'transaction_items',
    'transaction_tags',
    'attachments',
    'transfers',
    'envelope_budgets',
    'envelope_transfers',
    'assets',
    'goals',
    'liabilities',
    'receivables',
    'recurring_transactions',
    'reminders',
    'reminder_histories',
    'activity_sessions',
    'activity_checkpoints',
    'activity_entries',
    'account_reconciliation_logs',
    'recurring_transaction_runs',
    'hijri_settings',
    'hijri_month_overrides',
    'hijri_correction_logs',
    'assistant_memories',
    'assistant_learning_examples',
    'assistant_unanswered_questions',
  ];

  static const domainEntries = <FfmAssistantKnowledgeEntry>[
    FfmAssistantKnowledgeEntry(
      id: 'domain.transactions',
      title: 'Transaksi',
      content: 'Pemasukan, pengeluaran, transfer, item nota, lampiran, kategori, rekening, dan target terkait. Transfer bukan pemasukan atau pengeluaran; biaya admin transfer dicatat sebagai pengeluaran terpisah.',
      tags: ['income', 'expense', 'transfer', 'catat uang'],
    ),
    FfmAssistantKnowledgeEntry(
      id: 'domain.budget',
      title: 'Anggaran',
      content: 'Anggaran menetapkan alokasi per periode dan kategori, lalu dibandingkan dengan pemakaian transaksi. Agent hanya memberi preview perubahan sebelum menyimpan.',
      tags: ['budget', 'envelope', 'batas belanja'],
    ),
    FfmAssistantKnowledgeEntry(
      id: 'domain.goals',
      title: 'Target keuangan',
      content: 'Target memiliki nilai tujuan, batas waktu, progress, setoran, dan penggunaan. Setoran atau penggunaan tetap merupakan mutation yang harus dikonfirmasi.',
      tags: ['goal', 'target', 'progress'],
    ),
    FfmAssistantKnowledgeEntry(
      id: 'domain.financial-literacy',
      title: 'Literasi dan manajemen keuangan keluarga',
      content: 'Asisten boleh menjelaskan cara menabung, budgeting, cashflow, target, utang/piutang, aset, dan laporan. Jika pertanyaan menyangkut kondisi pengguna, baca agregat lokal terlebih dahulu. Pisahkan fakta, kalkulasi, asumsi, risiko, dan saran; jangan mengarang angka atau menyatakan persetujuan kredit.',
      tags: [
        'literasi keuangan',
        'menabung',
        'budgeting',
        'cashflow',
        'rencana keuangan',
      ],
    ),
    FfmAssistantKnowledgeEntry(
      id: 'domain.loan-affordability',
      title: 'Analisis kemampuan cicilan',
      content: 'Untuk pertanyaan kemampuan pinjaman, gunakan pemasukan dan pengeluaran pada periode yang sama serta cicilan kewajiban aktif. Batas internal konservatif 30% pemasukan hanya guardrail edukatif. Ruang cicilan baru tidak boleh melebihi sisa cashflow dan tidak mengubahnya menjadi nominal pokok tanpa bunga, biaya, dan tenor nyata.',
      tags: ['kemampuan pinjaman', 'cicilan aman', 'kredit', 'pinjaman'],
    ),
    FfmAssistantKnowledgeEntry(
      id: 'domain.assets',
      title: 'Aset keluarga',
      content: 'Aset mencatat kekayaan yang dipantau berdasarkan nama, nilai, tipe, penempatan, dan catatan.',
      tags: ['asset', 'kekayaan'],
    ),
    FfmAssistantKnowledgeEntry(
      id: 'domain.liabilities',
      title: 'Hutang dan piutang',
      content: 'Kewajiban dan uang yang perlu diterima memiliki nilai, pihak, jatuh tempo, cicilan, serta status. Perubahan harus melalui preview dan konfirmasi.',
      tags: ['liability', 'receivable', 'utang', 'piutang'],
    ),
    FfmAssistantKnowledgeEntry(
      id: 'domain.recurring',
      title: 'Transaksi berkala',
      content: 'Recurring transaction menyimpan jadwal pemasukan atau pengeluaran rutin dan histori prosesnya. Proses berikutnya tidak boleh menjadi autosave tanpa persetujuan.',
      tags: ['recurring', 'rutin', 'berkala'],
    ),
    FfmAssistantKnowledgeEntry(
      id: 'domain.activity',
      title: 'Aktivitas dan jurnal',
      content: 'Aktivitas menyimpan session, checkpoint, durasi, dan entry jurnal. Flow suara memiliki preview serta konfirmasi tersendiri.',
      tags: ['activity', 'jurnal', 'kegiatan'],
    ),
    FfmAssistantKnowledgeEntry(
      id: 'domain.reminders',
      title: 'Pengingat',
      content: 'Pengingat lokal memiliki jadwal, catatan, dan histori notifikasi. Agent dapat menyiapkan draft, tetapi tidak membuat pengingat diam-diam.',
      tags: ['reminder', 'pengingat', 'alarm'],
    ),
    FfmAssistantKnowledgeEntry(
      id: 'domain.assistant',
      title: 'Asisten dan pembelajaran',
      content: 'Asisten memakai SLM lokal untuk reasoning/extraction, registry untuk knowledge, adapter untuk aplikasi, dan Action Plan untuk lifecycle. Memory user serta workflow candidate hanya aktif setelah approval.',
      tags: ['assistant', 'agent', 'slm', 'training', 'learning'],
    ),
    FfmAssistantKnowledgeEntry(
      id: 'domain.operations',
      title: 'Operasi lokal',
      content: 'Backup, privacy, diagnostics, offline features, database structure, model manager, audit log, dan rekonsiliasi adalah fungsi pendukung yang dibaca atau dibuka melalui capability terkontrol.',
      tags: ['backup', 'privacy', 'diagnostic', 'offline', 'audit'],
    ),
  ];

  static const workflowEntries = <FfmAssistantKnowledgeEntry>[
    FfmAssistantKnowledgeEntry(
      id: 'workflow.first-setup',
      title: 'Urutan setup pertama',
      content: 'Periksa household dan data master, siapkan rekening serta kategori, lalu catat transaksi pertama. Jika SLM belum siap, gunakan aturan lokal dan arahkan user ke setup model tanpa mengunduh otomatis.',
      tags: ['pertama kali', 'setup', 'mulai'],
    ),
    FfmAssistantKnowledgeEntry(
      id: 'workflow.transaction',
      title: 'Alur transaksi aman',
      content: 'Pahami permintaan, resolve rekening/kategori, buat draft, tampilkan preview, tunggu konfirmasi, simpan melalui use case resmi, baca kembali, dan laporkan hasil verifikasi.',
      tags: ['workflow', 'preview', 'confirmation', 'verify'],
    ),
    FfmAssistantKnowledgeEntry(
      id: 'workflow.report',
      title: 'Alur laporan',
      content: 'Tentukan periode dan filter, agregasikan angka secara lokal, gunakan SLM hanya untuk narasi/insight, tampilkan preview, lalu ekspor sesuai format yang diminta user.',
      tags: ['laporan', 'report', 'export', 'ringkasan'],
    ),
    FfmAssistantKnowledgeEntry(
      id: 'workflow.suggestion',
      title: 'Alur saran',
      content: 'Ambil fakta dari adapter lokal, pisahkan fakta dari interpretasi, minta SLM menyusun penjelasan atau opsi, dan jangan melakukan mutation dari saran proaktif.',
      tags: ['saran', 'recommendation', 'proaktif'],
    ),
  ];

  List<FfmAssistantKnowledgeEntry> get entries => [
    ...FfmAssistantCatalog.pages.map(
      (page) => FfmAssistantKnowledgeEntry(
        id: 'page.${page.destination.name}',
        title: page.name,
        content: page.description,
        tags: page.aliases,
      ),
    ),
    ...domainEntries,
    ...workflowEntries,
  ];

  FfmAssistantKnowledgeEntry? find(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    for (final entry in entries) {
      if (entry.searchableText.contains(normalized)) return entry;
    }
    return entries.cast<FfmAssistantKnowledgeEntry?>().firstWhere(
      (entry) => entry!.tags.any(normalized.contains),
      orElse: () => null,
    );
  }

  String buildPromptContext({
    String? query,
    FfmAssistantDestination? currentDestination,
    List<String> capabilityIds = const <String>[],
    int maxEntries = 8,
  }) {
    final selected = <FfmAssistantKnowledgeEntry>[];
    if (currentDestination != null) {
      final page = FfmAssistantCatalog.findByDestination(currentDestination);
      if (page != null) {
        selected.add(
          entries.firstWhere(
            (entry) => entry.id == 'page.${page.destination.name}',
          ),
        );
      }
    }
    if (query != null && query.trim().isNotEmpty) {
      final normalized = query.toLowerCase();
      for (final entry in entries) {
        if (entry.searchableText.contains(normalized) &&
            !selected.contains(entry)) {
          selected.add(entry);
        }
      }
    }
    for (final entry in workflowEntries) {
      if (selected.length >= maxEntries) break;
      if (!selected.contains(entry)) selected.add(entry);
    }
    final bounded = selected.take(maxEntries);
    final capabilities = capabilityIds.isEmpty
        ? 'gunakan capability allowlist yang sesuai'
        : capabilityIds.take(24).join(', ');
    return [
      'Knowledge registry $formatVersion.',
      'Capability aktif: $capabilities.',
      'Fakta FFM yang relevan:',
      ...bounded.map((entry) => '- ${entry.title}: ${entry.content}'),
      'Aturan: angka harus berasal dari adapter lokal; SLM tidak boleh menjalankan SQL atau mutation; mutation selalu preview dan konfirmasi.',
    ].join('\n');
  }

  String buildDatabaseSchemaSummary() =>
      'Database lokal FFM memiliki ${databaseTables.length} tabel terkontrol: ${databaseTables.join(', ')}. SLM hanya menerima agregasi/ringkasan yang diperlukan, bukan seluruh baris tabel.';

  bool containsDestination(FfmAssistantDestination destination) =>
      FfmAssistantCatalog.findByDestination(destination) != null;
}
