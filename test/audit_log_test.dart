import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/database/audit_logger.dart';
import 'package:ffm_manager/features/audit/data/repositories/audit_log_repository.dart';

void main() {
  test(
    'repository audit log mendukung filter aksi, pencarian, dan waktu',
    () async {
      final database = createInMemoryDatabaseForTests();
      addTearDown(database.close);
      final logger = AuditLogger(database);

      await logger.record(
        action: 'tambah',
        entity: 'transaksi',
        newValue: {'id': 'tx-1', 'amount': 100000, 'account_id': 'cash'},
      );
      await logger.record(
        action: 'rekonsiliasi',
        entity: 'saldo_rekening',
        oldValue: {'account_id': 'bank', 'saldo_buku': 100000},
        newValue: {'account_id': 'bank', 'saldo_nyata': 99000, 'pin': '1234'},
      );

      final repository = SqliteAuditLogRepository(database);
      final all = await repository.getLogs(
        householdId: AppContext.householdId,
        limit: 20,
      );
      expect(all, hasLength(2));

      final reconciliation = await repository.getLogs(
        householdId: AppContext.householdId,
        action: 'rekonsiliasi',
      );
      expect(reconciliation, hasLength(1));
      expect(reconciliation.single.entity, 'saldo_rekening');
      expect(reconciliation.single.changedFields, contains('saldo_nyata'));
      expect(reconciliation.single.changedFields, isNot(contains('pin')));

      final searched = await repository.getLogs(
        householdId: AppContext.householdId,
        search: 'transaksi',
      );
      expect(searched, hasLength(1));
      expect(searched.single.action, 'tambah');

      final recent = await repository.getLogs(
        householdId: AppContext.householdId,
        from: DateTime.now().subtract(const Duration(minutes: 1)),
        to: DateTime.now().add(const Duration(minutes: 1)),
      );
      expect(recent, hasLength(2));
    },
  );
}
