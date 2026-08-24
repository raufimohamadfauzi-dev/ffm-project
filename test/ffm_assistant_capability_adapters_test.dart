import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_capability_adapters.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_plan.dart';

void main() {
  late AppDatabase database;
  late FfmAssistantCapabilityAdapterRegistry adapters;

  setUp(() {
    database = createInMemoryDatabaseForTests();
    adapters = FfmAssistantCapabilityAdapterRegistry(
      database: database,
      householdId: 'local-household',
      clock: () => DateTime(2026, 8, 23),
    );
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'read-only adapters mengembalikan hasil aman pada database kosong',
    () async {
      final planStep = const FfmAssistantActionStep(
        id: 'read',
        capabilityId: 'read.summary',
      );
      final summary = await adapters.handlers['read.summary']!(planStep);
      final accounts = await adapters.handlers['read.accounts']!(
        const FfmAssistantActionStep(
          id: 'accounts',
          capabilityId: 'read.accounts',
        ),
      );
      final categories = await adapters.handlers['read.categories']!(
        const FfmAssistantActionStep(
          id: 'categories',
          capabilityId: 'read.categories',
        ),
      );
      final transactions = await adapters.handlers['read.transactions']!(
        const FfmAssistantActionStep(
          id: 'transactions',
          capabilityId: 'read.transactions',
        ),
      );

      expect(summary.isSuccess, isTrue);
      expect(summary.message, contains('Ringkasan bulan ini'));
      expect(accounts.message, contains('Belum ada rekening'));
      expect(categories.message, contains('Kategori aktif'));
      expect(transactions.message, contains('Tidak ada transaksi'));
    },
  );
}
