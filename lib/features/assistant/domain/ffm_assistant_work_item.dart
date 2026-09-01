/// Kontrak hasil pemahaman perintah Agent/Gemini.
/// Memisahkan pekerjaan menjadi item terpisah dengan informasi yang jelas.
library;

import 'ffm_assistant_models.dart';

/// Tingkat keyakinan pemahaman Agent/Gemini.
enum FfmAssistantWorkItemConfidence {
  /// Parameter lengkap dan valid, siap untuk draft.
  high,

  /// Parameter sebagian diketahui, perlu klarifikasi pengguna.
  medium,

  /// Parameter tidak cukup atau ambigu, tidak dapat diproses tanpa klarifikasi.
  low,
}

/// Status field dalam konteks pemahaman.
enum FfmAssistantFieldStatus {
  /// Nilai sudah diketahui dan valid.
  known,

  /// Nilai belum diketahui dari konteks.
  unknown,

  /// Nilai ambigu atau konflik dengan Data Utama.
  ambiguous,
}

/// Informasi tentang satu field dalam konteks pemahaman.
class FfmAssistantFieldInfo {
  const FfmAssistantFieldInfo({
    required this.name,
    required this.status,
    this.value,
    this.ambiguityReason,
  });

  final String name;
  final FfmAssistantFieldStatus status;
  final String? value;
  final String? ambiguityReason;

  bool get isKnown => status == FfmAssistantFieldStatus.known;
  bool get isUnknown => status == FfmAssistantFieldStatus.unknown;
  bool get isAmbiguous => status == FfmAssistantFieldStatus.ambiguous;
}

/// Satu pekerjaan yang dipahami dari perintah pengguna.
class FfmAssistantWorkItem {
  const FfmAssistantWorkItem({
    required this.id,
    required this.intent,
    this.sourceIntent,
    required this.targetDestination,
    required this.confidence,
    required this.knownFields,
    required this.unknownFields,
    required this.ambiguousFields,
    this.clarificationQuestion,
    this.currentDestination,
    this.supportedForms,
  });

  /// ID unik untuk item pekerjaan ini.
  final String id;

  /// Intent yang terkait dengan pekerjaan ini.
  final FfmAssistantIntentType intent;

  /// Intent lengkap hasil interpreter. Ini menjaga draft, respons, provider,
  /// dan metadata tetap utuh saat UI menampilkan beberapa pekerjaan.
  final FfmAssistantIntent? sourceIntent;

  /// Halaman/form target untuk pekerjaan ini.
  final FfmAssistantDestination targetDestination;

  /// Halaman aktif saat perintah diberikan (untuk konteks, bukan asumsi).
  final FfmAssistantDestination? currentDestination;

  /// Daftar form yang didukung pada halaman aktif (untuk konteks).
  final List<FfmAssistantDestination>? supportedForms;

  /// Tingkat keyakinan pemahaman.
  final FfmAssistantWorkItemConfidence confidence;

  /// Field yang sudah diketahui nilainya.
  final List<FfmAssistantFieldInfo> knownFields;

  /// Field yang belum diketahui nilainya.
  final List<String> unknownFields;

  /// Field yang ambigu atau konflik.
  final List<FfmAssistantFieldInfo> ambiguousFields;

  /// Pertanyaan klarifikasi untuk pengguna (jika confidence bukan high).
  final String? clarificationQuestion;

  /// Apakah pekerjaan ini siap untuk dibuatkan draft?
  bool get isReadyForDraft => confidence == FfmAssistantWorkItemConfidence.high;

  /// Apakah pekerjaan ini memerlukan klarifikasi dari pengguna?
  bool get needsClarification => clarificationQuestion != null;

  /// Ringkasan singkat untuk ditampilkan di UI.
  String get summary {
    final destinationLabel = _destinationLabel(targetDestination);
    final intentLabel = _intentLabel(intent);
    return '$intentLabel → $destinationLabel';
  }

  String _destinationLabel(FfmAssistantDestination destination) {
    switch (destination) {
      case FfmAssistantDestination.summary:
        return 'Ringkasan';
      case FfmAssistantDestination.transactions:
        return 'Transaksi';
      case FfmAssistantDestination.budget:
        return 'Anggaran';
      case FfmAssistantDestination.analysis:
        return 'Analisis';
      case FfmAssistantDestination.otherMenu:
        return 'Menu lain';
      case FfmAssistantDestination.masterData:
        return 'Data Utama';
      case FfmAssistantDestination.assets:
        return 'Aset';
      case FfmAssistantDestination.goals:
        return 'Target Tabungan';
      case FfmAssistantDestination.liabilities:
        return 'Hutang';
      case FfmAssistantDestination.activity:
        return 'Aktivitas';
      case FfmAssistantDestination.reminders:
        return 'Pengingat';
      case FfmAssistantDestination.backup:
        return 'Backup';
      case FfmAssistantDestination.monthlyReport:
        return 'Laporan Bulanan';
      case FfmAssistantDestination.reconciliation:
        return 'Rekonsiliasi';
      case FfmAssistantDestination.appSecurity:
        return 'Keamanan';
      case FfmAssistantDestination.diagnostics:
        return 'Diagnostik';
      case FfmAssistantDestination.activityLog:
        return 'Log Aktivitas';

      case FfmAssistantDestination.recurringTransaction:
        return 'Transaksi Berulang';

      case FfmAssistantDestination.privacyCenter:
        return 'Privasi';
      case FfmAssistantDestination.databaseStructure:
        return 'Struktur Database';

      case FfmAssistantDestination.localModel:
        return 'Model Lokal';
      case FfmAssistantDestination.assistantProfile:
        return 'Profil Asisten';
      case FfmAssistantDestination.intelligenceDashboard:
        return 'Dashboard Intelijen';
    }
  }

