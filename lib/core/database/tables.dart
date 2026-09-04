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
  TextColumn get linkedActivityId => text().nullable()();
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
  // Calendar integration fields
  IntColumn get calendarEventId => integer().nullable()();
  BoolColumn get isSyncedToCalendar => boolean().withDefault(const Constant(false))();
  DateTimeColumn get syncedAt => dateTime().nullable()();

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

  /// Relasi ke master Categories dengan type = activity.
  /// Nullable agar data lama tetap dapat dibaca sebelum backfill migrasi.
  TextColumn get categoryId => text().nullable()();

  /// Label legacy untuk kompatibilitas data lama dan impor lama.
  TextColumn get category => text().withDefault(const Constant('lainnya'))();
  TextColumn get kind => text().withDefault(const Constant('timer'))();

  /// Mode aktivitas: time tracking vs catatan/riwayat
  /// Nullable untuk backward compatibility; default dihitung dari kind jika null
  TextColumn get mode => text().nullable()();

  /// Activity Intelligence Upgrade - Grouping & Subject Linking
  /// activity_group_id: Mengelompokkan aktivitas dalam satu rangkaian/proses
  /// subject_type: Jenis entitas yang sedang dikerjakan (crop, asset, dll)
  /// subject_id: ID spesifik entitas yang sedang dikerjakan
  TextColumn get activityGroupId => text().nullable()();
  TextColumn get subjectType => text().nullable()();
  TextColumn get subjectId => text().nullable()();

  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  DateTimeColumn get scheduledAt => dateTime().nullable()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  BoolColumn get isAllDay => boolean().withDefault(const Constant(false))();
  BoolColumn get isCompleted => boolean().withDefault(const Constant(false))();
  IntColumn get priority => integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('active'))();
  TextColumn get notes => text().nullable()();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Fakta panen yang dapat dicari ulang secara deterministik dari SQL.
/// Nilai finansial disimpan dalam satuan terkecil aplikasi (rupiah).
class HarvestEvents extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get commodity => text()();
  RealColumn get quantity => real()();
  TextColumn get unit => text().withDefault(const Constant('kg'))();
  IntColumn get unitPrice => integer().nullable()();
  IntColumn get totalAmount => integer().nullable()();
  TextColumn get buyerName => text().nullable()();
  TextColumn get location => text().nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get linkedActivityId => text().nullable()();
  DateTimeColumn get harvestedAt => dateTime()();
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

  /// Relasi ke master Categories dengan type = activity.
  TextColumn get categoryId => text().nullable()();

  /// Label legacy untuk kompatibilitas data lama dan impor lama.
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

/// Tugas adalah tindakan keluarga yang dikelola terpisah dari sesi aktivitas
/// bertimer, Catatan Harian, Rutinitas, dan Jadwal.
class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get title => text()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  TextColumn get status => text().withDefault(const Constant('open'))();
  DateTimeColumn get completedAt => dateTime().nullable()();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Rutinitas adalah kebiasaan berulang yang definisinya terpisah dari Tugas
/// satu kali, Catatan Harian, sesi Aktivitas, dan Jadwal kalender.
class DailyRoutines extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get title => text()();
  TextColumn get note => text().nullable()();
  TextColumn get weekdaysJson => text().withDefault(const Constant('[]'))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Satu pelaksanaan Rutinitas pada satu tanggal lokal.
