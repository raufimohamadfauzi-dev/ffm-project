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

  test('F2.5 offline: analisis arus kas, cicilan dan target dihitung secara deterministik (surplus)', () async {
    final now = DateTime(2026, 9, 15);
    // Pemasukan 15 juta
    await database
        .into(database.transactions)
        .insert(
          TransactionsCompanion.insert(
            id: 'inc-1',
            householdId: AppContext.householdId,
            type: 'income',
            amount: 15000000,
            date: now,
            recordedAt: now,
            createdAt: now,
          ),
        );
    // Pengeluaran operasional 8 juta -> Cashflow 7 juta
    await database
        .into(database.transactions)
        .insert(
          TransactionsCompanion.insert(
            id: 'exp-1',
            householdId: AppContext.householdId,
            type: 'expense',
            amount: -8000000,
            date: now,
            recordedAt: now,
            createdAt: now,
          ),
        );
    // Cicilan 2 juta per bulan
    await database
        .into(database.liabilities)
        .insert(
          LiabilitiesCompanion.insert(
            id: 'liab-1',
            householdId: AppContext.householdId,
            name: 'Cicilan Mobil',
            originalAmount: 50000000,
            remainingBalance: 20000000,
            monthlyInstallment: const Value(2000000),
            startDate: DateTime(2026, 1, 1),
            createdAt: now,
          ),
        );
    // Target: sisa 20 juta dalam 10 bulan -> 2 juta per bulan
    await database
        .into(database.goals)
        .insert(
          GoalsCompanion.insert(
            id: 'goal-1',
            householdId: AppContext.householdId,
            name: 'Dana Liburan',
            targetAmount: 30000000,
            currentAmount: const Value(10000000),
            targetDate: Value(DateTime(2027, 7, 15)),
            isActive: const Value(true),
            createdAt: now,
          ),
        );

    final interpreter = FfmAssistantInterpreter(database, clock: () => now);
    final intent = await interpreter.interpret(
      'Apakah arus kas saya cukup untuk cicilan dan target bulan ini?',
    );

    expect(intent.type, FfmAssistantIntentType.queryData);
    expect(intent.response, contains('Pemasukan tercatat: Rp15.000.000'));
    expect(intent.response, contains('Pengeluaran operasional: Rp8.000.000'));
    expect(intent.response, contains('Arus kas operasional: Rp7.000.000'));
    expect(intent.response, contains('Cicilan kewajiban aktif: Rp2.000.000'));
    expect(intent.response, contains('Total komitmen bulanan: Rp4.000.000'));
    expect(intent.response, contains('Sisa arus kas bersih: Rp3.000.000'));
    expect(intent.response, contains('Kesimpulan: **Arus kas mencukupi**'));
    expect(intent.response, contains('bersifat deterministik'));
  });

  test('F2.5 offline: analisis arus kas menyatakan defisit target jika cashflow hanya cukup untuk cicilan', () async {
    final now = DateTime(2026, 9, 15);
    // Pemasukan 10 juta, pengeluaran 7 juta -> Arus kas 3 juta
    await database
        .into(database.transactions)
        .insert(
          TransactionsCompanion.insert(
            id: 'inc-2',
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
            id: 'exp-2',
            householdId: AppContext.householdId,
            type: 'expense',
            amount: -7000000,
            date: now,
            recordedAt: now,
            createdAt: now,
          ),
        );
    // Cicilan 2.5 juta
    await database
        .into(database.liabilities)
        .insert(
          LiabilitiesCompanion.insert(
            id: 'liab-2',
            householdId: AppContext.householdId,
            name: 'Cicilan KPR',
            originalAmount: 100000000,
            remainingBalance: 50000000,
            monthlyInstallment: const Value(2500000),
            startDate: DateTime(2026, 1, 1),
            createdAt: now,
          ),
        );
    // Target butuh 2 juta per bulan (total komitmen 4.5 juta > arus kas 3 juta)
    await database
        .into(database.goals)
        .insert(
          GoalsCompanion.insert(
            id: 'goal-2',
            householdId: AppContext.householdId,
            name: 'Renovasi Dapur',
            targetAmount: 10000000,
            currentAmount: const Value(0),
            targetDate: Value(DateTime(2027, 2, 15)), // 5 bulan -> 2jt/bln
            isActive: const Value(true),
            createdAt: now,
          ),
        );

    final interpreter = FfmAssistantInterpreter(database, clock: () => now);
    final intent = await interpreter.interpret(
      'cukupkah arus kas untuk cicilan dan target?',
    );

    expect(intent.type, FfmAssistantIntentType.queryData);
    expect(intent.response, contains('Cicilan kewajiban aktif: Rp2.500.000'));
    expect(intent.response, contains('Total komitmen bulanan: Rp4.500.000'));
    expect(intent.response, contains('Sisa arus kas bersih: -Rp1.500.000'));
    expect(
      intent.response,
      contains(
        'cukup untuk cicilan utang, namun belum mencukupi penuh target tabungan',
      ),
    );
  });
}
