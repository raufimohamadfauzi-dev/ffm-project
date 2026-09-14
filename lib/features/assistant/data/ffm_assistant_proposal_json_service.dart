import 'dart:convert';

import '../../activity/domain/activity_mode_detector.dart';
import '../../activity/domain/entities/activity_entity.dart';
import '../../transaction/data/services/receipt_import_models.dart';
import '../domain/ffm_assistant_models.dart';
import '../domain/ffm_assistant_monitoring_job.dart';
import 'ffm_gemini_read_capability_service.dart';

/// Membaca proposal terstruktur dari LLM eksternal maupun Gemini Cloud.
///
/// Layanan ini tidak menyimpan apa pun. Ia hanya menerima schema sempit lalu
/// mengubahnya menjadi draft yang tetap harus divalidasi dan dikonfirmasi oleh
/// Agent/flow resmi FFM.
class FfmAssistantProposalJsonService {
  static const formatVersion = 'ffm-assistant-proposal-v1';
  static const capabilityRequestFormatVersion =
      'ffm-assistant-capability-request-v1';
  static const _userFriendlyError =
      'Maaf, saya belum bisa memproses permintaan ini. Coba gunakan kata kunci lain atau jelaskan dengan cara berbeda.';
  static Set<String> get geminiReadCapabilityIds =>
      FfmGeminiReadCapabilityPolicy.allowedCapabilityIds;

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
      if (!geminiReadCapabilityIds.contains(capabilityId)) {
        return FfmAssistantReadCapabilityRequestParseResult.invalid(
          'Capability Gemini tidak diizinkan. Pilihan yang tersedia: ${FfmGeminiReadCapabilityPolicy.formattedToolChoices}.',
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
      const allowedPeriods = {
        'current_month',
        'last_month',
        'last_3_months',
        'last_year',
        'year_to_date',
        'all_time',
      };
      if (period != null &&
          period.isNotEmpty &&
          !allowedPeriods.contains(period)) {
        return const FfmAssistantReadCapabilityRequestParseResult.invalid(
          'Periode capability baca tidak valid.',
        );
      }
      final argumentMap = arguments is Map
          ? Map<String, dynamic>.from(arguments)
          : const <String, dynamic>{};
      const allowedArguments = {
        'period',
        'startDate',
        'endDate',
        'tag',
        'tags',
        'treatmentType',
      };
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
      final startDate = _parseCapabilityDate(argumentMap['startDate']);
      final endDate = _parseCapabilityDate(argumentMap['endDate']);
      final treatmentType = argumentMap['treatmentType']
          ?.toString()
          .trim()
          .toLowerCase();
      if (treatmentType != null &&
          treatmentType.isNotEmpty &&
          treatmentType != 'obat' &&
          treatmentType != 'pupuk') {
        return const FfmAssistantReadCapabilityRequestParseResult.invalid(
          'Jenis perlakuan harus obat atau pupuk.',
        );
      }
      final tagValue = argumentMap['tags'] ?? argumentMap['tag'];
      final tags = tagValue is String
          ? tagValue
                .split(',')
                .map((value) => value.trim())
                .where((value) => value.isNotEmpty)
                .toList(growable: false)
          : const <String>[];
      if (tagValue != null && tagValue is! String) {
        return const FfmAssistantReadCapabilityRequestParseResult.invalid(
          'Tag/lahan harus berupa teks atau daftar dipisahkan koma.',
        );
      }
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
              endDate.difference(startDate).inDays > 730)) {
        return const FfmAssistantReadCapabilityRequestParseResult.invalid(
          'Rentang transaksi harus berurutan dan maksimal 730 hari (2 tahun).',
        );
      }
      return FfmAssistantReadCapabilityRequestParseResult.request(
        FfmAssistantReadCapabilityRequest(
          capabilityId: capabilityId,
          period: period ?? 'current_month',
          startDate: startDate,
          endDate: endDate,
          tagNames: tags,
          treatmentType: treatmentType?.isEmpty == true ? null : treatmentType,
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
      // Dukung bentuk navigasi "top-level" yang diinstruksikan ke Gemini:
      // {"formatVersion":"...","navigation":"masterData"}. Tanpa objek proposal,
      // field `navigation` di level atas tetap diperlakukan sebagai proposal.
      if (rawProposal == null) {
        final topLevelNavigation =
            decoded['navigation']?.toString().trim() ?? '';
        if (topLevelNavigation.isNotEmpty) {
          return _parseNavigation({'navigation': topLevelNavigation});
        }
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
        'daily_note' ||
        'dailyNote' ||
        'note' => _parseDailyNote(proposal, createdAt),
        'reminder' => _parseReminder(proposal, createdAt),
        'goal' => _parseGoal(proposal, createdAt),
        'goal_deposit' ||
        'goalDeposit' => _parseGoalDeposit(proposal, createdAt),
        'goal_usage' || 'goalUsage' => _parseGoalUsage(proposal, createdAt),
        'budget' => _parseBudget(proposal, createdAt),
        'liability' ||
        'debt' ||
        'hutang' => _parseLiability(proposal, createdAt),
        'receivable' || 'piutang' => _parseReceivable(proposal, createdAt),
        'liability_payment' ||
        'debt_payment' ||
        'pay_debt' ||
        'pay_liability' => _parseLiabilityPayment(proposal, createdAt),
        'receivable_payment' ||
        'receive_receivable' => _parseReceivablePayment(proposal, createdAt),
        'cash_flow_profile' ||
        'cashFlowProfile' ||
        'cycle' ||
        'agrotrack' => _parseCashFlowProfile(proposal, createdAt),
        'monitoring_job' ||
        'monitoringJob' ||
        'monitoring' => _parseMonitoringJob(proposal, createdAt),
        'memory' => _parseMemory(proposal),
        'navigation' => _parseNavigation(proposal),
        _ => const FfmAssistantProposalParseResult.invalid(_userFriendlyError),
      };
    } on FormatException {
      return const FfmAssistantProposalParseResult.invalid(_userFriendlyError);
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
            'daily_note' ||
            'dailyNote' ||
            'note' => _parseDailyNote(proposal, createdAt),
            'reminder' => _parseReminder(proposal, createdAt),
            'goal' => _parseGoal(proposal, createdAt),
            'goal_deposit' ||
            'goalDeposit' => _parseGoalDeposit(proposal, createdAt),
            'goal_usage' || 'goalUsage' => _parseGoalUsage(proposal, createdAt),
            'budget' => _parseBudget(proposal, createdAt),
            'liability' ||
            'debt' ||
            'hutang' => _parseLiability(proposal, createdAt),
            'receivable' || 'piutang' => _parseReceivable(proposal, createdAt),
            'liability_payment' ||
            'debt_payment' ||
            'pay_debt' ||
            'pay_liability' => _parseLiabilityPayment(proposal, createdAt),
            'receivable_payment' || 'receive_receivable' =>
              _parseReceivablePayment(proposal, createdAt),
            'cash_flow_profile' ||
            'cashFlowProfile' ||
            'cycle' ||
            'agrotrack' => _parseCashFlowProfile(proposal, createdAt),
            'monitoring_job' ||
            'monitoringJob' ||
            'monitoring' => _parseMonitoringJob(proposal, createdAt),
            'memory' => _parseMemory(proposal),
            'navigation' => _parseNavigation(proposal),
            _ => const FfmAssistantProposalParseResult.invalid(
              _userFriendlyError,
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
        _userFriendlyError,
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
    final rawDate = proposal['date']?.toString().trim();
    if (rawDate != null &&
        rawDate.isNotEmpty &&
        !_isValidTransactionDate(rawDate)) {
      return const FfmAssistantProposalParseResult.invalid(
        'Tanggal transaksi tidak valid.',
      );
    }

    final adminFee = _positiveInt(proposal['adminFee']);
    final hijriDate = proposal['hijriDate']?.toString().trim();
    final tags = _csvValue(proposal['tags']);
    final newTags = _csvValue(proposal['newTags']);
    final newMerchant = _boundedText(proposal['newMerchant'], 120);
    final receiptNumber = _boundedText(
      proposal['receiptNumber'] ?? proposal['nomorNota'],
      100,
    );
    final receiptPaidAmount = _nonNegativeInt(
      proposal['paidAmount'] ?? proposal['receiptPaidAmount'],
    );
    final receiptChangeAmount = _nonNegativeInt(
      proposal['changeAmount'] ?? proposal['receiptChangeAmount'],
    );
    final tax = _nonNegativeInt(proposal['tax'] ?? proposal['pajak']);
    final discount = _nonNegativeInt(
      proposal['discount'] ?? proposal['diskon'],
    );
    final receiptRawText = _boundedText(proposal['receiptRawText'], 1000);
    final location = _boundedText(
      proposal['location'] ?? proposal['lokasi'],
      200,
    );
    final sourceId = _boundedText(proposal['sourceId'], 120);
    final source = _boundedText(proposal['source'], 60);
    final recurringTransactionId = _boundedText(
      proposal['recurringTransactionId'],
      120,
    );
    final linkedActivityId = _boundedText(proposal['linkedActivityId'], 120);
    final attachmentPaths = proposal['attachmentPaths'] is List
        ? (proposal['attachmentPaths'] as List)
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .take(20)
              .toList(growable: false)
        : const <String>[];

    final rawItems = proposal['items'];
    final items = _receiptItems(rawItems);
    if (rawItems != null && items == null) {
      return const FfmAssistantProposalParseResult.invalid(
        'Rincian item transaksi tidak valid.',
      );
    }
    final itemsJson = items == null || items.isEmpty
        ? null
        : jsonEncode(_receiptItemsJson(items));

    final formValues = <String, dynamic>{
      'source': 'gemini_proposal',
      if (hijriDate != null && hijriDate.isNotEmpty) 'hijriDate': hijriDate,
      if (receiptNumber?.isNotEmpty == true) 'receiptNumber': receiptNumber!,
      if (receiptPaidAmount != null)
        'receiptPaidAmount': receiptPaidAmount.toString(),
      if (receiptChangeAmount != null)
        'receiptChangeAmount': receiptChangeAmount.toString(),
      if (receiptRawText?.isNotEmpty == true) 'receiptRawText': receiptRawText!,
      if (itemsJson?.isNotEmpty == true) 'itemsJson': itemsJson!,
      if (attachmentPaths.isNotEmpty)
        'attachmentPathsJson': jsonEncode(attachmentPaths),
    };
    if (tags != null) formValues['tags'] = tags;
    if (newTags != null) formValues['newTags'] = newTags;
    if (newMerchant != null) formValues['newMerchant'] = newMerchant;
    if (location?.isNotEmpty == true) formValues['location'] = location!;
    final incomeSource = _boundedText(proposal['incomeSource'], 120);
    if (incomeSource?.isNotEmpty == true) {
      formValues['incomeSource'] = incomeSource!;
    }
    for (final key in const [
      'accountId',
      'fromAccountId',
      'toAccountId',
      'categoryId',
      'merchantId',
      'accountReferenceStatus',
      'fromAccountReferenceStatus',
      'toAccountReferenceStatus',
      'categoryReferenceStatus',
      'merchantReferenceStatus',
      'accountIsArchived',
      'fromAccountIsArchived',
      'toAccountIsArchived',
      'categoryIsArchived',
      'merchantIsArchived',
      'categoryType',
    ]) {
      final value = proposal[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        formValues[key] = value;
      }
    }

    return FfmAssistantProposalParseResult.draft(
      FfmAssistantDraft(
        kind: kind,
        createdAt: createdAt,
        amount: amount,
        title: _boundedText(proposal['title'] ?? proposal['merchant'], 120),
        merchantName: _boundedText(proposal['merchant'], 120),
        location: location,
        partyName: _boundedText(
          proposal['party'] ??
              proposal['partyName'] ??
              proposal['incomeSource'],
          120,
        ),
        fromAccountName: _boundedText(
          proposal['fromAccount'] ??
              (kind == FfmAssistantDraftKind.expense
                  ? proposal['account'] ?? proposal['accountName']
                  : null),
          100,
        ),
        toAccountName: _boundedText(
          proposal['toAccount'] ??
              (kind == FfmAssistantDraftKind.income
                  ? proposal['account'] ?? proposal['accountName']
                  : null),
          100,
        ),
        categoryName: _boundedText(
          proposal['category'] ?? proposal['categoryName'],
          100,
        ),
        adminFee: adminFee,
        tax: tax,
        discount: discount,
        note: _boundedText(proposal['note'], 300),
        date: _dateOr(proposal['date'], createdAt),
        linkedActivityId: linkedActivityId,
        items: items ?? const <ReceiptOcrItem>[],
        receiptNumber: receiptNumber,
        receiptRawText: receiptRawText,
        sourceId: sourceId,
        source: source,
        recurringTransactionId: recurringTransactionId,
        receiptPaidAmount: receiptPaidAmount,
        receiptChangeAmount: receiptChangeAmount,
        tags: tags,
        newTags: newTags,
        newMerchant: newMerchant,
        attachmentPaths: attachmentPaths,
        formValues: formValues,
      ),
    );
  }

  static String? _csvValue(Object? value) {
    final values = switch (value) {
      String text => text.split(','),
      List list => list.map((item) => item.toString()),
      _ => const <String>[],
    };
    final normalized = values
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .join(',');
    return normalized.isEmpty ? null : _boundedText(normalized, 300);
  }

  static List<ReceiptOcrItem>? _receiptItems(Object? value) {
    if (value == null) return const <ReceiptOcrItem>[];
    Object? decoded = value;
    if (value is String) {
      try {
        decoded = jsonDecode(value);
      } on FormatException {
        return null;
      }
    }
    if (decoded is! List) return null;
    final items = <ReceiptOcrItem>[];
    for (final rawItem in decoded) {
      if (rawItem is! Map) return null;
      final item = Map<String, dynamic>.from(rawItem);
      final name = _boundedText(item['name'] ?? item['itemName'], 200) ?? '';
      final price = _integer(item['price']) ?? -1;
      final quantity = _positiveDouble(item['qty'] ?? item['quantity']) ?? -1;
      final rawSubtotal = item['subtotal'] ?? item['lineTotal'];
      final subtotal = rawSubtotal == null ? null : _integer(rawSubtotal) ?? -1;
      items.add(
        ReceiptOcrItem(
          name: name,
          price: price,
          quantity: quantity,
          unit: _boundedText(item['unit'], 40),
          lineTotal: subtotal,
        ),
      );
    }
    return items;
  }

  static List<Map<String, Object?>> _receiptItemsJson(
    List<ReceiptOcrItem> items,
  ) => [
    for (final item in items)
      {
        'name': item.name,
        'price': item.price,
        'qty': item.quantity,
        if (item.unit != null) 'unit': item.unit,
        if (item.lineTotal != null) 'subtotal': item.lineTotal,
      },
  ];

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
    final note = _boundedText(proposal['note'], 300);
    final proposedMode = ActivityMode.tryParse(
      proposal['activityMode'] ?? proposal['mode'] ?? proposal['kind'],
    );
    final decision = const ActivityModeDetector().detect(
      '$title ${note ?? ''}',
    );
    final mode = proposedMode ?? decision.mode;
    final groupId = _boundedText(proposal['activityGroupId'], 120);
    final subjectType = _boundedText(proposal['subjectType'], 80);
    final subjectId = _boundedText(proposal['subjectId'], 120);
    final parentSessionId = _boundedText(proposal['parentSessionId'], 120);
    return FfmAssistantProposalParseResult.draft(
      FfmAssistantDraft(
        kind: FfmAssistantDraftKind.activity,
        createdAt: createdAt,
        title: title,
        note: note,
        date: _dateOr(proposal['date'], createdAt),
        parentSessionId: parentSessionId,
        activityMode: mode,
        scheduledAt: proposal['scheduledAt'] == null
            ? null
            : _dateOr(proposal['scheduledAt'], createdAt),
        formValues: {
          'source': 'gemini_proposal',
          'activityMode': mode.value,
          'kind': mode.activityKind.value,
          if (proposedMode == null && decision.requiresClarification)
            'modeNeedsConfirmation': 'true',
          ...?(category == null ? null : {'category': category}),
          ...?(groupId == null ? null : {'activityGroupId': groupId}),
          ...?(subjectType == null ? null : {'subjectType': subjectType}),
          ...?(subjectId == null ? null : {'subjectId': subjectId}),
          ...?(parentSessionId == null
              ? null
              : {'parentSessionId': parentSessionId}),
        },
      ),
    );
  }

  static FfmAssistantProposalParseResult _parseDailyNote(
    Map<String, dynamic> proposal,
    DateTime createdAt,
  ) {
    final body = _boundedText(
      proposal['body'] ?? proposal['note'] ?? proposal['text'],
      2000,
    );
    if (body == null) {
      return const FfmAssistantProposalParseResult.invalid(
        'Isi Catatan Harian wajib diisi.',
      );
    }
    final dateValue =
        proposal['noteDate'] ?? proposal['targetDate'] ?? proposal['date'];
    final noteDate = DateTime.tryParse(dateValue?.toString() ?? '');
    if (noteDate == null) {
      return const FfmAssistantProposalParseResult.invalid(
        'Tanggal Catatan Harian wajib diisi dan valid.',
      );
    }
    
    // Tag wajib untuk daily_note
    final tagsValue = proposal['tags'] ?? proposal['tag'];
    final tags = _boundedText(tagsValue, 300);
    if (tags == null || tags.isEmpty) {
      return const FfmAssistantProposalParseResult.invalid(
        'Tag atau lahan wajib diisi untuk Catatan Harian. Sebutkan tag yang ada di Data Utama.',
      );
    }
    
    return FfmAssistantProposalParseResult.draft(
      FfmAssistantDraft(
        kind: FfmAssistantDraftKind.dailyNote,
        createdAt: createdAt,
        title: _boundedText(proposal['title'] ?? proposal['name'], 120),
        note: body,
        date: noteDate,
        formValues: {
          'source': 'gemini_proposal',
          'tags': tags,
        },
      ),
    );
  }

  static FfmAssistantProposalParseResult _parseReminder(
    Map<String, dynamic> proposal,
    DateTime createdAt,
  ) {
    final title = _boundedText(proposal['title'] ?? proposal['name'], 120);
    if (title == null || title.isEmpty) {
      return const FfmAssistantProposalParseResult.invalid(
        'Judul pengingat wajib diisi.',
      );
    }
    final note = _boundedText(proposal['note'], 300);
    DateTime targetDate = _dateOr(
      proposal['scheduledAt'] ?? proposal['targetDate'] ?? proposal['date'],
      createdAt.add(const Duration(hours: 1)),
    );
    final timeRaw = proposal['time']?.toString().trim();
    if (timeRaw != null && timeRaw.isNotEmpty) {
      final parsed = _parseHourMinute(timeRaw);
      if (parsed != null) {
        targetDate = DateTime(
          targetDate.year,
          targetDate.month,
          targetDate.day,
          parsed.$1,
          parsed.$2,
        );
      }
    }
    final rawRecurrence = proposal['recurrence'] ?? proposal['recurrenceType'];
    final recurrence = rawRecurrence?.toString().toLowerCase();
    if (recurrence != null &&
        !const {
          'once',
          'daily',
          'weekly',
          'sekali',
          'harian',
          'mingguan',
        }.contains(recurrence)) {
      return const FfmAssistantProposalParseResult.invalid(
        'Pola pengulangan pengingat tidak valid.',
      );
    }
    final soundUri = _boundedText(proposal['soundUri'], 500);
    final soundName = _boundedText(proposal['soundName'], 120);
    final weekdaysRaw = proposal['weekdays'];
    final List<int> weekdays = weekdaysRaw is List
        ? weekdaysRaw
              .map((e) => int.tryParse(e.toString()))
              .whereType<int>()
              .toList()
        : const [];
    if (weekdays.any((day) => day < 1 || day > 7) ||
        (recurrence == 'weekly' || recurrence == 'mingguan') &&
            weekdays.isEmpty) {
      return const FfmAssistantProposalParseResult.invalid(
        'Hari pengulangan pengingat harus berupa angka 1 sampai 7.',
      );
    }

    final rawMode =
        proposal['reminderMode'] ?? proposal['mode'] ?? proposal['type'];
    final modeValue = rawMode?.toString().toLowerCase() == 'alarm'
        ? 'alarm'
        : 'notification';

    final formValues = <String, dynamic>{
      'time':
          '${targetDate.hour.toString().padLeft(2, '0')}:${targetDate.minute.toString().padLeft(2, '0')}',
      'targetDate':
          '${targetDate.year}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}',
      'hasExplicitTime': timeRaw != null && timeRaw.isNotEmpty,
      'reminderMode': modeValue,
      'mode': modeValue,
    };
    if (recurrence != null) {
      formValues['recurrence'] = recurrence;
      formValues['recurrenceType'] = recurrence;
    }
    if (weekdays.isNotEmpty) {
      formValues['weekdays'] = weekdays;
    }
    if (soundUri != null) {
      formValues['soundUri'] = soundUri;
    }
    if (soundName != null) {
      formValues['soundName'] = soundName;
    }

    return FfmAssistantProposalParseResult.draft(
      FfmAssistantDraft(
        kind: FfmAssistantDraftKind.reminder,
        createdAt: createdAt,
        title: title,
        note: note,
        date: targetDate,
        soundUri: soundUri,
        soundName: soundName,
        formValues: formValues,
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
    final action = proposal['action']?.toString().trim().toLowerCase();
    if (action == 'deposit' || action == 'setor' || action == 'simpan') {
      return _parseGoalDeposit(proposal, createdAt);
    }
    if (action == 'usage' || action == 'pakai' || action == 'tarik') {
      return _parseGoalUsage(proposal, createdAt);
    }

    final title = _boundedText(proposal['title'] ?? proposal['name'], 100);
    if (title == null) {
      return const FfmAssistantProposalParseResult.invalid(
        'Target keuangan wajib punya nama/judul.',
      );
    }
    final amount = _positiveInt(proposal['amount'] ?? proposal['targetAmount']);
    final note = _boundedText(proposal['note'], 200);
    final category = _boundedText(
      proposal['category'] ?? proposal['categoryName'] ?? proposal['kategori'],
      100,
    );
    final rawTargetDate = proposal['targetDate']?.toString().trim();
    if (rawTargetDate != null &&
        rawTargetDate.isNotEmpty &&
        !_isValidTransactionDate(rawTargetDate)) {
      return const FfmAssistantProposalParseResult.invalid(
        'Batas waktu target harus berupa tanggal yang valid.',
      );
    }
    final date = rawTargetDate == null || rawTargetDate.isEmpty
        ? null
        : DateTime.parse(rawTargetDate);

    return FfmAssistantProposalParseResult.draft(
      FfmAssistantDraft(
        kind: FfmAssistantDraftKind.goal,
        createdAt: createdAt,
        title: title,
        amount: amount,
        note: note,
        date: date,
        categoryName: category,
        formValues: {
          if (proposal['categoryId'] != null)
            'categoryId': proposal['categoryId'].toString(),
        },
      ),
    );
  }

  static FfmAssistantProposalParseResult _parseGoalDeposit(
    Map<String, dynamic> proposal,
    DateTime createdAt,
  ) {
    final goalName = _boundedText(
      proposal['goal'] ??
          proposal['goalName'] ??
          proposal['target'] ??
          proposal['title'] ??
          proposal['name'],
      100,
    );
    if (goalName == null) {
      return const FfmAssistantProposalParseResult.invalid(
        'Setor target wajib menentukan nama target keuangan.',
      );
    }
    final amount = _positiveInt(proposal['amount'] ?? proposal['nominal']);
    if (amount == null) {
      return const FfmAssistantProposalParseResult.invalid(
        'Nominal setor target harus lebih dari nol.',
      );
    }
    final fromAccount = _boundedText(
      proposal['fromAccount'] ?? proposal['account'] ?? proposal['rekening'],
      100,
    );
    final note = _boundedText(proposal['note'] ?? proposal['catatan'], 200);
    final date = _dateOr(proposal['date'], createdAt);

    return FfmAssistantProposalParseResult.draft(
      FfmAssistantDraft(
        kind: FfmAssistantDraftKind.goalDeposit,
        createdAt: createdAt,
        goalName: goalName,
        title: 'Setor Target $goalName',
        amount: amount,
        fromAccountName: fromAccount,
        note: note,
        date: date,
        formValues: {
          'source': 'gemini_proposal',
          if (proposal['goalId'] != null)
            'goalId': proposal['goalId'].toString(),
          if (proposal['accountId'] != null)
            'accountId': proposal['accountId'].toString(),
          ...?(fromAccount == null ? null : {'fromAccount': fromAccount}),
        },
      ),
    );
  }

  static FfmAssistantProposalParseResult _parseGoalUsage(
    Map<String, dynamic> proposal,
    DateTime createdAt,
  ) {
    final goalName = _boundedText(
      proposal['goal'] ??
          proposal['goalName'] ??
          proposal['target'] ??
          proposal['title'] ??
          proposal['name'],
      100,
    );
    if (goalName == null) {
      return const FfmAssistantProposalParseResult.invalid(
        'Pakai target wajib menentukan nama target keuangan.',
      );
    }
    final amount = _positiveInt(proposal['amount'] ?? proposal['nominal']);
    if (amount == null) {
      return const FfmAssistantProposalParseResult.invalid(
        'Nominal pakai target harus lebih dari nol.',
      );
    }
    final toAccount = _boundedText(
      proposal['toAccount'] ?? proposal['account'] ?? proposal['rekening'],
      100,
    );
    final note = _boundedText(proposal['note'] ?? proposal['catatan'], 200);
    final date = _dateOr(proposal['date'], createdAt);

    return FfmAssistantProposalParseResult.draft(
      FfmAssistantDraft(
        kind: FfmAssistantDraftKind.goalUsage,
        createdAt: createdAt,
        goalName: goalName,
        title: 'Pakai Target $goalName',
        amount: amount,
        toAccountName: toAccount,
        note: note,
        date: date,
        formValues: {
          'source': 'gemini_proposal',
          if (proposal['goalId'] != null)
            'goalId': proposal['goalId'].toString(),
          if (proposal['accountId'] != null)
            'accountId': proposal['accountId'].toString(),
          ...?(toAccount == null ? null : {'toAccount': toAccount}),
        },
      ),
    );
  }

  static FfmAssistantProposalParseResult _parseBudget(
    Map<String, dynamic> proposal,
    DateTime createdAt,
  ) {
    final title = _boundedText(
      proposal['title'] ?? proposal['category'] ?? proposal['name'],
      100,
    );
    if (title == null) {
      return const FfmAssistantProposalParseResult.invalid(
        'Anggaran wajib punya nama/kategori.',
      );
    }
    final amount = _positiveInt(
      proposal['amount'] ?? proposal['limit'] ?? proposal['budgetAmount'],
    );
    final note = _boundedText(proposal['note'], 200);
    final periodType = _canonicalBudgetPeriod(
      proposal['period'] ?? proposal['periodType'],
    );
    final startDate = _dateOr(
      proposal['startDate'] ?? proposal['date'],
      createdAt,
    );
    final endDate = proposal['endDate'];
    final alertPercent = _positiveInt(proposal['alertPercent']);
    final rollover = _positiveInt(proposal['rollover']);
    final rawCategoryIds = proposal['categoryIds'] ?? proposal['categories'];
    final categoryIds = switch (rawCategoryIds) {
      List list =>
        list
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList(),
      String str =>
        str.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
      _ => null,
    };

    return FfmAssistantProposalParseResult.draft(
      FfmAssistantDraft(
        kind: FfmAssistantDraftKind.budget,
        createdAt: createdAt,
        title: title,
        amount: amount,
        categoryName: title,
        note: note,
        date: startDate,
        formValues: {
          if (periodType case final String p) 'periodType': p,
          'startDate': startDate.toIso8601String(),
          if (endDate != null) 'endDate': endDate.toString(),
          'alertPercent': alertPercent,
          'rollover': rollover,
          if (categoryIds != null && categoryIds.isNotEmpty)
            'categoryIdsJson': jsonEncode(categoryIds),
        },
      ),
    );
  }

  /// Normalisasi periode anggaran dari LLM/JSON ke kode kanonis.
  /// Mengembalikan null bila tidak dikenali agar form memakai default
  /// (filter halaman atau default kategori), bukan menebak.
  static String? _canonicalBudgetPeriod(Object? raw) {
    final value = raw?.toString().trim().toLowerCase();
    if (value == null || value.isEmpty) return null;
    return switch (value) {
      'weekly' || 'mingguan' || 'per minggu' => 'weekly',
      'biweekly' || 'per dua minggu' => 'biweekly',
      'monthly' || 'bulanan' || 'per bulan' || 'perbulan' => 'monthly',
      'bimonthly' => 'bimonthly',
      'fourmonthly' => 'fourmonthly',
      'fivemonthly' => 'fivemonthly',
      'nonrecurring' ||
      'tidak rutin' ||
      'tak rutin' ||
      'none' => 'nonrecurring',
      _ => null,
    };
  }

  static FfmAssistantProposalParseResult _parseLiability(
    Map<String, dynamic> proposal,
    DateTime createdAt,
  ) {
    final title = _boundedText(
      proposal['title'] ?? proposal['name'] ?? proposal['party'],
      100,
    );
    final party = _boundedText(
      proposal['party'] ??
          proposal['partyName'] ??
          proposal['lender'] ??
          proposal['pemberiPinjaman'] ??
          proposal['title'] ??
          proposal['name'],
      100,
    );
    final amount = _positiveInt(proposal['amount'] ?? proposal['nominal']);
    if (amount == null) {
      return const FfmAssistantProposalParseResult.invalid(
        'Nominal hutang harus lebih dari nol.',
      );
    }
    final monthlyInstallment = _positiveInt(
      proposal['monthlyInstallment'] ??
          proposal['installment'] ??
          proposal['cicilan'],
    );
    final interestRate = proposal['interestRate'] ?? proposal['bunga'];
    final note = _boundedText(proposal['note'] ?? proposal['catatan'], 300);
    final date = _dateOr(
      proposal['dueDate'] ?? proposal['targetDate'] ?? proposal['date'],
      createdAt.add(const Duration(days: 30)),
    );

    return FfmAssistantProposalParseResult.draft(
      FfmAssistantDraft(
        kind: FfmAssistantDraftKind.liability,
        createdAt: createdAt,
        title: title ?? 'Hutang',
        partyName: party ?? title ?? 'Hutang',
        amount: amount,
        note: note,
        date: date,
        formValues: {
          'source': 'gemini_proposal',
          if (party case final String p) 'partyName': p,
          if (proposal['dueDate'] != null)
            'dueDate': proposal['dueDate'].toString(),
          if (monthlyInstallment != null)
            'monthlyInstallment': monthlyInstallment.toString(),
          if (interestRate != null) 'interestRate': interestRate.toString(),
        },
      ),
    );
  }

  static FfmAssistantProposalParseResult _parseReceivable(
    Map<String, dynamic> proposal,
    DateTime createdAt,
  ) {
    final title = _boundedText(
      proposal['title'] ?? proposal['name'] ?? proposal['party'],
      100,
    );
    final party = _boundedText(
      proposal['party'] ??
          proposal['partyName'] ??
          proposal['borrower'] ??
          proposal['peminjam'] ??
          proposal['title'] ??
          proposal['name'],
      100,
    );
    final amount = _positiveInt(proposal['amount'] ?? proposal['nominal']);
    if (amount == null) {
      return const FfmAssistantProposalParseResult.invalid(
        'Nominal piutang harus lebih dari nol.',
      );
    }
    final monthlyInstallment = _positiveInt(
      proposal['monthlyInstallment'] ??
          proposal['installment'] ??
          proposal['cicilan'],
    );
    final interestRate = proposal['interestRate'] ?? proposal['bunga'];
    final note = _boundedText(proposal['note'] ?? proposal['catatan'], 300);
    final date = _dateOr(
      proposal['dueDate'] ?? proposal['targetDate'] ?? proposal['date'],
      createdAt.add(const Duration(days: 30)),
    );

    return FfmAssistantProposalParseResult.draft(
      FfmAssistantDraft(
        kind: FfmAssistantDraftKind.receivable,
        createdAt: createdAt,
        title: title ?? 'Piutang',
        partyName: party ?? title ?? 'Piutang',
        amount: amount,
        note: note,
        date: date,
        formValues: {
          'source': 'gemini_proposal',
          if (party case final String p) 'partyName': p,
          if (proposal['dueDate'] != null)
            'dueDate': proposal['dueDate'].toString(),
          if (monthlyInstallment != null)
            'monthlyInstallment': monthlyInstallment.toString(),
          if (interestRate != null) 'interestRate': interestRate.toString(),
        },
      ),
    );
  }

  static FfmAssistantProposalParseResult _parseLiabilityPayment(
    Map<String, dynamic> proposal,
    DateTime createdAt,
  ) {
    final targetId = proposal['targetId']?.toString().trim();
    final amount = _positiveInt(proposal['amount'] ?? proposal['nominal']);
    if (amount == null || amount <= 0) {
      return const FfmAssistantProposalParseResult.invalid(
        'Nominal pembayaran hutang harus lebih dari nol.',
      );
    }
    if (targetId == null || targetId.isEmpty) {
      return const FfmAssistantProposalParseResult.invalid(
        'Target hutang (targetId) harus diisi untuk pembayaran.',
      );
    }
    final accountId = proposal['accountId']?.toString().trim();
    final note = _boundedText(
      proposal['note'] ?? proposal['catatan'] ?? 'Pembayaran hutang',
      300,
    );
    final date = _dateOr(
      proposal['date'] ?? proposal['paymentDate'],
      createdAt,
    );

    return FfmAssistantProposalParseResult.draft(
      FfmAssistantDraft(
        kind: FfmAssistantDraftKind.liabilityPayment,
        createdAt: createdAt,
        title: 'Pembayaran Hutang',
        amount: amount,
        note: note,
        date: date,
        fromAccountName: proposal['fromAccount']?.toString().trim(),
        formValues: {
          'source': 'gemini_proposal',
          'entity': 'liability',
          'targetId': targetId,
          if (accountId != null && accountId.isNotEmpty) 'accountId': accountId,
        },
      ),
    );
  }

  static FfmAssistantProposalParseResult _parseReceivablePayment(
    Map<String, dynamic> proposal,
    DateTime createdAt,
  ) {
    final targetId = proposal['targetId']?.toString().trim();
    final amount = _positiveInt(proposal['amount'] ?? proposal['nominal']);
    if (amount == null || amount <= 0) {
      return const FfmAssistantProposalParseResult.invalid(
        'Nominal penerimaan piutang harus lebih dari nol.',
      );
    }
    if (targetId == null || targetId.isEmpty) {
      return const FfmAssistantProposalParseResult.invalid(
        'Target piutang (targetId) harus diisi untuk penerimaan.',
      );
    }
    final accountId = proposal['accountId']?.toString().trim();
    final note = _boundedText(
      proposal['note'] ?? proposal['catatan'] ?? 'Penerimaan piutang',
      300,
    );
    final date = _dateOr(
      proposal['date'] ?? proposal['paymentDate'],
      createdAt,
    );

    return FfmAssistantProposalParseResult.draft(
      FfmAssistantDraft(
        kind: FfmAssistantDraftKind.receivablePayment,
        createdAt: createdAt,
        title: 'Penerimaan Piutang',
        amount: amount,
        note: note,
        date: date,
        toAccountName: proposal['toAccount']?.toString().trim(),
        formValues: {
          'source': 'gemini_proposal',
          'entity': 'receivable',
          'targetId': targetId,
          if (accountId != null && accountId.isNotEmpty) 'accountId': accountId,
        },
      ),
    );
  }

  static FfmAssistantProposalParseResult _parseNavigation(
    Map<String, dynamic> proposal,
  ) {
    final navigationTarget = proposal['navigation']?.toString().trim();
    if (navigationTarget == null || navigationTarget.isEmpty) {
      return const FfmAssistantProposalParseResult.invalid(
        'Target navigasi wajib diisi.',
      );
    }

    // Return as a special draft with navigation info in formValues
    return FfmAssistantProposalParseResult.draft(
      FfmAssistantDraft(
        kind: FfmAssistantDraftKind
            .masterData, // Use existing kind as placeholder
        createdAt: DateTime.now(),
        title: 'Navigasi ke $navigationTarget',
        categoryName: navigationTarget,
        formValues: {'navigation': 'true', 'destination': navigationTarget},
      ),
    );
  }

  static FfmAssistantProposalParseResult _parseCashFlowProfile(
    Map<String, dynamic> proposal,
    DateTime createdAt,
  ) {
    final title = _boundedText(proposal['title'] ?? proposal['name'], 80);
    if (title == null || title.isEmpty) {
      return const FfmAssistantProposalParseResult.invalid(
        'Proposal siklus kas belum punya nama atau judul siklus.',
      );
    }
    final commodity =
        _boundedText(
          proposal['commodity'] ??
              proposal['commodityOrBusinessType'] ??
              proposal['businessType'],
          60,
        ) ??
        'Pertanian/Usaha';

    final initialCapital =
        _positiveInt(proposal['initialCapital'] ?? proposal['amount']) ?? 0;
    final estimatedInflow =
        _positiveInt(proposal['estimatedInflow'] ?? proposal['inflow']) ?? 0;
    final dailyLiving =
        _positiveInt(
          proposal['dailyLivingBudget'] ?? proposal['dailyBudget'],
        ) ??
        0;
    final dailyOps =
        _positiveInt(
          proposal['dailyOperationalBudget'] ?? proposal['operationalBudget'],
        ) ??
        0;

    DateTime targetHarvest;
    if (proposal['targetHarvestDate'] != null) {
      targetHarvest = _dateOr(
        proposal['targetHarvestDate'],
        createdAt.add(const Duration(days: 90)),
      );
    } else if (proposal['daysRemaining'] != null) {
      final days = _positiveInt(proposal['daysRemaining']) ?? 90;
      targetHarvest = createdAt.add(Duration(days: days));
    } else {
      targetHarvest = createdAt.add(const Duration(days: 90));
    }

    final rawType =
        _boundedText(
          proposal['cycleProfileType'] ?? proposal['profileType'],
          30,
        )?.toLowerCase() ??
        'agriculture';

    final draft = FfmAssistantDraft(
      kind: FfmAssistantDraftKind.cashFlowProfile,
      createdAt: createdAt,
      title: title,
      amount: initialCapital,
      commodityOrBusinessType: commodity,
      initialCapital: initialCapital,
      estimatedInflow: estimatedInflow,
      dailyLivingBudget: dailyLiving,
      dailyOperationalBudget: dailyOps,
      targetHarvestDate: targetHarvest,
      cycleProfileType: rawType,
      date: createdAt,
      note: _boundedText(proposal['note'], 160),
    );

    return FfmAssistantProposalParseResult.draft(draft);
  }

  static String? _extractJson(String text) {
    // Strip markdown code fences (```json ... ``` or ``` ... ```)
    var cleaned = text.replaceAll(
      RegExp(r'^```(?:json)?\s*\n?|\n?\s*```$'),
      '',
    );
    cleaned = cleaned.trim();

    // Try extracting a JSON object first
    final objectResult = _extractJsonObject(cleaned);
    if (objectResult != null) return objectResult;

    // Fallback: try extracting a JSON array
    final arrayResult = _extractJsonArray(cleaned);
    if (arrayResult != null) return arrayResult;

    // Last resort: extract between first { and last } (handles preamble text)
    return _extractJsonFallback(cleaned);
  }

  static String? _extractJsonObject(String text) {
    final start = text.indexOf('{');
    if (start < 0) return null;
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var index = start; index < text.length; index++) {
      final character = text[index];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (character == r'\') {
          escaped = true;
        } else if (character == '"') {
          inString = false;
        }
        continue;
      }
      if (character == '"') {
        inString = true;
      } else if (character == '{') {
        depth++;
      } else if (character == '}') {
        depth--;
        if (depth == 0) return text.substring(start, index + 1);
      }
    }
    return null;
  }

  static String? _extractJsonArray(String text) {
    final start = text.indexOf('[');
    if (start < 0) return null;
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var index = start; index < text.length; index++) {
      final character = text[index];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (character == r'\') {
          escaped = true;
        } else if (character == '"') {
          inString = false;
        }
        continue;
      }
      if (character == '"') {
        inString = true;
      } else if (character == '[') {
        depth++;
      } else if (character == ']') {
        depth--;
        if (depth == 0) return text.substring(start, index + 1);
      }
    }
    return null;
  }

  static String? _extractJsonFallback(String text) {
    final firstBrace = text.indexOf('{');
    final lastBrace = text.lastIndexOf('}');
    if (firstBrace < 0 || lastBrace <= firstBrace) return null;
    return text.substring(firstBrace, lastBrace + 1);
  }

  static FfmAssistantProposalParseResult _parseMonitoringJob(
    Map<String, dynamic> proposal,
    DateTime createdAt,
  ) {
    final presetRaw =
        proposal['preset']?.toString().toLowerCase().trim() ??
        'weeklyevaluation';
    final preset = switch (presetRaw) {
      'budgetmonitor' ||
      'budget_monitor' ||
      'anggaran' => FfmAssistantMonitoringPreset.budgetMonitor,
      'duecheck' ||
      'due_check' ||
      'tagihan' ||
      'hutang' => FfmAssistantMonitoringPreset.dueCheck,
      _ => FfmAssistantMonitoringPreset.weeklyEvaluation,
    };

    final cadenceRaw =
        proposal['cadence']?.toString().toLowerCase().trim() ?? 'weekly';
    final cadence = switch (cadenceRaw) {
      'daily' || 'harian' => FfmAssistantJobCadence.daily,
      'monthly' || 'bulanan' => FfmAssistantJobCadence.monthly,
      _ => FfmAssistantJobCadence.weekly,
    };

    final targetTimeMinutes =
        _positiveInt(
          proposal['targetTimeMinutes'] ?? proposal['timeMinutes'],
        ) ??
        (proposal['hour'] is int
            ? (proposal['hour'] as int) * 60 +
                  ((proposal['minute'] as int?) ?? 0)
            : 540); // default 09:00

    final targetDay = proposal['targetDay'] is int
        ? proposal['targetDay'] as int
        : null;
    final categoryFilter = _boundedText(
      proposal['categoryFilter'] ?? proposal['category'],
      60,
    );

    final hour = targetTimeMinutes ~/ 60;
    final minute = (targetTimeMinutes % 60).toString().padLeft(2, '0');
    final timeStr = 'pukul $hour:$minute';

    final draft = FfmAssistantDraft(
      kind: FfmAssistantDraftKind.monitoringJob,
      title: preset.label,
      note: '${preset.label} (${cadence.label} $timeStr)',
      createdAt: createdAt,
      formValues: <String, Object?>{
        'preset': preset.name,
        'cadence': cadence.name,
        'targetTimeMinutes': targetTimeMinutes,
        ...?(targetDay == null ? null : {'targetDay': targetDay}),
        ...?(categoryFilter == null
            ? null
            : {'categoryFilter': categoryFilter}),
        'deliveryChannel': proposal['deliveryChannel']?.toString() ?? 'inApp',
        'source': 'gemini_proposal',
      },
    );

    return FfmAssistantProposalParseResult.draft(draft);
  }

  static String? _boundedText(Object? value, int maxLength) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return null;
    return text.length <= maxLength ? text : text.substring(0, maxLength);
  }

  static int? _positiveInt(Object? value) {
    if (value is num) {
      if (!value.isFinite || value != value.roundToDouble()) return null;
      final result = value.toInt();
      return result > 0 ? result : null;
    }
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return null;
    final isPlainInteger = RegExp(r'^\d+$').hasMatch(text);
    final isGroupedInteger = RegExp(
      r'^(?:Rp\s*)?\d{1,3}(?:[.,]\d{3})+$',
      caseSensitive: false,
    ).hasMatch(text);
    if (!isPlainInteger && !isGroupedInteger) return null;
    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    final result = int.tryParse(digits);
    return result != null && result > 0 ? result : null;
  }

  static int? _nonNegativeInt(Object? value) {
    final result = _integer(value);
    return result != null && result >= 0 ? result : null;
  }

  static int? _integer(Object? value) {
    if (value is num) {
      if (!value.isFinite || value != value.roundToDouble()) return null;
      return value.toInt();
    }
    final text = value?.toString().trim() ?? '';
    if (!RegExp(r'^-?\d+$').hasMatch(text)) return null;
    return int.tryParse(text);
  }

  static double? _positiveDouble(Object? value) {
    final result = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString().trim() ?? '');
    return result != null && result.isFinite && result > 0 ? result : null;
  }

  static bool _isValidTransactionDate(String value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})(?:$|T)').firstMatch(value);
    if (match == null || DateTime.tryParse(value) == null) return false;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final normalized = DateTime(year, month, day);
    return normalized.year == year &&
        normalized.month == month &&
        normalized.day == day;
  }

  static DateTime _dateOr(Object? value, DateTime fallback) =>
      DateTime.tryParse(value?.toString() ?? '') ?? fallback;

  static (int, int)? _parseHourMinute(String text) {
    final cleaned = text.trim().toLowerCase();
    // 1. "08:00", "8:30", "14.15"
    final colonMatch = RegExp(r'(\d{1,2})[:.](\d{2})').firstMatch(cleaned);
    if (colonMatch != null) {
      final h = int.tryParse(colonMatch.group(1) ?? '');
      final m = int.tryParse(colonMatch.group(2) ?? '');
      if (h != null && m != null && h >= 0 && h <= 23 && m >= 0 && m <= 59) {
        return (h, m);
      }
    }
    // 2. "jam 8 pagi", "pukul 19", "8 malam", "1 siang", "jam 7", "pukul 07"
    final wordMatch = RegExp(
      r'(?:jam|pukul|pk)?\s*(\d{1,2})(?:\s*(pagi|siang|sore|malam))?',
    ).firstMatch(cleaned);
    if (wordMatch != null) {
      final h = int.tryParse(wordMatch.group(1) ?? '');
      final period = wordMatch.group(2);
      if (h != null && h >= 0 && h <= 23) {
        int adjusted = h;
        if (period == 'pagi') {
          adjusted = h == 12 ? 0 : h;
        } else if (period == 'siang') {
          adjusted = (h >= 1 && h <= 6) ? h + 12 : h;
        } else if (period == 'sore') {
          adjusted = (h >= 1 && h <= 6) ? h + 12 : h;
        } else if (period == 'malam') {
          adjusted = (h >= 1 && h <= 11) ? h + 12 : h;
        }
        return (adjusted.clamp(0, 23), 0);
      }
    }
    return null;
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

  bool get isValid => isProposal && error == null;
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
    this.tagNames = const [],
    this.treatmentType,
  });

  final String capabilityId;
  final String period;
  final DateTime? startDate;
  final DateTime? endDate;
  final List<String> tagNames;
  final String? treatmentType;
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
