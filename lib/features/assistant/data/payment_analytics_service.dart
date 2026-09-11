import 'package:shared_preferences/shared_preferences.dart';

/// Service untuk tracking analytics parser success rate.
/// Menggunakan SharedPreferences untuk menyimpan data secara lokal.
class PaymentAnalyticsService {
  PaymentAnalyticsService();

  static const _totalNotificationsKey = 'ffm_payment_total_notifications';
  static const _successfulParsesKey = 'ffm_payment_successful_parses';
  static const _failedParsesKey = 'ffm_payment_failed_parses';
  static const _userConfirmationsKey = 'ffm_payment_user_confirmations';
  static const _userDismissalsKey = 'ffm_payment_user_dismissals';
  static const _lastResetKey = 'ffm_payment_last_reset';
  
  static const _retentionDays = 30;

  SharedPreferences? _cachedPrefs;

  Future<SharedPreferences> _prefs() async =>
      _cachedPrefs ??= await SharedPreferences.getInstance();

  /// Track total notifications received
  Future<void> recordNotificationReceived() async {
    final prefs = await _prefs();
    final current = prefs.getInt(_totalNotificationsKey) ?? 0;
    await prefs.setInt(_totalNotificationsKey, current + 1);
  }

  /// Track successful parse
  Future<void> recordSuccessfulParse(String packageName) async {
    final prefs = await _prefs();
    final current = prefs.getInt(_successfulParsesKey) ?? 0;
    await prefs.setInt(_successfulParsesKey, current + 1);
    
    // Track per-app success rate
    final appKey = 'ffm_payment_${packageName}_success';
    final appCurrent = prefs.getInt(appKey) ?? 0;
    await prefs.setInt(appKey, appCurrent + 1);
  }

  /// Track failed parse with reason
  Future<void> recordFailedParse(String packageName, String reason) async {
    final prefs = await _prefs();
    final current = prefs.getInt(_failedParsesKey) ?? 0;
    await prefs.setInt(_failedParsesKey, current + 1);
    
    // Track per-app failure rate
    final appKey = 'ffm_payment_${packageName}_failed';
    final appCurrent = prefs.getInt(appKey) ?? 0;
    await prefs.setInt(appKey, appCurrent + 1);
    
    // Track failure reasons
    final reasonKey = 'ffm_payment_failure_$reason';
    final reasonCurrent = prefs.getInt(reasonKey) ?? 0;
    await prefs.setInt(reasonKey, reasonCurrent + 1);
  }

  /// Track user confirmation
  Future<void> recordUserConfirmation() async {
    final prefs = await _prefs();
    final current = prefs.getInt(_userConfirmationsKey) ?? 0;
    await prefs.setInt(_userConfirmationsKey, current + 1);
  }

  /// Track user dismissal
  Future<void> recordUserDismissal() async {
    final prefs = await _prefs();
    final current = prefs.getInt(_userDismissalsKey) ?? 0;
    await prefs.setInt(_userDismissalsKey, current + 1);
  }

  /// Get overall analytics summary
  Future<Map<String, dynamic>> getAnalyticsSummary() async {
    final prefs = await _prefs();
    
    final totalNotifications = prefs.getInt(_totalNotificationsKey) ?? 0;
    final successfulParses = prefs.getInt(_successfulParsesKey) ?? 0;
    final failedParses = prefs.getInt(_failedParsesKey) ?? 0;
    final userConfirmations = prefs.getInt(_userConfirmationsKey) ?? 0;
    final userDismissals = prefs.getInt(_userDismissalsKey) ?? 0;
    
    final parseSuccessRate = totalNotifications > 0 
        ? (successfulParses / totalNotifications * 100).toStringAsFixed(1)
        : '0.0';
    
    final userActionRate = (userConfirmations + userDismissals) > 0
        ? (userConfirmations / (userConfirmations + userDismissals) * 100).toStringAsFixed(1)
        : '0.0';

    return {
      'totalNotifications': totalNotifications,
      'successfulParses': successfulParses,
      'failedParses': failedParses,
      'parseSuccessRate': parseSuccessRate,
      'userConfirmations': userConfirmations,
      'userDismissals': userDismissals,
      'userActionRate': userActionRate,
    };
  }

  /// Get per-app analytics
  Future<Map<String, Map<String, int>>> getPerAppAnalytics() async {
    final prefs = await _prefs();
    final keys = prefs.getKeys();
    
    final Map<String, Map<String, int>> appStats = {};
    
    for (final key in keys) {
      if (key.startsWith('ffm_payment_') && key.contains('_success')) {
        final packageName = key.replaceAll('ffm_payment_', '').replaceAll('_success', '');
        final success = prefs.getInt(key) ?? 0;
        final failure = prefs.getInt('ffm_payment_${packageName}_failed') ?? 0;
        
        appStats[packageName] = {
          'success': success,
          'failure': failure,
          'total': success + failure,
        };
      }
    }
    
    return appStats;
  }

  /// Reset analytics data (untuk testing/debugging)
  Future<void> resetAnalytics() async {
    final prefs = await _prefs();
    await prefs.remove(_totalNotificationsKey);
    await prefs.remove(_successfulParsesKey);
    await prefs.remove(_failedParsesKey);
    await prefs.remove(_userConfirmationsKey);
    await prefs.remove(_userDismissalsKey);
    await prefs.remove(_lastResetKey);
    
    // Reset per-app stats
    final keys = prefs.getKeys();
    for (final key in keys) {
      if (key.startsWith('ffm_payment_')) {
        await prefs.remove(key);
      }
    }
  }

  /// Cleanup old analytics data (> retention days)
  Future<void> cleanupOldData() async {
    final prefs = await _prefs();
    final lastReset = prefs.getInt(_lastResetKey);
    
    if (lastReset == null) {
      await prefs.setInt(_lastResetKey, DateTime.now().millisecondsSinceEpoch);
      return;
    }
    
    final lastResetDate = DateTime.fromMillisecondsSinceEpoch(lastReset);
    final daysSinceReset = DateTime.now().difference(lastResetDate).inDays;
    
    if (daysSinceReset >= _retentionDays) {
      await resetAnalytics();
      await prefs.setInt(_lastResetKey, DateTime.now().millisecondsSinceEpoch);
    }
  }
}