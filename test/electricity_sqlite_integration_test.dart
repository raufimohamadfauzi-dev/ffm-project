import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_financial_snapshot_service.dart';
import 'package:ffm_manager/features/settings/data/utility_meter_repository.dart';
import 'package:ffm_manager/features/settings/domain/entities/utility_meter_models.dart';
import 'package:ffm_manager/features/transaction/domain/usecases/transaction_crud_usecases.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('transaksi PLN dan riwayat token tersimpan 1:1 di SQLite', () async {
    final database = createInMemoryDatabaseForTests();
    addTearDown(database.close);
    final repository = UtilityMeterRepository(database);
    final at = DateTime(2026, 9, 17, 17, 22);
    const transactionId = 'tx-pln-1';

    await database.transaction(() async {
      await SaveTransaction(database)(
        TransactionEntity(
          id: transactionId,
          householdId: 'household-a',
          categoryId: 'cat-pln',
          date: at,
          amount: -100660,
          owner: 'Keluarga',
          source: 'assistant_receipt',
          recordedAt: at,
        ),
      );
      await repository.recordLinkedPurchase(
        householdId: 'household-a',
        transactionId: transactionId,
        proposal: {
          'meterNumber': '14123456789',
          'proposedMeterName': 'Rumah Utama',
          'tokenCode': '12345678901234567890',
          'amount': 100660,
          'adminFee': 1000,
          'creditedKwh': 63.7,
          'timestamp': at.toIso8601String(),
        },
      );
    });

    final transactions = await database.select(database.transactions).get();
    final purchases = await repository.getPurchaseHistory('household-a');
    final meters = await repository.getAllMeters('household-a');

    expect(transactions, hasLength(1));
    expect(transactions.single.id, transactionId);
    expect(transactions.single.amount, -100660);
    expect(purchases, hasLength(1));
    expect(purchases.single.transactionId, transactionId);
    expect(purchases.single.meterId, meters.single.id);
    expect(purchases.single.amount, 100660);
    expect(purchases.single.adminFee, 1000);
    expect(purchases.single.creditedKwh, 63.7);
    expect(meters.single.name, 'Rumah Utama');
    expect(meters.single.lastTokenNumber, '12345678901234567890');

    final cloudDigest = await FfmAssistantFinancialSnapshotService(database)
        .buildElectricityDigest(householdId: 'household-a');
    expect(cloudDigest, contains('total_cost=100660'));
    expect(cloudDigest, contains('total_credited_kwh=63.70'));
    expect(cloudDigest, isNot(contains('12345678901234567890')));
    expect(cloudDigest, isNot(contains('14123456789')));

    await repository.recordLinkedPurchase(
      householdId: 'household-a',
      transactionId: transactionId,
      proposal: {
        'meterNumber': '14123456789',
        'tokenCode': '12345678901234567890',
        'amount': 100660,
        'adminFee': 1000,
        'creditedKwh': 63.7,
      },
    );
    expect(await repository.getPurchaseHistory('household-a'), hasLength(1));
  });

  test('draft kWh invalid membatalkan transaksi dan riwayat bersama', () async {
    final database = createInMemoryDatabaseForTests();
    addTearDown(database.close);
    final repository = UtilityMeterRepository(database);
    final at = DateTime(2026, 9, 17);

    await expectLater(
      database.transaction(() async {
        await SaveTransaction(database)(
          TransactionEntity(
            id: 'tx-invalid-pln',
            householdId: 'household-a',
            categoryId: 'cat-pln',
            date: at,
            amount: -50000,
            owner: 'Keluarga',
            source: 'assistant_receipt',
            recordedAt: at,
          ),
        );
        await repository.recordLinkedPurchase(
          householdId: 'household-a',
          transactionId: 'tx-invalid-pln',
          proposal: {
            'meterNumber': '14123456789',
            'amount': 50000,
            'creditedKwh': -12,
          },
        );
      }),
      throwsStateError,
    );

    expect(await database.select(database.transactions).get(), isEmpty);
    expect(await repository.getPurchaseHistory('household-a'), isEmpty);
  });

  test('merangkum pembelian listrik per bulan untuk satu IDPEL', () async {
    final database = createInMemoryDatabaseForTests();
    addTearDown(database.close);
    final repository = UtilityMeterRepository(database);

    for (final purchase in [
      ('tx-sep-1', '12345678901234567890', DateTime(2026, 9, 3), 50000, 30.0),
      ('tx-sep-2', '22345678901234567890', DateTime(2026, 9, 17), 100000, 60.0),
      ('tx-aug-1', '32345678901234567890', DateTime(2026, 8, 12), 75000, 45.0),
    ]) {
      await repository.recordLinkedPurchase(
        householdId: 'household-a',
        transactionId: purchase.$1,
        proposal: {
          'meterNumber': '14123456789',
          'tokenCode': purchase.$2,
          'amount': purchase.$4,
          'creditedKwh': purchase.$5,
          'timestamp': purchase.$3.toIso8601String(),
        },
      );
    }

    final usage = await repository.summarizeUsageByPeriod(
      'household-a',
      meterId: (await repository.getAllMeters('household-a')).single.id,
      period: 'monthly',
      limit: 6,
    );
    expect(usage, hasLength(2));
    expect(usage[0].label, 'Sep 2026');
    expect(usage[0].totalCost, 150000);
    expect(usage[0].totalKwh, 90);
    expect(usage[0].purchaseCount, 2);
    expect(usage[1].label, 'Agu 2026');
    expect(usage[1].totalCost, 75000);
    expect(usage[1].totalKwh, 45);
    expect(usage[1].purchaseCount, 1);
  });

  test('meter yang diarsipkan bisa dibuat ulang dengan nomor sama, tapi aktif tidak boleh duplikat', () async {
    final database = createInMemoryDatabaseForTests();
    addTearDown(database.close);
    final repository = UtilityMeterRepository(database);
    const meterNumber = '14123456789';

    final first = UtilityMeter(
      id: 'meter-a',
      householdId: 'household-a',
      name: 'Rumah Utama',
      meterNumber: meterNumber,
      createdAt: DateTime(2026, 9, 17),
    );
    await repository.saveMeter(first);
    await repository.archiveMeter('household-a', 'meter-a');

    final archivedSameNumber = first.copyWith(id: 'meter-b', name: 'Rumah Baru');
    await repository.saveMeter(archivedSameNumber);
    expect((await repository.getAllMeters('household-a')).length, 1);

    await expectLater(
      repository.saveMeter(archivedSameNumber.copyWith(id: 'meter-c')),
      throwsException,
    );
  });

  test('menyimpan pembacaan meter dan menghitung pemakaian aktual', () async {
    final database = createInMemoryDatabaseForTests();
    addTearDown(database.close);
    final repository = UtilityMeterRepository(database);
    final meter = UtilityMeter(
      id: 'meter-reading',
      householdId: 'household-a',
      name: 'Rumah Utama',
      meterNumber: '14123456789',
      createdAt: DateTime(2026, 9, 1),
    );
    await repository.saveMeter(meter);
    final from = DateTime(2026, 9, 1);
    final to = DateTime(2026, 10, 1);

    await repository.recordMeterReading(
      householdId: 'household-a',
      meterId: meter.id,
      readingKwh: 10112,
      recordedAt: from,
    );
    await repository.recordMeterReading(
      householdId: 'household-a',
      meterId: meter.id,
      readingKwh: 10237.5,
      recordedAt: to,
      source: 'photo',
      note: 'Foto display meter',
    );

    expect(
      await repository.calculateActualUsage(
        'household-a',
        meterId: meter.id,
        from: from,
        to: to,
      ),
      125.5,
    );
    final latest = await repository.getLatestReading('household-a', meter.id);
    expect(latest?.readingKwh, 10237.5);
    expect(latest?.source, 'photo');
    expect(
      (await repository.getMeterReadings('household-a', meterId: meter.id)),
      hasLength(2),
    );
  });

  test('menolak pembacaan lebih rendah dan meter yang tidak dikenal', () async {
    final database = createInMemoryDatabaseForTests();
    addTearDown(database.close);
    final repository = UtilityMeterRepository(database);
    final meter = UtilityMeter(
      id: 'meter-validation',
      householdId: 'household-a',
      name: 'Rumah Utama',
      meterNumber: '14123456789',
      createdAt: DateTime(2026, 9, 1),
    );
    await repository.saveMeter(meter);
    await repository.recordMeterReading(
      householdId: 'household-a',
      meterId: meter.id,
      readingKwh: 100,
      recordedAt: DateTime(2026, 9, 1),
    );

    await expectLater(
      repository.recordMeterReading(
        householdId: 'household-a',
        meterId: meter.id,
        readingKwh: 99,
        recordedAt: DateTime(2026, 9, 2),
      ),
      throwsStateError,
    );
    await expectLater(
      repository.recordMeterReading(
        householdId: 'household-a',
        meterId: 'missing-meter',
        readingKwh: 100,
      ),
      throwsStateError,
    );
  });

  test('agregasi periode dapat menyertakan pemakaian kWh aktual', () async {
    final database = createInMemoryDatabaseForTests();
    addTearDown(database.close);
    final repository = UtilityMeterRepository(database);
    final meterNumber = '14123456789';
    final before = DateTime(2026, 8, 31);
    final after = DateTime(2026, 10, 1);
    await repository.recordLinkedPurchase(
      householdId: 'household-a',
      transactionId: 'tx-actual-period',
      proposal: {
        'meterNumber': meterNumber,
        'tokenCode': '42345678901234567890',
        'amount': 150000,
        'creditedKwh': 90.0,
        'timestamp': DateTime(2026, 9, 17).toIso8601String(),
      },
    );
    final meter = (await repository.getAllMeters('household-a')).single;
    await repository.recordMeterReading(
      householdId: 'household-a',
      meterId: meter.id,
      readingKwh: 2000,
      recordedAt: before,
    );
    await repository.recordMeterReading(
      householdId: 'household-a',
      meterId: meter.id,
      readingKwh: 2125.5,
      recordedAt: after,
    );

    final usage = await repository.summarizeUsageByPeriod(
      'household-a',
      meterId: meter.id,
      period: 'monthly',
      includeReadings: true,
    );

    expect(usage, hasLength(1));
    expect(usage.single.totalKwh, 90);
    expect(usage.single.actualKwh, 125.5);
  });
}
