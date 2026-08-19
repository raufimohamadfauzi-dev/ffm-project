import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../../core/database/app_context.dart';
import '../../../core/database/app_database.dart';

class BackupPreview {
  const BackupPreview({
    required this.formatVersion,
    required this.isFull,
    required this.counts,
    this.transactionFrom,
    this.transactionTo,
  });

  final String formatVersion;
  final bool isFull;
  final Map<String, int> counts;
  final DateTime? transactionFrom;
  final DateTime? transactionTo;
}

class JsonBackupService {
  const JsonBackupService(this.database);

  final AppDatabase database;

  static const _tables = <String>[
    'transaction_tags',
    'transaction_items',
    'attachments',
    'transactions',
    'transfers',
    'envelope_transfers',
    'envelope_budgets',
    'recurring_transactions',
    'receivables',
    'liabilities',
    'goals',
    'assets',
    'transaction_parties',
    'accounts',
    'tags',
    'merchants',
    'categories',
    'hijri_correction_logs',
    'hijri_month_overrides',
    'hijri_settings',
    'households',
  ];

  Future<String> exportJson() async {
    final modules = <String, Object?>{};
    for (final table in _tables.reversed) {
      final rows = await database.customSelect('SELECT * FROM "$table"').get();
      modules[table] = rows.map((row) => _jsonSafe(row.data)).toList();
    }
    return jsonEncode({
      'formatVersion': 'ffm-v20-full',
      'householdId': AppContext.householdId,
      'exportedAt': DateTime.now().toIso8601String(),
      'isFull': true,
      'modules': modules,
    });
  }

  BackupPreview previewJson(String content) {
    final decoded = jsonDecode(content);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Berkas JSON tidak berbentuk cadangan FFM.');
    }
    final version = decoded['formatVersion']?.toString() ?? 'tidak dikenal';
    final isFull = decoded['isFull'] == true && decoded['modules'] is Map;
    final modules = decoded['modules'];
    if (modules is! Map) {
      return BackupPreview(
        formatVersion: version,
        isFull: false,
        counts: const {},
      );
    }
    final counts = <String, int>{};
    for (final entry in modules.entries) {
      final value = entry.value;
      if (value is List) counts[_countKey(entry.key.toString())] = value.length;
    }
    final transactionRows = modules['transactions'];
    DateTime? from;
    DateTime? to;
    if (transactionRows is List) {
      final dates =
          transactionRows
              .whereType<Map>()
              .map((row) => _dateFromJson(row['date']))
              .whereType<DateTime>()
              .toList()
            ..sort();
      if (dates.isNotEmpty) {
        from = dates.first;
        to = dates.last;
      }
    }
    return BackupPreview(
      formatVersion: version,
      isFull: isFull,
      counts: counts,
      transactionFrom: from,
      transactionTo: to,
    );
  }

  Future<void> importAndRestore(String path) async {
    final content = await File(path).readAsString();
    final decoded = jsonDecode(content);
    if (decoded is! Map<String, dynamic> || decoded['isFull'] != true) {
      throw const FormatException('Berkas ini bukan cadangan penuh FFM.');
    }
    final rawModules = decoded['modules'];
    if (rawModules is! Map) {
      throw const FormatException('Bagian data cadangan tidak ditemukan.');
    }
    final modules = <String, List<Map<String, dynamic>>>{};
    for (final table in _tables) {
      final rows = rawModules[table];
      if (rows is! List) continue;
      modules[table] = rows
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    }
    await database.transaction(() async {
      await database.customStatement('PRAGMA foreign_keys = OFF');
      try {
        for (final table in _tables) {
          await database.customStatement('DELETE FROM "$table"');
        }
        for (final table in _tables.reversed) {
          for (final row in modules[table] ?? const <Map<String, dynamic>>[]) {
            await _insertRow(table, row);
          }
        }
      } finally {
        await database.customStatement('PRAGMA foreign_keys = ON');
      }
    });
  }

  Future<void> _insertRow(String table, Map<String, dynamic> row) async {
    if (row.isEmpty) return;
    final columns = row.keys.map((key) => '"$key"').join(', ');
    final placeholders = List.filled(row.length, '?').join(', ');
    final values = row.values.map(_databaseValue).toList();
    await database.customStatement(
      'INSERT INTO "$table" ($columns) VALUES ($placeholders)',
      values,
    );
  }

  Object? _databaseValue(Object? value) {
    if (value is DateTime) return value.microsecondsSinceEpoch;
    if (value is bool) return value ? 1 : 0;
    return value;
  }

  Object? _jsonSafe(Object? value) {
    if (value is DateTime) return value.toIso8601String();
    if (value is Uint8List) return base64Encode(value);
    if (value is Map)
      return value.map(
        (key, value) => MapEntry(key.toString(), _jsonSafe(value)),
      );
    if (value is Iterable) return value.map(_jsonSafe).toList();
    return value;
  }

  DateTime? _dateFromJson(Object? value) {
    if (value is String) return DateTime.tryParse(value);
    if (value is int) return DateTime.fromMicrosecondsSinceEpoch(value);
    return null;
  }

  String _countKey(String table) => switch (table) {
    'transactions' => 'transactions',
    'assets' => 'assets',
    'liabilities' => 'liabilities',
    'goals' => 'goals',
    'envelope_budgets' => 'budgets',
    'recurring_transactions' => 'sinking_funds',
    _ => table,
  };
}
