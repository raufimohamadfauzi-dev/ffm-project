import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/entities/cash_flow_profile_models.dart';

/// Repository untuk menyimpan dan mengelola profil arus kas adaptif (Pertanian, Bisnis, Freelance).
///
/// Menyimpan secara lokal di SharedPreferences dengan format JSON agar ringan,
/// mandiri, dan bebas resiko schema migration.
class CashFlowProfileRepository {
  CashFlowProfileRepository();

  static const _keyPrefix = 'ffm_cash_flow_profiles_';
  SharedPreferences? _cachedPrefs;

  Future<SharedPreferences> _prefs() async =>
      _cachedPrefs ??= await SharedPreferences.getInstance();

  String _getKey(String householdId) => '$_keyPrefix$householdId';

  /// Mengambil semua profil yang tersimpan untuk sebuah household.
  Future<List<CashFlowProfile>> getAllProfiles(String householdId) async {
    final prefs = await _prefs();
    final raw = prefs.getString(_getKey(householdId));
    if (raw == null || raw.isEmpty) return [];

    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => CashFlowProfile.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Mengambil profil/siklus aktif saat ini (jika ada).
  Future<CashFlowProfile?> getActiveProfile(String householdId) async {
    final list = await getAllProfiles(householdId);
    return list.where((p) => p.isActive).firstOrNull;
  }

  /// Menyimpan atau memperbarui profil. Jika [profile.isActive] bernilai true,
  /// profil lain otomatis dijadikan non-aktif.
  Future<void> saveProfile(CashFlowProfile profile) async {
    final list = await getAllProfiles(profile.householdId);
    final idx = list.indexWhere((p) => p.id == profile.id);

    List<CashFlowProfile> updated;
    if (idx >= 0) {
      updated = List.of(list);
      updated[idx] = profile;
    } else {
      updated = [profile, ...list];
    }

    // Jika profil ini aktif, pastikan hanya 1 profil yang aktif
    if (profile.isActive) {
      updated = updated.map((p) {
        if (p.id == profile.id) return p;
        return p.copyWith(isActive: false);
      }).toList();
    }

    final prefs = await _prefs();
    await prefs.setString(
      _getKey(profile.householdId),
      jsonEncode(updated.map((p) => p.toJson()).toList()),
    );
  }

  /// Menjadikan profil tertentu sebagai profil aktif.
  Future<void> setActiveProfile(String householdId, String profileId) async {
    final list = await getAllProfiles(householdId);
    final updated = list.map((p) {
      return p.copyWith(isActive: p.id == profileId);
    }).toList();

    final prefs = await _prefs();
    await prefs.setString(
      _getKey(householdId),
      jsonEncode(updated.map((p) => p.toJson()).toList()),
    );
  }

  /// Menghapus profil berdasarkan ID.
  Future<void> deleteProfile(String householdId, String profileId) async {
    final list = await getAllProfiles(householdId);
    final updated = list.where((p) => p.id != profileId).toList();

    final prefs = await _prefs();
    await prefs.setString(
      _getKey(householdId),
      jsonEncode(updated.map((p) => p.toJson()).toList()),
    );
  }
}