  String _intentLabel(FfmAssistantIntentType intent) {
    switch (intent) {
      case FfmAssistantIntentType.createIncome:
        return 'Catat pemasukan';
      case FfmAssistantIntentType.createExpense:
        return 'Catat pengeluaran';
      case FfmAssistantIntentType.createTransfer:
        return 'Transfer';
      case FfmAssistantIntentType.createGoalDeposit:
        return 'Setoran target';
      case FfmAssistantIntentType.createGoalUsage:
        return 'Penggunaan target';
      case FfmAssistantIntentType.createGoal:
        return 'Buat target';
      case FfmAssistantIntentType.createLiability:
        return 'Buat hutang';
      case FfmAssistantIntentType.createBudget:
        return 'Buat anggaran';
      case FfmAssistantIntentType.createAsset:
        return 'Buat aset';
      case FfmAssistantIntentType.createReceivable:
        return 'Buat piutang';
      default:
        return intent.name;
    }
  }

  FfmAssistantWorkItem copyWith({
    FfmAssistantIntentType? intent,
    FfmAssistantIntent? sourceIntent,
    FfmAssistantDestination? targetDestination,
    FfmAssistantWorkItemConfidence? confidence,
    List<FfmAssistantFieldInfo>? knownFields,
    List<String>? unknownFields,
    List<FfmAssistantFieldInfo>? ambiguousFields,
    String? clarificationQuestion,
    FfmAssistantDestination? currentDestination,
    List<FfmAssistantDestination>? supportedForms,
  }) => FfmAssistantWorkItem(
    id: id,
    intent: intent ?? this.intent,
    sourceIntent: sourceIntent ?? this.sourceIntent,
    targetDestination: targetDestination ?? this.targetDestination,
    confidence: confidence ?? this.confidence,
    knownFields: knownFields ?? this.knownFields,
    unknownFields: unknownFields ?? this.unknownFields,
    ambiguousFields: ambiguousFields ?? this.ambiguousFields,
    clarificationQuestion: clarificationQuestion ?? this.clarificationQuestion,
    currentDestination: currentDestination ?? this.currentDestination,
    supportedForms: supportedForms ?? this.supportedForms,
  );
}

/// Hasil pemahaman perintah yang berisi daftar pekerjaan terpisah.
class FfmAssistantUnderstandingResult extends Iterable<FfmAssistantIntent> {
  const FfmAssistantUnderstandingResult({
    required this.workItems,
    this.intents = const <FfmAssistantIntent>[],
    required this.rawText,
    required this.normalizedText,
  });

  /// Daftar pekerjaan yang dipahami dari perintah.
  final List<FfmAssistantWorkItem> workItems;

  /// Intent asli yang diterima UI. Tetap termasuk jawaban non-aksi seperti
  /// bantuan, fallback, dan error, sehingga tidak hilang saat membuat daftar
  /// pekerjaan terstruktur.
  final List<FfmAssistantIntent> intents;

  @override
  Iterator<FfmAssistantIntent> get iterator => intents.iterator;

  /// Teks asli dari pengguna.
  final String rawText;

  /// Teks yang dinormalisasi.
  final String normalizedText;

  /// Apakah ada pekerjaan yang memerlukan klarifikasi?
  bool get needsClarification => workItems.any((item) => item.needsClarification);

  /// Apakah ada pekerjaan yang siap untuk draft?
  bool get hasReadyItems => workItems.any((item) => item.isReadyForDraft);

  /// Ringkasan singkat untuk ditampilkan di UI.
  String get summary {
    final count = workItems.length;
    if (count == 0) return 'Tidak ada pekerjaan dipahami';
    if (count == 1) return '1 pekerjaan dipahami';
    return '$count pekerjaan dipahami';
  }

  FfmAssistantUnderstandingResult copyWith({
    List<FfmAssistantWorkItem>? workItems,
    List<FfmAssistantIntent>? intents,
    String? rawText,
    String? normalizedText,
  }) => FfmAssistantUnderstandingResult(
    workItems: workItems ?? this.workItems,
    intents: intents ?? this.intents,
    rawText: rawText ?? this.rawText,
    normalizedText: normalizedText ?? this.normalizedText,
  );
}
