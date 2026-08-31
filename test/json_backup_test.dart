import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/database/audit_logger.dart';
import 'package:ffm_manager/features/backup/data/json_backup_service.dart';

void main() {
  test('cadangan penuh mencakup modul data dan jejak audit', () async {
    final source = createInMemoryDatabaseForTests();
    var sourceClosed = false;
    Future<void> closeSource() async {
      if (sourceClosed) return;
      sourceClosed = true;
      await source.close();
    }

    addTearDown(closeSource);
    final now = DateTime(2026, 8, 20, 10, 0);

    await AuditLogger(source).record(
      action: 'create',
      entity: 'transaction',
      newValue: {'id': 'trx-1', 'amount': 100000},
    );
    await source.customStatement(
      'INSERT INTO harvest_events '
      '(id, household_id, commodity, quantity, unit, unit_price, total_amount, '
      'buyer_name, location, note, linked_activity_id, harvested_at, is_archived, '
      'created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        'harvest-1',
        AppContext.householdId,
        'Pepaya',
        25.5,
        'kg',
        8000,
        204000,
        'Pak Budi',
        'Kebun A',
        'Panen pagi',
        null,
        now.microsecondsSinceEpoch,
        0,
        now.microsecondsSinceEpoch,
        now.microsecondsSinceEpoch,
      ],
    );
    await source.customStatement(
      'INSERT INTO account_reconciliation_logs '
      '(id, household_id, account_id, book_balance, actual_balance, difference, '
      'checked_at, note, adjustment_transaction_id, created_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        'recon-1',
        AppContext.householdId,
        'account-seabank',
        1000000,
        999000,
        -1000,
        now.microsecondsSinceEpoch,
        'Cek saldo',
        null,
        now.microsecondsSinceEpoch,
      ],
    );
    await source.customStatement(
      'INSERT INTO reminders '
      '(id, household_id, title, scheduled_at, recurrence_type, weekdays_json, '
      'is_active, default_snooze_minutes, notification_id, created_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        'reminder-1',
        AppContext.householdId,
        'Bayar listrik',
        now.microsecondsSinceEpoch,
        'once',
        '[]',
        1,
        10,
        101,
        now.microsecondsSinceEpoch,
      ],
    );
    await source.customStatement(
      'INSERT INTO assistant_agent_runs '
      '(id, household_id, trigger, status, summary, started_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?)',
      [
        'agent-run-1',
        AppContext.householdId,
        'database_change',
        'completed',
        'Ringkasan aman',
        now.microsecondsSinceEpoch,
        now.microsecondsSinceEpoch,
      ],
    );
    await source.customStatement(
      'CREATE TABLE activity_notes ('
      'id TEXT PRIMARY KEY, household_id TEXT NOT NULL, text TEXT NOT NULL, '
      'category TEXT NOT NULL, numeric_value REAL, unit TEXT, latitude REAL, '
      'longitude REAL, created_at INTEGER NOT NULL, linked_session_id TEXT, '
      'source TEXT NOT NULL, is_archived INTEGER NOT NULL DEFAULT 0, '
      'updated_at INTEGER)',
    );
    await source.customStatement(
      'INSERT INTO activity_notes '
      '(id, household_id, text, category, created_at, source, is_archived) '
      'VALUES (?, ?, ?, ?, ?, ?, ?)',
      [
        'activity-note-1',
        AppContext.householdId,
        'Menyiram kebun',
        'farming',
        now.microsecondsSinceEpoch,
        'manual',
        0,
      ],
    );

    final service = JsonBackupService(source);
    final historyRows = [
      {
        'isUser': true,
        'text': 'catat gaji',
        'imagePath': '/path/to/image.jpg',
        'api_key': 'must-not-export',
        'createdAt': now.toIso8601String(),
      },
    ];
    final filteredHistory = historyRows
        .map((row) {
          final mutable = Map<String, Object?>.of(row);
          mutable.remove('imagePath');
          return mutable;
        })
        .toList(growable: false);
    final content = await service.exportJson(
      assistantChatHistory: filteredHistory,
    );
    final decoded = jsonDecode(content) as Map<String, dynamic>;
    final modules = decoded['modules'] as Map<String, dynamic>;

    expect(decoded['formatVersion'], 'ffm-v24-full-safe');
    expect(decoded['schemaVersion'], source.schemaVersion);
    expect(decoded['isFull'], isTrue);
    expect(
      modules.keys,
      containsAll([
        'categories',
        'merchants',
        'tags',
        'accounts',
        'transactions',
        'transaction_items',
        'transfers',
        'envelope_budgets',
        'recurring_transactions',
        'recurring_transaction_runs',
        'assets',
        'liabilities',
        'receivables',
        'goals',
        'hijri_settings',
        'hijri_correction_logs',
        'hijri_month_overrides',
        'reminders',
        'reminder_histories',
        'account_reconciliation_logs',
        'audit_logs',
        'assistant_memories',
        'assistant_learning_examples',
        'assistant_unanswered_questions',
        'harvest_events',
        'activity_notes',
        'assistant_agent_runs',
        'assistant_agent_events',
        'assistant_agent_approvals',
        'assistant_agent_tool_executions',
        'assistant_agent_goals',
        'assistant_agent_tasks',
        'assistant_agent_task_executions',
        'assistant_chat_history',
      ]),
    );
    expect((modules['audit_logs'] as List), hasLength(1));
    expect((modules['account_reconciliation_logs'] as List), hasLength(1));
    expect((modules['harvest_events'] as List), hasLength(1));
    final exportedChat =
        (modules['assistant_chat_history'] as List).single as Map;
    expect(exportedChat.containsKey('api_key'), isFalse);
    final exportedReminder = (modules['reminders'] as List).single as Map;
    exportedReminder['scheduled_at'] = now.toIso8601String();

    final directory = await Directory.systemTemp.createTemp('ffm-backup-test-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/backup.json');
    await file.writeAsString(jsonEncode(decoded));

    await closeSource();
    final restored = createInMemoryDatabaseForTests();
    addTearDown(restored.close);
    List<Map<String, Object?>>? restoredHistory;
    await JsonBackupService(restored).importAndRestore(
      file.path,
      onRestoreChatHistory: (rows) async {
        restoredHistory = rows;
      },
    );

    final auditRows = await restored
        .customSelect('SELECT id, action FROM audit_logs')
        .get();
    final reconciliationRows = await restored
        .customSelect('SELECT id, difference FROM account_reconciliation_logs')
        .get();
    final reminderRows = await restored
        .customSelect('SELECT scheduled_at FROM reminders')
        .get();
    final agentRunRows = await restored
        .customSelect('SELECT id FROM assistant_agent_runs')
        .get();
    final activityNoteRows = await restored
        .customSelect('SELECT text FROM activity_notes')
        .get();
    expect(auditRows, hasLength(1));
    expect(auditRows.single.read<String>('action'), 'create');
    expect(reconciliationRows, hasLength(1));
    expect(reconciliationRows.single.read<int>('difference'), -1000);
    expect(reminderRows, hasLength(1));
    expect(
      reminderRows.single.read<int>('scheduled_at'),
      now.microsecondsSinceEpoch,
    );
    expect(agentRunRows, hasLength(1));
    expect(activityNoteRows.single.read<String>('text'), 'Menyiram kebun');

    expect(restoredHistory, isNotNull);
    expect(restoredHistory, hasLength(1));
    expect(restoredHistory!.single['text'], 'catat gaji');
    expect(restoredHistory!.single.containsKey('imagePath'), isFalse);
    expect(restoredHistory!.single.containsKey('api_key'), isFalse);
  });
}
