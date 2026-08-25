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
      case FfmAssistantDraftKind.income:
        if (_isBlank(draft.toAccountName)) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'income_destination_untracked',
              severity: FfmAssistantDraftIssueSeverity.warning,
              field: 'rekening tujuan',
              message: 'Rekening tujuan belum dipilih. Pemasukan akan berstatus Belum terlacak jika kamu lanjut.',
            ),
          );
        }
      case FfmAssistantDraftKind.expense:
        if (_isBlank(draft.fromAccountName)) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'expense_source_untracked',
              severity: FfmAssistantDraftIssueSeverity.warning,
              field: 'rekening sumber',
              message: 'Rekening sumber belum dipilih. Pengeluaran akan berstatus Belum terlacak jika kamu lanjut.',
            ),
          );
        }
      case FfmAssistantDraftKind.goalDeposit:
      case FfmAssistantDraftKind.goalUsage:
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
        if (_isBlank(draft.partyName)) {
          issues.add(
            const FfmAssistantDraftIssue(
              code: 'party_required',
              severity: FfmAssistantDraftIssueSeverity.required,
              field: 'nama orang',
              message:
                  'Sebut nama orangnya dulu supaya catatan tidak tertukar.',
            ),
          );
        }
      case FfmAssistantDraftKind.asset:
      case FfmAssistantDraftKind.masterData:
      case FfmAssistantDraftKind.reminder:
      case FfmAssistantDraftKind.activity:
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
      case FfmAssistantDraftKind.transactionUpdate:
      case FfmAssistantDraftKind.transactionArchive:
      case FfmAssistantDraftKind.transactionDelete:
      case FfmAssistantDraftKind.activityArchive:
      case FfmAssistantDraftKind.activityDelete:
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
    }
    return issues;
  }

  static bool _needsAmount(FfmAssistantDraftKind kind) => switch (kind) {
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
    FfmAssistantDraftKind.profile ||
    FfmAssistantDraftKind.goalArchive ||
    FfmAssistantDraftKind.reminderArchive ||
    FfmAssistantDraftKind.transactionArchive ||
    FfmAssistantDraftKind.transactionDelete ||
    FfmAssistantDraftKind.activityArchive ||
    FfmAssistantDraftKind.activityDelete => false,
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

  static bool _isBlank(String? value) => value == null || value.trim().isEmpty;
}
