/// Fondasi Asisten FFM Lokal: semua aksi keuangan tetap berupa draft sampai
/// pengguna melihat preview dan mengonfirmasinya.
library;

import '../../activity/domain/activity_voice.dart';

enum FfmAssistantResponseMode { localRules }

enum FfmAssistantRoutingMode { agent, geminiCloud }

enum FfmAssistantResponseOrigin {
  agentOrchestrator,
  localFallback,
  geminiCloud,
  cloudError,
}

class FfmAssistantProcessEvent {
  const FfmAssistantProcessEvent({
    required this.label,
    required this.elapsed,
    this.detail,
  });

  final String label;
  final Duration elapsed;
  final String? detail;
}

class FfmAssistantProcessTrace {
  const FfmAssistantProcessTrace({
    required this.origin,
    required this.elapsed,
    required this.events,
    this.fallbackReason,
    this.pluginName,
    this.pluginCategory,
    this.tokenUsage,
  });

  final FfmAssistantResponseOrigin origin;
  final Duration elapsed;
  final List<FfmAssistantProcessEvent> events;
  final String? fallbackReason;

  /// Nama plugin harness yang menghasilkan jawaban ini, jika ada.
  /// Contoh: 'receivable_sense', 'emergency_fund_logic'.
  final String? pluginName;

  /// Label tampilan ramah pengguna untuk kategori plugin.
  /// Contoh: '👁️ Sense', '🧮 Logic', '✋ Actuator'.
  final String? pluginCategory;

  /// Konsumsi token (promptTokenCount, candidatesTokenCount, totalTokenCount) jika ada.
  final Map<String, dynamic>? tokenUsage;
}

enum FfmAssistantIntentType {
  changeTheme,
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
  createLiabilityPayment,
  updateLiability,
  archiveLiability,
  createReceivable,
  createReceivablePayment,
  updateReceivable,
  archiveReceivable,
  createAsset,
  updateAsset,
  archiveAsset,
  createBudget,
  createCashFlowProfile,
  createMasterData,
  createTag,
  editDraft,
  reviseDraft,
  updateMerchant,
  archiveMerchant,
  deleteMerchant,
  updateTag,
  archiveTag,
  deleteTag,
  updateIncomeSource,
  archiveIncomeSource,
  deleteIncomeSource,
  updateCategory,
  archiveCategory,
  deleteCategory,
  updateAccount,
  archiveAccount,
  deleteAccount,
  updateBudget,
  archiveBudget,
  createReminder,
  updateReminder,
  archiveReminder,
  createActivity,
  createDailyNote,
  archiveDailyNote,
  createTask,
  updateTask,
  completeTask,
  reopenTask,
  archiveTask,
  createRoutine,
  updateRoutine,
  markRoutineComplete,
  unmarkRoutineComplete,
  activateRoutine,
  deactivateRoutine,
  archiveRoutine,
  createSchedule,
  updateSchedule,
  archiveSchedule,
  updateRecurringTransaction,
  archiveRecurringTransaction,
  updateGoal,
  archiveGoal,
  updateTransaction,
  archiveTransaction,
  deleteTransaction,
  archiveActivity,
  deleteActivity,
  finishActivity,
  updateActivity,
  editActivity,
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
  familyProfile,
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
  recurringTransaction,
  privacyCenter,
  databaseStructure,
  assistantProfile,
  intelligenceDashboard,
  paymentDetector,
  telegramSetup,
  agentInbox,
  autonomyMonitor,
  hijriSettings,
  calendarSettings,
  marketNewsRadar,
  utilityMeter,
}

