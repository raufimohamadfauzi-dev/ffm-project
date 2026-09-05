import 'dart:convert';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/backup/data/json_backup_service.dart';
import 'package:ffm_manager/features/settings/data/vehicle_repository.dart';
import 'package:ffm_manager/features/settings/domain/entities/vehicle_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('Kendaraan dan riwayat log BBM diekspor dan dipulihkan dengan aman via JsonBackupService', () async {
    final db = createInMemoryDatabaseForTests();
    addTearDown(db.close);

    final backupService = JsonBackupService(db);

    final vehicle = Vehicle(
      id: 'v-test-1',
      householdId: 'h-1',
      name: 'Vario 160 Touring',
      plateNumber: 'B 1234 ABC',
      brandModel: 'Honda Vario 160',
      vehicleType: 'motor',
      fuelType: 'Pertamax',
      tankCapacity: 5.5,
      lastOdometer: 15400,
      createdAt: DateTime(2026, 9, 1),
      fuelLogs: [
        FuelLogEntry(
          id: 'log-1',
          date: DateTime(2026, 9, 3, 8, 30),
          liters: 4.5,
          totalAmount: 58500,
          odometerKm: 15400,
          fuelType: 'Pertamax',
          spbuLocation: 'SPBU Pertamina Pasteur',
        ),
      ],
    );

    final rawVehicles = <Map<String, Object?>>[vehicle.toJson()];

    // 1. Ekspor ke JSON
    final jsonString = await backupService.exportJson(
      vehicles: rawVehicles,
    );

    expect(jsonString, contains('Vario 160 Touring'));
    expect(jsonString, contains('B 1234 ABC'));
    expect(jsonString, contains('SPBU Pertamina Pasteur'));

    // 2. Pratinjau hitungan modul
    final preview = backupService.previewJson(jsonString);
    expect(preview.counts['vehicles'], 1);

    // 3. Verifikasi struktur data di dalam JSON
    final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
    final modules = decoded['modules'] as Map<String, dynamic>;
    final exportedList = modules['vehicles'] as List;
    expect(exportedList, hasLength(1));

    final restoredVehicle = Vehicle.fromJson(exportedList.first as Map<String, dynamic>);
    expect(restoredVehicle.id, 'v-test-1');
    expect(restoredVehicle.name, 'Vario 160 Touring');
    expect(restoredVehicle.fuelLogs.length, 1);
    expect(restoredVehicle.fuelLogs.first.liters, 4.5);
    expect(restoredVehicle.fuelLogs.first.spbuLocation, 'SPBU Pertamina Pasteur');
  });

  test('Pemulihan cadangan menggabungkan kendaraan ke HP yang sudah punya data tanpa menghapus data yang ada', () async {
    final repo = VehicleRepository();
    const householdId = 'h-1';

    // Kendaraan yang sudah ada di HP baru
    await repo.saveVehicle(
      Vehicle(
        id: 'v-local-1',
        householdId: householdId,
        name: 'Scoopy Istri',
        plateNumber: 'B 5555 XYZ',
        createdAt: DateTime(2026, 9, 1),
      ),
    );

    // Kendaraan dari backup yang diimpor
    final backupVehicles = [
      Vehicle(
        id: 'v-backup-1',
        householdId: householdId,
        name: 'Vario Suami',
        plateNumber: 'D 1111 AAA',
        createdAt: DateTime(2026, 8, 1),
      ).toJson(),
    ];

    await repo.importRaw(householdId, backupVehicles);

    final all = await repo.getAllVehicles(householdId);
    // Kedua kendaraan harus ada (data HP baru tidak terhapus)
    expect(all, hasLength(2));
    expect(all.any((v) => v.plateNumber == 'B 5555 XYZ'), isTrue);
    expect(all.any((v) => v.plateNumber == 'D 1111 AAA'), isTrue);
  });
}
