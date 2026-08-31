import 'dart:convert';

import '../domain/ffm_assistant_models.dart';

/// Membaca proposal terstruktur dari LLM eksternal maupun Gemini Cloud.
///
/// Layanan ini tidak menyimpan apa pun. Ia hanya menerima schema sempit lalu
/// mengubahnya menjadi draft yang tetap harus divalidasi dan dikonfirmasi oleh
/// Agent/flow resmi FFM.
class FfmAssistantProposalJsonService {
  static const formatVersion = 'ffm-assistant-proposal-v1';
  static const capabilityRequestFormatVersion =
      'ffm-assistant-capability-request-v1';

  /// Membaca permintaan capability Gemini yang sangat sempit. Kontrak ini
  /// sengaja hanya mengenali capability read-only yang di-allowlist; JSON ini
  /// bukan action plan dan tidak dapat membawa perintah mutasi.
  static FfmAssistantReadCapabilityRequestParseResult
  parseReadCapabilityRequest(String rawText) {
    final jsonText = _extractJson(rawText.trim());
    if (jsonText == null) {
      return const FfmAssistantReadCapabilityRequestParseResult.notRequest();
    }
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map ||
          decoded['formatVersion']?.toString() !=
              capabilityRequestFormatVersion) {
        return const FfmAssistantReadCapabilityRequestParseResult.notRequest();
      }
      if (decoded['kind']?.toString() != 'read_capability_request') {
        return const FfmAssistantReadCapabilityRequestParseResult.invalid(
          'Format request capability tidak dikenali.',
        );
      }
      final capabilityId = decoded['capabilityId']?.toString().trim() ?? '';
      // Capability read yang boleh dipanggil model harus punya adapter hasil
      // bounded sendiri. Jangan mengizinkan ID registry lain secara otomatis.
      if (capabilityId != 'read.summary' &&
          capabilityId != 'read.transactions' &&
          capabilityId != 'read.accounts' &&
          capabilityId != 'read.budget' &&
          capabilityId != 'read.categories' &&
          capabilityId != 'read.goals') {
        return const FfmAssistantReadCapabilityRequestParseResult.invalid(
          'Capability Gemini tidak diizinkan. Hanya read.summary, read.transactions, read.accounts, read.budget, read.categories, atau read.goals yang tersedia.',
        );
      }
      final arguments = decoded['arguments'];
      if (arguments != null && arguments is! Map) {
        return const FfmAssistantReadCapabilityRequestParseResult.invalid(
          'Argumen capability harus berupa objek JSON.',
        );
      }
      final period = arguments is Map
          ? arguments['period']?.toString().trim()
          : null;
      if (period != null && period.isNotEmpty && period != 'current_month') {
        return const FfmAssistantReadCapabilityRequestParseResult.invalid(
          'Capability baca Gemini hanya mendukung periode current_month.',
        );
      }
      final argumentMap = arguments is Map
          ? Map<String, dynamic>.from(arguments)
          : const <String, dynamic>{};
      const allowedArguments = {'period', 'startDate', 'endDate'};
      if (argumentMap.keys.any((key) => !allowedArguments.contains(key))) {
        return const FfmAssistantReadCapabilityRequestParseResult.invalid(
          'Argumen capability baca tidak diizinkan.',
        );
      }
      if (capabilityId == 'read.summary' && argumentMap.length > 1) {
        return const FfmAssistantReadCapabilityRequestParseResult.invalid(
          'read.summary tidak menerima filter tambahan.',
        );
      }
      if ((capabilityId == 'read.accounts' ||
              capabilityId == 'read.budget' ||
              capabilityId == 'read.categories' ||
              capabilityId == 'read.goals') &&
          argumentMap.isNotEmpty) {
        return FfmAssistantReadCapabilityRequestParseResult.invalid(
          '$capabilityId tidak menerima filter tambahan.',
        );
      }
      final startDate = _parseCapabilityDate(argumentMap['startDate']);
      final endDate = _parseCapabilityDate(argumentMap['endDate']);
      if ((argumentMap.containsKey('startDate') && startDate == null) ||
          (argumentMap.containsKey('endDate') && endDate == null)) {
        return const FfmAssistantReadCapabilityRequestParseResult.invalid(
          'Tanggal capability harus berformat YYYY-MM-DD.',
        );
      }
      if ((startDate == null) != (endDate == null)) {
        return const FfmAssistantReadCapabilityRequestParseResult.invalid(
          'Filter transaksi harus menyertakan startDate dan endDate bersama-sama.',
        );
      }
      if (startDate != null &&
          (endDate!.isBefore(startDate) ||
              endDate.difference(startDate).inDays > 13)) {
        return const FfmAssistantReadCapabilityRequestParseResult.invalid(
          'Rentang transaksi harus berurutan dan maksimal 14 hari.',
        );
      }
      return FfmAssistantReadCapabilityRequestParseResult.request(
        FfmAssistantReadCapabilityRequest(
          capabilityId: capabilityId,
          period: 'current_month',
          startDate: startDate,
          endDate: endDate,
        ),
      );
    } on FormatException {
      return const FfmAssistantReadCapabilityRequestParseResult.invalid(
        'JSON request capability belum valid.',
      );
    }
  }

  static DateTime? _parseCapabilityDate(Object? value) {
    final raw = value?.toString().trim() ?? '';
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) return null;
    final parsed = DateTime.tryParse(raw);
    return parsed != null && parsed.toIso8601String().startsWith(raw)
        ? DateTime(parsed.year, parsed.month, parsed.day)
        : null;
  }

  static FfmAssistantProposalParseResult parse(
    String rawText, {
    required DateTime createdAt,
  }) {
    final jsonText = _extractJson(rawText.trim());
    if (jsonText == null) {
      return const FfmAssistantProposalParseResult.notProposal();
    }
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map ||
          decoded['formatVersion']?.toString() != formatVersion) {
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
      final proposal = Map<String, dynamic>.from(rawProposal);
      return switch (proposal['type']?.toString()) {
        'master_data' => _parseMasterData(proposal, createdAt),
        'transaction' => _parseTransaction(proposal, createdAt),
        'activity' => _parseActivity(proposal, createdAt),
        'goal' => _parseGoal(proposal, createdAt),
        'budget' => _parseBudget(proposal, createdAt),
        'memory' => _parseMemory(proposal),
        _ => const FfmAssistantProposalParseResult.invalid(
          'Jenis proposal belum didukung. Gunakan master_data, transaction, activity, goal, budget, atau memory.',
        ),
      };
    } on FormatException {
      return const FfmAssistantProposalParseResult.invalid(
        'JSON proposal belum valid. Salin ulang hasil LLM tanpa Markdown atau teks tambahan.',
      );
    }
  }

  /// Parse beberapa proposal sekaligus dari satu respon LLM.
  ///
  /// Mendukung format:
  /// ```json
  /// { "formatVersion": "ffm-assistant-proposal-v1", "proposals": [ ... ] }
  /// ```
  /// atau fallback ke `parse()` single proposal.
  static FfmAssistantMultiProposalParseResult parseMultiple(
    String rawText, {
    required DateTime createdAt,
  }) {
    final jsonText = _extractJson(rawText.trim());
    if (jsonText == null) {
      return const FfmAssistantMultiProposalParseResult.notProposal();
    }
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map ||
          decoded['formatVersion']?.toString() != formatVersion) {
        return const FfmAssistantMultiProposalParseResult.notProposal();
      }
      final rawProposals = decoded['proposals'];
      if (rawProposals is List && rawProposals.isNotEmpty) {
        final drafts = <FfmAssistantDraft>[];
        final teachings = <FfmAssistantTeachingProposal>[];
        String? firstError;
        for (final item in rawProposals) {
          if (item is! Map) continue;
          final proposal = Map<String, dynamic>.from(item);
          final result = switch (proposal['type']?.toString()) {
            'master_data' => _parseMasterData(proposal, createdAt),
            'transaction' => _parseTransaction(proposal, createdAt),
            'activity' => _parseActivity(proposal, createdAt),
            'goal' => _parseGoal(proposal, createdAt),
            'budget' => _parseBudget(proposal, createdAt),
            'memory' => _parseMemory(proposal),
            _ => const FfmAssistantProposalParseResult.invalid(
              'Jenis proposal belum didukung.',
            ),
          };
          if (result.error != null && firstError == null) {
            firstError = result.error;
          }
          if (result.draft != null) drafts.add(result.draft!);
          if (result.teachingProposal != null) {
            teachings.add(result.teachingProposal!);
          }
        }
        if (drafts.isEmpty && teachings.isEmpty && firstError != null) {
          return FfmAssistantMultiProposalParseResult.error(firstError);
        }
        return FfmAssistantMultiProposalParseResult.multi(
          drafts: drafts,
          teachingProposals: teachings,
        );
      }
      final single = parse(rawText, createdAt: createdAt);
      if (single.draft != null) {
        return FfmAssistantMultiProposalParseResult.multi(
          drafts: [single.draft!],
          teachingProposals: const [],
        );
      }
      if (single.teachingProposal != null) {
        return FfmAssistantMultiProposalParseResult.multi(
          drafts: const [],
          teachingProposals: [single.teachingProposal!],
        );
      }
      if (single.error != null) {
        return FfmAssistantMultiProposalParseResult.error(single.error!);
      }
      return const FfmAssistantMultiProposalParseResult.notProposal();
    } on FormatException {
      return const FfmAssistantMultiProposalParseResult.error(
        'JSON proposal belum valid.',
      );
    }
  }

  static FfmAssistantProposalParseResult _parseMasterData(
    Map<String, dynamic> proposal,
    DateTime createdAt,
  ) {
    final target = _targetFor(proposal['target']?.toString());
    final name = _boundedText(proposal['name'], 100);
    if (target == null || name == null) {
      return const FfmAssistantProposalParseResult.invalid(
        'Target Data Utama dan nama wajib diisi.',
      );
    }
    final rawFields = proposal['fields'];
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
        'Ada nilai form yang tidak didukung pada Data Utama.',
      );
    }
    return FfmAssistantProposalParseResult.draft(
      FfmAssistantDraft(
        kind: FfmAssistantDraftKind.masterData,
        createdAt: createdAt,
        title: name,
        categoryName: target,
        note: _boundedText(proposal['note'], 300),
        formValues: safeFields,
      ),
    );
  }

  static FfmAssistantProposalParseResult _parseTransaction(
    Map<String, dynamic> proposal,
    DateTime createdAt,
  ) {
    final kind = switch (proposal['kind']?.toString().trim().toLowerCase()) {
      'income' || 'pemasukan' => FfmAssistantDraftKind.income,
      'expense' || 'pengeluaran' => FfmAssistantDraftKind.expense,
      'transfer' => FfmAssistantDraftKind.transfer,
      _ => null,
    };
    final amount = _positiveInt(proposal['amount']);
    if (kind == null || amount == null) {
      return const FfmAssistantProposalParseResult.invalid(
        'Jenis transaksi dan nominal lebih dari nol wajib diisi.',
      );
    }
    return FfmAssistantProposalParseResult.draft(
      FfmAssistantDraft(
        kind: kind,
        createdAt: createdAt,
        amount: amount,
        title: _boundedText(proposal['title'] ?? proposal['merchant'], 120),
        partyName: _boundedText(proposal['party'], 120),
        fromAccountName: _boundedText(proposal['fromAccount'], 100),
        toAccountName: _boundedText(proposal['toAccount'], 100),
        categoryName: _boundedText(proposal['category'], 100),
        note: _boundedText(proposal['note'], 300),
        date: _dateOr(proposal['date'], createdAt),
        formValues: const {'source': 'gemini_proposal'},
      ),
    );
  }

  static FfmAssistantProposalParseResult _parseActivity(
    Map<String, dynamic> proposal,
    DateTime createdAt,
  ) {
    final title = _boundedText(proposal['title'] ?? proposal['name'], 120);
    if (title == null) {
      return const FfmAssistantProposalParseResult.invalid(
        'Judul aktivitas wajib diisi.',
      );
    }
    final category = _boundedText(proposal['category'], 100);
    return FfmAssistantProposalParseResult.draft(
      FfmAssistantDraft(
        kind: FfmAssistantDraftKind.activity,
        createdAt: createdAt,
        title: title,
        note: _boundedText(proposal['note'], 300),
        date: _dateOr(proposal['date'], createdAt),
        formValues: {
          'source': 'gemini_proposal',
          ...?(category == null ? null : {'category': category}),
        },
      ),
    );
  }

  static FfmAssistantProposalParseResult _parseMemory(
    Map<String, dynamic> proposal,
  ) {
    const allowedKinds = {
      'profile',
      'preference',
      'goal',
      'habit',
      'explicitFact',
      'correction',
      'identity',
    };
    final kind = proposal['kind']?.toString().trim() ?? '';
    final trigger = _boundedText(proposal['trigger'], 200);
    final value = _boundedText(proposal['value'], 500);
    if (!allowedKinds.contains(kind) || trigger == null || value == null) {
      return const FfmAssistantProposalParseResult.invalid(
        'Memory harus memiliki kind yang didukung, trigger, dan value.',
      );
    }
    return FfmAssistantProposalParseResult.teaching(
      FfmAssistantTeachingProposal(
        kind: kind,
        triggerText: trigger,
        valueText: value,
      ),
    );
  }

  static FfmAssistantProposalParseResult _parseGoal(
    Map<String, dynamic> proposal,
    DateTime createdAt,
  ) {
    final title = _boundedText(proposal['title'] ?? proposal['name'], 100);
    if (title == null) {
      return const FfmAssistantProposalParseResult.invalid(
        'Target keuangan wajib punya nama/judul.',
      );
    }
    final amount = _positiveInt(proposal['amount'] ?? proposal['targetAmount']);
    final note = _boundedText(proposal['note'], 200);
    final date = _dateOr(proposal['targetDate'], createdAt.add(const Duration(days: 30)));

    return FfmAssistantProposalParseResult.draft(FfmAssistantDraft(
      kind: FfmAssistantDraftKind.goal,
      createdAt: createdAt,
      title: title,
      amount: amount,
      note: note,
      date: date,
    ));
  }

  static FfmAssistantProposalParseResult _parseBudget(
    Map<String, dynamic> proposal,
    DateTime createdAt,
  ) {
    final title = _boundedText(proposal['title'] ?? proposal['category'] ?? proposal['name'], 100);
    if (title == null) {
      return const FfmAssistantProposalParseResult.invalid(
        'Anggaran wajib punya nama/kategori.',
      );
    }
    final amount = _positiveInt(proposal['amount'] ?? proposal['limit'] ?? proposal['budgetAmount']);
    final note = _boundedText(proposal['note'], 200);

    return FfmAssistantProposalParseResult.draft(FfmAssistantDraft(
      kind: FfmAssistantDraftKind.budget,
      createdAt: createdAt,
      title: title,
      amount: amount,
      categoryName: title,
      note: note,
      date: createdAt,
    ));
  }

  static String? _extractJson(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    return text.substring(start, end + 1);
  }

  static String? _boundedText(Object? value, int maxLength) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return null;
    return text.length <= maxLength ? text : text.substring(0, maxLength);
  }

  static int? _positiveInt(Object? value) {
    if (value is num) {
      final result = value.toInt();
      return result > 0 ? result : null;
    }
    final digits = value?.toString().replaceAll(RegExp(r'[^0-9]'), '') ?? '';
    final result = int.tryParse(digits);
    return result != null && result > 0 ? result : null;
  }

  static DateTime _dateOr(Object? value, DateTime fallback) =>
      DateTime.tryParse(value?.toString() ?? '') ?? fallback;

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
      final balance = int.tryParse(
        (fields['openingBalance']?.trim().isEmpty ?? true)
            ? '0'
            : fields['openingBalance']!.replaceAll(RegExp(r'[^0-9]'), ''),
      );
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
  const FfmAssistantProposalParseResult._({
    this.draft,
    this.teachingProposal,
    this.error,
  });

  const FfmAssistantProposalParseResult.notProposal() : this._();
  const FfmAssistantProposalParseResult.invalid(String error)
    : this._(error: error);
  const FfmAssistantProposalParseResult.draft(FfmAssistantDraft draft)
    : this._(draft: draft);
  const FfmAssistantProposalParseResult.teaching(
    FfmAssistantTeachingProposal teachingProposal,
  ) : this._(teachingProposal: teachingProposal);

  final FfmAssistantDraft? draft;
  final FfmAssistantTeachingProposal? teachingProposal;
  final String? error;

  bool get isProposal =>
      draft != null || teachingProposal != null || error != null;
}

