import 'package:drift/drift.dart';

class Households extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get husbandName => text().nullable()();
  TextColumn get wifeName => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get name => text()();
  TextColumn get type => text()();
  TextColumn get parentId => text().nullable()();
  TextColumn get defaultBudgetPeriod =>
      text().withDefault(const Constant('none'))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Merchants extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get name => text()();
  TextColumn get details => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Tags extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get name => text()();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Accounts extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get name => text()();
  TextColumn get type => text()();
  IntColumn get openingBalance => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class TransactionParties extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get name => text()();
  TextColumn get role => text().nullable()();
  TextColumn get kind => text().withDefault(const Constant('custom'))();
  TextColumn get details => text().nullable()();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Transactions extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get type => text()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get merchantId => text().nullable()();
  TextColumn get accountId => text().nullable()();
  TextColumn get goalId => text().nullable()();
  IntColumn get amount => integer()();
  DateTimeColumn get date => dateTime()();
  DateTimeColumn get recordedAt => dateTime()();
  TextColumn get note => text().nullable()();
  TextColumn get owner => text().nullable()();
  TextColumn get partyName => text().nullable()();
  TextColumn get source => text().nullable()();
  TextColumn get sourceId => text().nullable()();
  TextColumn get recurringTransactionId => text().nullable()();
  TextColumn get location => text().nullable()();
  TextColumn get transferId => text().nullable()();
  TextColumn get receiptRawText => text().nullable()();
  TextColumn get receiptNumber => text().nullable()();
  IntColumn get receiptPaidAmount => integer().nullable()();
  IntColumn get receiptChangeAmount => integer().nullable()();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class TransactionItems extends Table {
  TextColumn get id => text()();
  TextColumn get transactionId => text()();
  TextColumn get itemName => text()();
  RealColumn get qty => real().withDefault(const Constant(1))();
  TextColumn get unit => text().nullable()();
  IntColumn get price => integer().withDefault(const Constant(0))();
  IntColumn get amount => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class TransactionTags extends Table {
  TextColumn get transactionId => text()();
  TextColumn get tagId => text()();

  @override
  Set<Column<Object>> get primaryKey => {transactionId, tagId};
}

class Attachments extends Table {
  TextColumn get id => text()();
  TextColumn get transactionId => text().nullable()();
  TextColumn get path => text()();
  TextColumn get kind => text().withDefault(const Constant('file'))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Transfers extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get fromAccountId => text()();
  TextColumn get toAccountId => text()();
  IntColumn get amount => integer()();
  IntColumn get adminFee => integer().withDefault(const Constant(0))();
  TextColumn get feeTransactionId => text().nullable()();
  DateTimeColumn get date => dateTime()();
  DateTimeColumn get recordedAt => dateTime()();
  TextColumn get note => text().nullable()();
  TextColumn get source => text().nullable()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class EnvelopeBudgets extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get categoryIdsJson => text().withDefault(const Constant('[]'))();
  TextColumn get name => text()();
  TextColumn get month => text().nullable()();
  IntColumn get allocated => integer().withDefault(const Constant(0))();
  TextColumn get periodType => text().withDefault(const Constant('monthly'))();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime()();
  IntColumn get alertPercent => integer().withDefault(const Constant(80))();
  IntColumn get rollover => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class EnvelopeTransfers extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get fromEnvelopeId => text()();
  TextColumn get toEnvelopeId => text()();
  TextColumn get month => text().nullable()();
  IntColumn get amount => integer()();
  DateTimeColumn get date => dateTime().nullable()();
  DateTimeColumn get recordedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get note => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Assets extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get name => text()();
  TextColumn get assetType => text()();
  IntColumn get value => integer().withDefault(const Constant(0))();
  TextColumn get placement => text().withDefault(const Constant('Keluarga'))();
  TextColumn get note => text().nullable()();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Goals extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get name => text()();
  IntColumn get targetAmount => integer()();
  IntColumn get currentAmount => integer().withDefault(const Constant(0))();
  DateTimeColumn get targetDate => dateTime().nullable()();
  TextColumn get categoryId => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Liabilities extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get name => text()();
  IntColumn get originalAmount => integer()();
  IntColumn get remainingBalance => integer()();
  IntColumn get monthlyInstallment =>
      integer().withDefault(const Constant(0))();
  RealColumn get interestRate => real().withDefault(const Constant(0))();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  TextColumn get note => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Receivables extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get name => text()();
  IntColumn get originalAmount => integer()();
  IntColumn get remainingBalance => integer()();
  IntColumn get monthlyInstallment =>
      integer().withDefault(const Constant(0))();
  RealColumn get interestRate => real().withDefault(const Constant(0))();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  TextColumn get note => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class RecurringTransactions extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get name => text()();
  TextColumn get type => text()();
  IntColumn get amount => integer()();

  /// Nilai bunga per periode dalam persen, hanya dipakai saat calcMode=percent.
  RealColumn get ratePercent => real().nullable()();

  /// fixed = nominal tetap, percent = persentase saldo buku.
  TextColumn get calcMode => text().withDefault(const Constant('fixed'))();
  TextColumn get categoryId => text().nullable()();
  TextColumn get accountId => text().nullable()();
  TextColumn get sourceId => text().nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get periodType => text().withDefault(const Constant('monthly'))();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Reminders extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get title => text()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get scheduledAt => dateTime()();
  TextColumn get recurrenceType => text().withDefault(const Constant('once'))();
  TextColumn get weekdaysJson => text().withDefault(const Constant('[]'))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get soundUri => text().nullable()();
  TextColumn get soundName => text().nullable()();
  IntColumn get defaultSnoozeMinutes =>
      integer().withDefault(const Constant(10))();
  IntColumn get notificationId => integer()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class ReminderHistories extends Table {
  TextColumn get id => text()();
  TextColumn get reminderId => text()();
  TextColumn get householdId => text()();
  TextColumn get title => text()();
  TextColumn get occurrenceKey => text()();
  DateTimeColumn get scheduledAt => dateTime()();
  DateTimeColumn get triggeredAt => dateTime().nullable()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get snoozedUntil => dateTime().nullable()();
  IntColumn get notificationId => integer()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class ActivitySessions extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get title => text()();
  TextColumn get parentSessionId => text().nullable()();
  TextColumn get category => text().withDefault(const Constant('lainnya'))();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  TextColumn get notes => text().nullable()();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class ActivityCheckpoints extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId => text()();
  TextColumn get label => text()();
  TextColumn get place => text().nullable()();
  DateTimeColumn get occurredAt => dateTime()();
  IntColumn get sequence => integer()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class ActivityEntries extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId => text().nullable()();
  TextColumn get householdId => text()();
  TextColumn get activityType =>
      text().withDefault(const Constant('lainnya'))();
  TextColumn get title => text()();
  TextColumn get participants => text().nullable()();
  TextColumn get topic => text().nullable()();
  TextColumn get place => text().nullable()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get followUp => text().nullable()();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Catatan refleksi atau ringkasan harian, terpisah dari sesi Aktivitas.
///
/// Tabel ini tidak boleh dipakai untuk menggantikan ActivitySessions,
/// ActivityCheckpoints, maupun ActivityEntries yang sudah ada.
class DailyNotes extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  DateTimeColumn get noteDate => dateTime()();
  TextColumn get title => text().nullable()();
  TextColumn get body => text()();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class AccountReconciliationLogs extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get accountId => text()();
  IntColumn get bookBalance => integer()();
  IntColumn get actualBalance => integer()();
  IntColumn get difference => integer()();
  DateTimeColumn get checkedAt => dateTime()();
  TextColumn get note => text().nullable()();
  TextColumn get adjustmentTransactionId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class RecurringTransactionRuns extends Table {
  TextColumn get id => text()();
  TextColumn get recurringTransactionId => text()();
  TextColumn get occurrenceKey => text()();
  DateTimeColumn get occurrenceDate => dateTime()();
  TextColumn get transactionId => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class HijriSettings extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get method => text().withDefault(const Constant('umm_al_qura'))();
  TextColumn get region => text().withDefault(const Constant('global'))();
  IntColumn get dayAdjustment => integer().withDefault(const Constant(0))();
  TextColumn get timezone => text().withDefault(const Constant('local'))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class HijriMonthOverrides extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  IntColumn get hijriYear => integer()();
  IntColumn get hijriMonth => integer()();
  DateTimeColumn get gregorianStartDate => dateTime()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class HijriCorrectionLogs extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get action => text()();
  TextColumn get settingKey => text()();
  TextColumn get oldValue => text().nullable()();
  TextColumn get newValue => text().nullable()();
  DateTimeColumn get timestamp => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Ajaran eksplisit pengguna untuk Asisten FFM.
///
/// Tidak menyimpan riwayat percakapan mentah. Tabel hanya berisi alias,
/// jawaban, kebiasaan, atau alur yang pengguna setujui untuk dipakai ulang.
class AssistantMemories extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();

  /// alias, answer, preference, atau workflow.
  TextColumn get kind => text()();

  /// Kalimat atau frasa yang akan dipahami Asisten.
  TextColumn get triggerText => text()();

  /// Makna, jawaban, atau nilai tujuan yang disetujui pengguna.
  TextColumn get valueText => text()();

  /// Metadata aman dan terstruktur, misalnya route atau draft kind.
  TextColumn get metadataJson => text().withDefault(const Constant('{}'))();
  TextColumn get source => text().withDefault(const Constant('user'))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Contoh perintah yang pengguna setujui untuk dijadikan bahan evaluasi
/// pemahaman Asisten. Teks wajib sudah disanitasi; ini bukan riwayat chat.
class AssistantLearningExamples extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get inputText => text()();
  TextColumn get intentLabel => text()();
  TextColumn get source =>
      text().withDefault(const Constant('user_approved'))();
  IntColumn get schemaVersion => integer().withDefault(const Constant(1))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Pertanyaan yang belum bisa dijawab dengan tepat oleh Asisten.
///
/// Teks sudah disanitasi sebelum disimpan. Antrean ini bukan riwayat chat,
/// tidak berisi jawaban LLM, dan hanya dipakai untuk menyiapkan pelatihan.
/// Koreksi user terhadap nilai yang diusulkan SLM. Teks disimpan sebagai
/// nilai terstruktur, bukan riwayat percakapan mentah.
class UserCorrections extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get merchantName => text()();
  TextColumn get fieldName => text()();
  TextColumn get slmValue => text().nullable()();
  TextColumn get correctedValue => text()();
  DateTimeColumn get timestamp => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Preferensi eksplisit yang ditetapkan user, terpisah dari observasi transaksi.
class UserPreferences extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get preferenceKey => text()();
  TextColumn get preferenceValue => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Ringkasan deterministik dari koreksi user, bukan hasil training model.
class InteractionPatterns extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get merchantName => text()();
  TextColumn get fieldName => text()();
  TextColumn get mostCommonValue => text()();
  RealColumn get confidenceScore => real()();
  IntColumn get sampleCount => integer()();
  DateTimeColumn get lastUpdated => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class AssistantUnansweredQuestions extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get questionText => text()();
  TextColumn get pageContext => text().nullable()();
  IntColumn get occurrenceCount => integer().withDefault(const Constant(1))();
  BoolColumn get isResolved => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Umpan balik yang pengguna kirim atas jawaban Asisten, bukan koreksi data
/// transaksi dan bukan knowledge yang langsung aktif.
class AssistantResponseFeedbacks extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get questionText => text()();
  TextColumn get responseText => text()();
  TextColumn get feedbackKind => text()();
  TextColumn get note => text().nullable()();
  TextColumn get pageContext => text().nullable()();
  TextColumn get reviewStatus =>
      text().withDefault(const Constant('pending'))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
