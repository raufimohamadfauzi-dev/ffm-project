import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/asset/domain/entities/asset_entity.dart';
import 'package:ffm_manager/features/asset/domain/usecases/asset_crud_usecases.dart';
import 'package:ffm_manager/features/transaction/domain/usecases/transaction_crud_usecases.dart';

void main() {
  test(
    'aset bisa disimpan, diubah, dibaca, lalu diarsipkan tanpa hapus permanen',
    () async {
      final database = createInMemoryDatabaseForTests();
      addTearDown(database.close);
      final createdAt = DateTime(2026, 8, 19);
      final saveAsset = SaveAsset(database);

      await saveAsset(
        AssetEntity(
          id: 'asset-motor',
          householdId: AppContext.householdId,
          name: 'Motor keluarga',
          assetType: 'Kendaraan',
          value: 18000000,
          placement: 'Rumah',
          createdAt: createdAt,
          note: 'Dipakai bersama',
        ),
      );

      var assets = await GetAssets(database)(AppContext.householdId);
      expect(assets, hasLength(1));
      expect(assets.single.name, 'Motor keluarga');
      expect(assets.single.value, 18000000);

      await saveAsset(
        AssetEntity(
          id: 'asset-motor',
          householdId: AppContext.householdId,
          name: 'Motor keluarga',
          assetType: 'Kendaraan',
          value: 16500000,
          placement: 'Garasi',
          createdAt: createdAt,
          updatedAt: DateTime(2026, 8, 20),
        ),
      );

      assets = await GetAssets(database)(AppContext.householdId);
      expect(assets, hasLength(1));
      expect(assets.single.value, 16500000);
      expect(assets.single.placement, 'Garasi');

      await ArchiveAsset(database)(AppContext.householdId, 'asset-motor');
      expect(await GetAssets(database)(AppContext.householdId), isEmpty);
      final archived = await (database.select(
        database.assets,
      )..where((row) => row.id.equals('asset-motor'))).getSingle();
      expect(archived.isArchived, isTrue);
    },
  );

  test(
    'batch transaksi dan rincian item disimpan lewat satu use case atomik',
    () async {
      final database = createInMemoryDatabaseForTests();
      addTearDown(database.close);
      final recordedAt = DateTime(2026, 8, 20, 7, 15);
      final entities = [
        TransactionEntity(
          id: 'batch-1',
          householdId: AppContext.householdId,
          date: recordedAt,
          amount: -10500,
          owner: 'Keluarga',
          categoryId: 'expense-category',
          accountId: 'account-cash',
          source: 'json_batch',
          recordedAt: recordedAt,
        ),
        TransactionEntity(
          id: 'batch-2',
          householdId: AppContext.householdId,
          date: recordedAt,
          amount: -25000,
          owner: 'Keluarga',
          categoryId: 'expense-category',
          accountId: 'account-cash',
          source: 'json_batch',
          recordedAt: recordedAt,
        ),
      ];
      await SaveTransactionBatch(database)(
        entities,
        itemsByTransactionId: {
          'batch-1': [
            TransactionItemEntity(
              id: 'batch-item-1',
              transactionId: 'batch-1',
              itemName: 'Sayur',
              price: 3500,
              qty: 1,
            ),
            TransactionItemEntity(
              id: 'batch-item-2',
              transactionId: 'batch-1',
              itemName: 'Mie',
              price: 7000,
              qty: 1,
            ),
          ],
          'batch-2': [
            TransactionItemEntity(
              id: 'batch-item-3',
              transactionId: 'batch-2',
              itemName: 'BBM motor',
              price: 25000,
              qty: 1,
            ),
          ],
        },
      );

      final result = await GetTransactions(database)(AppContext.householdId);
      final byId = {for (final row in result) row.transaction.id: row};
      expect(byId.keys, containsAll(['batch-1', 'batch-2']));
      expect(byId['batch-1']!.items, hasLength(2));
      expect(byId['batch-1']!.items.first.itemName, 'Sayur');
      expect(byId['batch-2']!.items.single.itemName, 'BBM motor');
    },
  );

  test('pemasukan, pengeluaran, target, dan item nota tersimpan sebagai transaksi berbeda', () async {
    final database = createInMemoryDatabaseForTests();
    addTearDown(database.close);
    final saveTransaction = SaveTransaction(database);
    final recordedAt = DateTime(2026, 8, 19, 10, 30);

    await saveTransaction(
      TransactionEntity(
        id: 'income-1',
        householdId: AppContext.householdId,
        date: recordedAt,
        amount: 1000000,
        owner: 'Keluarga',
        categoryId: 'income-category',
        accountId: 'account-seabank',
        recordedAt: recordedAt,
      ),
    );
    await saveTransaction(
      TransactionEntity(
        id: 'expense-1',
        householdId: AppContext.householdId,
        date: recordedAt,
        amount: -12500,
        owner: 'Keluarga',
        categoryId: 'expense-category',
        accountId: 'account-seabank',
        recordedAt: recordedAt,
      ),
      items: [
        TransactionItemEntity(
          id: 'item-1',
          transactionId: 'expense-1',
          itemName: 'Beras',
          price: 10000,
          qty: 1,
        ),
        TransactionItemEntity(
          id: 'item-2',
          transactionId: 'expense-1',
          itemName: 'Sayur',
          price: 2500,
          qty: 1,
        ),
      ],
    );
    await saveTransaction(
      TransactionEntity(
        id: 'goal-1',
        householdId: AppContext.householdId,
        date: recordedAt,
        amount: -200000,
        owner: 'Keluarga',
        categoryId: null,
        source: 'goal_contribution',
        accountId: 'account-seabank',
        goalId: 'target-darurat',
        recordedAt: recordedAt,
      ),
    );

    final transactions = await GetTransactions(database)(
      AppContext.householdId,
    );
    final byId = {
      for (final entry in transactions) entry.transaction.id: entry,
    };

    expect(byId['income-1']!.transaction.amount, 1000000);
    expect(byId['income-1']!.transaction.accountId, 'account-seabank');
    expect(byId['expense-1']!.transaction.amount, -12500);
    expect(byId['expense-1']!.items, hasLength(2));
    expect(byId['expense-1']!.items.first.amount, 10000);
    expect(byId['goal-1']!.transaction.amount, -200000);
    expect(byId['goal-1']!.transaction.goalId, 'target-darurat');
    expect(byId['goal-1']!.transaction.source, 'goal_contribution');
    expect(byId['goal-1']!.transaction.categoryId, isNull);
  });
}
