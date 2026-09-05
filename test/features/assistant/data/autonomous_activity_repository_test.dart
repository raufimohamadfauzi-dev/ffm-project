import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/native.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/advisor/data/cash_flow_profile_repository.dart';
import 'package:ffm_manager/features/advisor/domain/entities/cash_flow_profile_models.dart';
import 'package:ffm_manager/features/assistant/data/autonomous_activity_repository.dart';
import 'package:ffm_manager/features/assistant/domain/entities/autonomous_activity_models.dart';
import 'package:ffm_manager/features/settings/data/vehicle_repository.dart';
import 'package:ffm_manager/features/settings/domain/entities/vehicle_models.dart';

void main() {
  group('AutonomousActivityRepository Tests', () {
    late AppDatabase database;
    late VehicleRepository vehicleRepository;
    late CashFlowProfileRepository cashFlowRepository;
    late AutonomousActivityRepository repository;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      database = AppDatabase(NativeDatabase.memory());
      vehicleRepository = VehicleRepository();
      cashFlowRepository = CashFlowProfileRepository();
      repository = AutonomousActivityRepository(
        database: database,
        vehicleRepository: vehicleRepository,
        cashFlowProfileRepository: cashFlowRepository,
      );
    });

    tearDown(() async {
      await database.close();
    });

    test('recordActivity and getRecentActivities work correctly', () async {
      final record = AutonomousActivityRecord(
        id: 'act_1',
        householdId: 'house_1',
        title: 'Pencatatan BBM',
        description: '3.5L Pertalite Rp 35.000',
        activityType: AutonomousActivityType.fuelLog,
        occurredAt: DateTime(2026, 9, 5, 10, 0),
      );

      await repository.recordActivity(record);
      final list = await repository.getRecentActivities('house_1');

      expect(list.length, equals(1));
      expect(list.first.id, equals('act_1'));
      expect(list.first.title, equals('Pencatatan BBM'));
      expect(list.first.status, equals(AutonomousActivityStatus.active));
    });

    test('correctActivity updates title, description and sets status to corrected', () async {
      final record = AutonomousActivityRecord(
        id: 'act_2',
        householdId: 'house_1',
        title: 'Pendaftaran Meteran',
        description: 'Meteran PLN 123456',
        activityType: AutonomousActivityType.utilityMeter,
        occurredAt: DateTime(2026, 9, 5, 11, 0),
      );

      await repository.recordActivity(record);

      final ok = await repository.correctActivity(
        householdId: 'house_1',
        activityId: 'act_2',
        newTitle: 'Meteran Ruko Utama',
        newDescription: 'Meteran PLN Ruko 123456',
      );

      expect(ok, isTrue);
      final list = await repository.getRecentActivities('house_1');
      expect(list.first.title, equals('Meteran Ruko Utama'));
      expect(list.first.description, equals('Meteran PLN Ruko 123456'));
      expect(list.first.status, equals(AutonomousActivityStatus.corrected));
    });

    test('revertActivity reverts fuelLog by deleting the log entry from VehicleRepository', () async {
      final vehicle = Vehicle(
        id: 'veh_1',
        householdId: 'house_1',
        name: 'Vario 160',
        plateNumber: 'B 1234 ABC',
        vehicleType: 'motor',
        createdAt: DateTime.now(),
      );
      await vehicleRepository.saveVehicle(vehicle);

      final fuelLog = FuelLogEntry(
        id: 'fuel_log_1',
        date: DateTime.now(),
        liters: 4.0,
        totalAmount: 40000,
        fuelType: 'Pertalite',
      );
      await vehicleRepository.addFuelLog(
        householdId: 'house_1',
        vehicleId: 'veh_1',
        fuelLog: fuelLog,
      );

      // Verify log exists
      var loadedVeh = (await vehicleRepository.getAllVehicles('house_1')).first;
      expect(loadedVeh.fuelLogs.length, equals(1));

      // Record activity
      final record = AutonomousActivityRecord(
        id: 'act_fuel_1',
        householdId: 'house_1',
        title: 'Pencatatan BBM Vario',
        description: '4L Pertalite',
        activityType: AutonomousActivityType.fuelLog,
        occurredAt: DateTime.now(),
        payload: {
          'vehicleId': 'veh_1',
          'logId': 'fuel_log_1',
        },
      );
      await repository.recordActivity(record);

      // Revert activity
      final reverted = await repository.revertActivity(
        householdId: 'house_1',
        activityId: 'act_fuel_1',
      );
      expect(reverted, isTrue);

      // Verify fuel log is deleted from vehicle
      loadedVeh = (await vehicleRepository.getAllVehicles('house_1')).first;
      expect(loadedVeh.fuelLogs, isEmpty);

      // Verify activity status is reverted
      final activities = await repository.getRecentActivities('house_1');
      expect(activities.first.status, equals(AutonomousActivityStatus.reverted));
    });

    test('revertActivity restores previous harvest date for harvestShift activity', () async {
      final initialDate = DateTime(2026, 10, 1);
      final shiftedDate = DateTime(2026, 10, 15);

      final profile = CashFlowProfile(
        id: 'prof_1',
        householdId: 'house_1',
        profileType: CashFlowProfileType.agriculture,
        name: 'Kebun Jagung',
        commodityOrBusinessType: 'Jagung',
        startDate: DateTime(2026, 8, 1),
        targetHarvestDate: shiftedDate,
        initialCapital: 5000000,
        estimatedInflow: 15000000,
        dailyLivingBudget: 50000,
      );
      await cashFlowRepository.saveProfile(profile);

      final record = AutonomousActivityRecord(
        id: 'act_harvest_1',
        householdId: 'house_1',
        title: 'Pembaruan Jadwal Panen',
        description: 'Panen mundur 14 hari',
        activityType: AutonomousActivityType.harvestShift,
        occurredAt: DateTime.now(),
        payload: {
          'profileId': 'prof_1',
          'previousHarvestDate': initialDate.toIso8601String(),
          'newHarvestDate': shiftedDate.toIso8601String(),
        },
      );
      await repository.recordActivity(record);

      final reverted = await repository.revertActivity(
        householdId: 'house_1',
        activityId: 'act_harvest_1',
      );
      expect(reverted, isTrue);

      // Check restored harvest date
      final restoredProfile = (await cashFlowRepository.getAllProfiles('house_1')).first;
      expect(restoredProfile.targetHarvestDate, equals(initialDate));
    });

    test('correctActivity synchronizes fuel log liters and totalAmount in VehicleRepository', () async {
      final vehicle = Vehicle(
        id: 'veh_corr',
        householdId: 'house_1',
        name: 'Vario 160',
        plateNumber: 'B 9999 XYZ',
        vehicleType: 'motor',
        createdAt: DateTime.now(),
      );
      await vehicleRepository.saveVehicle(vehicle);

      final fuelLog = FuelLogEntry(
        id: 'fuel_log_corr',
        date: DateTime.now(),
        liters: 3.0,
        totalAmount: 30000,
        fuelType: 'Pertalite',
      );
      await vehicleRepository.addFuelLog(
        householdId: 'house_1',
        vehicleId: 'veh_corr',
        fuelLog: fuelLog,
      );

      final record = AutonomousActivityRecord(
        id: 'act_fuel_corr',
        householdId: 'house_1',
        title: 'Pencatatan BBM',
        description: '3.0L BBM Rp 30.000',
        activityType: AutonomousActivityType.fuelLog,
        occurredAt: DateTime.now(),
        payload: {
          'vehicleId': 'veh_corr',
          'fuelLogId': 'fuel_log_corr',
          'liters': 3.0,
          'cost': 30000,
        },
      );
      await repository.recordActivity(record);

      final ok = await repository.correctActivity(
        householdId: 'house_1',
        activityId: 'act_fuel_corr',
        newTitle: 'Pencatatan BBM (Revisi)',
        newDescription: '4.5L BBM Rp 45.000',
        updatedPayload: {
          'liters': 4.5,
          'cost': 45000,
        },
      );
      expect(ok, isTrue);

      final updatedVeh = (await vehicleRepository.getAllVehicles('house_1')).firstWhere((v) => v.id == 'veh_corr');
      final updatedLog = updatedVeh.fuelLogs.firstWhere((l) => l.id == 'fuel_log_corr');
      expect(updatedLog.liters, equals(4.5));
      expect(updatedLog.totalAmount, equals(45000.0));
    });
  });
}