enum FfmAssistantDraftKind {
  income,
  expense,
  transfer,
  goalDeposit,
  goalUsage,
  goal,
  liability,
  liabilityUpdate,
  liabilityArchive,
  liabilityPayment,
  receivable,
  receivableUpdate,
  receivableArchive,
  receivablePayment,
  asset,
  assetUpdate,
  assetArchive,
  budget,
  budgetUpdate,
  budgetArchive,
  cashFlowProfile,
  masterData,
  merchantUpdate,
  merchantArchive,
  merchantDelete,
  tagUpdate,
  tagArchive,
  tagDelete,
  incomeSourceUpdate,
  incomeSourceArchive,
  incomeSourceDelete,
  categoryUpdate,
  categoryArchive,
  categoryDelete,
  accountUpdate,
  accountArchive,
  accountDelete,
  reminder,
  reminderUpdate,
  reminderArchive,
  activity,
  dailyNote,
  dailyNoteArchive,
  task,
  taskUpdate,
  taskComplete,
  taskReopen,
  taskArchive,
  routine,
  routineUpdate,
  routineMarkComplete,
  routineUnmarkComplete,
  routineActivate,
  routineDeactivate,
  routineArchive,
  schedule,
  scheduleUpdate,
  scheduleArchive,
  recurringTransactionUpdate,
  recurringTransactionArchive,
  profile,
  goalUpdate,
  goalArchive,
  transactionUpdate,
  transactionArchive,
  transactionDelete,
  activityArchive,
  activityDelete,
  activityFinish,
  activityUpdate,
  activityEdit,
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
    this.review,
    this.confidence = 0,
    this.clarification,
    this.response,
    this.teachingProposal,
    this.responseMode = FfmAssistantResponseMode.localRules,
    this.responseOrigin = FfmAssistantResponseOrigin.agentOrchestrator,
    this.pluginName,
    this.pluginCategory,
    this.pluginMetadata,
    this.verifiedFacts,
    this.analysisResults,
  });

  final String rawText;
  final String normalizedText;
  final FfmAssistantIntentType type;
  final FfmAssistantDestination? destination;
  final FfmAssistantDraft? draft;
  final FfmAssistantDraftReview? review;
  final double confidence;
  final String? clarification;
  final String? response;
  final FfmAssistantTeachingProposal? teachingProposal;
  final FfmAssistantResponseMode responseMode;
  final FfmAssistantResponseOrigin responseOrigin;

  /// Nama plugin harness yang menangani intent ini, misal 'receivable_sense'.
  final String? pluginName;

  /// Label kategori plugin yang ditampilkan di UI, misal '👁️ Sense' atau '🧮 Logic'.
  final String? pluginCategory;

  /// Metadata terstruktur tambahan dari plugin harness (contoh: payload rekap/aktivitas live).
  final Map<String, dynamic>? pluginMetadata;

  /// Verified facts dari database untuk grounding response
  final String? verifiedFacts;

  /// Analysis results dari analysis engine
  final String? analysisResults;

  bool get needsClarification => clarification != null;
  bool get needsConfirmation => draft != null && !needsClarification;
  bool get needsTeachingApproval => teachingProposal != null;

  FfmAssistantIntent copyWith({
    FfmAssistantDestination? destination,
    FfmAssistantDraft? draft,
    FfmAssistantDraftReview? review,
    String? response,
    String? clarification,
    FfmAssistantResponseMode? responseMode,
    FfmAssistantResponseOrigin? responseOrigin,
    String? pluginName,
    String? pluginCategory,
    Map<String, dynamic>? pluginMetadata,
    String? verifiedFacts,
    String? analysisResults,
  }) => FfmAssistantIntent(
    rawText: rawText,
    normalizedText: normalizedText,
    type: type,
    destination: destination ?? this.destination,
    draft: draft ?? this.draft,
    review: review ?? this.review,
    confidence: confidence,
    clarification: clarification ?? this.clarification,
    response: response ?? this.response,
    teachingProposal: teachingProposal,
    responseMode: responseMode ?? this.responseMode,
    responseOrigin: responseOrigin ?? this.responseOrigin,
    pluginName: pluginName ?? this.pluginName,
    pluginCategory: pluginCategory ?? this.pluginCategory,
    pluginMetadata: pluginMetadata ?? this.pluginMetadata,
    verifiedFacts: verifiedFacts ?? this.verifiedFacts,
    analysisResults: analysisResults ?? this.analysisResults,
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
    this.linkedActivityId,
    this.formValues = const <String, String>{},
    this.merchantName,
    this.location,
    this.slmFieldValues = const <String, String>{},
    this.metadata,
    this.commodityOrBusinessType,
    this.targetHarvestDate,
    this.initialCapital,
    this.estimatedInflow,
    this.dailyLivingBudget,
    this.dailyOperationalBudget,
    this.cycleProfileType,
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
  final String? linkedActivityId;
  final Map<String, String> formValues;

  /// Merchant dan nilai field yang berasal dari tebakan awal SLM/rule parser.
  /// Hanya dipakai untuk pembelajaran setelah user mengonfirmasi form.
  final String? merchantName;
  final String? location;
  final Map<String, String> slmFieldValues;

  /// Metadata tambahan untuk integrasi spesifik (misal: calendar sync)
  final Map<String, dynamic>? metadata;

  /// Field khusus untuk Siklus Kas / AgroTrack
  final String? commodityOrBusinessType;
  final DateTime? targetHarvestDate;
  final int? initialCapital;
  final int? estimatedInflow;
  final int? dailyLivingBudget;
  final int? dailyOperationalBudget;
  final String? cycleProfileType;

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
    String? linkedActivityId,
    Map<String, String>? formValues,
    String? merchantName,
    String? location,
    Map<String, String>? slmFieldValues,
    Map<String, dynamic>? metadata,
    String? commodityOrBusinessType,
    DateTime? targetHarvestDate,
    int? initialCapital,
    int? estimatedInflow,
    int? dailyLivingBudget,
    int? dailyOperationalBudget,
    String? cycleProfileType,
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
    linkedActivityId: linkedActivityId ?? this.linkedActivityId,
    formValues: formValues ?? this.formValues,
    merchantName: merchantName ?? this.merchantName,
    location: location ?? this.location,
    slmFieldValues: slmFieldValues ?? this.slmFieldValues,
    metadata: metadata ?? this.metadata,
    commodityOrBusinessType:
        commodityOrBusinessType ?? this.commodityOrBusinessType,
    targetHarvestDate: targetHarvestDate ?? this.targetHarvestDate,
    initialCapital: initialCapital ?? this.initialCapital,
    estimatedInflow: estimatedInflow ?? this.estimatedInflow,
    dailyLivingBudget: dailyLivingBudget ?? this.dailyLivingBudget,
    dailyOperationalBudget:
        dailyOperationalBudget ?? this.dailyOperationalBudget,
    cycleProfileType: cycleProfileType ?? this.cycleProfileType,
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
    this.filePath,
    this.fileFormat,
    this.processTrace,
    this.createdAt,
    this.verifiedFacts,
    this.analysisResults,
    this.feedbackType,
    this.feedbackCategory,
    this.sentAt,
    this.receivedAt,
    this.modelUsed,
    this.absorbedMemory,
  });

  final bool isUser;
  final String text;
  final FfmAssistantIntent? intent;
  final ActivityVoiceIntent? activityIntent;
  final String? understanding;
  final FfmAssistantDraftReview? review;
  final String? filePath;
  final String? fileFormat;
  final FfmAssistantProcessTrace? processTrace;
  final DateTime? createdAt;
  final String? verifiedFacts;
  final String? analysisResults;
  final String? feedbackType;
  final String? feedbackCategory;

  /// Waktu user/assistant mengirim pesan. Fallback ke [createdAt] untuk data lama.
  final DateTime? sentAt;

  /// Waktu jawaban asisten diterima/ditampilkan. Bermakna untuk pesan bot.
  final DateTime? receivedAt;

  /// Id human-readable model/alur pembuat jawaban (mis. 'gemini-cloud',
  /// 'agent', atau 'local'). Fallback dapat diturunkan dari [processTrace].
  final String? modelUsed;

  /// Fakta/pola memori personal yang diserap asisten dari pesan ini.
  final String? absorbedMemory;
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

