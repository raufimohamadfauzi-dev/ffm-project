import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/database/audit_logger.dart';
import 'package:ffm_manager/features/recurring_transaction/domain/usecases/recurring_transaction_crud_usecases.dart';

void main() {
  test(
    'rekonsiliasi mencatat selisih positif, negatif, dan saldo yang sama',
    () async {
      final database = createInMemoryDatabaseForTests();
      addTearDown(database.close);
      final checkedAt = DateTime(2026, 8, 20, 9, 30);

      for (final id in ['account-more', 'account-less', 'account-same']) {
        await database
            .into(database.accounts)
            .insert(
              AccountsCompanion.insert(
                id: id,
                householdId: AppContext.householdId,
                name: id,
                type: 'bank',
                openingBalance: const Value(100000),
                createdAt: checkedAt,
              ),
            );
      }

      final createLog = CreateReconciliationLog(database);
      final positive = await createLog(
        householdId: AppContext.householdId,
        accountId: 'account-more',
        actualBalance: 110000,
        checkedAt: checkedAt,
      );
      final negative = await createLog(
        householdId: AppContext.householdId,
        accountId: 'account-less',
        actualBalance: 90000,
        checkedAt: checkedAt,
      );
      final equal = await createLog(
        householdId: AppContext.householdId,
        accountId: 'account-same',
        actualBalance: 100000,
        checkedAt: checkedAt,
      );

      expect(positive.bookBalance, 100000);
      expect(positive.difference, 10000);
      expect(positive.adjustmentTransactionId, isNotNull);
      expect(negative.difference, -10000);
      expect(negative.adjustmentTransactionId, isNotNull);
      expect(equal.difference, 0);
      expect(equal.adjustmentTransactionId, isNull);

      final adjustments = await (database.select(
        database.transactions,
      )..where((row) => row.source.equals('balance_adjustment'))).get();
      expect(adjustments, hasLength(2));
      expect(
        adjustments.map((row) => row.amount),
        containsAll(<int>[10000, -10000]),
      );

      await AuditLogger(database).record(
        action: 'rekonsiliasi',
        entity: 'saldo_rekening',
        oldValue: {
          'account_id': 'account-more',
          'saldo_buku': positive.bookBalance,
        },
        newValue: {
          'account_id': 'account-more',
          'saldo_nyata': positive.actualBalance,
          'selisih': positive.difference,
        },
      );
      final auditRows = await database
          .customSelect(
            'SELECT action, entity, old_value, new_value FROM audit_logs WHERE household_id = :householdId',
            variables: [Variable.withString(AppContext.householdId)],
          )
          .get();
      expect(auditRows, hasLength(1));
      expect(auditRows.single.read<String>('action'), 'rekonsiliasi');
      expect(auditRows.single.read<String>('entity'), 'saldo_rekening');
      expect(
        auditRows.single.read<String>('new_value'),
        contains('saldo_nyata'),
      );
    },
  );
}
