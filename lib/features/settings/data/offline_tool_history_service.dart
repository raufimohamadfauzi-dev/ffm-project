import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class OfflineToolHistoryService {
  OfflineToolHistoryService([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _reconciliationsKey = 'offline_reconciliation_history';
  static const _alertsKey = 'offline_spending_alerts';
  static const _alertThresholdKey = 'offline_alert_threshold';
  static const _importsKey = 'offline_import_history';
  static const _healthReportsKey = 'offline_health_reports';
  static const _monthlyReportsKey = 'offline_monthly_reports';

  Future<List<ReconciliationRecord>> readReconciliations() async {
    final raw = await _storage.read(key: _reconciliationsKey);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map(
            (item) =>
                ReconciliationRecord.fromJson(Map<String, dynamic>.from(item)),
          )
          .whereType<ReconciliationRecord>()
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveReconciliation(ReconciliationRecord record) async {
    final records = [...await readReconciliations(), record]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await _storage.write(
      key: _reconciliationsKey,
      value: jsonEncode(records.take(20).map((item) => item.toJson()).toList()),
    );
  }

  Future<List<ImportRecord>> readImports() async {
    final raw = await _storage.read(key: _importsKey);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => ImportRecord.fromJson(Map<String, dynamic>.from(item)))
          .whereType<ImportRecord>()
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveImport(ImportRecord record) async {
    final records = [...await readImports(), record]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await _storage.write(
      key: _importsKey,
      value: jsonEncode(records.take(30).map((item) => item.toJson()).toList()),
    );
  }

  Future<List<HealthReportRecord>> readHealthReports() async {
    final raw = await _storage.read(key: _healthReportsKey);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map(
            (item) =>
                HealthReportRecord.fromJson(Map<String, dynamic>.from(item)),
          )
          .whereType<HealthReportRecord>()
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveHealthReport(HealthReportRecord report) async {
    final reports = [...await readHealthReports(), report]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await _storage.write(
      key: _healthReportsKey,
      value: jsonEncode(reports.take(20).map((item) => item.toJson()).toList()),
    );
  }

  Future<List<MonthlyReportRecord>> readMonthlyReports() async {
    final raw = await _storage.read(key: _monthlyReportsKey);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map(
            (item) =>
                MonthlyReportRecord.fromJson(Map<String, dynamic>.from(item)),
          )
          .whereType<MonthlyReportRecord>()
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveMonthlyReport(MonthlyReportRecord report) async {
    final reports = [...await readMonthlyReports(), report]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await _storage.write(
      key: _monthlyReportsKey,
      value: jsonEncode(reports.take(30).map((item) => item.toJson()).toList()),
    );
  }

  Future<List<SpendingAlertRecord>> readAlerts() async {
    final raw = await _storage.read(key: _alertsKey);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map(
            (item) =>
                SpendingAlertRecord.fromJson(Map<String, dynamic>.from(item)),
          )
          .whereType<SpendingAlertRecord>()
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveAlerts(List<SpendingAlertRecord> alerts) async {
    await _storage.write(
      key: _alertsKey,
      value: jsonEncode(alerts.take(50).map((item) => item.toJson()).toList()),
    );
  }

  Future<double> readAlertThreshold() async {
    final raw = await _storage.read(key: _alertThresholdKey);
    return double.tryParse(raw ?? '') ?? 1.5;
  }

  Future<void> saveAlertThreshold(double value) async {
    await _storage.write(key: _alertThresholdKey, value: value.toString());
  }

  Future<bool> readAlertCategoryEnabled(String categoryId) async {
    final raw = await _storage.read(key: 'offline_alert_category_$categoryId');
    return raw != 'false';
  }

  Future<void> saveAlertCategoryEnabled(String categoryId, bool enabled) async {
    await _storage.write(
      key: 'offline_alert_category_$categoryId',
      value: enabled.toString(),
    );
  }
}

class ReconciliationRecord {
  const ReconciliationRecord({
    required this.createdAt,
    required this.bookBalance,
    required this.actualBalance,
    required this.difference,
    this.accountId,
    this.accountName,
    this.adjustmentTransactionId,
    this.isAdjusted = false,
  });

  final DateTime createdAt;
  final int bookBalance;
  final int actualBalance;
  final int difference;
  final String? accountId;
  final String? accountName;
  final String? adjustmentTransactionId;
  final bool isAdjusted;

  Map<String, dynamic> toJson() => {
    'createdAt': createdAt.toIso8601String(),
    'bookBalance': bookBalance,
    'actualBalance': actualBalance,
    'difference': difference,
    'accountId': accountId,
    'accountName': accountName,
    'adjustmentTransactionId': adjustmentTransactionId,
    'isAdjusted': isAdjusted,
  };

  static ReconciliationRecord? fromJson(Map<String, dynamic> json) {
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '');
    final bookBalance = int.tryParse(json['bookBalance']?.toString() ?? '');
    final actualBalance = int.tryParse(json['actualBalance']?.toString() ?? '');
    final difference = int.tryParse(json['difference']?.toString() ?? '');
    final accountId = json['accountId']?.toString();
    final accountName = json['accountName']?.toString();
    final adjustmentTransactionId = json['adjustmentTransactionId']?.toString();
    final isAdjusted = json['isAdjusted'] == true;
    if (createdAt == null ||
        bookBalance == null ||
        actualBalance == null ||
        difference == null) {
      return null;
    }
    return ReconciliationRecord(
      createdAt: createdAt,
      bookBalance: bookBalance,
      actualBalance: actualBalance,
      difference: difference,
      accountId: accountId,
      accountName: accountName,
      adjustmentTransactionId: adjustmentTransactionId,
      isAdjusted: isAdjusted,
    );
  }
}

class HealthReportRecord {
  const HealthReportRecord({
    required this.createdAt,
    required this.tablesChecked,
    required this.criticalCount,
    required this.warningCount,
    required this.infoCount,
    required this.resolvedKeys,
  });

  final DateTime createdAt;
  final int tablesChecked;
  final int criticalCount;
  final int warningCount;
  final int infoCount;
  final List<String> resolvedKeys;

  Map<String, dynamic> toJson() => {
    'createdAt': createdAt.toIso8601String(),
    'tablesChecked': tablesChecked,
    'criticalCount': criticalCount,
    'warningCount': warningCount,
    'infoCount': infoCount,
    'resolvedKeys': resolvedKeys,
  };

  static HealthReportRecord? fromJson(Map<String, dynamic> json) {
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '');
    final tablesChecked = int.tryParse(json['tablesChecked']?.toString() ?? '');
    final criticalCount = int.tryParse(json['criticalCount']?.toString() ?? '');
    final warningCount = int.tryParse(json['warningCount']?.toString() ?? '');
    final infoCount = int.tryParse(json['infoCount']?.toString() ?? '');
    final resolvedKeys = (json['resolvedKeys'] is List)
        ? (json['resolvedKeys'] as List).map((item) => item.toString()).toList()
        : <String>[];
    if (createdAt == null ||
        tablesChecked == null ||
        criticalCount == null ||
        warningCount == null ||
        infoCount == null) {
      return null;
    }
    return HealthReportRecord(
      createdAt: createdAt,
      tablesChecked: tablesChecked,
      criticalCount: criticalCount,
      warningCount: warningCount,
      infoCount: infoCount,
      resolvedKeys: resolvedKeys,
    );
  }
}

class ImportRecord {
  const ImportRecord({
    required this.createdAt,
    required this.fileName,
    required this.totalRows,
    required this.importedRows,
    required this.duplicateRows,
    required this.skippedRows,
    required this.rolledBack,
  });

  final DateTime createdAt;
  final String fileName;
  final int totalRows;
  final int importedRows;
  final int duplicateRows;
  final int skippedRows;
  final bool rolledBack;

  Map<String, dynamic> toJson() => {
    'createdAt': createdAt.toIso8601String(),
    'fileName': fileName,
    'totalRows': totalRows,
    'importedRows': importedRows,
    'duplicateRows': duplicateRows,
    'skippedRows': skippedRows,
    'rolledBack': rolledBack,
  };

  static ImportRecord? fromJson(Map<String, dynamic> json) {
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '');
    final fileName = json['fileName']?.toString();
    final totalRows = int.tryParse(json['totalRows']?.toString() ?? '');
    final importedRows = int.tryParse(json['importedRows']?.toString() ?? '');
    final duplicateRows = int.tryParse(json['duplicateRows']?.toString() ?? '');
    final skippedRows = int.tryParse(json['skippedRows']?.toString() ?? '');
    if (createdAt == null ||
        fileName == null ||
        totalRows == null ||
        importedRows == null ||
        duplicateRows == null ||
        skippedRows == null) {
      return null;
    }
    return ImportRecord(
      createdAt: createdAt,
      fileName: fileName,
      totalRows: totalRows,
      importedRows: importedRows,
      duplicateRows: duplicateRows,
      skippedRows: skippedRows,
      rolledBack: json['rolledBack'] == true,
    );
  }
}

class SpendingAlertRecord {
  const SpendingAlertRecord({
    required this.createdAt,
    required this.title,
    required this.message,
    this.isRead = false,
  });

  final DateTime createdAt;
  final String title;
  final String message;
  final bool isRead;

  SpendingAlertRecord copyWith({bool? isRead}) => SpendingAlertRecord(
    createdAt: createdAt,
    title: title,
    message: message,
    isRead: isRead ?? this.isRead,
  );

  Map<String, dynamic> toJson() => {
    'createdAt': createdAt.toIso8601String(),
    'title': title,
    'message': message,
    'isRead': isRead,
  };

  static SpendingAlertRecord? fromJson(Map<String, dynamic> json) {
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '');
    final title = json['title']?.toString();
    final message = json['message']?.toString();
    if (createdAt == null || title == null || message == null) return null;
    return SpendingAlertRecord(
      createdAt: createdAt,
      title: title,
      message: message,
      isRead: json['isRead'] == true,
    );
  }
}

class MonthlyReportRecord {
  const MonthlyReportRecord({
    required this.createdAt,
    required this.month,
    required this.income,
    required this.expense,
    required this.net,
  });

  final DateTime createdAt;
  final DateTime month;
  final int income;
  final int expense;
  final int net;

  Map<String, dynamic> toJson() => {
    'createdAt': createdAt.toIso8601String(),
    'month': month.toIso8601String(),
    'income': income,
    'expense': expense,
    'net': net,
  };

  static MonthlyReportRecord? fromJson(Map<String, dynamic> json) {
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '');
    final month = DateTime.tryParse(json['month']?.toString() ?? '');
    final income = int.tryParse(json['income']?.toString() ?? '');
    final expense = int.tryParse(json['expense']?.toString() ?? '');
    final net = int.tryParse(json['net']?.toString() ?? '');
    if (createdAt == null ||
        month == null ||
        income == null ||
        expense == null ||
        net == null) {
      return null;
    }
    return MonthlyReportRecord(
      createdAt: createdAt,
      month: month,
      income: income,
      expense: expense,
      net: net,
    );
  }
}
