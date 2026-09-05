import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/database/app_database.dart';
import '../../advisor/data/cash_flow_profile_repository.dart';
import '../../settings/data/utility_meter_repository.dart';
import '../../settings/data/vehicle_repository.dart';
import '../domain/entities/autonomous_activity_models.dart';

/// Repository untuk mencatat, membaca, dan membatalkan/mengoreksi aktivitas otonom Asisten FFM.
class AutonomousActivityRepository {
  AutonomousActivityRepository({
    this.database,
    this.vehicleRepository,
    this.meterRepository,
    this.cashFlowProfileRepository,
  });

  static const _keyPrefix = 'ffm_autonomous_activities_v1_';
  static const maxActivities = 50;

  final AppDatabase? database;
  final VehicleRepository? vehicleRepository;
  final UtilityMeterRepository? meterRepository;
  final CashFlowProfileRepository? cashFlowProfileRepository;
  SharedPreferences? _cachedPrefs;

  Future<SharedPreferences> _prefs() async =>
      _cachedPrefs ??= await SharedPreferences.getInstance();

  String _getKey(String householdId) => '$_keyPrefix$householdId';

  /// Mengambil daftar aktivitas otonom yang tercatat, diurutkan dari yang terbaru.
  Future<List<AutonomousActivityRecord>> getRecentActivities(
    String householdId,
  ) async {
    final prefs = await _prefs();
    final raw = prefs.getString(_getKey(householdId));
    if (raw == null || raw.isEmpty) return const [];

    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final activities = list
          .map((e) => AutonomousActivityRecord.fromJson(e as Map<String, dynamic>))
          .toList();
      activities.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
      return activities;
    } catch (_) {
      return const [];
    }
  }

  /// Mencatat tindakan otonom baru ke riwayat audit.
  Future<void> recordActivity(AutonomousActivityRecord record) async {
    final list = await getRecentActivities(record.householdId);
    final updated = [record, ...list];
    if (updated.length > maxActivities) {
      updated.removeRange(maxActivities, updated.length);
    }

    final prefs = await _prefs();
    await prefs.setString(
      _getKey(record.householdId),
      jsonEncode(updated.map((e) => e.toJson()).toList()),
    );
  }

  /// Membatalkan / me-revert tindakan otonom yang sebelumnya dijalankan.
  /// Mengembalikan data ke kondisi semula dan mengubah status menjadi [reverted].
  Future<bool> revertActivity({
    required String householdId,
    required String activityId,
  }) async {
    final list = await getRecentActivities(householdId);
    final idx = list.indexWhere((a) => a.id == activityId);
    if (idx < 0) return false;

    final target = list[idx];
    if (target.status == AutonomousActivityStatus.reverted) return false;

    // Eksekusi pembalikan state sesuai jenis aktivitas otonom
    try {
      switch (target.activityType) {
        case AutonomousActivityType.envelopeRebalance:
          final transferId = target.payload['transferId']?.toString();
          if (transferId != null && database != null) {
            await (database!.delete(database!.envelopeTransfers)
                  ..where((row) => row.id.equals(transferId)))
                .go();
          }
          break;

        case AutonomousActivityType.fuelLog:
          final vehicleId = target.payload['vehicleId']?.toString();
          final logId = target.payload['logId']?.toString();
          if (vehicleId != null && logId != null && vehicleRepository != null) {
            await vehicleRepository!.deleteFuelLog(
              householdId: householdId,
              vehicleId: vehicleId,
              fuelLogId: logId,
            );
          }
          break;

        case AutonomousActivityType.harvestShift:
          final profileId = target.payload['profileId']?.toString();
          final previousDateStr = target.payload['previousHarvestDate']?.toString();
          if (profileId != null && previousDateStr != null && cashFlowProfileRepository != null) {
            final profiles = await cashFlowProfileRepository!.getAllProfiles(householdId);
            final pIdx = profiles.indexWhere((p) => p.id == profileId);
            if (pIdx >= 0) {
              final previousDate = DateTime.parse(previousDateStr);
              final restoredProfile = profiles[pIdx].copyWith(targetHarvestDate: previousDate);
              await cashFlowProfileRepository!.saveProfile(restoredProfile);
            }
          }
          break;

        case AutonomousActivityType.utilityMeter:
          final meterId = target.payload['meterId']?.toString();
          final isNewMeter = target.payload['isNewMeter'] == true;
          if (meterId != null && meterRepository != null) {
            if (isNewMeter) {
              await meterRepository!.deleteMeter(householdId, meterId);
            }
          }
          break;

        case AutonomousActivityType.habitDeclaration:
          // Kebiasaan di memori dapat dinonaktifkan
          break;
      }
    } catch (_) {
      return false;
    }

    // Tandai status aktivitas sebagai reverted
    list[idx] = target.copyWith(status: AutonomousActivityStatus.reverted);

    final prefs = await _prefs();
    await prefs.setString(
      _getKey(householdId),
      jsonEncode(list.map((e) => e.toJson()).toList()),
    );
    return true;
  }

  /// Mengoreksi data teks atau payload dari aktivitas otonom yang tercatat.
  Future<bool> correctActivity({
    required String householdId,
    required String activityId,
    String? newTitle,
    String? newDescription,
    Map<String, dynamic>? updatedPayload,
  }) async {
    final list = await getRecentActivities(householdId);
    final idx = list.indexWhere((a) => a.id == activityId);
    if (idx < 0) return false;

    final target = list[idx];
    final mergedPayload = Map<String, dynamic>.of(target.payload);
    if (updatedPayload != null) {
      mergedPayload.addAll(updatedPayload);
    }

    // Sinkronisasi pembaruan ke sumber data asli (Database / Repository)
    try {
      switch (target.activityType) {
        case AutonomousActivityType.envelopeRebalance:
          final transferId = mergedPayload['transferId']?.toString();
          final newAmount = (mergedPayload['amount'] as num?)?.toInt();
          if (transferId != null && newAmount != null && database != null) {
            await (database!.update(database!.envelopeTransfers)
                  ..where((t) => t.id.equals(transferId)))
                .write(EnvelopeTransfersCompanion(amount: Value(newAmount)));
          }
          break;

        case AutonomousActivityType.fuelLog:
          final vehicleId = mergedPayload['vehicleId']?.toString();
          final fuelLogId = mergedPayload['fuelLogId']?.toString();
          if (vehicleId != null && fuelLogId != null && vehicleRepository != null) {
            final vehicles = await vehicleRepository!.getAllVehicles(householdId);
            final vIdx = vehicles.indexWhere((v) => v.id == vehicleId);
            if (vIdx >= 0) {
              final v = vehicles[vIdx];
              final newLiters = (mergedPayload['liters'] as num?)?.toDouble();
              final newCost = (mergedPayload['cost'] as num?)?.toInt();
              final newOdo = (mergedPayload['odometer'] as num?)?.toDouble();
              final updatedLogs = v.fuelLogs.map((l) {
                if (l.id == fuelLogId) {
                  return l.copyWith(
                    liters: newLiters ?? l.liters,
                    totalAmount: newCost != null ? newCost.toDouble() : l.totalAmount,
                    odometerKm: newOdo ?? l.odometerKm,
                  );
                }
                return l;
              }).toList();
              await vehicleRepository!.saveVehicle(v.copyWith(fuelLogs: updatedLogs));
            }
          }
          break;

        case AutonomousActivityType.utilityMeter:
          final meterId = mergedPayload['meterId']?.toString();
          if (meterId != null && meterRepository != null) {
            final meterNumber = mergedPayload['meterNumber']?.toString();
            final alias = mergedPayload['alias']?.toString();
            final tariffPower = mergedPayload['tariffPower']?.toString();
            final meters = await meterRepository!.getAllMeters(householdId);
            final mIdx = meters.indexWhere((m) => m.id == meterId);
            if (mIdx >= 0) {
              final m = meters[mIdx];
              await meterRepository!.saveMeter(m.copyWith(
                meterNumber: meterNumber ?? m.meterNumber,
                name: alias ?? m.name,
                tariffPower: tariffPower ?? m.tariffPower,
              ));
            }
          }
          break;

        case AutonomousActivityType.harvestShift:
          final newDateStr = mergedPayload['newHarvestDate']?.toString();
          if (newDateStr != null && cashFlowProfileRepository != null) {
            final newDate = DateTime.tryParse(newDateStr);
            if (newDate != null) {
              final profile = await cashFlowProfileRepository!.getActiveProfile(householdId);
              if (profile != null) {
                await cashFlowProfileRepository!.saveProfile(
                  profile.copyWith(targetHarvestDate: newDate),
                );
              }
            }
          }
          break;

        case AutonomousActivityType.habitDeclaration:
          break;
      }
    } catch (_) {}

    list[idx] = target.copyWith(
      title: newTitle ?? target.title,
      description: newDescription ?? target.description,
      payload: mergedPayload,
      status: AutonomousActivityStatus.corrected,
    );

    final prefs = await _prefs();
    await prefs.setString(
      _getKey(householdId),
      jsonEncode(list.map((e) => e.toJson()).toList()),
    );
    return true;
  }
}
