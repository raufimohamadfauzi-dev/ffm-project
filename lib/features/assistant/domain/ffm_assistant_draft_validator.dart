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
    FfmAssistantDraftKind.profile => false,
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
