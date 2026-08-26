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

    final service = JsonBackupService(source);
    final historyRows = [
      {
        'isUser': true,
        'text': 'catat gaji',
        'imagePath': '/path/to/image.jpg',
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

    expect(decoded['formatVersion'], 'ffm-v23-full');
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
        'account_reconciliation_logs',
        'audit_logs',
        'assistant_memories',
        'assistant_learning_examples',
        'assistant_unanswered_questions',
        'assistant_chat_history',
      ]),
    );
    expect((modules['audit_logs'] as List), hasLength(1));
    expect((modules['account_reconciliation_logs'] as List), hasLength(1));

    final directory = await Directory.systemTemp.createTemp('ffm-backup-test-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/backup.json');
    await file.writeAsString(content);

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
    expect(auditRows, hasLength(1));
    expect(auditRows.single.read<String>('action'), 'create');
    expect(reconciliationRows, hasLength(1));
    expect(reconciliationRows.single.read<int>('difference'), -1000);

    expect(restoredHistory, isNotNull);
    expect(restoredHistory, hasLength(1));
    expect(restoredHistory!.single['text'], 'catat gaji');
    expect(restoredHistory!.single.containsKey('imagePath'), isFalse);
  });
}
