/// Fondasi Asisten FFM Lokal: semua aksi keuangan tetap berupa draft sampai
import '../../activity/domain/activity_voice.dart';

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

  FfmAssistantIntent copyWith({
    FfmAssistantDraft? draft,
    String? response,
    String? clarification,
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
  });

  final bool isUser;
  final String text;
  final FfmAssistantIntent? intent;
  final ActivityVoiceIntent? activityIntent;
  final String? understanding;
  final FfmAssistantDraftReview? review;
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
  FfmAssistantDraftReview? activeDraftReview;
  FfmAssistantIntent? activeDraftIntent;

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
          'Mencatat pemasukan, pengeluaran, transfer, target, dan impor JSON.',
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
    FfmAssistantPage(
      destination: FfmAssistantDestination.appSecurity,
      name: 'Kunci aplikasi',
      description: 'Mengaktifkan, mengganti, atau mematikan PIN aplikasi.',
      aliases: ['kunci aplikasi', 'pin aplikasi', 'ganti pin', 'ubah pin'],
    ),
    FfmAssistantPage(
      destination: FfmAssistantDestination.diagnostics,
      name: 'Bantuan perbaikan',
      description: 'Melihat error teknis yang benar-benar tercatat dan menyalin laporan aman.',
      aliases: ['bantuan perbaikan', 'laporan error', 'error aplikasi'],
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
        FfmAssistantDestination.otherMenu => 'Lainnya berisi jalan ke fitur pendukung seperti Data Utama, aset, target, hutang & piutang, aktivitas, pengingat, laporan, cadangan, dan Pusat Latihan Asisten.',
      };
}