class FfmAssistantMultiProposalParseResult {
  const FfmAssistantMultiProposalParseResult._({
    this.drafts = const [],
    this.teachingProposals = const [],
    this.error,
  });

  const FfmAssistantMultiProposalParseResult.notProposal() : this._();
  const FfmAssistantMultiProposalParseResult.error(String error)
    : this._(error: error);
  const FfmAssistantMultiProposalParseResult.multi({
    required List<FfmAssistantDraft> drafts,
    required List<FfmAssistantTeachingProposal> teachingProposals,
  }) : this._(drafts: drafts, teachingProposals: teachingProposals);

  final List<FfmAssistantDraft> drafts;
  final List<FfmAssistantTeachingProposal> teachingProposals;
  final String? error;

  bool get isProposal =>
      drafts.isNotEmpty || teachingProposals.isNotEmpty || error != null;
  bool get hasMultipleDrafts => drafts.length > 1;
}

class FfmAssistantReadCapabilityRequest {
  const FfmAssistantReadCapabilityRequest({
    required this.capabilityId,
    required this.period,
    this.startDate,
    this.endDate,
  });

  final String capabilityId;
  final String period;
  final DateTime? startDate;
  final DateTime? endDate;
}

class FfmAssistantReadCapabilityRequestParseResult {
  const FfmAssistantReadCapabilityRequestParseResult._({
    this.request,
    this.error,
  });

  const FfmAssistantReadCapabilityRequestParseResult.notRequest() : this._();
  const FfmAssistantReadCapabilityRequestParseResult.request(
    FfmAssistantReadCapabilityRequest request,
  ) : this._(request: request);
  const FfmAssistantReadCapabilityRequestParseResult.invalid(String error)
    : this._(error: error);

  final FfmAssistantReadCapabilityRequest? request;
  final String? error;
}
