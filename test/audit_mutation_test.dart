import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/asset/domain/entities/asset_entity.dart';
import 'package:ffm_manager/features/asset/domain/usecases/asset_crud_usecases.dart';
import 'package:ffm_manager/features/goal/domain/entities/goal_entity.dart';
import 'package:ffm_manager/features/goal/domain/usecases/goal_crud_usecases.dart';
import 'package:ffm_manager/features/liability/domain/entities/liability_entity.dart';
import 'package:ffm_manager/features/liability/domain/usecases/liability_crud_usecases.dart';
import 'package:ffm_manager/features/receivable/domain/entities/receivable_entity.dart';
import 'package:ffm_manager/features/receivable/domain/usecases/receivable_crud_usecases.dart';
import 'package:ffm_manager/features/recurring_transaction/domain/usecases/recurring_transaction_crud_usecases.dart';

void main() {
  test('mutasi non-kas penting tercatat di Log Aktivitas', () async {
    final database = createInMemoryDatabaseForTests();
    addTearDown(database.close);
    final householdId = AppContext.householdId;
    final date = DateTime(2026, 8, 20);

    await SaveAsset(database)(
      AssetEntity(
        id: 'asset-1',
        householdId: householdId,
        name: 'Motor',
        assetType: 'Kendaraan',
        value: 12000000,
        placement: 'Garasi',
        createdAt: date,
      ),
    );
    await SaveLiability(database)(
      LiabilityEntity(
        id: 'liability-1',
        householdId: householdId,
        name: 'Cicilan',
        originalAmount: 5000000,
        remainingBalance: 4000000,
        monthlyInstallment: 500000,
        startDate: date,
        dueDate: date.add(const Duration(days: 30)),
        updatedAt: date,
      ),
    );
    await SaveReceivable(database)(
      ReceivableEntity(
        id: 'receivable-1',
        householdId: householdId,
        name: 'Pinjaman keluarga',
        originalAmount: 1000000,
        remainingBalance: 1000000,
        monthlyInstallment: 250000,
        startDate: date,
        dueDate: date.add(const Duration(days: 30)),
        updatedAt: date,
      ),
    );
    await SaveGoal(database)(
      GoalEntity(
        id: 'goal-1',
        householdId: householdId,
        name: 'Dana darurat',
        targetAmount: 5000000,
        currentAmount: 500000,
        targetDate: date.add(const Duration(days: 90)),
        createdAt: date,
      ),
    );
    await CreateRecurringTransaction(database)(
      householdId: householdId,
      name: 'Bunga harian',
      type: 'income',
      amount: 1000,
      startDate: date,
      periodType: 'daily',
      calcMode: 'fixed',
    );
    await ProcessRecurringTransactions(database)(householdId, now: date);

    final rows = await database
        .customSelect('SELECT action, entity FROM audit_logs')
        .get();
    final events = rows
        .map(
          (row) =>
              '${row.read<String>('action')}|${row.read<String>('entity')}',
        )
        .toSet();

    expect(
      events,
      containsAll([
        'simpan aset|asset',
        'simpan hutang|liability',
        'simpan piutang|receivable',
        'simpan target|goal',
        'simpan aturan berkala|recurring_transaction',
        'buat transaksi berkala|transaction',
      ]),
    );
  });
}