/// Menyimpan state draft transaksi yang sedang disusun antar giliran.
/// Expire setelah [_expiresAt] (default 5 menit).
class FfmAssistantPendingDraft {
  FfmAssistantPendingDraft({
    required this.type,
    this.amount,
    this.accountName,
    this.categoryName,
    this.toAccountName,
    this.merchantName,
    this.note,
    DateTime? createdAt,
    Duration expiry = const Duration(minutes: 5),
  }) : createdAt = createdAt ?? DateTime.now(),
       _expiresAt = (createdAt ?? DateTime.now()).add(expiry);

  final String type; // 'income', 'expense', 'transfer'
  int? amount;
  String? accountName;
  String? categoryName;
  String? toAccountName;
  String? merchantName;
  String? note;
  final DateTime createdAt;
  final DateTime _expiresAt;

  bool get isExpired => DateTime.now().isAfter(_expiresAt);
  bool get isComplete {
    if (type == 'transfer') {
      return amount != null && accountName != null && toAccountName != null;
    }
    if (type == 'income') {
      return amount != null && accountName != null;
    }
    return amount != null && categoryName != null;
  }

  List<String> get missingFields {
    final missing = <String>[];
    if (amount == null) missing.add('nominal');
    if (type == 'expense' && categoryName == null) missing.add('kategori');
    if (accountName == null) missing.add('sumber dana/akun');
    if (type == 'transfer' && toAccountName == null) {
      missing.add('rekening tujuan');
    }
    return missing;
  }