///
/// ID disusun deterministik oleh repository dari rutinitas dan tanggal agar
/// pengulangan penandaan tidak membuat riwayat ganda.
class DailyRoutineCompletions extends Table {
  TextColumn get id => text()();
  TextColumn get routineId => text()();
  TextColumn get householdId => text()();
  DateTimeColumn get routineDate => dateTime()();
  DateTimeColumn get completedAt => dateTime()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Agenda lokal satu kali pada tanggal tertentu. Jadwal tidak mengaktifkan
/// notifikasi, tidak membuat Aktivitas, dan tidak menjalankan transaksi.
class ScheduleEntries extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get title => text()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get scheduledDate => dateTime()();
  BoolColumn get isAllDay => boolean().withDefault(const Constant(true))();
  IntColumn get startMinutes => integer().nullable()();
  IntColumn get endMinutes => integer().nullable()();
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

/// Ringkasan eksekusi agent yang aman untuk dipulihkan dan diaudit.
///
/// Tabel ini sengaja tidak menyimpan prompt, chain-of-thought, atau input tool
/// mentah. Detail sensitif tetap berada pada data domain dan batas executor.
class AssistantAgentRuns extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get trigger => text()();
  TextColumn get status => text()();
  TextColumn get summary => text()();
  TextColumn get domain => text().nullable()();
  TextColumn get entityId => text().nullable()();
  TextColumn get activityId => text().nullable()();
  TextColumn get model => text().nullable()();
  TextColumn get decisionSummary => text().nullable()();
  TextColumn get error => text().nullable()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get finishedAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Event durable untuk pemicu agent. Status disimpan agar event yang sama
/// tidak diproses ulang setelah aplikasi dibuka kembali.
class AssistantAgentEvents extends Table {
  TextColumn get eventId => text()();
  TextColumn get householdId => text()();
  TextColumn get eventType => text()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  TextColumn get entityId => text().nullable()();
  TextColumn get activityId => text().nullable()();
  TextColumn get payloadJson => text().withDefault(const Constant('{}'))();
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  TextColumn get error => text().nullable()();
  DateTimeColumn get occurredAt => dateTime()();
  DateTimeColumn get lastAttemptAt => dateTime().nullable()();
  DateTimeColumn get processedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {eventId};
}

/// Keputusan approval yang aman untuk diaudit. Tidak menyimpan prompt atau
/// payload tool mentah, hanya relasi run dan ringkasan tindakan.
class AssistantAgentApprovals extends Table {
  TextColumn get id => text()();
  TextColumn get runId => text()();
  TextColumn get householdId => text()();
  TextColumn get status => text()();
  TextColumn get summary => text()();
  TextColumn get actor => text().nullable()();
  TextColumn get reason => text().nullable()();
  DateTimeColumn get requestedAt => dateTime()();
  DateTimeColumn get decidedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Status capability per step untuk audit run tanpa menyimpan parameter mentah.
class AssistantAgentToolExecutions extends Table {
  TextColumn get id => text()();
  TextColumn get runId => text()();
  TextColumn get householdId => text()();
  TextColumn get stepId => text()();
  TextColumn get capabilityId => text()();
  TextColumn get status => text()();
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  TextColumn get resultSummary => text().nullable()();
  TextColumn get error => text().nullable()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get finishedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Goal berkelanjutan milik Agent, terpisah dari target keuangan pengguna.
class AssistantAgentGoals extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get domain => text()();
  TextColumn get entityId => text().nullable()();
  TextColumn get activityId => text().nullable()();
  TextColumn get title => text()();
  TextColumn get objective => text()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  IntColumn get priority => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get lastRunAt => dateTime().nullable()();
  DateTimeColumn get nextRunAt => dateTime().nullable()();
  TextColumn get completionCondition => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Task yang dimiliki Goal Agent, terpisah dari tugas keluarga biasa.
class AssistantAgentTasks extends Table {
  TextColumn get id => text()();
  TextColumn get goalId => text()();
  TextColumn get householdId => text()();
  TextColumn get title => text()();
  TextColumn get objective => text().nullable()();
  TextColumn get capabilityId => text().nullable()();
  TextColumn get parametersJson => text().withDefault(const Constant('{}'))();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  IntColumn get priority => integer().withDefault(const Constant(0))();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  IntColumn get maxRetries => integer().withDefault(const Constant(3))();
  DateTimeColumn get dueAt => dateTime().nullable()();
  DateTimeColumn get lastRunAt => dateTime().nullable()();
  DateTimeColumn get nextRunAt => dateTime().nullable()();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get completedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Riwayat setiap percobaan Task Agent tanpa menyimpan prompt atau input tool.
class AssistantAgentTaskExecutions extends Table {
  TextColumn get id => text()();
  TextColumn get taskId => text()();
  TextColumn get goalId => text()();
  TextColumn get householdId => text()();
  TextColumn get runId => text().nullable()();
  TextColumn get status => text()();
  TextColumn get summary => text().nullable()();
  TextColumn get error => text().nullable()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get finishedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
