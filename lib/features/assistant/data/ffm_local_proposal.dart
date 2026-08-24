import 'dart:convert';

class FfmLocalProposalWarning {
  const FfmLocalProposalWarning({
    required this.field,
    required this.code,
    required this.message,
  });

  final String field;
  final String code;
  final String message;

  Map<String, dynamic> toJson() => {
    'field': field,
    'code': code,
    'message': message,
  };

  static FfmLocalProposalWarning? tryParse(Object? value) {
    if (value is! Map) return null;
    final field = value['field'];
    final code = value['code'];
    final message = value['message'];
    if (field is! String ||
        code is! String ||
        message is! String ||
        field.isEmpty ||
        code.isEmpty ||
        message.isEmpty) {
      return null;
    }
    return FfmLocalProposalWarning(field: field, code: code, message: message);
  }
}

class FfmLocalProposalItem {
  const FfmLocalProposalItem({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
    required this.itemConfidence,
  });

  final String name;
  final int quantity;
  final int unitPrice;
  final int totalPrice;
  final double itemConfidence;

  Map<String, dynamic> toJson() => {
    'name': name,
    'quantity': quantity,
    'unitPrice': unitPrice,
    'totalPrice': totalPrice,
    'itemConfidence': itemConfidence,
  };

  static FfmLocalProposalItem? tryParse(Object? value) {
    if (value is! Map) return null;
    final name = value['name'];
    final quantity = _parseInteger(value['quantity']);
    final unitPrice = _parseInteger(value['unitPrice']);
    final totalPrice = _parseInteger(value['totalPrice']);
    final confidence = _parseConfidence(value['itemConfidence']);
    if (name is! String ||
        name.trim().isEmpty ||
        quantity == null ||
        unitPrice == null ||
        totalPrice == null ||
        confidence == null ||
        quantity <= 0 ||
        unitPrice < 0 ||
        totalPrice < 0) {
      return null;
    }
    return FfmLocalProposalItem(
      name: name.trim(),
      quantity: quantity,
      unitPrice: unitPrice,
      totalPrice: totalPrice,
      itemConfidence: confidence,
    );
  }
}

class FfmLocalProposal {
  const FfmLocalProposal({
    required this.formatVersion,
    required this.proposalType,
    required this.merchantName,
    required this.transactionDate,
    required this.timezone,
    required this.totalAmount,
    required this.currency,
    required this.suggestedCategory,
    required this.suggestedAccount,
    required this.items,
    required this.fieldConfidence,
    required this.warnings,
    required this.needsClarification,
    required this.clarificationQuestion,
    required this.issues,
    this.actionTarget,
    this.missingFields = const [],
    this.extractedFields = const <String, String>{},
    this.suggestedCapabilities = const <String>[],
    this.reasoning,
    this.assistantMessage,
  });

  final String formatVersion;
  final String proposalType;
  final String? actionTarget;
  final String? merchantName;
  final DateTime? transactionDate;
  final String timezone;
  final int? totalAmount;
  final String currency;
  final String? suggestedCategory;
  final String? suggestedAccount;
  final List<FfmLocalProposalItem> items;
  final Map<String, double> fieldConfidence;
  final List<FfmLocalProposalWarning> warnings;
  final bool needsClarification;
  final String? clarificationQuestion;
  final List<String> issues;
  final List<String> missingFields;
  final Map<String, String> extractedFields;
  final List<String> suggestedCapabilities;
  final String? reasoning;
  final String? assistantMessage;

  bool get needsReview {
    final isTransaction =
        proposalType == 'expense' ||
        proposalType == 'income' ||
        proposalType == 'transfer';
    return issues.isNotEmpty ||
        warnings.isNotEmpty ||
        needsClarification ||
        (isTransaction && (totalAmount == null || transactionDate == null));
  }

  Map<String, dynamic> toJson() => {
    'formatVersion': formatVersion,
    'proposalType': proposalType,
    'merchantName': merchantName,
    'transactionDate': transactionDate == null
        ? null
        : _formatDate(transactionDate!),
    'timezone': timezone,
    'totalAmount': totalAmount,
    'currency': currency,
    'suggestedCategory': suggestedCategory,
    'suggestedAccount': suggestedAccount,
    'items': items.map((item) => item.toJson()).toList(growable: false),
    'fieldConfidence': fieldConfidence,
    'warnings': warnings.map((warning) => warning.toJson()).toList(),
    'needsClarification': needsClarification,
    'clarificationQuestion': clarificationQuestion,
    'actionTarget': actionTarget,
    'missingFields': missingFields,
    'extractedFields': extractedFields,
    'suggestedCapabilities': suggestedCapabilities,
    'reasoning': reasoning,
    'assistantMessage': assistantMessage,
  };
}

class FfmLocalProposalParseResult {
  const FfmLocalProposalParseResult({
    required this.proposal,
    required this.rawJson,
  });