  void fillFromAnswer(
    String answer, {
    List<String> accountNames = const [],
    List<String> categoryNames = const [],
  }) {
    final lower = answer.toLowerCase().trim();
    for (final name in accountNames) {
      if (lower.contains(name.toLowerCase())) {
        accountName ??= name;
        if (type == 'transfer' &&
            toAccountName == null &&
            accountName != name) {
          toAccountName = name;
        }
      }
    }
    for (final name in categoryNames) {
      if (lower.contains(name.toLowerCase()) && categoryName == null) {
        categoryName = name;
      }
    }
  }

  FfmAssistantDraft toDraft() => FfmAssistantDraft(
    kind: switch (type) {
      'income' => FfmAssistantDraftKind.income,
      'transfer' => FfmAssistantDraftKind.transfer,
      _ => FfmAssistantDraftKind.expense,
    },
    createdAt: createdAt,
    date: createdAt,
    title: merchantName,
    amount: amount,
    categoryName: categoryName,
    fromAccountName: accountName,
    toAccountName: toAccountName,
    note: note,
  );
}

/// Status sementara satu draft di percakapan. Tidak pernah berarti data sudah
/// tersimpan; status selesai hanya boleh ditetapkan oleh hasil form resmi.
enum FfmAssistantDraftQueueStatus {
  ready,
  needsClarification,
  openingForm,
  cancelled,
  completed,
}

/// Item antrean draft yang terisolasi dalam satu sesi chat.
class FfmAssistantDraftQueueItem {
  const FfmAssistantDraftQueueItem({
    required this.id,
    required this.intent,
    required this.review,
    required this.targetDestination,
    required this.createdAt,
    required this.status,
    this.knownFieldCount = 0,
    this.missingFields = const <String>[],
    this.warningCount = 0,
  });

  final String id;
  final FfmAssistantIntent intent;
  final FfmAssistantDraftReview review;
  final FfmAssistantDestination? targetDestination;
  final DateTime createdAt;
  final FfmAssistantDraftQueueStatus status;
  final int knownFieldCount;
  final List<String> missingFields;
  final int warningCount;

  bool get canOpen =>
      status == FfmAssistantDraftQueueStatus.ready && review.canContinue;

