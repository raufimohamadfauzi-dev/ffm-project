/// Fondasi Asisten FFM Lokal: semua aksi keuangan tetap berupa draft sampai
import '../../activity/domain/activity_voice.dart';

/// pengguna melihat preview dan mengonfirmasinya.
enum FfmAssistantResponseMode { localRules, localModel }

enum FfmAssistantIntentType {
  openPage,
  listPages,
  setupGuide,
  featureHelp,
  assistantIdentity,
  createProfile,
  calendarQuery,
  transactionStats,
  weeklyAnalysis,
  financialWarnings,
  queryData,
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
  updateTransaction,
  archiveTransaction,
  deleteTransaction,
  archiveActivity,
  deleteActivity,
  explainJson,
  createJsonTemplate,
  exportReport,
  replaceDraftText,
  removeDraftItem,
  teachMemory,
  readLastResponse,
  diagnosticStatus,
  confirm,
  cancel,
  help,
  outOfDomain,
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
  appSecurity,
  diagnostics,
  activityLog,
  assistantTraining,
  recurringTransaction,
  offlineAdvanced,
  privacyCenter,
  databaseStructure,
  offlineFeatures,
  localModel,
  assistantProfile,
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
  profile,
  transactionUpdate,
  transactionArchive,
  transactionDelete,
  activityArchive,
  activityDelete,
}

/// Tingkat masalah draft. Hanya [required] dan [conflict] yang menahan
/// pengguna dari membuka form konfirmasi.
enum FfmAssistantDraftIssueSeverity { required, conflict, warning }

/// Hasil pemeriksaan lokal pada satu field draft. Tidak pernah menyimpan atau
/// mengubah data keuangan.
class FfmAssistantDraftIssue {
  const FfmAssistantDraftIssue({
    required this.code,
    required this.severity,
    required this.message,
    this.field,
  });

  final String code;
  final FfmAssistantDraftIssueSeverity severity;
  final String message;
  final String? field;

  bool get blocksContinuation =>
      severity == FfmAssistantDraftIssueSeverity.required ||
      severity == FfmAssistantDraftIssueSeverity.conflict;
}

/// Snapshot draft yang sedang ditinjau di chat. Versi bertambah hanya ketika
/// pengguna menyetujui revisi; belum ada insert/update database finansial.
class FfmAssistantDraftReview {
  const FfmAssistantDraftReview({
    required this.draft,
    required this.version,
    required this.issues,
    this.changeSummary,
  });

  final FfmAssistantDraft draft;
  final int version;
  final List<FfmAssistantDraftIssue> issues;
  final String? changeSummary;

  bool get canContinue => !issues.any((issue) => issue.blocksContinuation);

  FfmAssistantDraftReview revise({
    required FfmAssistantDraft nextDraft,
    required List<FfmAssistantDraftIssue> nextIssues,
    required String changeSummary,
  }) => FfmAssistantDraftReview(
    draft: nextDraft,
    version: version + 1,
    issues: nextIssues,
    changeSummary: changeSummary,
  );
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
    this.responseMode = FfmAssistantResponseMode.localRules,
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
  final FfmAssistantResponseMode responseMode;

  bool get needsClarification => clarification != null;
  bool get needsConfirmation => draft != null && !needsClarification;
  bool get needsTeachingApproval => teachingProposal != null;

  FfmAssistantIntent copyWith({
    FfmAssistantDraft? draft,
    String? response,
    String? clarification,
    FfmAssistantResponseMode? responseMode,
  }) => FfmAssistantIntent(
    rawText: rawText,
    normalizedText: normalizedText,
    type: type,
    destination: destination,
    draft: draft ?? this.draft,
    confidence: confidence,
    clarification: clarification ?? this.clarification,
    response: response ?? this.response,
    teachingProposal: teachingProposal,
    responseMode: responseMode ?? this.responseMode,
  );
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
    this.formValues = const <String, String>{},
    this.merchantName,
    this.slmFieldValues = const <String, String>{},
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
  final Map<String, String> formValues;

