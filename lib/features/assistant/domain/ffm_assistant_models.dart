/// Fondasi Asisten FFM Lokal: semua aksi keuangan tetap berupa draft sampai
/// pengguna melihat preview dan mengonfirmasinya.
enum FfmAssistantIntentType {
  openPage,
  listPages,
  setupGuide,
  featureHelp,
  assistantIdentity,
  calendarQuery,
  transactionStats,
  weeklyAnalysis,
  financialWarnings,
  createIncome,
  createExpense,
  createTransfer,
  createGoalDeposit,
  createGoalUsage,
  createGoal,
  createLiability,
  createReceivable,
  createAsset,
  createBudget,
  createMasterData,
  createReminder,
  createActivity,
  explainJson,
  createJsonTemplate,
  exportReport,
  replaceDraftText,
  removeDraftItem,
  teachMemory,
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
  goal,
  liability,
  receivable,
  asset,
  budget,
  masterData,
  reminder,
  activity,
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
    this.teachingProposal,
  });

  final String rawText;
  final String normalizedText;
  final FfmAssistantIntentType type;
  final FfmAssistantDestination? destination;
  final FfmAssistantDraft? draft;
  final double confidence;
  final String? clarification;
  final String? response;
  final FfmAssistantTeachingProposal? teachingProposal;

  bool get needsClarification => clarification != null;
  bool get needsConfirmation => draft != null && !needsClarification;
  bool get needsTeachingApproval => teachingProposal != null;
}

/// Ajaran yang ditampilkan dulu di chat. Repository SQLite hanya boleh
/// menyimpan proposal ini setelah pengguna menekan aksi persetujuan.
class FfmAssistantTeachingProposal {
  const FfmAssistantTeachingProposal({
    required this.kind,
    required this.triggerText,
    required this.valueText,
  });

  final String kind;
  final String triggerText;
  final String valueText;
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
    this.categoryName,
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
  final String? categoryName;
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
    String? categoryName,
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
    categoryName: categoryName ?? this.categoryName,
    adminFee: adminFee ?? this.adminFee,
    goalName: goalName ?? this.goalName,
    note: note ?? this.note,
    date: date ?? this.date,
  );
}

class FfmAssistantChatEntry {
  const FfmAssistantChatEntry({
    required this.isUser,
    required this.text,
    this.intent,
    this.understanding,
  });

  final bool isUser;
  final String text;
  final FfmAssistantIntent? intent;
  final String? understanding;
}

/// Konteks pertanyaan yang perlu dijawab sebelum sebuah draft dapat dibuka.
/// Tidak memuat aksi simpan dan hanya hidup selama sesi chat aktif.
class FfmAssistantPendingDialog {
  const FfmAssistantPendingDialog({
    required this.originalRequest,
    required this.prompt,
    required this.missingFields,
    this.draft,
  });

  final String originalRequest;
  final String prompt;
  final List<String> missingFields;
  final FfmAssistantDraft? draft;
}

class FfmAssistantChatSession {
  FfmAssistantChatSession()
    : entries = [
        const FfmAssistantChatEntry(
          isUser: false,
          text: 'Hai, aku Asisten FFM. Mau cek data, pindah halaman, siapin draft, atau tanya kalender? Tulis santai aja. Contoh: “Sekarang jam berapa?”, “90 hari lagi tanggal berapa?”, atau “Ada berapa transaksi bulan ini?”',
        ),
      ];

  final List<FfmAssistantChatEntry> entries;
  final List<FfmAssistantIntent> queuedIntents = [];
  String? lastAssistantText;
  FfmAssistantPendingDialog? pendingDialog;

  void reset() {
    entries
      ..clear()
      ..add(
        const FfmAssistantChatEntry(
          isUser: false,
          text: 'Chat sudah direset. Mau cek data, pindah halaman, siapin draft, atau tanya kalender?',
        ),
      );
    queuedIntents.clear();
    lastAssistantText = null;
    pendingDialog = null;
  }
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

  static FfmAssistantPage? findByDestination(
    FfmAssistantDestination destination,
  ) {
    for (final page in pages) {
      if (page.destination == destination) return page;
    }
    return null;
  }

  static String listForChat() =>
      pages.map((page) => '• ${page.name} — ${page.description}').join('\n');
}
