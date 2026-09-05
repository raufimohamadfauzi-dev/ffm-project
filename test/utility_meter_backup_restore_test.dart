import 'dart:convert';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/backup/data/json_backup_service.dart';
import 'package:ffm_manager/features/settings/data/utility_meter_repository.dart';
import 'package:ffm_manager/features/settings/domain/entities/utility_meter_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('UtilityMeter dan kode token 20-digit tersimpan dan dipulihkan tanpa teredaksi', () async {
    final db = createInMemoryDatabaseForTests();
    addTearDown(db.close);

    final backupService = JsonBackupService(db);

    final originalMeter = UtilityMeter(
      id: 'meter-test-1',
      householdId: 'h-1',
      name: 'Pompa Sawah Barat',
      meterNumber: '14123456789',
      customerName: 'H. Fauzi',
      tariffPower: 'R1/900VA',
      lastTokenNumber: '12345678901234567890',
      lastAmount: 100000,
      lastPurchasedAt: DateTime(2026, 9, 5, 14, 30),
      createdAt: DateTime(2026, 9, 5, 10, 0),
    );

    final rawMeters = <Map<String, Object?>>[originalMeter.toJson()];

    // Export to JSON
    final jsonString = await backupService.exportJson(
      utilityMeters: rawMeters,
    );

    expect(jsonString, contains('Pompa Sawah Barat'));
    expect(jsonString, contains('14123456789'));
    // Pastikan kode token 20-digit TIDAK diredaksi oleh filter keamanan
    expect(jsonString, contains('12345678901234567890'));

    final preview = backupService.previewJson(jsonString);
    expect(preview.counts['utility_meters'], 1);

    final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
    final modules = decoded['modules'] as Map<String, dynamic>;
    final exportedList = modules['utility_meters'] as List;
    expect(exportedList, hasLength(1));

    final restoredMeter = UtilityMeter.fromJson(exportedList.first as Map<String, dynamic>);
    expect(restoredMeter.id, 'meter-test-1');
    expect(restoredMeter.name, 'Pompa Sawah Barat');
    expect(restoredMeter.lastTokenNumber, '12345678901234567890');
    expect(restoredMeter.formattedTokenNumber, '1234-5678-9012-3456-7890');
    expect(restoredMeter.lastAmount, 100000);
  });

  test('importRaw menggabungkan (merge) data baru tanpa menghapus data yang sudah ada di HP', () async {
    final repo = UtilityMeterRepository();
    // Meteran yang sudah ada di HP baru
    await repo.saveMeter(
      UtilityMeter(
        id: 'meter-local-existing',
        householdId: 'h-1',
        name: 'Listrik Rumah HP Baru',
        meterNumber: '11112222333',
        createdAt: DateTime(2026, 9, 1),
      ),
    );

    // Data dari file backup yang diimpor
    final backupRows = [
      UtilityMeter(
        id: 'meter-from-backup',
        householdId: 'h-1',
        name: 'Listrik Sawah Cadangan',
        meterNumber: '44445555666',
        createdAt: DateTime(2026, 8, 15),
      ).toJson(),
    ];

    await repo.importRaw('h-1', backupRows);

    final all = await repo.getAllMeters('h-1');
    // Kedua data harus ada: yang sudah ada di HP TIDAK terhapus!
    expect(all, hasLength(2));
    expect(all.any((m) => m.id == 'meter-local-existing'), isTrue);
    expect(all.any((m) => m.id == 'meter-from-backup'), isTrue);
  });
}
