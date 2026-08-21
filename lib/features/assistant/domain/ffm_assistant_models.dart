/// Fondasi Asisten FFM Lokal: semua aksi keuangan tetap berupa draft sampai
/// pengguna melihat preview dan mengonfirmasinya.
enum FfmAssistantIntentType {
  openPage,
  listPages,
  transactionStats,
  createIncome,
  createExpense,
  createTransfer,
  createGoalDeposit,
  createGoalUsage,
  createLiability,
  createReceivable,
  explainJson,
  createJsonTemplate,
  exportReport,
  replaceDraftText,
  removeDraftItem,
  readLastResponse,
  confirm,
  cancel,
  help,
  unknown,
}

enum FfmAssistantDestination {
  summary,
  transactions,
  budget,
  analysis,
  otherMenu,
  masterData,
  assets,
  goals,
  liabilities,
  activity,
  reminders,
  backup,
  monthlyReport,
  reconciliation,
}

enum FfmAssistantDraftKind {
  income,
  expense,
  transfer,
  goalDeposit,
  goalUsage,
  liability,
  receivable,
}

class FfmAssistantIntent {
  const FfmAssistantIntent({
    required this.rawText,
    required this.normalizedText,
    required this.type,
    this.destination,
    this.draft,
    this.confidence = 0,
    this.clarification,
    this.response,
  });

  final String rawText;
  final String normalizedText;
  final FfmAssistantIntentType type;
  final FfmAssistantDestination? destination;
  final FfmAssistantDraft? draft;
  final double confidence;
  final String? clarification;
  final String? response;

  bool get needsClarification => clarification != null;
  bool get needsConfirmation => draft != null && !needsClarification;
}

class FfmAssistantDraft {
  const FfmAssistantDraft({
    required this.kind,
    required this.createdAt,
    this.amount,
    this.title,
    this.partyName,
    this.fromAccountName,
    this.toAccountName,
    this.adminFee,
    this.goalName,
    this.note,
    this.date,
  });

  final FfmAssistantDraftKind kind;
  final DateTime createdAt;
  final int? amount;
  final String? title;
  final String? partyName;
  final String? fromAccountName;
  final String? toAccountName;
  final int? adminFee;
  final String? goalName;
  final String? note;
  final DateTime? date;

  bool get hasAmount => amount != null && amount! > 0;

  FfmAssistantDraft copyWith({
    int? amount,
    String? title,
    String? partyName,
    String? fromAccountName,
    String? toAccountName,
    int? adminFee,
    String? goalName,
    String? note,
    DateTime? date,
  }) => FfmAssistantDraft(
    kind: kind,
    createdAt: createdAt,
    amount: amount ?? this.amount,
    title: title ?? this.title,
    partyName: partyName ?? this.partyName,
    fromAccountName: fromAccountName ?? this.fromAccountName,
    toAccountName: toAccountName ?? this.toAccountName,
    adminFee: adminFee ?? this.adminFee,
    goalName: goalName ?? this.goalName,
    note: note ?? this.note,
    date: date ?? this.date,
  );
}

class FfmAssistantPage {
  const FfmAssistantPage({
    required this.destination,
    required this.name,
    required this.description,
    required this.aliases,
  });

  final FfmAssistantDestination destination;
  final String name;
  final String description;
  final List<String> aliases;
}

abstract final class FfmAssistantCatalog {
  static const pages = <FfmAssistantPage>[
    FfmAssistantPage(
      destination: FfmAssistantDestination.summary,
      name: 'Ringkasan',
      description:
          'Melihat arus kas, grafik pengeluaran, dan kondisi bulan berjalan.',
      aliases: ['beranda', 'home', 'ringkasan', 'dashboard'],
    ),
    FfmAssistantPage(
      destination: FfmAssistantDestination.transactions,
      name: 'Transaksi',
      description:
          'Mencatat pemasukan, pengeluaran, transfer, target, OCR, dan JSON.',
      aliases: ['transaksi', 'catatan uang', 'uang masuk', 'uang keluar'],
    ),
    FfmAssistantPage(
      destination: FfmAssistantDestination.budget,
      name: 'Anggaran',
      description: 'Mengatur batas biaya mingguan atau bulanan.',
      aliases: ['anggaran', 'budget', 'batas belanja'],
    ),
    FfmAssistantPage(
      destination: FfmAssistantDestination.analysis,
      name: 'Analisa',
      description: 'Membaca pola keuangan dan saran dari data yang tersimpan.',
      aliases: ['analisa', 'analisis', 'insight'],
    ),
    FfmAssistantPage(
      destination: FfmAssistantDestination.masterData,
      name: 'Data Utama',
      description: 'Mengelola kategori, toko, tag, rekening, sumber pemasukan, dan keluarga.',
      aliases: ['data utama', 'rekening', 'kategori', 'master data'],
    ),
    FfmAssistantPage(
      destination: FfmAssistantDestination.assets,
      name: 'Aset keluarga',
      description: 'Mencatat aset yang ingin dipantau.',
      aliases: ['aset', 'kekayaan'],
    ),
    FfmAssistantPage(
      destination: FfmAssistantDestination.goals,
      name: 'Target keuangan',
      description: 'Memantau uang yang sedang dikumpulkan.',
      aliases: ['target', 'tujuan keuangan', 'dana target'],
    ),
    FfmAssistantPage(
      destination: FfmAssistantDestination.liabilities,
      name: 'Hutang & piutang',
      description: 'Mencatat kewajiban dan uang yang masih perlu diterima.',
      aliases: ['hutang', 'utang', 'piutang', 'pinjaman'],
    ),
    FfmAssistantPage(
      destination: FfmAssistantDestination.activity,
      name: 'Aktivitas',
      description: 'Melacak aktivitas harian serta durasinya.',
      aliases: ['aktivitas', 'jurnal', 'kegiatan'],
    ),
    FfmAssistantPage(
      destination: FfmAssistantDestination.reminders,
      name: 'Pengingat',
      description: 'Membuat pengingat lokal yang tidak boleh terlewat.',
      aliases: ['pengingat', 'reminder', 'alarm'],
    ),
    FfmAssistantPage(
      destination: FfmAssistantDestination.backup,
      name: 'Ekspor & cadangan',
      description: 'Membuat JSON, CSV, HTML, PDF, atau memulihkan data.',
      aliases: ['ekspor', 'backup', 'cadangan', 'json', 'pdf', 'html'],
    ),
    FfmAssistantPage(
      destination: FfmAssistantDestination.monthlyReport,
      name: 'Ringkasan bulanan',
      description: 'Membandingkan arus kas dan laporan per bulan.',
      aliases: ['laporan', 'laporan bulanan', 'ringkasan bulanan'],
    ),
    FfmAssistantPage(
      destination: FfmAssistantDestination.reconciliation,
      name: 'Rekonsiliasi saldo',
      description: 'Mencocokkan saldo nyata dengan catatan akun.',
      aliases: ['rekonsiliasi', 'cek saldo', 'cocokkan saldo'],
    ),
  ];

  static FfmAssistantPage? findByText(String normalizedText) {
    final matches = pages.where(
      (page) => page.aliases.any(
        (alias) => normalizedText.contains(alias.toLowerCase()),
      ),
    );
    return matches.isEmpty ? null : matches.first;
  }

  static String listForChat() =>
      pages.map((page) => '• ${page.name} — ${page.description}').join('\n');
}
