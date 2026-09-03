import 'package:shared_preferences/shared_preferences.dart';
import 'ffm_assistant_insight.dart';

class FfmProactiveDeliveryPolicy {
  FfmProactiveDeliveryPolicy({SharedPreferences? preferences})
      : _prefs = preferences;

  static const keyEnabled = 'ffm_proactive_notifications_enabled';
  static const keyQuietHoursEnabled = 'ffm_proactive_quiet_hours_enabled';
  static const keyQuietHoursStart = 'ffm_proactive_quiet_hours_start';
  static const keyQuietHoursEnd = 'ffm_proactive_quiet_hours_end';
  static const keyDailyLimit = 'ffm_proactive_daily_limit';
  static const keySentCount = 'ffm_proactive_sent_count';
  static const keySentDate = 'ffm_proactive_sent_date';
  static const keyDisabledDetectors = 'ffm_proactive_disabled_detectors';

  final SharedPreferences? _prefs;

  Future<SharedPreferences> _getPrefs() async {
    return _prefs ?? await SharedPreferences.getInstance();
  }

  Future<bool> isEnabled() async {
    final prefs = await _getPrefs();
    return prefs.getBool(keyEnabled) ?? true;
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await _getPrefs();
    await prefs.setBool(keyEnabled, value);
  }

  Future<bool> isQuietHoursEnabled() async {
    final prefs = await _getPrefs();
    return prefs.getBool(keyQuietHoursEnabled) ?? true;
  }

  Future<void> setQuietHoursEnabled(bool value) async {
    final prefs = await _getPrefs();
    await prefs.setBool(keyQuietHoursEnabled, value);
  }

  Future<int> getQuietHoursStart() async {
    final prefs = await _getPrefs();
    return prefs.getInt(keyQuietHoursStart) ?? 22; // Jam 22:00 malam
  }

  Future<void> setQuietHoursStart(int hour) async {
    final prefs = await _getPrefs();
    await prefs.setInt(keyQuietHoursStart, hour.clamp(0, 23));
  }

  Future<int> getQuietHoursEnd() async {
    final prefs = await _getPrefs();
    return prefs.getInt(keyQuietHoursEnd) ?? 6; // Jam 06:00 pagi
  }

  Future<void> setQuietHoursEnd(int hour) async {
    final prefs = await _getPrefs();
    await prefs.setInt(keyQuietHoursEnd, hour.clamp(0, 23));
  }

  Future<int> getDailyLimit() async {
    final prefs = await _getPrefs();
    return prefs.getInt(keyDailyLimit) ?? 3; // Maks 3 notifikasi/hari
  }

  Future<void> setDailyLimit(int limit) async {
    final prefs = await _getPrefs();
    await prefs.setInt(keyDailyLimit, limit.clamp(1, 10));
  }

  Future<List<String>> getDisabledDetectors() async {
    final prefs = await _getPrefs();
    return prefs.getStringList(keyDisabledDetectors) ?? const [];
  }

  Future<void> setDetectorDisabled(String detectorType, bool disabled) async {
    final prefs = await _getPrefs();
    final list = (prefs.getStringList(keyDisabledDetectors) ?? <String>[]).toList();
    if (disabled && !list.contains(detectorType)) {
      list.add(detectorType);
    } else if (!disabled) {
      list.remove(detectorType);
    }
    await prefs.setStringList(keyDisabledDetectors, list);
  }

  /// Memvalidasi apakah sebuah insight layak dikirimkan sebagai notifikasi push Android
  /// dengan mempertimbangkan status aktif, jam hening, batas harian, prioritas, dan preferensi detektor.
  Future<bool> shouldDeliverNotification(
    FfmAssistantInsight insight, {
    DateTime? now,
  }) async {
    final current = now ?? DateTime.now();
    final prefs = await _getPrefs();

    // 1. Cek saklar utama
    final enabled = prefs.getBool(keyEnabled) ?? true;
    if (!enabled) return false;

    // 2. Cek status insight (hanya newInsight yang layak dinotifikasikan)
    if (insight.status != FfmAssistantInsightStatus.newInsight) {
      return false;
    }

    // 3. Cek prioritas minimal (hanya yang cukup krusial)
    if (insight.priority < 60 &&
        insight.severity != FfmAssistantInsightSeverity.critical &&
        insight.severity != FfmAssistantInsightSeverity.warning) {
      return false;
    }

    // 4. Cek apakah jenis detektor ini dimatikan oleh pengguna
    final disabledList = prefs.getStringList(keyDisabledDetectors) ?? const [];
    if (disabledList.contains(insight.type.name)) {
      return false;
    }

    // 5. Cek jam hening (Quiet Hours)
    final quietHours = prefs.getBool(keyQuietHoursEnabled) ?? true;
    if (quietHours) {
      final start = prefs.getInt(keyQuietHoursStart) ?? 22;
      final end = prefs.getInt(keyQuietHoursEnd) ?? 6;
      final hour = current.hour;

      if (start > end) {
        // Melintasi tengah malam, misal 22:00 s.d. 06:00
        if (hour >= start || hour < end) return false;
      } else {
        if (hour >= start && hour < end) return false;
      }
    }

    // 6. Cek batas harian
    final dailyLimit = prefs.getInt(keyDailyLimit) ?? 3;
    final todayStr = '${current.year}-${current.month.toString().padLeft(2, '0')}-${current.day.toString().padLeft(2, '0')}';
    final savedDate = prefs.getString(keySentDate);
    final count = savedDate == todayStr ? (prefs.getInt(keySentCount) ?? 0) : 0;

    if (count >= dailyLimit) {
      return false;
    }

    return true;
  }

  /// Mencatat bahwa notifikasi berhasil dikirim hari ini untuk pembatasan harian
  Future<void> recordNotificationDelivered({DateTime? now}) async {
    final current = now ?? DateTime.now();
    final prefs = await _getPrefs();
    final todayStr = '${current.year}-${current.month.toString().padLeft(2, '0')}-${current.day.toString().padLeft(2, '0')}';
    final savedDate = prefs.getString(keySentDate);
    final count = savedDate == todayStr ? (prefs.getInt(keySentCount) ?? 0) : 0;

    await prefs.setString(keySentDate, todayStr);
    await prefs.setInt(keySentCount, count + 1);
  }
}
