import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/entities/vehicle_models.dart';

/// Repository untuk menyimpan dan mengelola Buku Saku Kendaraan & Riwayat Log BBM.
///
/// Menyimpan secara lokal di SharedPreferences dengan format JSON agar instan,
/// handal, dan bebas resiko migrasi skema database SQLite.
class VehicleRepository {
  VehicleRepository();

  static const _keyPrefix = 'ffm_vehicles_';
  SharedPreferences? _cachedPrefs;

  Future<SharedPreferences> _prefs() async =>
      _cachedPrefs ??= await SharedPreferences.getInstance();

  String _getKey(String householdId) => '$_keyPrefix$householdId';

  /// Mengambil semua daftar kendaraan yang tersimpan untuk sebuah household.
  Future<List<Vehicle>> getAllVehicles(String householdId) async {
    final prefs = await _prefs();
    final raw = prefs.getString(_getKey(householdId));
    if (raw == null || raw.isEmpty) return [];

    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => Vehicle.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Normalisasi plat nomor (hilangkan spasi, tanda minus, titik, dan jadikan huruf kapital).
  static String normalizePlate(String rawPlate) {
    return rawPlate.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
  }

  /// Mencari kendaraan berdasarkan plat nomor / nomor polisi.
  Future<Vehicle?> findVehicleByPlate(
    String householdId,
    String rawPlate,
  ) async {
    final clean = normalizePlate(rawPlate);
    if (clean.isEmpty) return null;
    final all = await getAllVehicles(householdId);
    return all
        .where((v) => normalizePlate(v.plateNumber) == clean)
        .firstOrNull;
  }

  /// Mencari kendaraan berdasarkan kata kunci (nama, merek/model, atau plat nomor).
  Future<Vehicle?> findVehicleByNameOrKeyword(
    String householdId,
    String keyword,
  ) async {
    final q = keyword.trim().toLowerCase();
    if (q.isEmpty) return null;
    final cleanQ = normalizePlate(q);
    final all = await getAllVehicles(householdId);

    // 1. Cocokkan plat nomor persis
    if (cleanQ.isNotEmpty) {
      final byPlate = all
          .where((v) => normalizePlate(v.plateNumber) == cleanQ)
          .firstOrNull;
      if (byPlate != null) return byPlate;
    }

    // 2. Cocokkan nama kendaraan
    for (final v in all) {
      if (v.name.toLowerCase().contains(q)) return v;
    }

    // 3. Cocokkan merek / model
    for (final v in all) {
      if (v.brandModel.toLowerCase().contains(q)) return v;
    }

    return null;
  }

  /// Menyimpan atau memperbarui kendaraan.
  Future<void> saveVehicle(Vehicle vehicle) async {
    final list = await getAllVehicles(vehicle.householdId);
    final idx = list.indexWhere((v) => v.id == vehicle.id);

    List<Vehicle> updated;
    if (idx >= 0) {
      updated = List.of(list);
      updated[idx] = vehicle;
    } else {
      updated = [vehicle, ...list];
    }

    final prefs = await _prefs();
    await prefs.setString(
      _getKey(vehicle.householdId),
      jsonEncode(updated.map((v) => v.toJson()).toList()),
    );
  }

  /// Menghapus kendaraan berdasarkan ID.
  Future<void> deleteVehicle(String householdId, String vehicleId) async {
    final list = await getAllVehicles(householdId);
    final updated = list.where((v) => v.id != vehicleId).toList();

    final prefs = await _prefs();
    await prefs.setString(
      _getKey(householdId),
      jsonEncode(updated.map((v) => v.toJson()).toList()),
    );
  }

  /// Menambahkan riwayat pengisian BBM ke kendaraan terkait dan memperbarui odometer jika tersedia.
  Future<void> addFuelLog({
    required String householdId,
    required String vehicleId,
    required FuelLogEntry fuelLog,
  }) async {
    final list = await getAllVehicles(householdId);
    final idx = list.indexWhere((v) => v.id == vehicleId);
    if (idx < 0) return;

    final target = list[idx];
    final updatedLogs = [fuelLog, ...target.fuelLogs];

    // Perbarui lastOdometer jika log baru memiliki odometer lebih tinggi
    double? newOdo = target.lastOdometer;
    if (fuelLog.odometerKm != null) {
      if (newOdo == null || fuelLog.odometerKm! > newOdo) {
        newOdo = fuelLog.odometerKm;
      }
    }

    list[idx] = target.copyWith(
      fuelLogs: updatedLogs,
      lastOdometer: newOdo,
    );

    final prefs = await _prefs();
    await prefs.setString(
      _getKey(householdId),
      jsonEncode(list.map((v) => v.toJson()).toList()),
    );
  }

  /// Menghapus satu catatan log BBM tertentu dari kendaraan.
  Future<void> deleteFuelLog({
    required String householdId,
    required String vehicleId,
    required String fuelLogId,
  }) async {
    final list = await getAllVehicles(householdId);
    final idx = list.indexWhere((v) => v.id == vehicleId);
    if (idx < 0) return;

    final target = list[idx];
    final updatedLogs = target.fuelLogs.where((l) => l.id != fuelLogId).toList();

    list[idx] = target.copyWith(fuelLogs: updatedLogs);

    final prefs = await _prefs();
    await prefs.setString(
      _getKey(householdId),
      jsonEncode(list.map((v) => v.toJson()).toList()),
    );
  }

  /// Ekspor seluruh kendaraan dalam bentuk data map mentah untuk Full Backup.
  Future<List<Map<String, Object?>>> exportRaw(String householdId) async {
    final list = await getAllVehicles(householdId);
    return list.map((v) => v.toJson()).toList();
  }

  /// Impor dan pulihkan kendaraan dari Full Backup dengan sistem penggabungan (merge & append).
  /// Data yang sudah ada di HP baru tidak akan terhapus, melainkan disatukan.
  Future<void> importRaw(
    String householdId,
    List<Map<String, Object?>> rows,
  ) async {
    final incoming = rows.map((e) => Vehicle.fromJson(e)).toList();
    final existing = await getAllVehicles(householdId);

    final idMap = <String, int>{};
    final plateMap = <String, int>{};

    for (var i = 0; i < existing.length; i++) {
      final v = existing[i];
      idMap[v.id] = i;
      final cleanPlate = normalizePlate(v.plateNumber);
      if (cleanPlate.isNotEmpty) {
        plateMap[cleanPlate] = i;
      }
    }

    final merged = List<Vehicle>.from(existing);

    for (final inc in incoming) {
      final cleanPlate = normalizePlate(inc.plateNumber);
      int? existingIdx;
      if (idMap.containsKey(inc.id)) {
        existingIdx = idMap[inc.id];
      } else if (cleanPlate.isNotEmpty && plateMap.containsKey(cleanPlate)) {
        existingIdx = plateMap[cleanPlate];
      }

      if (existingIdx != null && existingIdx >= 0 && existingIdx < merged.length) {
        // Kendaraan sudah ada di perangkat: gabungkan riwayat log BBM tanpa menghapus data lokal
        final cur = merged[existingIdx];
        final existingLogIds = cur.fuelLogs.map((l) => l.id).toSet();
        final combinedLogs = List<FuelLogEntry>.from(cur.fuelLogs);

        for (final log in inc.fuelLogs) {
          if (!existingLogIds.contains(log.id)) {
            combinedLogs.add(log);
            existingLogIds.add(log.id);
          }
        }

        // Perbarui lastOdometer jika impor memiliki nilai lebih tinggi
        var mergedOdo = cur.lastOdometer;
        if (inc.lastOdometer != null) {
          if (mergedOdo == null || inc.lastOdometer! > mergedOdo) {
            mergedOdo = inc.lastOdometer;
          }
        }

        merged[existingIdx] = cur.copyWith(
          fuelLogs: combinedLogs,
          lastOdometer: mergedOdo,
          brandModel: cur.brandModel.isNotEmpty ? cur.brandModel : inc.brandModel,
          tankCapacity: cur.tankCapacity > 0 ? cur.tankCapacity : inc.tankCapacity,
        );
      } else {
        // Kendaraan baru: tambahkan (append) ke daftar
        merged.add(inc);
        idMap[inc.id] = merged.length - 1;
        if (cleanPlate.isNotEmpty) {
          plateMap[cleanPlate] = merged.length - 1;
        }
      }
    }

    final prefs = await _prefs();
    await prefs.setString(
      _getKey(householdId),
      jsonEncode(merged.map((v) => v.toJson()).toList()),
    );
  }
}
