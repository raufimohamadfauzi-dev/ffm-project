import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/entities/utility_meter_models.dart';

/// Repository untuk menyimpan dan mengelola Buku Saku Meteran & Token Listrik PLN.
///
/// Menyimpan secara lokal di SharedPreferences dengan format JSON agar instan,
/// handal, dan bebas resiko migrasi skema database SQLite.
class UtilityMeterRepository {
  UtilityMeterRepository();

  static const _keyPrefix = 'ffm_utility_meters_';
  SharedPreferences? _cachedPrefs;

  Future<SharedPreferences> _prefs() async =>
      _cachedPrefs ??= await SharedPreferences.getInstance();

  String _getKey(String householdId) => '$_keyPrefix$householdId';

  /// Mengambil semua daftar meteran yang tersimpan untuk sebuah household.
  Future<List<UtilityMeter>> getAllMeters(String householdId) async {
    final prefs = await _prefs();
    final raw = prefs.getString(_getKey(householdId));
    if (raw == null || raw.isEmpty) return [];

    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => UtilityMeter.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Mencari meteran berdasarkan nomor meteran atau ID pelanggan PLN (mengabaikan spasi/strip).
  Future<UtilityMeter?> findMeterByNumber(
    String householdId,
    String rawNumber,
  ) async {
    final clean = rawNumber.replaceAll(RegExp(r'\D'), '');
    if (clean.isEmpty) return null;
    final all = await getAllMeters(householdId);
    return all
        .where(
          (m) => m.meterNumber.replaceAll(RegExp(r'\D'), '') == clean,
        )
        .firstOrNull;
  }

  /// Menyimpan atau memperbarui meteran.
  Future<void> saveMeter(UtilityMeter meter) async {
    final list = await getAllMeters(meter.householdId);
    final idx = list.indexWhere((m) => m.id == meter.id);

    List<UtilityMeter> updated;
    if (idx >= 0) {
      updated = List.of(list);
      updated[idx] = meter;
    } else {
      updated = [meter, ...list];
    }

    final prefs = await _prefs();
    await prefs.setString(
      _getKey(meter.householdId),
      jsonEncode(updated.map((m) => m.toJson()).toList()),
    );
  }

  /// Menghapus meteran berdasarkan ID.
  Future<void> deleteMeter(String householdId, String meterId) async {
    final list = await getAllMeters(householdId);
    final updated = list.where((m) => m.id != meterId).toList();

    final prefs = await _prefs();
    await prefs.setString(
      _getKey(householdId),
      jsonEncode(updated.map((m) => m.toJson()).toList()),
    );
  }

  /// Memperbarui kode token 20-digit terakhir dan histori pembelian untuk nomor meteran terkait.
  Future<void> updateLastToken({
    required String householdId,
    required String meterNumber,
    required String tokenCode,
    double? amount,
    DateTime? timestamp,
  }) async {
    final list = await getAllMeters(householdId);
    final clean = meterNumber.replaceAll(RegExp(r'\D'), '');
    final idx = list.indexWhere(
      (m) => m.meterNumber.replaceAll(RegExp(r'\D'), '') == clean,
    );
    if (idx >= 0) {
      final target = list[idx];
      list[idx] = target.copyWith(
        lastTokenNumber: tokenCode,
        lastAmount: amount ?? target.lastAmount,
        lastPurchasedAt: timestamp ?? DateTime.now(),
      );
      final prefs = await _prefs();
      await prefs.setString(
        _getKey(householdId),
        jsonEncode(list.map((m) => m.toJson()).toList()),
      );
    }
  }
}
