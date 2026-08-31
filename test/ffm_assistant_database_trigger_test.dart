import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_autonomy_repository.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_autonomy_trigger_service.dart';
import 'package:ffm_manager/features/transaction/domain/usecases/transaction_crud_usecases.dart';

void main() {
  test(
    'penyimpanan transaksi mengantrekan database.changed tanpa nominal',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final autonomy = FfmAssistantAutonomyRepository(database);
      final trigger = FfmAssistantAutonomyTriggerService(autonomy);

      await SaveTransaction(database, autonomyTrigger: trigger)(
        TransactionEntity(
          id: 'database-trigger-transaction',
          householdId: 'household-a',
          date: DateTime(2026, 9, 1),
          amount: 125000,
          owner: 'Naya',
          categoryId: null,
          recordedAt: DateTime(2026, 9, 1, 12),
          updatedAt: DateTime(2026, 9, 1, 12),
        ),
      );

      final events = await autonomy.pendingEvents(householdId: 'household-a');
      expect(events, hasLength(1));
      expect(events.single.type, 'database.changed');
      expect(events.single.payload, {
        'entityType': 'transaction',
        'operation': 'save',
      });
    },
  );
}
