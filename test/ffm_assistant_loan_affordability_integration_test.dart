import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = createInMemoryDatabaseForTests();
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'kemampuan pinjaman memakai pemasukan, pengeluaran, dan cicilan lokal',
    () async {
      final now = DateTime(2026, 8, 23);
      await database
          .into(database.transactions)
          .insert(
            TransactionsCompanion.insert(
              id: 'income-august',
              householdId: AppContext.householdId,
              type: 'income',
              amount: 10000000,
              date: now,
              recordedAt: now,
              createdAt: now,
            ),
          );
      await database
          .into(database.transactions)
          .insert(
            TransactionsCompanion.insert(
              id: 'expense-august',
              householdId: AppContext.householdId,
              type: 'expense',
              amount: -6000000,
              date: now,
              recordedAt: now,
              createdAt: now,
            ),
          );
      await database
          .into(database.liabilities)
          .insert(
            LiabilitiesCompanion.insert(
              id: 'motor-loan',
              householdId: AppContext.householdId,
              name: 'Cicilan motor',
              originalAmount: 12000000,
              remainingBalance: 6000000,
              monthlyInstallment: const Value(1000000),
              startDate: DateTime(2026, 1, 1),
              createdAt: now,
            ),
          );

      final interpreter = FfmAssistantInterpreter(database, clock: () => now);
      final intent = await interpreter.interpret(
        'berapa cicilan maksimal yang aman untuk saya?',
      );

      expect(intent.type, FfmAssistantIntentType.queryData);
      expect(intent.response, contains('Pemasukan tercatat: Rp10.000.000'));
      expect(intent.response, contains('Pengeluaran tercatat: Rp6.000.000'));
      expect(intent.response, contains('Cicilan aktif: Rp1.000.000'));
      expect(
        intent.response,
        contains('Estimasi cicilan baru konservatif: maksimal Rp2.000.000'),
      );
      expect(intent.response, contains('bukan persetujuan kredit'));
    },
  );
}
