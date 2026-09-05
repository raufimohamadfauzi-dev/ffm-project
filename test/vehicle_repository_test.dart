import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ffm_manager/features/settings/data/vehicle_repository.dart';
import 'package:ffm_manager/features/settings/domain/entities/vehicle_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Vehicle & FuelLogEntry Entity Tests', () {
    test('Vehicle formatting and calculations work correctly', () {
      final now = DateTime(2026, 9, 5);
      final log1 = FuelLogEntry(
        id: 'log1',
        date: DateTime(2026, 9, 1),
        liters: 4.0,
        totalAmount: 40000,
        odometerKm: 10000,
        fuelType: 'Pertalite',
      );
      final log2 = FuelLogEntry(
        id: 'log2',
        date: DateTime(2026, 9, 4),
        liters: 4.0,
        totalAmount: 40000,
        odometerKm: 10200, // 200 km / 4 L = 50 km/L
        fuelType: 'Pertalite',
      );

      final vehicle = Vehicle(
        id: 'v1',
        householdId: 'h1',
        name: 'Vario 160',
        plateNumber: 'b 1234 abc',
        brandModel: 'Honda Vario 160 CBS',
        vehicleType: 'motor',
        fuelType: 'Pertalite',
        tankCapacity: 5.5,
        lastOdometer: 10200,
        createdAt: now,
        fuelLogs: [log1, log2],
      );

      expect(vehicle.formattedPlateNumber, 'B 1234 ABC');
      expect(vehicle.totalLitersForMonth(now), 8.0);
      expect(vehicle.totalExpenseForMonth(now), 80000);
      expect(vehicle.averageKmPerLiter, 50.0);
      expect(log1.effectivePricePerLiter, 10000.0);

      // JSON round trip
      final json = vehicle.toJson();
      final fromJson = Vehicle.fromJson(json);
      expect(fromJson.name, vehicle.name);
      expect(fromJson.plateNumber, vehicle.plateNumber);
      expect(fromJson.fuelLogs.length, 2);
      expect(fromJson.fuelLogs.first.totalAmount, 40000);
    });
  });

  group('VehicleRepository CRUD & Matching Tests', () {
    test('Menyimpan, membaca, dan menghapus kendaraan', () async {
      final repo = VehicleRepository();
      const householdId = 'h1';

      final v1 = Vehicle(
        id: 'v1',
        householdId: householdId,
        name: 'Vario Ayah',
        plateNumber: 'B 1234 ABC',
        brandModel: 'Honda Vario',
        createdAt: DateTime.now(),
      );

      await repo.saveVehicle(v1);

      final all = await repo.getAllVehicles(householdId);
      expect(all.length, 1);
      expect(all.first.name, 'Vario Ayah');

      // Matching by plate
      final matchedByPlate = await repo.findVehicleByPlate(householdId, 'b-1234-abc');
      expect(matchedByPlate, isNotNull);
      expect(matchedByPlate!.id, 'v1');

      // Matching by keyword
      final matchedByKeyword = await repo.findVehicleByNameOrKeyword(householdId, 'vario');
      expect(matchedByKeyword, isNotNull);
      expect(matchedByKeyword!.id, 'v1');

      // Delete
      await repo.deleteVehicle(householdId, 'v1');
      final afterDelete = await repo.getAllVehicles(householdId);
      expect(afterDelete.isEmpty, isTrue);
    });

    test('addFuelLog memperbarui log BBM dan lastOdometer', () async {
      final repo = VehicleRepository();
      const householdId = 'h1';

      final v = Vehicle(
        id: 'v1',
        householdId: householdId,
        name: 'Avanza',
        plateNumber: 'D 5678 XY',
        createdAt: DateTime.now(),
      );
      await repo.saveVehicle(v);

      final log = FuelLogEntry(
        id: 'l1',
        date: DateTime.now(),
        liters: 30.0,
        totalAmount: 300000,
        odometerKm: 45000,
        fuelType: 'Pertalite',
      );
      await repo.addFuelLog(householdId: householdId, vehicleId: 'v1', fuelLog: log);

      final updated = await repo.getAllVehicles(householdId);
      expect(updated.first.fuelLogs.length, 1);
      expect(updated.first.lastOdometer, 45000);
    });
  });

  group('Safe Restore (Merge & Append) Tests - Jangan Dihapus tapi Ditambahkan', () {
    test('importRaw menggabungkan kendaraan baru dan riwayat BBM tanpa menghapus data HP', () async {
      final repo = VehicleRepository();
      const householdId = 'h_safe';

      // 1. Data yang sudah ada di HP baru
      final existingVehicle = Vehicle(
        id: 'existing_v1',
        householdId: householdId,
        name: 'Beat Harian HP Baru',
        plateNumber: 'B 9999 HP',
        brandModel: 'Honda Beat',
        createdAt: DateTime(2026, 1, 1),
        fuelLogs: [
          FuelLogEntry(
            id: 'existing_log_1',
            date: DateTime(2026, 1, 5),
            liters: 3.5,
            totalAmount: 35000,
          ),
        ],
      );
      await repo.saveVehicle(existingVehicle);

      // Pastikan ada 1 kendaraan di HP
      final initial = await repo.getAllVehicles(householdId);
      expect(initial.length, 1);
      expect(initial.first.name, 'Beat Harian HP Baru');

      // 2. Data dari Berkas Cadangan (Backup) yang akan dipulihkan:
      // - Berisi Beat (plat nomor sama 'B 9999 HP') dengan log BBM baru
      // - Berisi Truk Gabah (kendaraan baru yang belum ada di HP)
      final incomingBackup = [
        Vehicle(
          id: 'backup_v1',
          householdId: householdId,
          name: 'Beat Harian',
          plateNumber: 'b 9999 hp', // Plat sama persis
          brandModel: 'Honda Beat Deluxe',
          createdAt: DateTime(2025, 12, 1),
          fuelLogs: [
            FuelLogEntry(
              id: 'existing_log_1', // duplikat log lama
              date: DateTime(2026, 1, 5),
              liters: 3.5,
              totalAmount: 35000,
            ),
            FuelLogEntry(
              id: 'backup_log_2', // log baru dari backup
              date: DateTime(2026, 2, 10),
              liters: 4.0,
              totalAmount: 40000,
            ),
          ],
        ).toJson(),
        Vehicle(
          id: 'backup_v2',
          householdId: householdId,
          name: 'Truk Gabah',
          plateNumber: 'E 1122 GG',
          vehicleType: 'truk',
          fuelType: 'Solar',
          tankCapacity: 60.0,
          createdAt: DateTime(2026, 2, 1),
          fuelLogs: [
            FuelLogEntry(
              id: 'log_truk_1',
              date: DateTime(2026, 2, 15),
              liters: 50.0,
              totalAmount: 340000,
              fuelType: 'Solar',
            ),
          ],
        ).toJson(),
      ];

      // 3. Eksekusi importRaw (Safe Restore)
      await repo.importRaw(householdId, incomingBackup);

      // 4. Verifikasi hasil penggabungan (Merge & Append)
      final afterRestore = await repo.getAllVehicles(householdId);

      // Harus ada 2 kendaraan (Beat + Truk)
      expect(afterRestore.length, 2);

      // Data kendaraan lama 'Beat Harian HP Baru' TIDAK TERHAPUS!
      final beat = afterRestore.firstWhere((v) => v.plateNumber == 'B 9999 HP');
      expect(beat.name, 'Beat Harian HP Baru');
      // Riwayat log BBM digabungkan (log lama + log baru dari backup)
      expect(beat.fuelLogs.length, 2);
      expect(beat.fuelLogs.any((l) => l.id == 'existing_log_1'), isTrue);
      expect(beat.fuelLogs.any((l) => l.id == 'backup_log_2'), isTrue);

      // Kendaraan baru 'Truk Gabah' berhasil ditambahkan (append)
      final truk = afterRestore.firstWhere((v) => v.plateNumber == 'E 1122 GG');
      expect(truk.name, 'Truk Gabah');
      expect(truk.vehicleType, 'truk');
      expect(truk.fuelType, 'Solar');
      expect(truk.fuelLogs.length, 1);
    });
  });
}