  final FfmLocalProposal proposal;
  final String? rawJson;

  bool get needsReview => proposal.needsReview;
}

/// Parser tanpa jalur database. Semua hasil model dianggap tidak tepercaya dan
/// selalu menghasilkan proposal yang dapat ditinjau, termasuk JSON rusak.
class FfmLocalProposalParser {
  const FfmLocalProposalParser._();

  static const formatVersion = 'ffm-local-vision-proposal-v2';
  static const _warningCodes = {
    'low_confidence',
    'sum_mismatch',
    'ambiguous_category',
    'ambiguous_account',
    'unreadable_date',
    'unreadable_amount',
  };

  static FfmLocalProposalParseResult parse(String output) {
    final rawJson = _extractJsonObject(output);
    final decoded = rawJson == null ? null : _tryDecode(rawJson);
    if (decoded is! Map) {
      return FfmLocalProposalParseResult(
        rawJson: rawJson,
        proposal: _emptyProposal(const ['invalid_json']),
      );
    }
    final map = Map<String, dynamic>.from(decoded);

    final issues = <String>[];
    final version = map['formatVersion'];
    if (version != formatVersion) issues.add('unsupported_format_version');
    final proposalType = map['proposalType'];
    if (proposalType is! String ||
        !const {
          'expense',
          'income',
          'transfer',
          'navigation',
          'read_query',
          'help',
          'out_of_domain',
          'unknown',
        }.contains(proposalType)) {
      issues.add('invalid_proposal_type');
    }

    final totalAmount = _integer(map['totalAmount']);
    final isTransaction =
        proposalType == 'expense' ||
        proposalType == 'income' ||
        proposalType == 'transfer';
    if (isTransaction && (totalAmount == null || totalAmount < 0)) {
      issues.add('invalid_total_amount');
    }

    final date = _parseDate(map['transactionDate']);
    if (isTransaction && date == null) {
      issues.add('invalid_transaction_date');
    }

    final itemValues = map['items'];
    final items = <FfmLocalProposalItem>[];
    if (itemValues is List) {
      for (final value in itemValues) {
        final item = FfmLocalProposalItem.tryParse(value);
        if (item == null) {
          issues.add('invalid_item');
        } else {
          items.add(item);
        }
      }
    } else if (isTransaction) {
      issues.add('invalid_items');
    }

    final fieldConfidence = <String, double>{};
    final rawConfidence = map['fieldConfidence'];
    if (rawConfidence is Map) {
      for (final entry in rawConfidence.entries) {
        final key = entry.key;
        final value = _confidence(entry.value);
        if (key is String && value != null) {
          fieldConfidence[key] = value;
          if (value < .6) issues.add('low_confidence:$key');
        } else {
          issues.add('invalid_field_confidence');
        }
      }
    } else if (isTransaction) {
      issues.add('invalid_field_confidence');
    }

    final warnings = <FfmLocalProposalWarning>[];
    final rawWarnings = map['warnings'];
    if (rawWarnings is List) {
      for (final value in rawWarnings) {
        final warning = FfmLocalProposalWarning.tryParse(value);
        if (warning == null) {
          issues.add('invalid_warning');
        } else {
          warnings.add(
            _warningCodes.contains(warning.code)
                ? warning
                : FfmLocalProposalWarning(
                    field: warning.field,
                    code: 'unknown_warning_code',
                    message: warning.message,
                  ),
          );
          if (!_warningCodes.contains(warning.code)) {
            issues.add('unknown_warning_code');
          }
        }
      }
    } else if (isTransaction) {
      issues.add('invalid_warnings');
    }

    if (totalAmount != null) {
      final itemTotal = items.fold<int>(
        0,
        (sum, item) => sum + item.totalPrice,
      );
      if (itemTotal != totalAmount) {
        issues.add('sum_mismatch');
        if (!warnings.any((warning) => warning.code == 'sum_mismatch')) {
          warnings.add(
            FfmLocalProposalWarning(
              field: 'totalAmount',
              code: 'sum_mismatch',
              message:
                  'Jumlah item tidak sama dengan total struk, mohon periksa.',
            ),
          );
        }
      }
    }

    final needsClarification = map['needsClarification'] == true;
    final clarification = map['clarificationQuestion'];
    if (needsClarification && clarification is! String) {
      issues.add('missing_clarification_question');
    }

    return FfmLocalProposalParseResult(
      rawJson: rawJson,
      proposal: FfmLocalProposal(
        formatVersion: version is String ? version : formatVersion,
        proposalType: proposalType is String ? proposalType : 'expense',
        merchantName: _text(map['merchantName']),
        transactionDate: date,
        timezone: _text(map['timezone']) ?? 'Asia/Jakarta',
        totalAmount: totalAmount,
        currency: _text(map['currency']) ?? 'IDR',
        suggestedCategory: _text(map['suggestedCategory']),
        suggestedAccount: _text(map['suggestedAccount']),
        items: items,
        fieldConfidence: fieldConfidence,
        warnings: warnings,
        needsClarification: needsClarification,
        clarificationQuestion: clarification is String ? clarification : null,
        actionTarget: _text(map['actionTarget']),
        issues: List.unmodifiable(issues),
        missingFields: _missingFieldsFromIssues(issues),
        extractedFields: _extractedFields(map),
        suggestedCapabilities: _suggestedCapabilities(map),
        reasoning: _text(map['reasoning']),
        assistantMessage: _assistantMessage(map['assistantMessage']),
      ),
    );
  }