  FfmAssistantDraftQueueItem copyWith({
    FfmAssistantIntent? intent,
    FfmAssistantDraftReview? review,
    FfmAssistantDestination? targetDestination,
    FfmAssistantDraftQueueStatus? status,
    int? knownFieldCount,
    List<String>? missingFields,
    int? warningCount,
  }) => FfmAssistantDraftQueueItem(
    id: id,
    intent: intent ?? this.intent,
    review: review ?? this.review,
    targetDestination: targetDestination ?? this.targetDestination,
    createdAt: createdAt,
    status: status ?? this.status,
    knownFieldCount: knownFieldCount ?? this.knownFieldCount,
    missingFields: missingFields ?? this.missingFields,
    warningCount: warningCount ?? this.warningCount,
  );
}

class FfmAssistantChatSession {
  FfmAssistantChatSession()
    : entries = [
        const FfmAssistantChatEntry(
          isUser: false,
          text: 'Halo! Ketik saja perintahmu.',
        ),
      ];

  final List<FfmAssistantChatEntry> entries;
  final List<FfmAssistantIntent> queuedIntents = [];
  final List<FfmAssistantDraftQueueItem> draftQueue = [];
  String? lastAssistantText;
  FfmAssistantPendingDialog? pendingDialog;
  FfmAssistantDraftReview? activeDraftReview;
  FfmAssistantIntent? activeDraftIntent;
  String? activeDraftQueueId;
  FfmAssistantPendingDraft? pendingDraft;

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
    draftQueue.clear();
    lastAssistantText = null;
    pendingDialog = null;
    activeDraftReview = null;
    activeDraftIntent = null;
    activeDraftQueueId = null;
    pendingDraft = null;
  }

  void addEntry(FfmAssistantChatEntry entry) {
    entries.add(entry);
  }

  void updateEntryWithFeedback(int index, String feedbackType, String? feedbackCategory) {
    if (index >= 0 && index < entries.length) {
      final entry = entries[index];
      entries[index] = FfmAssistantChatEntry(
        isUser: entry.isUser,
        text: entry.text,
        intent: entry.intent,
        activityIntent: entry.activityIntent,
        understanding: entry.understanding,
        review: entry.review,
        filePath: entry.filePath,
        fileFormat: entry.fileFormat,
        processTrace: entry.processTrace,
        createdAt: entry.createdAt,
        verifiedFacts: entry.verifiedFacts,
        analysisResults: entry.analysisResults,
        feedbackType: feedbackType,
        feedbackCategory: feedbackCategory,
        sentAt: entry.sentAt,
        receivedAt: entry.receivedAt,
        modelUsed: entry.modelUsed,
      );
    }
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
      description: 'Mengelola kategori, toko, tag, rekening, dan sumber pemasukan.',
      aliases: ['data utama', 'rekening', 'kategori', 'master data'],
      dataSection: FfmAssistantDataSection.masterData,
    ),
    FfmAssistantPage(
      destination: FfmAssistantDestination.familyProfile,
      name: 'Profil Keluarga',
      description: 'Mengisi profil keluarga dan data pribadi yang membantu Asisten memahami keluargamu.',
      aliases: [
        'profil keluarga',
        'data keluarga',
        'profil rumah tangga',
        'isi nama keluarga',
      ],
      dataSection: FfmAssistantDataSection.profile,
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
      description: 'Melacak aktivitas harian berdurasi serta mengelola Catatan Harian, Tugas, Rutinitas, dan Jadwal secara terpisah.',
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
      destination: FfmAssistantDestination.intelligenceDashboard,
      name: 'Intelligence Dashboard',
      description: 'Mengatur koneksi memori cloud Supabase dan Gemini Cloud.',
      aliases: [
        'intelligence dashboard',
        'dashboard kecerdasan',
        'cloud brain',
        'supabase',
        'gemini',
      ],
    ),
    FfmAssistantPage(
      destination: FfmAssistantDestination.paymentDetector,
      name: 'Pendeteksi Notifikasi Pembayaran',
      description: 'Mendeteksi otomatis pembayaran dan transfer dari aplikasi bank dan e-wallet.',
      aliases: [
        'deteksi notifikasi',
        'pendeteksi notifikasi',
        'notifikasi pembayaran',
        'deteksi pembayaran',
        'deteksi otomatis',
        'notifikasi bank',
        'notifikasi gopay',
        'notifikasi seabank',
        'pendeteksi bayar otomatis',
        'deteksi bayar',
        'qris',
      ],
    ),
    FfmAssistantPage(
      destination: FfmAssistantDestination.telegramSetup,
      name: 'Telegram Bot Keluarga',
      description: 'Mengatur bot Telegram keluarga untuk laporan mingguan dan alarm boncos.',
      aliases: [
        'telegram',
        'bot telegram',
        'halaman telegram',
        'telegram setup',
        'bot keluarga',
        'integrasi telegram',
        'setting telegram',
        'pengaturan telegram',
        'telegram bot',
      ],
    ),
    FfmAssistantPage(
      destination: FfmAssistantDestination.agentInbox,
      name: 'Laporan & Kotak Masuk Asisten',
      description: 'Melihat rekomendasi proaktif, deteksi runway, dan anomali belanja.',
      aliases: [
        'inbox',
        'inbox agent',
        'kotak masuk',
        'kotak masuk asisten',
        'laporan asisten',
        'inbox asisten',
        'rekomendasi proaktif',
        'agent inbox',
      ],
    ),
    FfmAssistantPage(
      destination: FfmAssistantDestination.autonomyMonitor,
      name: 'Monitoring Agent',
      description: 'Memeriksa riwayat run dan eksekusi tool Agent secara read-only.',
      aliases: [
        'monitoring agent',
        'monitor agent',
        'autonomy monitor',
        'riwayat tool',
        'eksekusi agent',
        'autonomous agent',
        'monitor otonomi',
        'otonomi',
      ],
    ),
    FfmAssistantPage(
      destination: FfmAssistantDestination.hijriSettings,
      name: 'Kalender Hijriah & Hilal',
      description: 'Mengatur koreksi Hilal dan penetapan awal bulan Hijriah.',
      aliases: [
        'kalender hijriah',
        'hijriah',
        'hilal',
        'pengaturan hijriah',
        'rukyat hilal',
        'isbat',
      ],
    ),
    FfmAssistantPage(
      destination: FfmAssistantDestination.calendarSettings,
      name: 'Kalender & Smartwatch',
      description: 'Sinkronisasi tagihan ke Google Calendar dan jam tangan pintar.',
      aliases: [
        'kalender smartwatch',
        'google calendar',
        'sinkronisasi kalender',
        'smartwatch',
        'jam tangan pintar',
        'kalender',
      ],
    ),
    FfmAssistantPage(
      destination: FfmAssistantDestination.marketNewsRadar,
      name: 'Radar Berita Pasar',
      description: 'Memantau berita dan isu pasar terkini.',
      aliases: [
        'radar berita',
        'berita pasar',
        'market news',
        'news radar',
        'radar pasar',
      ],
    ),
    FfmAssistantPage(
      destination: FfmAssistantDestination.utilityMeter,
      name: 'Buku Saku Meteran & Token',
      description: 'Menyimpan daftar nomor meteran PLN dan token listrik 20-digit.',
      aliases: [
        'meteran listrik',
        'token listrik',
        'buku meteran',
        'nomor meter',
        'meteran pln',
        'id pelanggan pln',
        'idpel',
        'pulsa listrik',
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
        FfmAssistantDestination.transactions => 'Transaksi dipakai untuk catat pemasukan, pengeluaran, transfer antar rekening, setor atau pakai target, input banyak transaksi, serta impor JSON dari LLM eksternal. Transfer hanya memindahkan saldo; biaya adminnya dicatat sebagai pengeluaran terpisah.',
        FfmAssistantDestination.budget => 'Anggaran berisi batas total mingguan atau bulanan, target kategori yang opsional, dan mode Tidak Rutin untuk kebutuhan yang tidak dibeli rutin. Anggaran memantau pengeluaran yang tersimpan; tidak bergantung pada pemasukan.',
        FfmAssistantDestination.analysis => 'Analisa membaca transaksi nyata yang sudah tersimpan untuk melihat pola pemasukan, pengeluaran, dan anggaran. Kalau datanya masih kosong, Asisten akan bilang belum ada cukup data—tidak membuat angka sendiri.',
        FfmAssistantDestination.masterData => 'Data Utama berisi lima bagian: Rekening atau Tunai untuk sumber saldo, Kategori pemasukan/pengeluaran, Toko atau pihak, Tag untuk penanda tambahan, dan Sumber pemasukan. Bagian ini adalah bahan pilihan saat kamu mengisi transaksi; semua bisa ditambah, diedit, atau diarsipkan. Profil keluarga dikelola terpisah di halaman Profil Keluarga.',
        FfmAssistantDestination.familyProfile => 'Profil Keluarga menyimpan nama rumah tangga, nama suami/istri, dan data pribadi (Kenalkan Diri) yang membantu Asisten memberi jawaban lebih kontekstual. Data keluarga seperti aset, target keuangan, dan hutang & piutang dikelola pada menu masing-masing di Lainnya.',
        FfmAssistantDestination.assets => 'Aset keluarga dipakai untuk mencatat barang atau kepemilikan bernilai yang ingin dipantau, misalnya kebun, kendaraan, alat kerja, atau tabungan khusus. Aset bukan transaksi harian dan tidak otomatis mengubah saldo rekening.',
        FfmAssistantDestination.goals => 'Target keuangan dipakai untuk uang yang sedang dikumpulkan dengan tujuan tertentu. Kamu bisa setor ke target atau memakai uang target; keduanya dicatat terpisah agar progres target tetap jelas.',
        FfmAssistantDestination.liabilities => 'Hutang & piutang mencatat uang yang kamu pinjam atau uang yang harus diterima dari orang lain. Kamu bisa melihat sisa, membuat strategi pelunasan, dan mengarsipkan catatan yang selesai tanpa menghapus riwayat finansial.',
        FfmAssistantDestination.activity => 'Aktivitas & Jurnal memiliki lima bagian terpisah: aktivitas bertimer untuk melacak kegiatan dan lama waktunya, Catatan Harian untuk teks bebas, Tugas untuk tindakan satu kali, Rutinitas untuk kebiasaan berulang dengan tanda pelaksanaan per hari, serta Jadwal untuk agenda lokal bertanggal tanpa alarm. Beberapa aktivitas dapat aktif bersamaan; pembaruan atau selesai pada satu aktivitas tidak otomatis menutup aktivitas lain. Catatan Harian, Tugas, Rutinitas, dan Jadwal tidak mengubah sesi aktivitas dan hanya dapat diarsipkan lunak lewat Agent.',
        FfmAssistantDestination.reminders => 'Pengingat membuat alarm lokal untuk hal yang perlu dilakukan. Kamu dapat menunda, menyelesaikan, atau melihat riwayat tanpa mengubah transaksi keuangan.',
        FfmAssistantDestination.backup => 'Ekspor & cadangan dipakai untuk membuat atau memulihkan data FFM, termasuk data utama, transaksi, aset, target, hutang/piutang, aktivitas, pengingat, memori ajar, dan contoh belajar. Periksa preview sebelum impor.',
        FfmAssistantDestination.monthlyReport => 'Ringkasan bulanan membandingkan pemasukan, pengeluaran, dan arus kas berdasarkan periode yang kamu pilih. Laporan hanya menampilkan catatan nyata yang ada di perangkat.',
        FfmAssistantDestination.reconciliation => 'Rekonsiliasi saldo membantu mencocokkan saldo catatan FFM dengan saldo nyata di rekening atau tunai. Bila ada selisih, kamu dapat meninjau penyebabnya lalu buat penyesuaian secara sadar.',
        FfmAssistantDestination.appSecurity => 'Kunci aplikasi dipakai untuk mengaktifkan, mengganti, atau mematikan PIN FFM. PIN hanya dimasukkan lewat keypad khusus, tidak lewat chat, dan setiap perubahan meminta konfirmasi kamu.',
        FfmAssistantDestination.diagnostics => 'Bantuan perbaikan menampilkan error teknis yang benar-benar tertangkap secara lokal. Kamu bisa salin laporan yang sudah disaring; PIN, data keuangan, rekening, dan isi chat tidak ikut dimasukkan.',
        FfmAssistantDestination.activityLog => 'Log aktivitas menampilkan jejak perubahan lokal, termasuk transaksi, transfer, impor, dan rekonsiliasi.',
        FfmAssistantDestination.recurringTransaction => 'Pemasukan berkala mengatur aturan pemasukan atau pengeluaran rutin harian, mingguan, atau bulanan.',
        FfmAssistantDestination.privacyCenter => 'Pusat privasi menjelaskan lokasi data, enkripsi, izin perangkat, serta kendali ekspor dan penghapusan.',
        FfmAssistantDestination.databaseStructure => 'Struktur database memperlihatkan tabel dan gambaran database lokal FFM.',
        FfmAssistantDestination.assistantProfile => 'Profil Personalisasi Asisten mengelola data belajar asisten: ekspor, impor, dan reset learning terenkripsi. Nama rumah tangga dan data pribadi seperti nama/panggilan dikelola di halaman Profil Keluarga.',
        FfmAssistantDestination.otherMenu => 'Lainnya berisi jalan ke fitur pendukung seperti Data Utama, aset, target, hutang & piutang, aktivitas, pengingat, laporan, dan cadangan.',
        FfmAssistantDestination.intelligenceDashboard => 'Intelligence Dashboard menyimpan dan menguji key serta model Gemini Cloud, mengatur koneksi Supabase, dan menampilkan status konfigurasi yang dipakai chatbot.',
        FfmAssistantDestination.paymentDetector => 'Pendeteksi notifikasi pembayaran menangkap notifikasi transaksi dari aplikasi bank (BCA, Mandiri, BRI, BNI, SeaBank) dan e-wallet (GoPay, OVO, DANA, ShopeePay) secara otomatis dan lokal di perangkat untuk dijadikan draft pencatatan.',
        FfmAssistantDestination.telegramSetup => 'Telegram Bot Keluarga mengirimkan laporan mingguan dan notifikasi peringatan boncos ke grup chat keluarga.',
        FfmAssistantDestination.agentInbox => 'Laporan & Kotak Masuk Asisten menampilkan rekomendasi proaktif, deteksi runway, rebalance anggaran, dan anomali belanja.',
        FfmAssistantDestination.autonomyMonitor => 'Monitoring Agent menampilkan riwayat eksekusi tool dan aktivitas otonom agent secara read-only.',
        FfmAssistantDestination.hijriSettings => 'Kalender Hijriah & Hilal mengatur penetapan tanggal dan koreksi Hilal untuk penanggalan Islam.',
        FfmAssistantDestination.calendarSettings => 'Kalender & Smartwatch mengatur sinkronisasi tagihan ke Google Calendar dan jam tangan pintar.',
        FfmAssistantDestination.marketNewsRadar => 'Radar Berita Pasar menampilkan berita dan perkembangan isu finansial terkini.',
        FfmAssistantDestination.utilityMeter => 'Buku Saku Meteran & Token menyimpan daftar IDPEL atau nomor meteran PLN properti rumah, ladang/sawah, dan toko, lengkap dengan 20 digit token listrik terakhir untuk disalin instan.',
      };
}
