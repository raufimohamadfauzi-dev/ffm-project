import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Konfigurasi integrasi Telegram Bot Asisten Keluarga FFM.
class TelegramConfig {
  const TelegramConfig({
    this.botToken = '',
    this.chatId = '',
    this.isEnabled = false,
    this.weeklyReportEnabled = true,
    this.alertsEnabled = true,
    this.notifyOnNewTransaction = false,
    this.notifyMinAmount = 50000,
  });

  final String botToken;
  final String chatId;
  final bool isEnabled;
  final bool weeklyReportEnabled;
  final bool alertsEnabled;
  final bool notifyOnNewTransaction;
  final int notifyMinAmount;

  /// Memeriksa apakah kredensial dasar sudah terisi
  bool get isConfigured =>
      botToken.trim().isNotEmpty && chatId.trim().isNotEmpty;

  /// Memeriksa apakah fitur aktif dan kredensial siap digunakan
  bool get isReady => isEnabled && isConfigured;

  TelegramConfig copyWith({
    String? botToken,
    String? chatId,
    bool? isEnabled,
    bool? weeklyReportEnabled,
    bool? alertsEnabled,
    bool? notifyOnNewTransaction,
    int? notifyMinAmount,
  }) {
    return TelegramConfig(
      botToken: botToken ?? this.botToken,
      chatId: chatId ?? this.chatId,
      isEnabled: isEnabled ?? this.isEnabled,
      weeklyReportEnabled: weeklyReportEnabled ?? this.weeklyReportEnabled,
      alertsEnabled: alertsEnabled ?? this.alertsEnabled,
      notifyOnNewTransaction:
          notifyOnNewTransaction ?? this.notifyOnNewTransaction,
      notifyMinAmount: notifyMinAmount ?? this.notifyMinAmount,
    );
  }
}

/// Repositori untuk menyimpan konfigurasi Telegram Bot secara aman di perangkat lokal.
/// Bot Token dan Chat ID disimpan di [FlutterSecureStorage], sedangkan flag boolean
/// disimpan di [SharedPreferences].
class TelegramConfigRepository {
  TelegramConfigRepository({
    FlutterSecureStorage? secureStorage,
    this.preferences,
  })  : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;
  final SharedPreferences? preferences;

  static const String _keyBotToken = 'ffm_telegram_bot_token';
  static const String _keyChatId = 'ffm_telegram_chat_id';
  static const String _keyIsEnabled = 'ffm_telegram_is_enabled';
  static const String _keyWeeklyReport = 'ffm_telegram_weekly_report_enabled';
  static const String _keyAlerts = 'ffm_telegram_alerts_enabled';
  static const String _keyNotifyNewTx = 'ffm_telegram_notify_new_tx';
  static const String _keyNotifyMinAmount = 'ffm_telegram_notify_min_amount';
  static const String _keyLastWeeklyReportSent =
      'ffm_telegram_last_weekly_report_sent';

  Future<SharedPreferences> get _prefs async =>
      preferences ?? await SharedPreferences.getInstance();

  /// Memuat konfigurasi Telegram tersimpan
  Future<TelegramConfig> loadConfig() async {
    try {
      final token = await _secureStorage.read(key: _keyBotToken) ?? '';
      final chat = await _secureStorage.read(key: _keyChatId) ?? '';
      final prefs = await _prefs;
      final enabled = prefs.getBool(_keyIsEnabled) ?? false;
      final weekly = prefs.getBool(_keyWeeklyReport) ?? true;
      final alerts = prefs.getBool(_keyAlerts) ?? true;
      final notifyNewTx = prefs.getBool(_keyNotifyNewTx) ?? false;
      final minAmount = prefs.getInt(_keyNotifyMinAmount) ?? 50000;

      return TelegramConfig(
        botToken: token,
        chatId: chat,
        isEnabled: enabled,
        weeklyReportEnabled: weekly,
        alertsEnabled: alerts,
        notifyOnNewTransaction: notifyNewTx,
        notifyMinAmount: minAmount,
      );
    } catch (_) {
      return const TelegramConfig();
    }
  }

  /// Menyimpan konfigurasi Telegram secara aman
  Future<void> saveConfig(TelegramConfig config) async {
    await _secureStorage.write(key: _keyBotToken, value: config.botToken.trim());
    await _secureStorage.write(key: _keyChatId, value: config.chatId.trim());

    final prefs = await _prefs;
    await prefs.setBool(_keyIsEnabled, config.isEnabled);
    await prefs.setBool(_keyWeeklyReport, config.weeklyReportEnabled);
    await prefs.setBool(_keyAlerts, config.alertsEnabled);
    await prefs.setBool(_keyNotifyNewTx, config.notifyOnNewTransaction);
    await prefs.setInt(_keyNotifyMinAmount, config.notifyMinAmount);
  }

  /// Memuat tanggal terakhir kali laporan mingguan berhasil dikirim
  Future<DateTime?> loadLastWeeklyReportSent() async {
    try {
      final prefs = await _prefs;
      final iso = prefs.getString(_keyLastWeeklyReportSent);
      if (iso == null || iso.isEmpty) return null;
      return DateTime.tryParse(iso);
    } catch (_) {
      return null;
    }
  }

  /// Menyimpan tanggal terakhir kali laporan mingguan berhasil dikirim
  Future<void> saveLastWeeklyReportSent(DateTime time) async {
    try {
      final prefs = await _prefs;
      await prefs.setString(_keyLastWeeklyReportSent, time.toIso8601String());
    } catch (_) {}
  }

  /// Menghapus kredensial Telegram jika pengguna ingin mereset
  Future<void> clearConfig() async {
    await _secureStorage.delete(key: _keyBotToken);
    await _secureStorage.delete(key: _keyChatId);

    final prefs = await _prefs;
    await prefs.remove(_keyIsEnabled);
    await prefs.remove(_keyWeeklyReport);
    await prefs.remove(_keyAlerts);
    await prefs.remove(_keyNotifyNewTx);
    await prefs.remove(_keyNotifyMinAmount);
    await prefs.remove(_keyLastWeeklyReportSent);
  }
}
