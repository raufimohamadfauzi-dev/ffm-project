import 'dart:convert';

import '../domain/ffm_assistant_models.dart';

/// Membaca proposal yang pengguna tempel dari LLM eksternal.
///
/// Layanan ini tidak menyimpan apa pun. Ia hanya menerima schema sempit untuk
/// Data Utama lalu mengubahnya menjadi rancangan yang tetap harus dibuka dan
/// disimpan sendiri oleh pengguna melalui form resmi FFM.
class FfmAssistantProposalJsonService {
  static const formatVersion = 'ffm-assistant-proposal-v1';

  static FfmAssistantProposalParseResult parse(
    String rawText, {
    required DateTime createdAt,
  }) {
    final trimmed = rawText.trim();
    if (!trimmed.startsWith('{')) {
      return const FfmAssistantProposalParseResult.notProposal();
    }
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) {
        return const FfmAssistantProposalParseResult.notProposal();
      }
      if (decoded['formatVersion']?.toString() != formatVersion) {
        return const FfmAssistantProposalParseResult.notProposal();
      }
      final rawProposal = decoded['proposal'];
      if (rawProposal == null) {
        final clarification = decoded['clarification']?.toString().trim() ?? '';
        return FfmAssistantProposalParseResult.invalid(
          clarification.isEmpty
              ? 'Proposal belum bisa dibuat karena masih ada informasi yang kurang.'
              : clarification,
        );
      }
      if (rawProposal is! Map) {
        return const FfmAssistantProposalParseResult.invalid(
          'Proposal JSON belum punya objek “proposal”.',
        );
      }
      if (rawProposal['type']?.toString() != 'master_data') {
        return const FfmAssistantProposalParseResult.invalid(
          'Untuk saat ini proposal JSON hanya mendukung Data Utama.',
        );
      }
      final target = _targetFor(rawProposal['target']?.toString());
      if (target == null) {
        return const FfmAssistantProposalParseResult.invalid(
          'Target Data Utama harus kategori, toko, tag, rekening, atau sumber pemasukan.',
        );
      }
      final name = rawProposal['name']?.toString().trim() ?? '';
      if (name.isEmpty || name.length > 100) {
        return const FfmAssistantProposalParseResult.invalid(
          'Nama Data Utama wajib diisi dan maksimal 100 karakter.',
        );
      }
      final rawFields = rawProposal['fields'];
      if (rawFields != null && rawFields is! Map) {
        return const FfmAssistantProposalParseResult.invalid(
          'Bagian “fields” harus berbentuk objek JSON.',
        );
      }
      final fields = rawFields is Map
          ? rawFields.map((key, value) => MapEntry('$key', '$value'))
          : <String, String>{};
      final safeFields = _safeFields(target, fields);
      if (safeFields == null) {
        return const FfmAssistantProposalParseResult.invalid(
          'Ada nilai form yang tidak didukung. Cek jenis kategori, jenis rekening, periode, atau saldo awalnya.',
        );
      }
      return FfmAssistantProposalParseResult.draft(
        FfmAssistantDraft(
          kind: FfmAssistantDraftKind.masterData,
          createdAt: createdAt,
          title: name,
          categoryName: target,
          note: rawProposal['note']?.toString().trim().isEmpty ?? true
              ? null
              : rawProposal['note'].toString().trim().substring(
                  0,
                  rawProposal['note'].toString().trim().length > 300
                      ? 300
                      : rawProposal['note'].toString().trim().length,
                ),
          formValues: safeFields,
        ),
      );
    } on FormatException {
      return const FfmAssistantProposalParseResult.invalid(
        'JSON proposal belum valid. Salin ulang hasil LLM tanpa Markdown atau teks tambahan.',
      );
    }
  }

  static String? _targetFor(String? raw) => switch (raw?.trim().toLowerCase()) {
    'kategori' || 'category' => 'kategori',
    'toko' || 'merchant' || 'tempat' => 'toko',
    'tag' => 'tag',
    'rekening' || 'account' => 'rekening',
    'sumber_pemasukan' ||
    'income_source' ||
    'sumber pemasukan' => 'sumber_pemasukan',
    _ => null,
  };

  static Map<String, String>? _safeFields(
    String target,
    Map<String, String> fields,
  ) {
    String value(String key) => fields[key]?.trim().toLowerCase() ?? '';
    final safe = <String, String>{};
    if (target == 'kategori') {
      final type = switch (value('type')) {
        'income' || 'pemasukan' => 'income',
        'expense' || 'pengeluaran' || '' => 'expense',
        _ => null,
      };
      final period = switch (value('defaultBudgetPeriod')) {
        'none' || 'tidak ada' || '' => 'none',
        'weekly' || 'mingguan' => 'weekly',
        'monthly' || 'bulanan' => 'monthly',
        _ => null,
      };
      if (type == null || period == null) return null;
      safe
        ..['type'] = type
        ..['defaultBudgetPeriod'] = type == 'income' ? 'none' : period;
    } else if (target == 'rekening') {
      final accountType = switch (value('accountType')) {
        'cash' || 'tunai' || '' => 'cash',
        'bank' => 'bank',
        'ewallet' || 'e-wallet' || 'dompet digital' => 'ewallet',
        _ => null,
      };
      final rawBalance = fields['openingBalance']?.trim() ?? '';
      final balance = rawBalance.isEmpty
          ? 0
          : int.tryParse(rawBalance.replaceAll(RegExp(r'[^0-9]'), ''));
      if (accountType == null || balance == null || balance < 0) return null;
      safe
        ..['accountType'] = accountType
        ..['openingBalance'] = '$balance';
    } else if (target == 'toko' || target == 'sumber_pemasukan') {
      final details = fields['details']?.trim() ?? '';
      if (details.length > 300) return null;
      if (details.isNotEmpty) safe['details'] = details;
    }
    return safe;
  }
}

class FfmAssistantProposalParseResult {
  const FfmAssistantProposalParseResult._({this.draft, this.error});

  const FfmAssistantProposalParseResult.notProposal() : this._();
  const FfmAssistantProposalParseResult.invalid(String error)
    : this._(error: error);
  const FfmAssistantProposalParseResult.draft(FfmAssistantDraft draft)
    : this._(draft: draft);

  final FfmAssistantDraft? draft;
  final String? error;

  bool get isProposal => draft != null || error != null;
}