  /// Merchant dan nilai field yang berasal dari tebakan awal SLM/rule parser.
  /// Hanya dipakai untuk pembelajaran setelah user mengonfirmasi form.
  final String? merchantName;
  final Map<String, String> slmFieldValues;

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
    Map<String, String>? formValues,
    String? merchantName,
    Map<String, String>? slmFieldValues,
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
    formValues: formValues ?? this.formValues,
    merchantName: merchantName ?? this.merchantName,
    slmFieldValues: slmFieldValues ?? this.slmFieldValues,
  );
}

class FfmAssistantChatEntry {
  const FfmAssistantChatEntry({
    required this.isUser,
    required this.text,
    this.intent,
    this.activityIntent,
    this.understanding,
    this.review,
    this.imagePath,
    this.filePath,
    this.fileFormat,
    this.createdAt,
  });

  final bool isUser;
  final String text;
  final FfmAssistantIntent? intent;
  final ActivityVoiceIntent? activityIntent;
  final String? understanding;
  final FfmAssistantDraftReview? review;
  final String? imagePath;
  final String? filePath;
  final String? fileFormat;
  final DateTime? createdAt;
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
          text: 'Hai, aku Asisten FFM. Tulis pertanyaan atau perintah dengan santai. Aku bisa bantu cek data lokal, buka halaman, siapkan draft untuk kamu tinjau, atau jawab kalender perangkat.',
        ),
      ];

  final List<FfmAssistantChatEntry> entries;
  final List<FfmAssistantIntent> queuedIntents = [];
  String? lastAssistantText;
  FfmAssistantPendingDialog? pendingDialog;
  FfmAssistantDraftReview? activeDraftReview;
  FfmAssistantIntent? activeDraftIntent;

  void reset() {
    entries
      ..clear()
      ..add(
        const FfmAssistantChatEntry(
          isUser: false,
          text: 'Chat sudah direset. Kamu bisa tanya data lokal, minta pindah halaman, atau cek kalender perangkat.',
        ),
      );
    queuedIntents.clear();
    lastAssistantText = null;
    pendingDialog = null;
    activeDraftReview = null;
    activeDraftIntent = null;
  }
}

class FfmAssistantPage {
  const FfmAssistantPage({
    required this.destination,
    required this.name,
    required this.description,
    required this.aliases,
    this.dataSection,
  });

  final FfmAssistantDestination destination;
  final String name;
  final String description;
  final List<String> aliases;
  final FfmAssistantDataSection? dataSection;
}

/// Section dengan data lokal yang dapat diperiksa kelengkapannya secara
/// deterministik. Section lain tetap ada di katalog untuk pertanyaan
/// kemampuan dan isi, tetapi tidak dipaksa memiliki status data yang semu.
enum FfmAssistantDataSection {
  masterData,
  profile,
  budget,
  goals,
  assets,
  liabilities,
  reminders,
  activities,
  transactions,
}

/// Tiga bentuk pertanyaan dasar yang dapat dijawab tanpa membuat draft atau
/// menyentuh data finansial. Pengenalan topik selalu memakai [FfmAssistantCatalog]
/// supaya sinonim tidak tersebar sebagai tambalan di interpreter dan query tool.
enum FfmAssistantBasicQuestionKind { capability, completeness, contents }

class FfmAssistantBasicQuestion {
  const FfmAssistantBasicQuestion({required this.kind, required this.page});

  final FfmAssistantBasicQuestionKind kind;
  final FfmAssistantPage page;
}

class FfmAssistantOtherMenuItem {
  const FfmAssistantOtherMenuItem({
    required this.name,
    required this.description,
    required this.destination,
  });

