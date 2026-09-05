import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';

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

  Future<String> exportJson({
    List<Map<String, Object?>>? assistantChatHistory,
    List<Map<String, Object?>>? assistantChatConversations,
    List<Map<String, Object?>>? utilityMeters,
    List<Map<String, Object?>>? cashFlowProfiles,
    List<Map<String, Object?>>? vehicles,
  }) async {
    final tables = await _getUserTableNames();
    final modules = <String, Object?>{};
    for (final table in tables) {
      final rows = await database.customSelect('SELECT * FROM "$table"').get();
      modules[table] = rows.map((row) => _jsonSafe(row.data)).toList();
    }
    if (assistantChatHistory != null) {
      modules['assistant_chat_history'] = assistantChatHistory
          .map(_jsonSafe)
          .whereType<Map<String, Object?>>()
          .toList(growable: false);
    }
    if (assistantChatConversations != null) {
      modules['assistant_chat_conversations'] = assistantChatConversations
          .map(_jsonSafe)
          .whereType<Map<String, Object?>>()
          .toList(growable: false);
    }
    if (utilityMeters != null) {
      modules['utility_meters'] = utilityMeters
          .map(_jsonSafe)
          .whereType<Map<String, Object?>>()
          .toList(growable: false);
    }
    if (cashFlowProfiles != null) {
      modules['cash_flow_profiles'] = cashFlowProfiles
          .map(_jsonSafe)
          .whereType<Map<String, Object?>>()
          .toList(growable: false);
    }
    if (vehicles != null) {
      modules['vehicles'] = vehicles
          .map(_jsonSafe)
          .whereType<Map<String, Object?>>()
          .toList(growable: false);
    }
    return jsonEncode({
      'formatVersion': 'ffm-v24-full-safe',
      'schemaVersion': database.schemaVersion,
      'householdId': AppContext.householdId,
      'exportedAt': DateTime.now().toIso8601String(),
      'isFull': true,
      'redaction': {
        'secretFieldsExcluded': true,
        'excludedNames': const [
          'api_key',
          'token',
          'password',
          'pin',
          'otp',
          'secret',
          'credential',
        ],
      },
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

  Future<void> importAndRestore(
    String path, {
    Future<void> Function(List<Map<String, Object?>> rows)?
    onRestoreChatHistory,
    Future<void> Function(List<Map<String, Object?>> rows)?
    onRestoreChatConversations,
    Future<void> Function(List<Map<String, Object?>> rows)?
    onRestoreUtilityMeters,
    Future<void> Function(List<Map<String, Object?>> rows)?
    onRestoreCashFlowProfiles,
    Future<void> Function(List<Map<String, Object?>> rows)?
    onRestoreVehicles,
  }) async {
    final content = await File(path).readAsString();
    final decoded = jsonDecode(content);
    if (decoded is! Map<String, dynamic> || decoded['isFull'] != true) {
      throw const FormatException('Berkas ini bukan cadangan penuh FFM.');
    }
    final rawModules = decoded['modules'];
    if (rawModules is! Map) {
      throw const FormatException('Bagian data cadangan tidak ditemukan.');
    }
    await _ensureAuditTable();
    if (rawModules['activity_notes'] is List) {
      await _ensureActivityNotesTable();
    }
    final tables = await _getUserTableNames();
    final modules = <String, List<Map<String, dynamic>>>{};
    for (final table in tables) {
      final rows = rawModules[table];
      if (rows is! List) continue;
      modules[table] = rows
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    }
    final chatHistoryRows = rawModules['assistant_chat_history'];
    final chatConversationRows = rawModules['assistant_chat_conversations'];
    final utilityMeterRows = rawModules['utility_meters'];
    final cashFlowProfileRows = rawModules['cash_flow_profiles'];
    final vehicleRows = rawModules['vehicles'];
    final safeChatHistory = chatHistoryRows is List
        ? chatHistoryRows
              .whereType<Map>()
              .map((row) => Map<String, Object?>.from(row))
              .toList()
        : null;
    final safeChatConversations = chatConversationRows is List
        ? chatConversationRows
              .whereType<Map>()
              .map((row) => Map<String, Object?>.from(row))
              .toList()
        : null;
    final safeUtilityMeters = utilityMeterRows is List
        ? utilityMeterRows
              .whereType<Map>()
              .map((row) => Map<String, Object?>.from(row))
              .toList()
        : null;
    final safeCashFlowProfiles = cashFlowProfileRows is List
        ? cashFlowProfileRows
              .whereType<Map>()
              .map((row) => Map<String, Object?>.from(row))
              .toList()
        : null;
    final safeVehicles = vehicleRows is List
        ? vehicleRows
              .whereType<Map>()
              .map((row) => Map<String, Object?>.from(row))
              .toList()
        : null;

    final tableColumnsMap = await _getTableColumnsMap(tables);

    await database.transaction(() async {
      await database.customStatement('PRAGMA foreign_keys = OFF');
      try {
        for (final table in tables) {
          final validColumns = tableColumnsMap[table];
          if (validColumns == null || validColumns.isEmpty) continue;
          for (final row in modules[table] ?? const <Map<String, dynamic>>[]) {
            await _insertRowAdaptive(table, row, validColumns);
          }
        }
      } finally {
        await database.customStatement('PRAGMA foreign_keys = ON');
      }
    });

    if (onRestoreChatHistory != null && safeChatHistory != null) {
      await onRestoreChatHistory(safeChatHistory);
    }
    if (onRestoreChatConversations != null && safeChatConversations != null) {
      await onRestoreChatConversations(safeChatConversations);
    }
    if (onRestoreUtilityMeters != null && safeUtilityMeters != null) {
      await onRestoreUtilityMeters(safeUtilityMeters);
    }
    if (onRestoreCashFlowProfiles != null && safeCashFlowProfiles != null) {
      await onRestoreCashFlowProfiles(safeCashFlowProfiles);
    }
    if (onRestoreVehicles != null && safeVehicles != null) {
      await onRestoreVehicles(safeVehicles);
    }
  }

  Future<List<String>> _getUserTableNames() async {
    final rows = await database
        .customSelect(
          "SELECT name FROM sqlite_master "
          "WHERE type = 'table' AND name NOT LIKE 'sqlite_%' "
          'ORDER BY name',
        )
        .get();
    return rows
        .map((row) => row.data['name']?.toString())
        .whereType<String>()
        .where((name) => RegExp(r'^[a-z0-9_]+$').hasMatch(name))
        .toList(growable: false);
  }

  Future<bool> _tableExists(String table) async {
    final tables = await _getUserTableNames();
    return tables.contains(table);
  }

  Future<void> _ensureAuditTable() async {
    await database.customStatement(
      'CREATE TABLE IF NOT EXISTS audit_logs ('
      'id TEXT PRIMARY KEY, household_id TEXT NOT NULL, action TEXT NOT NULL, '
      'entity TEXT NOT NULL, old_value TEXT, new_value TEXT, timestamp INTEGER NOT NULL)',
    );
  }

  Future<void> _ensureActivityNotesTable() async {
    await database.customStatement(
      'CREATE TABLE IF NOT EXISTS activity_notes ('
      'id TEXT PRIMARY KEY, household_id TEXT NOT NULL, text TEXT NOT NULL, '
      'category TEXT NOT NULL, numeric_value REAL, unit TEXT, latitude REAL, '
      'longitude REAL, created_at INTEGER NOT NULL, linked_session_id TEXT, '
      'source TEXT NOT NULL, is_archived INTEGER NOT NULL DEFAULT 0, '
      'updated_at INTEGER)',
    );
  }

  Future<Map<String, Set<String>>> _getTableColumnsMap(
    List<String> tables,
  ) async {
    final columnsMap = <String, Set<String>>{};
    for (final table in tables) {
      if (!await _tableExists(table)) continue;
      final rows = await database
          .customSelect('PRAGMA table_info("$table")')
          .get();
      final columns = rows
          .map((r) => r.data['name']?.toString())
          .whereType<String>()
          .toSet();
      columnsMap[table] = columns;
    }
    return columnsMap;
  }

  Future<void> _insertRowAdaptive(
    String table,
    Map<String, dynamic> row,
    Set<String> validColumns,
  ) async {
    if (row.isEmpty || validColumns.isEmpty) return;

    // Hanya ambil kolom dari JSON yang benar-benar ada di tabel database SQLite saat ini
    final filteredEntries = row.entries
        .where((e) => validColumns.contains(e.key))
        .toList();
    if (filteredEntries.isEmpty) return;

    final columns = filteredEntries.map((e) => '"${e.key}"').join(', ');
    final placeholders = List.filled(filteredEntries.length, '?').join(', ');
    final values = filteredEntries
        .map((entry) => _databaseValue(entry.key, entry.value))
        .toList();

    await database.customStatement(
      'INSERT OR IGNORE INTO "$table" ($columns) VALUES ($placeholders)',
      values,
    );
  }

  bool _isSecretField(String key) {
    final normalized = key.toLowerCase().replaceAll('-', '_');
    // Field token listrik PLN (misal: lastTokenNumber, tokenNumber, lastToken) bukan token auth rahasia
    if (normalized.contains('tokennumber') ||
        normalized.contains('token_number') ||
        normalized.contains('lasttoken') ||
        normalized.contains('last_token') ||
        normalized.contains('tokenhistory') ||
        normalized.contains('token_history')) {
      return false;
    }
    return normalized.contains('api_key') ||
        normalized.contains('token') ||
        normalized.contains('password') ||
        normalized == 'pin' ||
        normalized.contains('otp') ||
        normalized.contains('secret') ||
        normalized.contains('credential');
  }

  Object? _databaseValue(String column, Object? value) {
    if (value is DateTime) return value.microsecondsSinceEpoch;
    if (value is bool) return value ? 1 : 0;
    if (value is String && _isTimestampColumn(column)) {
      final dateTime = DateTime.tryParse(value);
      if (dateTime != null) return dateTime.microsecondsSinceEpoch;
    }
    return value;
  }

  bool _isTimestampColumn(String column) => const {
    'checked_at',
    'completed_at',
    'created_at',
    'date',
    'due_at',
    'due_date',
    'end_date',
    'ended_at',
    'exported_at',
    'finished_at',
    'gregorian_start_date',
    'harvested_at',
    'last_attempt_at',
    'last_run_at',
    'last_updated',
    'next_run_at',
    'note_date',
    'occurred_at',
    'occurrence_date',
    'processed_at',
    'recorded_at',
    'routine_date',
    'scheduled_at',
    'scheduled_date',
    'snoozed_until',
    'start_date',
    'started_at',
    'target_date',
    'timestamp',
    'triggered_at',
    'updated_at',
  }.contains(column);

  Object? _jsonSafe(Object? value) {
    if (value is DateTime) return value.toIso8601String();
    if (value is Uint8List) return base64Encode(value);
    if (value is Map) {
      final safe = <String, Object?>{};
      for (final entry in value.entries) {
        final key = entry.key.toString();
        if (_isSecretField(key)) continue;
        safe[key] = _jsonSafe(entry.value);
      }
      return safe;
    }
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
    'recurring_transaction_runs' => 'recurring_runs',
    'account_reconciliation_logs' => 'reconciliations',
    'audit_logs' => 'activity_logs',
    'activity_sessions' => 'activity_sessions',
    'activity_checkpoints' => 'activity_checkpoints',
    'activity_entries' => 'activity_entries',
    'assistant_memories' => 'assistant_memories',
    'assistant_learning_examples' => 'assistant_learning_examples',
    'assistant_chat_history' => 'assistant_chat_history',
    'utility_meters' => 'utility_meters',
    'cash_flow_profiles' => 'cash_flow_profiles',
    'vehicles' => 'vehicles',
    _ => table,
  };
}