  static FfmLocalProposal _emptyProposal(List<String> issues) =>
      FfmLocalProposal(
        formatVersion: formatVersion,
        proposalType: 'expense',
        merchantName: null,
        transactionDate: null,
        timezone: 'Asia/Jakarta',
        totalAmount: null,
        currency: 'IDR',
        suggestedCategory: null,
        suggestedAccount: null,
        items: const [],
        fieldConfidence: const {},
        warnings: const [],
        needsClarification: true,
        clarificationQuestion: 'Hasil AI lokal belum dapat dibaca. Periksa atau isi transaksi secara manual.',
        actionTarget: null,
        issues: List.unmodifiable(issues),
        missingFields: const [],
        extractedFields: const {},
        suggestedCapabilities: const [],
        reasoning: null,
        assistantMessage: null,
      );

  static Object? _tryDecode(String value) {
    try {
      return jsonDecode(value);
    } on FormatException {
      return null;
    }
  }

  static String? _extractJsonObject(String output) {
    final unfenced = output.replaceAll(RegExp(r'^```(?:json)?\s*|\s*```$'), '');
    final start = unfenced.indexOf('{');
    final end = unfenced.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    return unfenced.substring(start, end + 1);
  }

  static String? _text(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    return value.trim();
  }

  static String? _assistantMessage(Object? value) {
    final text = _text(value);
    if (text == null) return null;
    final compact = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.length < 4) return null;
    return compact.length > 700 ? '${compact.substring(0, 700)}…' : compact;
  }

  static List<String> _missingFieldsFromIssues(List<String> issues) {
    final missing = <String>{};
    for (final issue in issues) {
      if (issue == 'invalid_total_amount')
        missing.add('totalAmount');
      else if (issue == 'invalid_transaction_date')
        missing.add('transactionDate');
      else if (issue == 'invalid_items')
        missing.add('items');
      else if (issue == 'invalid_field_confidence')
        missing.add('fieldConfidence');
      else if (issue.startsWith('low_confidence:'))
        missing.add(issue.substring('low_confidence:'.length));
      else if (issue == 'missing_clarification_question')
        missing.add('clarificationQuestion');
    }
    return missing.toList();
  }

  static Map<String, String> _extractedFields(Map<String, dynamic> map) {
    final fields = <String, String>{};
    final merchant = _text(map['merchantName']);
    if (merchant != null) fields['merchantName'] = merchant;
    final category = _text(map['suggestedCategory']);
    if (category != null) fields['suggestedCategory'] = category;
    final account = _text(map['suggestedAccount']);
    if (account != null) fields['suggestedAccount'] = account;
    final date = _text(map['transactionDate']);
    if (date != null) fields['transactionDate'] = date;
    final amount = map['totalAmount'];
    if (amount is int) fields['totalAmount'] = amount.toString();
    final target = _text(map['actionTarget']);
    if (target != null) fields['actionTarget'] = target;
    return fields;
  }

  static List<String> _suggestedCapabilities(Map<String, dynamic> map) {
    final type = map['proposalType'];
    if (type is! String) return const [];
    return switch (type) {
      'expense' => const ['draft.expense', 'mutate.save_draft'],
      'income' => const ['draft.income', 'mutate.save_draft'],
      'transfer' => const ['draft.transfer', 'mutate.save_draft'],
      'navigation' => const ['navigate'],
      'read_query' => const [
        'read.transactions',
        'read.summary',
        'read.analysis',
      ],
      'help' => const ['read.summary', 'read.transactions'],
      _ => const [],
    };
  }

  static int? _integer(Object? value) => _parseInteger(value);

  static double? _confidence(Object? value) => _parseConfidence(value);

  static DateTime? _parseDate(Object? value) {
    if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      return null;
    }
    final date = DateTime.tryParse('${value}T00:00:00Z');
    if (date == null || _dateOnly(date) != value) return null;
    return date;
  }

  static String _dateOnly(DateTime value) => _formatDate(value);
}

int? _parseInteger(Object? value) =>
    value is int && !value.isNegative ? value : null;

double? _parseConfidence(Object? value) {
  if (value is! num) return null;
  final result = value.toDouble();
  return result >= 0 && result <= 1 ? result : null;
}

String _formatDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