  final String name;
  final String description;
  final FfmAssistantDestination destination;
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
          'Mencatat pemasukan, pengeluaran, transfer, target, dan impor JSON.',
      aliases: ['transaksi', 'catatan uang', 'uang masuk', 'uang keluar'],
      dataSection: FfmAssistantDataSection.transactions,
    ),
    FfmAssistantPage(
      destination: FfmAssistantDestination.budget,
      name: 'Anggaran',
      description: 'Mengatur batas biaya mingguan atau bulanan.',
      aliases: ['anggaran', 'budget', 'batas belanja'],
      dataSection: FfmAssistantDataSection.budget,
    ),
    FfmAssistantPage(
      destination: FfmAssistantDestination.analysis,
      name: 'Analisa',
      description: 'Membaca pola keuangan dan saran dari data yang tersimpan.',
      aliases: ['analisa', 'analisis', 'insight'],
    ),
    FfmAssistantPage(
      destination: FfmAssistantDestination.otherMenu,
      name: 'Lainnya',
      description: 'Membuka menu fitur pendukung, termasuk Data Utama, cadangan, keamanan, dan Pengetahuan Asisten.',
      aliases: [
        'lainnya',
        'menu lainnya',
        'menu lain',
        'halaman lainnya',
        'fitur lainnya',
        'tab lainnya',
        'navbar lainnya',
      ],
    ),
    FfmAssistantPage(
      destination: FfmAssistantDestination.masterData,
      name: 'Data Utama',
      description: 'Mengelola kategori, toko, tag, rekening, sumber pemasukan, dan keluarga.',
      aliases: ['data utama', 'rekening', 'kategori', 'master data'],
      dataSection: FfmAssistantDataSection.masterData,
    ),
    FfmAssistantPage(
      destination: FfmAssistantDestination.assets,
      name: 'Aset keluarga',
      description: 'Mencatat aset yang ingin dipantau.',
      aliases: ['aset', 'kekayaan'],
      dataSection: FfmAssistantDataSection.assets,
    ),
    FfmAssistantPage(
      destination: FfmAssistantDestination.goals,
      name: 'Target keuangan',
      description: 'Memantau uang yang sedang dikumpulkan.',
      aliases: ['target', 'tujuan keuangan', 'dana target'],
      dataSection: FfmAssistantDataSection.goals,
    ),
    FfmAssistantPage(
      destination: FfmAssistantDestination.liabilities,
      name: 'Hutang & piutang',
      description: 'Mencatat kewajiban dan uang yang masih perlu diterima.',
      aliases: ['hutang', 'utang', 'piutang', 'pinjaman'],
      dataSection: FfmAssistantDataSection.liabilities,
    ),
    FfmAssistantPage(
      destination: FfmAssistantDestination.activity,
      name: 'Aktivitas',
      description: 'Melacak aktivitas harian serta durasinya.',
      aliases: ['aktivitas', 'jurnal', 'kegiatan'],
      dataSection: FfmAssistantDataSection.activities,
    ),
    FfmAssistantPage(
      destination: FfmAssistantDestination.reminders,
      name: 'Pengingat',
      description: 'Membuat pengingat lokal yang tidak boleh terlewat.',
      aliases: ['pengingat', 'reminder', 'alarm'],
      dataSection: FfmAssistantDataSection.reminders,
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
    FfmAssistantPage(
      destination: FfmAssistantDestination.appSecurity,
      name: 'Kunci aplikasi',
      description: 'Mengaktifkan, mengganti, atau mematikan PIN aplikasi.',
      aliases: [
        'kunci aplikasi',
        'keamanan aplikasi',
        'halaman keamanan',
        'keamanan pin',
        'pin keamanan',
        'pin aplikasi',
        'halaman pin',
        'menu pin',
        'ke pin',
        'pergi ke pin',
        'buka pin',
        'ganti pin',
        'ubah pin',
      ],
    ),
    FfmAssistantPage(
      destination: FfmAssistantDestination.diagnostics,
      name: 'Bantuan perbaikan',
      description: 'Melihat error teknis yang benar-benar tercatat dan menyalin laporan aman.',
      aliases: ['bantuan perbaikan', 'laporan error', 'error aplikasi'],
    ),
    FfmAssistantPage(
      destination: FfmAssistantDestination.activityLog,
      name: 'Log aktivitas',
      description: 'Melihat jejak perubahan transaksi, transfer, impor, dan rekonsiliasi.',
      aliases: [
        'log aktivitas',
        'riwayat aktivitas',
        'riwayat perubahan',
        'jejak perubahan',
      ],
    ),
    FfmAssistantPage(
      destination: FfmAssistantDestination.assistantTraining,
      name: 'Pengetahuan Asisten',
      description: 'Mengelola ajaran lokal, alias, pertanyaan belum terjawab, dan contoh belajar yang disetujui.',
      aliases: [
        'pengetahuan asisten',
        'latihan asisten',
        'belajar asisten',
        'ajaran asisten',
      ],
    ),
    FfmAssistantPage(
      destination: FfmAssistantDestination.recurringTransaction,
      name: 'Pemasukan berkala',
      description: 'Mengatur pemasukan atau pengeluaran rutin harian, mingguan, dan bulanan.',
      aliases: [
        'pemasukan berkala',
        'pemasukan rutin',
        'transaksi berkala',
        'transaksi rutin',
      ],
    ),
    FfmAssistantPage(
      destination: FfmAssistantDestination.offlineAdvanced,
      name: 'Alat offline lanjutan',
      description: 'Membuka pemeriksaan lokal, cek saldo, rekonsiliasi, dan alat impor di perangkat.',
      aliases: [
        'alat offline lanjutan',
        'offline lanjutan',
        'pemeriksaan offline',
      ],
    ),
    FfmAssistantPage(
      destination: FfmAssistantDestination.privacyCenter,
      name: 'Pusat privasi',
      description:
          'Melihat lokasi data, enkripsi, izin perangkat, dan kendali ekspor.',
      aliases: ['pusat privasi', 'privasi aplikasi', 'keamanan privasi'],
    ),
    FfmAssistantPage(
      destination: FfmAssistantDestination.databaseStructure,
      name: 'Struktur database',
      description: 'Melihat tabel dan gambaran struktur database lokal FFM.',
      aliases: ['struktur database', 'struktur basis data', 'tabel database'],
    ),
    FfmAssistantPage(
      destination: FfmAssistantDestination.offlineFeatures,
      name: 'Fitur tanpa internet',
      description:
          'Membaca panduan teknologi dan fitur yang berjalan tanpa internet.',
      aliases: [
        'fitur tanpa internet',
        'fitur offline',
        'mode offline',
        'bisa tanpa internet',
      ],
    ),
    FfmAssistantPage(
      destination: FfmAssistantDestination.assistantProfile,
      name: 'Profil Personalisasi Asisten',
      description: 'Mengenalkan diri, serta mengelola ekspor dan impor profil personalisasi terenkripsi.',
      aliases: [
        'profil',
        'profil saya',
        'identitas',
        'kenalkan diri',
        'personalisasi',
      ],
      dataSection: FfmAssistantDataSection.profile,
    ),
    FfmAssistantPage(
      destination: FfmAssistantDestination.localModel,
      name: 'Model Asisten Lokal',
      description: 'Mengunduh, mengimpor, memverifikasi, atau membagikan bundle SLM lokal.',
      aliases: [
        'model asisten lokal',
        'model lokal',
        'slm lokal',
        'qwen lokal',
        'qwen2-vl',
      ],
    ),
  ];

  static const otherMenuItems = <FfmAssistantOtherMenuItem>[
    FfmAssistantOtherMenuItem(
      name: 'Data Utama',
      description: 'Mengisi kategori, toko, tag, rekening, dan sumber pemasukan untuk pilihan transaksi.',
      destination: FfmAssistantDestination.masterData,
    ),
    FfmAssistantOtherMenuItem(
      name: 'Aset keluarga',
      description:
          'Mencatat barang atau kekayaan keluarga yang ingin dipantau.',
      destination: FfmAssistantDestination.assets,
    ),
    FfmAssistantOtherMenuItem(
      name: 'Target keuangan',
      description:
          'Memantau uang yang ingin dikumpulkan sampai batas waktu tertentu.',
      destination: FfmAssistantDestination.goals,
    ),
    FfmAssistantOtherMenuItem(
      name: 'Hutang & piutang',
      description:
          'Mengelola kewajiban dan uang yang masih perlu diterima keluarga.',
      destination: FfmAssistantDestination.liabilities,
    ),
    FfmAssistantOtherMenuItem(
      name: 'Ekspor & cadangan',
      description:
          'Membuat JSON, CSV, HTML, PDF, atau memulihkan data dari berkas.',
      destination: FfmAssistantDestination.backup,
    ),
    FfmAssistantOtherMenuItem(
      name: 'Ringkasan bulanan',
      description:
          'Membandingkan arus kas, kesehatan keuangan, dan laporan per bulan.',
      destination: FfmAssistantDestination.monthlyReport,
    ),
    FfmAssistantOtherMenuItem(
      name: 'Log aktivitas',
      description: 'Melihat jejak perubahan transaksi, transfer, impor, dan rekonsiliasi.',
      destination: FfmAssistantDestination.activityLog,
    ),
    FfmAssistantOtherMenuItem(
      name: 'Pengetahuan Asisten',
      description: 'Mengajarkan istilah, jawaban fitur, dan kebiasaan lokal secara eksplisit.',
      destination: FfmAssistantDestination.assistantTraining,
    ),
    FfmAssistantOtherMenuItem(
      name: 'Pengingat',
      description:
          'Membuat pengingat lokal untuk hal yang tidak boleh terlupakan.',
      destination: FfmAssistantDestination.reminders,
    ),
    FfmAssistantOtherMenuItem(
      name: 'Pemasukan berkala',
      description:
          'Mengatur pemasukan atau biaya rutin harian, mingguan, dan bulanan.',
      destination: FfmAssistantDestination.recurringTransaction,
    ),
    FfmAssistantOtherMenuItem(
      name: 'Alat offline lanjutan',
      description: 'Mengecek saldo, rekonsiliasi, impor data, dan pemeriksaan lokal di perangkat.',
      destination: FfmAssistantDestination.offlineAdvanced,
    ),
    FfmAssistantOtherMenuItem(
      name: 'Kunci aplikasi',
      description:
          'Mengatur PIN untuk membantu menjaga akses ke data keluarga.',
      destination: FfmAssistantDestination.appSecurity,
    ),
    FfmAssistantOtherMenuItem(
      name: 'Bantuan perbaikan',
      description: 'Melihat error teknis lokal dan menyalin laporan yang sudah disaring.',
      destination: FfmAssistantDestination.diagnostics,
    ),
    FfmAssistantOtherMenuItem(
      name: 'Pusat privasi',
      description:
          'Melihat lokasi data, enkripsi, izin perangkat, dan kendali ekspor.',
      destination: FfmAssistantDestination.privacyCenter,
    ),
    FfmAssistantOtherMenuItem(
      name: 'Struktur database',
      description: 'Melihat tabel dan gambaran isi database lokal FFM.',
      destination: FfmAssistantDestination.databaseStructure,
    ),
    FfmAssistantOtherMenuItem(
      name: 'Fitur tanpa internet',
      description:
          'Membaca panduan lengkap tentang teknologi offline yang tersedia.',
      destination: FfmAssistantDestination.offlineFeatures,
    ),
    FfmAssistantOtherMenuItem(
      name: 'Model Asisten Lokal',
      description: 'Mengunduh SLM dari GitHub atau mengimpor bundle offline yang sudah diverifikasi.',
      destination: FfmAssistantDestination.localModel,
    ),
  ];

  static String listOtherMenuForChat() => otherMenuItems
      .asMap()
      .entries
      .map(
        (entry) =>
            '${entry.key + 1}. ${entry.value.name} — ${entry.value.description}',
      )
      .join('\\n');

  static FfmAssistantPage? findByText(String normalizedText) {
    FfmAssistantPage? best;
    var bestScore = 0;
    for (final page in pages) {
      for (final alias in page.aliases) {
        if (normalizedText.contains(alias.toLowerCase()) &&
            alias.length > bestScore) {
          best = page;
          bestScore = alias.length;
        }
      }
    }
    return best;
  }

  static FfmAssistantPage? findByDestination(
    FfmAssistantDestination destination,
  ) {
    for (final page in pages) {
      if (page.destination == destination) return page;
    }
    return null;
  }

  static FfmAssistantBasicQuestion? classifyBasicQuestion(
    String normalizedText,
  ) {
    final page = findByText(normalizedText);
    if (page == null) return null;
    if (RegExp(r'\b(lengkap|kelengkapan|terisi|diisi)\b')
        .hasMatch(normalizedText)) {
      return FfmAssistantBasicQuestion(
        kind: FfmAssistantBasicQuestionKind.completeness,
        page: page,
      );
    }
    final asksContents =
        normalizedText.contains('ada apa saja') ||
        normalizedText.contains('apa saja di') ||
        normalizedText.contains('apa isi') ||
        normalizedText.contains('isinya apa') ||
        normalizedText.startsWith('daftar ') ||
        normalizedText.contains('daftar isi') ||
        normalizedText.contains('fitur apa saja');
    if (asksContents) {
      return FfmAssistantBasicQuestion(
        kind: FfmAssistantBasicQuestionKind.contents,
        page: page,
      );
    }
    final asksCapability = RegExp(r'\b(bisa|bisakah|mampu|dapat)\b')
        .hasMatch(normalizedText);
    if (asksCapability) {
      return FfmAssistantBasicQuestion(
        kind: FfmAssistantBasicQuestionKind.capability,
        page: page,
      );
    }
    return null;
  }

  static String answerBasicQuestion(
    FfmAssistantBasicQuestion question,
  ) => switch (question.kind) {
    FfmAssistantBasicQuestionKind.capability =>
      'Ya. ${question.page.name} bisa digunakan untuk ${question.page.description.toLowerCase()} Cara pakainya: buka ${question.page.name}, periksa pilihan yang tersedia, lalu simpan hanya setelah kamu setuju.',
    FfmAssistantBasicQuestionKind.contents =>
      question.page.destination == FfmAssistantDestination.otherMenu
          ? 'Menu Lainnya berisi:\n${listOtherMenuForChat()}'
          : '${question.page.name} berisi: ${detailFor(question.page.destination)}',
    FfmAssistantBasicQuestionKind.completeness =>
      question.page.dataSection == null
          ? '${question.page.name} bukan section data yang memiliki status lengkap/belum lengkap. ${question.page.description} Kamu bisa membuka halamannya untuk memeriksa pengaturan atau hasil terakhir yang tersedia.'
          : 'Kelengkapan ${question.page.name} akan dicek dari data lokal yang relevan.',
  };

  static String listForChat() =>
      pages.map((page) => '• ${page.name} — ${page.description}').join('\n');

  static String detailFor(FfmAssistantDestination destination) =>
      switch (destination) {
        FfmAssistantDestination.summary => 'Ringkasan adalah beranda kondisi keuangan. Di sini kamu bisa lihat saldo yang tercatat, arus pemasukan/pengeluaran, grafik, dan pintasan ke bagian penting. Angkanya hanya berasal dari data yang memang sudah kamu simpan.',
        FfmAssistantDestination.transactions => 'Transaksi dipakai untuk catat pemasukan, pengeluaran, transfer antar rekening, setor atau pakai target, input cepat, serta impor JSON. Transfer hanya memindahkan saldo; biaya adminnya dicatat sebagai pengeluaran terpisah.',
        FfmAssistantDestination.budget => 'Anggaran berisi batas total mingguan atau bulanan, target kategori yang opsional, dan mode Tidak Rutin untuk kebutuhan yang tidak dibeli rutin. Anggaran memantau pengeluaran yang tersimpan; tidak bergantung pada pemasukan.',
        FfmAssistantDestination.analysis => 'Analisa membaca transaksi nyata yang sudah tersimpan untuk melihat pola pemasukan, pengeluaran, dan anggaran. Kalau datanya masih kosong, Asisten akan bilang belum ada cukup data—tidak membuat angka sendiri.',
        FfmAssistantDestination.masterData => 'Data Utama berisi enam bagian: Rekening atau Tunai untuk sumber saldo, Kategori pemasukan/pengeluaran, Toko atau pihak, Tag untuk penanda tambahan, Sumber pemasukan, dan Profil keluarga. Bagian ini adalah bahan pilihan saat kamu mengisi transaksi; semua bisa ditambah, diedit, atau diarsipkan.',
        FfmAssistantDestination.assets => 'Aset keluarga dipakai untuk mencatat barang atau kepemilikan bernilai yang ingin dipantau, misalnya kebun, kendaraan, alat kerja, atau tabungan khusus. Aset bukan transaksi harian dan tidak otomatis mengubah saldo rekening.',
        FfmAssistantDestination.goals => 'Target keuangan dipakai untuk uang yang sedang dikumpulkan dengan tujuan tertentu. Kamu bisa setor ke target atau memakai uang target; keduanya dicatat terpisah agar progres target tetap jelas.',
        FfmAssistantDestination.liabilities => 'Hutang & piutang mencatat uang yang kamu pinjam atau uang yang harus diterima dari orang lain. Kamu bisa melihat sisa, membuat strategi pelunasan, dan mengarsipkan catatan yang selesai tanpa menghapus riwayat finansial.',
        FfmAssistantDestination.activity => 'Aktivitas melacak kegiatan harian dan lama waktunya. Beberapa aktivitas dapat aktif bersamaan; pembaruan atau selesai pada satu aktivitas tidak otomatis menutup aktivitas lain.',
        FfmAssistantDestination.reminders => 'Pengingat membuat alarm lokal untuk hal yang perlu dilakukan. Kamu dapat menunda, menyelesaikan, atau melihat riwayat tanpa mengubah transaksi keuangan.',
        FfmAssistantDestination.backup => 'Ekspor & cadangan dipakai untuk membuat atau memulihkan data FFM, termasuk data utama, transaksi, aset, target, hutang/piutang, aktivitas, pengingat, memori ajar, dan contoh belajar. Periksa preview sebelum impor.',
        FfmAssistantDestination.monthlyReport => 'Ringkasan bulanan membandingkan pemasukan, pengeluaran, dan arus kas berdasarkan periode yang kamu pilih. Laporan hanya menampilkan catatan nyata yang ada di perangkat.',
        FfmAssistantDestination.reconciliation => 'Rekonsiliasi saldo membantu mencocokkan saldo catatan FFM dengan saldo nyata di rekening atau tunai. Bila ada selisih, kamu dapat meninjau penyebabnya lalu buat penyesuaian secara sadar.',
        FfmAssistantDestination.appSecurity => 'Kunci aplikasi dipakai untuk mengaktifkan, mengganti, atau mematikan PIN FFM. PIN hanya dimasukkan lewat keypad khusus, tidak lewat chat, dan setiap perubahan meminta konfirmasi kamu.',
        FfmAssistantDestination.diagnostics => 'Bantuan perbaikan menampilkan error teknis yang benar-benar tertangkap secara lokal. Kamu bisa salin laporan yang sudah disaring; PIN, data keuangan, rekening, dan isi chat tidak ikut dimasukkan.',
        FfmAssistantDestination.activityLog => 'Log aktivitas menampilkan jejak perubahan lokal, termasuk transaksi, transfer, impor, dan rekonsiliasi.',
        FfmAssistantDestination.assistantTraining => 'Pengetahuan Asisten mengelola alias, ajaran lokal, pertanyaan belum terjawab, dan contoh belajar yang harus disetujui sebelum disimpan.',
        FfmAssistantDestination.recurringTransaction => 'Pemasukan berkala mengatur aturan pemasukan atau pengeluaran rutin harian, mingguan, atau bulanan. Penyimpanan dan perubahan aturan tetap dilakukan lewat form.',
        FfmAssistantDestination.offlineAdvanced => 'Alat offline lanjutan menyediakan pemeriksaan lokal, cek saldo, rekonsiliasi, dan alat impor yang berjalan di perangkat.',
        FfmAssistantDestination.privacyCenter => 'Pusat privasi menjelaskan lokasi data, enkripsi, izin perangkat, serta kendali ekspor dan penghapusan.',
        FfmAssistantDestination.databaseStructure => 'Struktur database memperlihatkan tabel dan gambaran database lokal FFM tanpa memberi model akses langsung ke database.',
        FfmAssistantDestination.offlineFeatures => 'Fitur tanpa internet menjelaskan bagian FFM yang tetap berjalan lokal, termasuk database, Asisten aturan, dan setup SLM setelah model tersedia.',
        FfmAssistantDestination.localModel => 'Model Asisten Lokal dipakai untuk mengunduh dari GitHub, mengimpor bundle offline, memverifikasi, menghapus, atau membagikan bundle SLM.',
        FfmAssistantDestination.assistantProfile => 'Profil Personalisasi Asisten menyimpan identitas, pekerjaan, rutinitas, dan preferensi untuk membantu asisten menjawab lebih relevan tanpa mengirim data transaksi mentah. Kamu juga bisa ekspor atau impor profil di sini.',
        FfmAssistantDestination.otherMenu => 'Lainnya berisi jalan ke fitur pendukung seperti Data Utama, aset, target, hutang & piutang, aktivitas, pengingat, laporan, cadangan, dan Pengetahuan Asisten.',
      };
}
