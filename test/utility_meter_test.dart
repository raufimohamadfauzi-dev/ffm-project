import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ffm_manager/features/settings/data/utility_meter_repository.dart';
import 'package:ffm_manager/features/settings/domain/entities/utility_meter_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('UtilityMeterRepository & UtilityMeter Tests', () {
    const householdId = 'hh_test_1';

    test('Menyimpan meteran baru dan memformat nomor meteran & token', () async {
      final repo = UtilityMeterRepository();

      final meter = UtilityMeter(
        id: 'meter_1',
        householdId: householdId,
        name: 'Pompa Air Sawah (Ladang)',
        meterNumber: '14238765432',
        customerName: 'H. Ahmad',
        tariffPower: 'B1/2200VA',
        location: 'Sawah Blok 4',
        createdAt: DateTime(2026, 9, 1),
        lastTokenNumber: '12345678901234567890',
        lastAmount: 100000,
      );

      await repo.saveMeter(meter);

      final meters = await repo.getAllMeters(householdId);
      expect(meters, hasLength(1));
      expect(meters.first.name, 'Pompa Air Sawah (Ladang)');
      expect(meters.first.formattedMeterNumber, '1423 8765 432');
      expect(
        meters.first.formattedTokenNumber,
        '1234-5678-9012-3456-7890',
      );
      expect(meters.first.lastAmount, 100000);
    });

    test('Mencari meteran berdasarkan nomor meteran (toleran terhadap spasi / strip)', () async {
      final repo = UtilityMeterRepository();

      await repo.saveMeter(
        UtilityMeter(
          id: 'm_rumah',
          householdId: householdId,
          name: 'Rumah Utama',
          meterNumber: '32019876543',
          createdAt: DateTime(2026, 9, 1),
        ),
      );

      // Cari dengan format berbeda
      final found = await repo.findMeterByNumber(householdId, '3201-9876-543');
      expect(found, isNotNull);
      expect(found!.id, 'm_rumah');
      expect(found.name, 'Rumah Utama');

      final foundSpaces = await repo.findMeterByNumber(householdId, '3201 9876 543');
      expect(foundSpaces, isNotNull);
      expect(foundSpaces!.id, 'm_rumah');
    });

    test('Memperbarui kode token terakhir secara instan', () async {
      final repo = UtilityMeterRepository();

      await repo.saveMeter(
        UtilityMeter(
          id: 'm_ruko',
          householdId: householdId,
          name: 'Ruko Toko',
          meterNumber: '55667788990',
          createdAt: DateTime(2026, 9, 1),
        ),
      );

      await repo.updateLastToken(
        householdId: householdId,
        meterNumber: '55667788990',
        tokenCode: '99887766554433221100',
        amount: 50000,
      );

      final updated = await repo.findMeterByNumber(householdId, '55667788990');
      expect(updated, isNotNull);
      expect(updated!.lastTokenNumber, '99887766554433221100');
      expect(
        updated.formattedTokenNumber,
        '9988-7766-5544-3322-1100',
      );
      expect(updated.lastAmount, 50000);
    });

    test('Menghapus meteran', () async {
      final repo = UtilityMeterRepository();

      await repo.saveMeter(
        UtilityMeter(
          id: 'm_hapus',
          householdId: householdId,
          name: 'Meter Sementara',
          meterNumber: '11223344556',
          createdAt: DateTime(2026, 9, 1),
        ),
      );

      var list = await repo.getAllMeters(householdId);
      expect(list, hasLength(1));

      await repo.deleteMeter(householdId, 'm_hapus');

      list = await repo.getAllMeters(householdId);
      expect(list, isEmpty);
    });
  });
}
