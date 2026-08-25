import 'package:shared_preferences/shared_preferences.dart';

import '../domain/ffm_assistant_proactive_service.dart';

/// Penyimpan cooldown lokal untuk kartu saran proaktif yang bersifat read-only.
///
/// Cooldown tidak menyimpan isi percakapan atau data finansial. Kunci hanya
/// memuat ID saran dan halaman tujuan, sehingga saran yang sama tidak muncul
/// berulang ketika pengguna membuka kembali halaman yang sama dalam waktu dekat.
class FfmAssistantProactiveCooldown {
  FfmAssistantProactiveCooldown({
    SharedPreferences? preferences,
    DateTime Function()? clock,
    this.duration = const Duration(minutes: 30),
  }) : _preferences = preferences,
       _clock = clock ?? DateTime.now;

  static const _keyPrefix = 'ffm_assistant_proactive_cooldown_v1';

  final SharedPreferences? _preferences;
  final DateTime Function() _clock;
  final Duration duration;
  SharedPreferences? _loadedPreferences;

  Future<bool> mayShow(FfmAssistantProactiveSuggestion suggestion) async {
    final storedAt = (await _prefs()).getInt(_keyFor(suggestion));
    if (storedAt == null) return true;
    final elapsed = _clock().difference(
      DateTime.fromMillisecondsSinceEpoch(storedAt),
    );
    return elapsed.isNegative || elapsed >= duration;
  }

  Future<void> markShown(FfmAssistantProactiveSuggestion suggestion) async {
    await (await _prefs()).setInt(
      _keyFor(suggestion),
      _clock().millisecondsSinceEpoch,
    );
  }

  Future<void> clear(FfmAssistantProactiveSuggestion suggestion) async {
    await (await _prefs()).remove(_keyFor(suggestion));
  }

  Future<SharedPreferences> _prefs() async => _loadedPreferences ??=
      _preferences ?? await SharedPreferences.getInstance();

  String _keyFor(FfmAssistantProactiveSuggestion suggestion) {
    final destination = suggestion.destination?.name ?? 'global';
    return '$_keyPrefix.$destination.${suggestion.id}';
  }
}
