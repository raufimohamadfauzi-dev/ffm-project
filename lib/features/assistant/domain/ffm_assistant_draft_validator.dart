import 'ffm_assistant_models.dart';

/// Pemeriksa deterministik draft Asisten. Pemeriksaan ini sengaja murni,
/// offline, dan tidak mengakses atau menyimpan data agar dapat diuji langsung.
abstract final class FfmAssistantDraftValidator {
  static List<FfmAssistantDraftIssue> validate(FfmAssistantDraft draft) {
    final issues = <FfmAssistantDraftIssue>[];

    if (!draft.hasAmount && _needsAmount(draft.kind)) {
      issues.add(
        const FfmAssistantDraftIssue(
          code: 'amount_required',
          severity: FfmAssistantDraftIssueSeverity.required,
          field: 'nominal',
          message: 'Nominalnya belum ada. Isi dulu biar draft-nya jelas.',
        ),
      );
    }
    if (draft.amount != null && draft.amount! <= 0) {
      issues.add(
        const FfmAssistantDraftIssue(
          code: 'amount_invalid',
          severity: FfmAssistantDraftIssueSeverity.conflict,
          field: 'nominal',
          message: 'Nominal harus lebih dari Rp0.',
        ),
      );
    }

    switch (draft.kind) {
      case FfmAssistantDraftKind.transfer:
        _validateTransfer(draft, issues);
        _validateTransactionDate(draft, issues);
        _validateTransactionReferences(draft, issues);
      case FfmAssistantDraftKind.income:
        _validateReceiptFields(draft, issues);
        _validateTransactionDate(draft, issues);
        _validateTransactionReferences(draft, issues);
        if (_isBlank(draft.toAccountName)) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'income_destination_untracked',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'rekening tujuan',
              message: 'Rekening tujuan belum dipilih. Sebut nama rekening yang ada di Data Utama.',
            ),
          );
        }
        if (_isBlank(draft.categoryName)) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'income_category_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'kategori',
              message: 'Kategori pemasukan belum ada. Sebut nama kategori yang ada di Data Utama, atau buat dulu lewat "buat kategori [nama]".',
            ),
          );
        }
      case FfmAssistantDraftKind.expense:
        _validateReceiptFields(draft, issues);
        _validateTransactionDate(draft, issues);
        _validateTransactionReferences(draft, issues);
        if (_isBlank(draft.fromAccountName)) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'expense_source_untracked',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'rekening sumber',
              message: 'Rekening sumber belum dipilih. Sebut nama rekening yang ada di Data Utama.',
            ),
          );
        }
        if (_isBlank(draft.categoryName)) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'expense_category_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'kategori',
              message: 'Kategori pengeluaran belum ada. Sebut nama kategori yang ada di Data Utama, atau buat dulu lewat "buat kategori [nama]".',
            ),
          );
        }
      case FfmAssistantDraftKind.goalDeposit:
        if (_isBlank(draft.goalName)) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'goal_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'target',
              message: 'Pilih target keuangan dulu supaya uangnya tidak salah masuk.',
            ),
          );
        }
        if (_isBlank(draft.fromAccountName)) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'goal_source_untracked',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'rekening sumber',
              message: 'Rekening sumber belum dipilih. Sebut nama rekening yang ada di Data Utama, atau pilih di dropdown Rekening sumber dana.',
            ),
          );
        }
        if (draft.date == null) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'goal_date_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'tanggal',
              message: 'Tanggal alokasi belum dipilih.',
            ),
          );
        }
      case FfmAssistantDraftKind.goalUsage:
        if (_isBlank(draft.goalName)) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'goal_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'target',
              message:
                  'Pilih target keuangan dulu supaya dana tidak salah diambil.',
            ),
          );
        }
        if (_isBlank(draft.toAccountName)) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'goal_destination_untracked',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'rekening tujuan',
              message: 'Rekening tujuan belum dipilih.',
            ),
          );
        }
        if (draft.date == null) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'goal_date_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'tanggal',
              message: 'Tanggal alokasi belum dipilih.',
            ),
          );
        }
      case FfmAssistantDraftKind.goal:
        if (_isBlank(draft.title)) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'goal_name_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'nama target',
              message: 'Nama targetnya belum ada.',
            ),
          );
        }
        if (draft.date == null) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'goal_date_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'batas waktu',
              message: 'Batas waktu target belum dipilih.',
            ),
          );
        }
      case FfmAssistantDraftKind.goalUpdate:
      case FfmAssistantDraftKind.goalArchive:
        if (_isBlank(draft.formValues['targetId'])) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'goal_target_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'target keuangan',
              message: 'Target keuangan belum ditemukan secara unik.',
            ),
          );
        }
      case FfmAssistantDraftKind.reminderArchive:
        if (_isBlank(draft.formValues['targetId'])) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'reminder_target_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'pengingat',
              message: 'Pengingat target belum ditemukan secara unik.',
            ),
          );
        }
      case FfmAssistantDraftKind.liability:
      case FfmAssistantDraftKind.receivable:
        if (_isBlank(draft.partyName) && _isBlank(draft.title)) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'party_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'nama orang',
              message: 'Sebut nama orang atau nama hutang/piutang dulu supaya catatan tidak tertukar.',
            ),
          );
        }
      case FfmAssistantDraftKind.liabilityUpdate:
        if (_isBlank(draft.formValues['targetId']) || _isBlank(draft.title)) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'liability_update_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'Hutang',
              message: 'Target atau nama Hutang belum valid.',
            ),
          );
        }
      case FfmAssistantDraftKind.liabilityArchive:
        if (_isBlank(draft.formValues['targetId'])) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'liability_target_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'Hutang',
              message: 'Hutang target belum ditemukan secara unik.',
            ),
          );
        }
      case FfmAssistantDraftKind.liabilityPayment:
        if (_isBlank(draft.formValues['targetId'])) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'liability_payment_target_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'Hutang',
              message: 'Hutang target belum dipilih secara unik.',
            ),
          );
        }
        if (!draft.hasAmount) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'liability_payment_amount_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'nominal',
              message: 'Nominal pembayaran hutang belum ada.',
            ),
          );
        }
      case FfmAssistantDraftKind.receivableUpdate:
        if (_isBlank(draft.formValues['targetId']) || _isBlank(draft.title)) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'receivable_update_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'Piutang',
              message: 'Target atau nama Piutang belum valid.',
            ),
          );
        }
      case FfmAssistantDraftKind.receivableArchive:
        if (_isBlank(draft.formValues['targetId'])) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'receivable_target_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'Piutang',
              message: 'Piutang target belum ditemukan secara unik.',
            ),
          );
        }
      case FfmAssistantDraftKind.receivablePayment:
        if (_isBlank(draft.formValues['targetId'])) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'receivable_payment_target_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'Piutang',
              message: 'Piutang target belum dipilih secara unik.',
            ),
          );
        }
        if (!draft.hasAmount) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'receivable_payment_amount_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'nominal',
              message: 'Nominal penerimaan piutang belum ada.',
            ),
          );
        }
      case FfmAssistantDraftKind.merchantUpdate:
        if (_isBlank(draft.formValues['targetId']) || _isBlank(draft.title)) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'merchant_update_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'Toko/Tempat',
              message: 'Target atau nama Toko/Tempat belum valid.',
            ),
          );
        }
      case FfmAssistantDraftKind.merchantArchive:
        if (_isBlank(draft.formValues['targetId'])) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'merchant_target_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'Toko/Tempat',
              message: 'Toko/Tempat target belum ditemukan secara unik.',
            ),
          );
        }
      case FfmAssistantDraftKind.merchantDelete:
        if (_isBlank(draft.formValues['targetId'])) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'merchant_target_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'Toko/Tempat',
              message: 'Toko/Tempat target belum ditemukan secara unik.',
            ),
          );
        }
      case FfmAssistantDraftKind.tagUpdate:
        if (_isBlank(draft.formValues['targetId']) || _isBlank(draft.title)) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'tag_update_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'Tag',
              message: 'Target atau nama Tag belum valid.',
            ),
          );
        }
      case FfmAssistantDraftKind.tagArchive:
        if (_isBlank(draft.formValues['targetId'])) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'tag_target_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'Tag',
              message: 'Tag target belum ditemukan secara unik.',
            ),
          );
        }
      case FfmAssistantDraftKind.tagDelete:
        if (_isBlank(draft.formValues['targetId'])) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'tag_target_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'Tag',
              message: 'Tag target belum ditemukan secara unik.',
            ),
          );
        }
      case FfmAssistantDraftKind.incomeSourceUpdate:
        if (_isBlank(draft.formValues['targetId']) || _isBlank(draft.title)) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'income_source_update_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'Sumber Pemasukan',
              message: 'Target atau nama Sumber Pemasukan belum valid.',
            ),
          );
        }
      case FfmAssistantDraftKind.incomeSourceArchive:
        if (_isBlank(draft.formValues['targetId'])) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'income_source_target_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'Sumber Pemasukan',
              message: 'Sumber Pemasukan target belum ditemukan secara unik.',
            ),
          );
        }
      case FfmAssistantDraftKind.incomeSourceDelete:
        if (_isBlank(draft.formValues['targetId'])) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'income_source_target_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'Sumber Pemasukan',
              message: 'Sumber Pemasukan target belum ditemukan secara unik.',
            ),
          );
        }
      case FfmAssistantDraftKind.categoryUpdate:
        if (_isBlank(draft.formValues['targetId']) || _isBlank(draft.title)) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'category_update_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'Kategori',
              message: 'Target atau nama Kategori belum valid.',
            ),
          );
        }
      case FfmAssistantDraftKind.categoryArchive:
        if (_isBlank(draft.formValues['targetId'])) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'category_target_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'Kategori',
              message: 'Kategori target belum ditemukan secara unik.',
            ),
          );
        }
      case FfmAssistantDraftKind.categoryDelete:
        if (_isBlank(draft.formValues['targetId'])) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'category_target_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'Kategori',
              message: 'Kategori target belum ditemukan secara unik.',
            ),
          );
        }
      case FfmAssistantDraftKind.accountUpdate:
        if (_isBlank(draft.formValues['targetId']) || _isBlank(draft.title)) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'account_update_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'Rekening',
              message: 'Target atau nama Rekening belum valid.',
            ),
          );
        }
      case FfmAssistantDraftKind.accountArchive:
        if (_isBlank(draft.formValues['targetId'])) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'account_target_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'Rekening',
              message: 'Rekening target belum ditemukan secara unik.',
            ),
          );
        }
      case FfmAssistantDraftKind.accountDelete:
        if (_isBlank(draft.formValues['targetId'])) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'account_target_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'Rekening',
              message: 'Rekening target belum ditemukan secara unik.',
            ),
          );
        }
      case FfmAssistantDraftKind.recurringTransactionUpdate:
        if (_isBlank(draft.formValues['targetId']) || _isBlank(draft.title)) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'recurring_transaction_update_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'Transaksi Berkala',
              message: 'Target atau nama jadwal Transaksi Berkala belum valid.',
            ),
          );
        }
      case FfmAssistantDraftKind.recurringTransactionArchive:
        if (_isBlank(draft.formValues['targetId'])) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'recurring_transaction_target_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'Transaksi Berkala',
              message: 'Jadwal Transaksi Berkala target belum ditemukan secara unik.',
            ),
          );
        }
      case FfmAssistantDraftKind.asset:
      case FfmAssistantDraftKind.masterData:
      case FfmAssistantDraftKind.reminder:
      case FfmAssistantDraftKind.profile:
        if (_isBlank(draft.title)) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'title_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'nama',
              message: 'Nama atau judulnya belum ada.',
            ),
          );
        }
      case FfmAssistantDraftKind.assetUpdate:
        if (_isBlank(draft.formValues['targetId'])) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'asset_target_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'Aset',
              message: 'Aset target belum ditemukan secara unik.',
            ),
          );
        }
        if (_isBlank(draft.title) || !draft.hasAmount) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'asset_update_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'nama atau nilai Aset',
              message: 'Nama atau nilai baru Aset belum valid.',
            ),
          );
        }
      case FfmAssistantDraftKind.assetArchive:
        if (_isBlank(draft.formValues['targetId'])) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'asset_target_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'Aset',
              message: 'Aset target belum ditemukan secara unik.',
            ),
          );
        }
      case FfmAssistantDraftKind.dailyNote:
        if (_isBlank(draft.note)) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'daily_note_body_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'isi catatan',
              message: 'Isi Catatan Harian belum ada.',
            ),
          );
        }
        if (draft.date == null) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'daily_note_date_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'tanggal catatan',
              message: 'Tanggal Catatan Harian belum valid.',
            ),
          );
        }
      case FfmAssistantDraftKind.dailyNoteArchive:
        if (_isBlank(draft.formValues['targetId'])) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'daily_note_target_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'Catatan Harian',
              message: 'Catatan Harian target belum ditemukan secara unik.',
            ),
          );
        }
      case FfmAssistantDraftKind.activity:
        if (_isBlank(draft.title)) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'activity_title_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'judul aktivitas',
              message: 'Judul aktivitas belum ada.',
            ),
          );
        }
        if (draft.date == null && draft.scheduledAt == null) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'activity_date_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'tanggal aktivitas',
              message: 'Tanggal atau waktu aktivitas belum valid.',
            ),
          );
        }
      case FfmAssistantDraftKind.task:
        if (_isBlank(draft.title)) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'task_title_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'judul tugas',
              message: 'Judul Tugas belum ada.',
            ),
          );
        }
      case FfmAssistantDraftKind.taskUpdate:
      case FfmAssistantDraftKind.taskComplete:
      case FfmAssistantDraftKind.taskReopen:
      case FfmAssistantDraftKind.taskArchive:
        if (_isBlank(draft.formValues['targetId'])) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'task_target_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'Tugas',
              message: 'Tugas target belum ditemukan secara unik.',
            ),
          );
        }
      case FfmAssistantDraftKind.routine:
        if (_isBlank(draft.title)) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'routine_title_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'judul Rutinitas',
              message: 'Judul Rutinitas belum ada.',
            ),
          );
        }
      case FfmAssistantDraftKind.routineUpdate:
      case FfmAssistantDraftKind.routineMarkComplete:
      case FfmAssistantDraftKind.routineUnmarkComplete:
      case FfmAssistantDraftKind.routineActivate:
      case FfmAssistantDraftKind.routineDeactivate:
      case FfmAssistantDraftKind.routineArchive:
        if (_isBlank(draft.formValues['targetId'])) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'routine_target_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'Rutinitas',
              message: 'Rutinitas target belum ditemukan secara unik.',
            ),
          );
        }
      case FfmAssistantDraftKind.schedule:
        if (_isBlank(draft.title)) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'schedule_title_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'judul Jadwal',
              message: 'Judul Jadwal belum ada.',
            ),
          );
        }
        if (draft.date == null) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'schedule_date_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'tanggal Jadwal',
              message: 'Tanggal Jadwal belum ada.',
            ),
          );
        }
      case FfmAssistantDraftKind.scheduleUpdate:
      case FfmAssistantDraftKind.scheduleArchive:
        if (_isBlank(draft.formValues['targetId'])) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'schedule_target_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'Jadwal',
              message: 'Jadwal target belum ditemukan secara unik.',
            ),
          );
        }
      case FfmAssistantDraftKind.reminderUpdate:
        if (_isBlank(draft.formValues['targetId'])) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'reminder_target_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'Pengingat',
              message: 'Pengingat target belum ditemukan secara unik.',
            ),
          );
        }
        if (_isBlank(draft.title) || draft.date == null) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'reminder_update_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'judul atau waktu Pengingat',
              message: 'Judul atau waktu baru Pengingat belum valid.',
            ),
          );
        }
      case FfmAssistantDraftKind.transactionUpdate:
      case FfmAssistantDraftKind.transactionArchive:
      case FfmAssistantDraftKind.transactionDelete:
      case FfmAssistantDraftKind.activityArchive:
      case FfmAssistantDraftKind.activityDelete:
      case FfmAssistantDraftKind.activityFinish:
      case FfmAssistantDraftKind.activityUpdate:
      case FfmAssistantDraftKind.activityEdit:
        if (_isBlank(draft.formValues['targetId'])) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'transaction_target_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'transaksi',
              message: 'Transaksi target belum ditemukan secara unik.',
            ),
          );
        }
      case FfmAssistantDraftKind.budget:
        if (!draft.hasAmount) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'budget_amount_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'batas anggaran',
              message: 'Batas anggarannya belum ada.',
            ),
          );
        }
      case FfmAssistantDraftKind.budgetUpdate:
      case FfmAssistantDraftKind.budgetArchive:
        if (_isBlank(draft.formValues['targetId'])) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'budget_target_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'pos Anggaran',
              message: 'Pos Anggaran belum ditemukan secara unik.',
            ),
          );
        }
        if (draft.kind == FfmAssistantDraftKind.budgetUpdate &&
            !draft.hasAmount) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'budget_amount_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'batas Anggaran',
              message: 'Batas Anggaran baru belum ada.',
            ),
          );
        }
      case FfmAssistantDraftKind.cashFlowProfile:
        if (_isBlank(draft.title) && _isBlank(draft.commodityOrBusinessType)) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'cycle_name_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'nama siklus atau komoditas',
              message: 'Nama siklus atau jenis komoditas belum ada. Contoh: "Siklus Padi Ciherang".',
            ),
          );
        }
        if (draft.initialCapital != null && draft.initialCapital! < 0) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'initial_capital_negative',
              severity: FfmAssistantDraftIssueSeverity.conflict,
              field: 'modal awal',
              message: 'Modal awal tidak boleh negatif.',
            ),
          );
        }
        if (draft.estimatedInflow != null && draft.estimatedInflow! < 0) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'estimated_inflow_negative',
              severity: FfmAssistantDraftIssueSeverity.conflict,
              field: 'estimasi panen/pemasukan',
              message: 'Estimasi panen atau pemasukan tidak boleh negatif.',
            ),
          );
        }
        if (draft.dailyLivingBudget != null && draft.dailyLivingBudget! < 0) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'daily_living_budget_negative',
              severity: FfmAssistantDraftIssueSeverity.conflict,
              field: 'jatah dapur harian',
              message: 'Jatah dapur harian tidak boleh negatif.',
            ),
          );
        }
        if (draft.dailyOperationalBudget != null &&
            draft.dailyOperationalBudget! < 0) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'daily_operational_budget_negative',
              severity: FfmAssistantDraftIssueSeverity.conflict,
              field: 'jatah operasional harian',
              message: 'Jatah operasional harian tidak boleh negatif.',
            ),
          );
        }
      case FfmAssistantDraftKind.monitoringJob:
        break;
    }
    return issues;
  }

  static bool _needsAmount(FfmAssistantDraftKind kind) => switch (kind) {
    FfmAssistantDraftKind.cashFlowProfile ||
    FfmAssistantDraftKind.masterData ||
    FfmAssistantDraftKind.reminder ||
    FfmAssistantDraftKind.activity ||
    FfmAssistantDraftKind.dailyNote ||
    FfmAssistantDraftKind.dailyNoteArchive ||
    FfmAssistantDraftKind.task ||
    FfmAssistantDraftKind.taskUpdate ||
    FfmAssistantDraftKind.taskComplete ||
    FfmAssistantDraftKind.taskReopen ||
    FfmAssistantDraftKind.taskArchive ||
    FfmAssistantDraftKind.routine ||
    FfmAssistantDraftKind.routineUpdate ||
    FfmAssistantDraftKind.routineMarkComplete ||
    FfmAssistantDraftKind.routineUnmarkComplete ||
    FfmAssistantDraftKind.routineActivate ||
    FfmAssistantDraftKind.routineDeactivate ||
    FfmAssistantDraftKind.routineArchive ||
    FfmAssistantDraftKind.schedule ||
    FfmAssistantDraftKind.scheduleUpdate ||
    FfmAssistantDraftKind.scheduleArchive ||
    FfmAssistantDraftKind.recurringTransactionUpdate ||
    FfmAssistantDraftKind.recurringTransactionArchive ||
    FfmAssistantDraftKind.merchantUpdate ||
    FfmAssistantDraftKind.merchantArchive ||
    FfmAssistantDraftKind.merchantDelete ||
    FfmAssistantDraftKind.tagUpdate ||
    FfmAssistantDraftKind.tagArchive ||
    FfmAssistantDraftKind.tagDelete ||
    FfmAssistantDraftKind.incomeSourceUpdate ||
    FfmAssistantDraftKind.incomeSourceArchive ||
    FfmAssistantDraftKind.incomeSourceDelete ||
    FfmAssistantDraftKind.categoryUpdate ||
    FfmAssistantDraftKind.categoryArchive ||
    FfmAssistantDraftKind.categoryDelete ||
    FfmAssistantDraftKind.accountUpdate ||
    FfmAssistantDraftKind.accountArchive ||
    FfmAssistantDraftKind.accountDelete ||
    FfmAssistantDraftKind.budgetArchive ||
    FfmAssistantDraftKind.reminderUpdate ||
    FfmAssistantDraftKind.profile ||
    FfmAssistantDraftKind.goalArchive ||
    FfmAssistantDraftKind.reminderArchive ||
    FfmAssistantDraftKind.transactionArchive ||
    FfmAssistantDraftKind.transactionDelete ||
    FfmAssistantDraftKind.activityArchive ||
    FfmAssistantDraftKind.activityDelete ||
    FfmAssistantDraftKind.monitoringJob => false,
    _ => true,
  };

  static void _validateTransfer(
    FfmAssistantDraft draft,
    List<FfmAssistantDraftIssue> issues,
  ) {
    if (_isBlank(draft.fromAccountName)) {
      issues.add(
        const FfmAssistantDraftIssue(
          code: 'transfer_source_required',
          severity: FfmAssistantDraftIssueSeverity.required,
          field: 'rekening asal',
          message: 'Pilih rekening asal dulu.',
        ),
      );
    }
    if (_isBlank(draft.toAccountName)) {
      issues.add(
        const FfmAssistantDraftIssue(
          code: 'transfer_destination_required',
          severity: FfmAssistantDraftIssueSeverity.required,
          field: 'rekening tujuan',
          message: 'Pilih rekening tujuan dulu.',
        ),
      );
    }
    final from = draft.fromAccountName?.trim().toLowerCase();
    final to = draft.toAccountName?.trim().toLowerCase();
    if (from != null && from.isNotEmpty && from == to) {
      issues.add(
        const FfmAssistantDraftIssue(
          code: 'transfer_same_account',
          severity: FfmAssistantDraftIssueSeverity.conflict,
          field: 'rekening',
          message:
              'Rekening asal dan tujuan sama. Pilih dua rekening yang berbeda.',
        ),
      );
    }
    if (draft.adminFee != null && draft.adminFee! < 0) {
      issues.add(
        const FfmAssistantDraftIssue(
          code: 'admin_fee_invalid',
          severity: FfmAssistantDraftIssueSeverity.conflict,
          field: 'biaya admin',
          message: 'Biaya admin tidak boleh negatif.',
        ),
      );
    }
    if (draft.adminFee != null &&
        draft.adminFee! > 0 &&
        draft.amount != null &&
        draft.adminFee! > draft.amount!) {
      issues.add(
        const FfmAssistantDraftIssue(
          code: 'admin_fee_unusual',
          severity: FfmAssistantDraftIssueSeverity.warning,
          field: 'biaya admin',
          message: 'Biaya admin lebih besar dari nominal transfer. Cek lagi kalau memang benar.',
        ),
      );
    }
  }

  static void _validateReceiptFields(
    FfmAssistantDraft draft,
    List<FfmAssistantDraftIssue> issues,
  ) {
    if (draft.tax != null && draft.tax! < 0 ||
        draft.discount != null && draft.discount! < 0) {
      issues.add(
        const FfmAssistantDraftIssue(
          code: 'receipt_adjustment_invalid',
          severity: FfmAssistantDraftIssueSeverity.conflict,
          field: 'pajak/diskon',
          message: 'Pajak dan diskon tidak boleh negatif.',
        ),
      );
    }
    if (draft.receiptPaidAmount != null && draft.receiptPaidAmount! < 0 ||
        draft.receiptChangeAmount != null && draft.receiptChangeAmount! < 0 ||
        draft.receiptChangeAmount != null && draft.receiptPaidAmount == null) {
      issues.add(
        const FfmAssistantDraftIssue(
          code: 'receipt_payment_invalid',
          severity: FfmAssistantDraftIssueSeverity.conflict,
          field: 'dibayar/kembalian',
          message: 'Nominal dibayar dan kembalian harus valid dan konsisten.',
        ),
      );
    }
    if (draft.items.isNotEmpty) {
      final subtotal = draft.items.fold<int>(
        0,
        (sum, item) => sum + item.calculatedTotal,
      );
      final expected = subtotal + (draft.tax ?? 0) - (draft.discount ?? 0);
      if (draft.amount != null && expected != draft.amount) {
        issues.add(
          const FfmAssistantDraftIssue(
            code: 'receipt_total_mismatch',
            severity: FfmAssistantDraftIssueSeverity.conflict,
            field: 'nominal',
            message: 'Total harus sama dengan subtotal + pajak - diskon.',
          ),
        );
      }
      for (final item in draft.items) {
        final calculatedSubtotal = (item.price * item.quantity).round();
        if (item.name.trim().isEmpty ||
            item.price <= 0 ||
            item.quantity <= 0 ||
            item.lineTotal != null && item.lineTotal != calculatedSubtotal) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'receipt_item_invalid',
              severity: FfmAssistantDraftIssueSeverity.conflict,
              field: 'items',
              message: 'Setiap item harus memiliki nama, harga, jumlah, dan total yang valid.',
            ),
          );
          break;
        }
      }
    } else if (draft.tax != null || draft.discount != null) {
      issues.add(
        const FfmAssistantDraftIssue(
          code: 'receipt_items_required',
          severity: FfmAssistantDraftIssueSeverity.required,
          field: 'items',
          message: 'Pajak atau diskon membutuhkan rincian item untuk verifikasi total.',
        ),
      );
    }
    if (draft.receiptPaidAmount != null &&
        draft.amount != null &&
        draft.receiptPaidAmount! - (draft.receiptChangeAmount ?? 0) !=
            draft.amount) {
      issues.add(
        const FfmAssistantDraftIssue(
          code: 'receipt_payment_mismatch',
          severity: FfmAssistantDraftIssueSeverity.conflict,
          field: 'dibayar/kembalian',
          message:
              'Nominal dibayar dikurangi kembalian harus sama dengan total.',
        ),
      );
    }
  }

  static void _validateTransactionDate(
    FfmAssistantDraft draft,
    List<FfmAssistantDraftIssue> issues,
  ) {
    if (draft.date == null) {
      issues.add(
        const FfmAssistantDraftIssue(
          code: 'transaction_date_required',
          severity: FfmAssistantDraftIssueSeverity.required,
          field: 'tanggal',
          message: 'Tanggal transaksi belum valid.',
        ),
      );
    }
  }

  static void _validateTransactionReferences(
    FfmAssistantDraft draft,
    List<FfmAssistantDraftIssue> issues,
  ) {
    final statusKeys = switch (draft.kind) {
      FfmAssistantDraftKind.income => const [
        'accountReferenceStatus',
        'toAccountReferenceStatus',
        'categoryReferenceStatus',
        'merchantReferenceStatus',
      ],
      FfmAssistantDraftKind.expense => const [
        'accountReferenceStatus',
        'fromAccountReferenceStatus',
        'categoryReferenceStatus',
        'merchantReferenceStatus',
      ],
      FfmAssistantDraftKind.transfer => const [
        'fromAccountReferenceStatus',
        'toAccountReferenceStatus',
      ],
      _ => const <String>[],
    };
    for (final key in statusKeys) {
      final status = draft.formValues[key]?.toString().trim().toLowerCase();
      if (status != null && status.isNotEmpty && status != 'resolved') {
        issues.add(
          FfmAssistantDraftIssue(
            code: 'transaction_reference_unresolved',
            severity: FfmAssistantDraftIssueSeverity.conflict,
            field: key,
            message: 'Referensi rekening, kategori, atau toko belum ditemukan secara unik.',
          ),
        );
      }
    }
    for (final key in const [
      'accountIsArchived',
      'fromAccountIsArchived',
      'toAccountIsArchived',
      'categoryIsArchived',
      'merchantIsArchived',
    ]) {
      if (draft.formValues[key] == true ||
          draft.formValues[key]?.toString().toLowerCase() == 'true') {
        issues.add(
          FfmAssistantDraftIssue(
            code: 'transaction_reference_archived',
            severity: FfmAssistantDraftIssueSeverity.conflict,
            field: key,
            message: 'Referensi transaksi sudah diarsipkan dan tidak dapat digunakan.',
          ),
        );
      }
    }
    final categoryType = draft.formValues['categoryType']
        ?.toString()
        .trim()
        .toLowerCase();
    final expectedType = draft.kind == FfmAssistantDraftKind.income
        ? 'income'
        : draft.kind == FfmAssistantDraftKind.expense
        ? 'expense'
        : null;
    if (categoryType != null &&
        categoryType.isNotEmpty &&
        expectedType != null &&
        categoryType != expectedType) {
      issues.add(
        const FfmAssistantDraftIssue(
          code: 'transaction_category_type_mismatch',
          severity: FfmAssistantDraftIssueSeverity.conflict,
          field: 'kategori',
          message: 'Jenis kategori tidak sesuai dengan jenis transaksi.',
        ),
      );
    }
  }

  static bool _isBlank(String? value) => value == null || value.trim().isEmpty;
}
