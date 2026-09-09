import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Status pengiriman Telegram yang ditampilkan kepada pengguna.
enum TelegramDeliveryStatus { none, pending, sent, failed }

/// Status operasional terakhir yang dilihat halaman setup Telegram.
class TelegramOperationalStatus {
  const TelegramOperationalStatus({
    this.lastVerifiedAt,
    this.lastVerifiedOk = false,
    this.lastDeliveryStatus = TelegramDeliveryStatus.none,
    this.lastDeliveryMessage,
    this.verificationFingerprint,
  });

  final DateTime? lastVerifiedAt;
  final bool lastVerifiedOk;
  final TelegramDeliveryStatus lastDeliveryStatus;
  final String? lastDeliveryMessage;

  /// Fingerprint kredensial (token + chat) saat verifikasi terakhir berhasil.
  /// Berguna untuk tidak mengklaim "Terhubung" terhadap kredensial baru.
  final String? verificationFingerprint;

  bool get hasVerified => lastVerifiedAt != null && lastVerifiedOk;
  TelegramOperationalStatus copyWith({
    DateTime? lastVerifiedAt,
    bool? lastVerifiedOk,
    TelegramDeliveryStatus? lastDeliveryStatus,
    String? lastDeliveryMessage,
    String? verificationFingerprint,
  }) => TelegramOperationalStatus(
    lastVerifiedAt: lastVerifiedAt ?? this.lastVerifiedAt,
    lastVerifiedOk: lastVerifiedOk ?? this.lastVerifiedOk,
    lastDeliveryStatus: lastDeliveryStatus ?? this.lastDeliveryStatus,
    lastDeliveryMessage: lastDeliveryMessage ?? this.lastDeliveryMessage,
    verificationFingerprint:
        verificationFingerprint ?? this.verificationFingerprint,
  );
}

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
///
/// Semua operasi tulis memakai strategi commit dengan rollback: bila langkah
/// penulisan gagal, nilai lama dikembalikan sebelum error dilempar ke pemanggil
/// sehingga kegagalan konfigurasi selalu terlihat (tidak pernah ditelan diam-diam).
class TelegramConfigRepository {
  TelegramConfigRepository({
    FlutterSecureStorage? secureStorage,
    this.preferences,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage();

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
  static const String _keyWeeklyReportClaim =
      'ffm_telegram_weekly_report_claim';
  static const String _keyLastVerifiedAt = 'ffm_telegram_last_verified_at';
  static const String _keyLastVerifiedOk = 'ffm_telegram_last_verified_ok';
  static const String _keyLastVerifiedFingerprint =
      'ffm_telegram_last_verified_fingerprint';
  static const String _keyLastDeliveryStatus =
      'ffm_telegram_last_delivery_status';
  static const String _keyLastDeliveryMessage =
      'ffm_telegram_last_delivery_message';
  static const String _keyAlertDeliveredIds = 'ffm_telegram_alert_delivered';
  static const String _keyAlertFailedIds = 'ffm_telegram_alert_failed';
  static const String _keyAlertDeliveryRetryAt = 'ffm_telegram_alert_retry_at';

  static const int _maxTrackedAlertIds = 200;

  final Map<String, bool> _weeklyClaimLocks = {};

  /// Bandingan identitas kredensial (bot token + chat id) tanpa menyimpan
  /// rahasia. Dipakai untuk mengikat status verifikasi dan pesan antrean ke
  /// pasangan kredensial yang saat itu aktif.
  static String credentialFingerprintFor(String botToken, String chatId) =>
      sha256.convert(utf8.encode('${botToken.trim()}#${chatId.trim()}')).toString();

  Future<SharedPreferences> get _prefs async =>
      preferences ?? await SharedPreferences.getInstance();

  /// Memuat konfigurasi Telegram tersimpan.
  ///
  /// Gagal membaca (misal secure storage/prefs error) melempar exception agar
  /// pemanggil bisa membedakan "belum diatur" (valid) dari "gagal membaca"
  /// (ada masalah perangkat) — bukan asumsi default kosong.
  Future<TelegramConfig> loadConfig() async {
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
  }

  /// Menyimpan konfigurasi Telegram secara aman dengan rollback.
  ///
  /// Urutan penulisan: prefs (non-rahasia) lalu secure storage (rahasia).
  /// Bila ada langkah yang gagal, nilai lama dipulihkan sebisanya lalu error
  /// dilempar agar halaman setup bisa menampilkan pesan kegagalan.
  Future<void> saveConfig(TelegramConfig config) async {
    final snapshot = await _loadSnapshot();
    // ignore: avoid_catches_without_on_clauses
    try {
      final prefs = await _prefs;
      await prefs.setBool(_keyIsEnabled, config.isEnabled);
      await prefs.setBool(_keyWeeklyReport, config.weeklyReportEnabled);
      await prefs.setBool(_keyAlerts, config.alertsEnabled);
      await prefs.setBool(_keyNotifyNewTx, config.notifyOnNewTransaction);
      await prefs.setInt(_keyNotifyMinAmount, config.notifyMinAmount);
      await _secureStorage.write(
        key: _keyBotToken,
        value: config.botToken.trim(),
      );
      await _secureStorage.write(key: _keyChatId, value: config.chatId.trim());
    } catch (_) {
      await _restoreSnapshot(snapshot);
      rethrow;
    }
  }

  Future<TelegramConfig> _loadSnapshot() async {
    // ignore: avoid_catches_without_on_clauses
    try {
      return await loadConfig();
    } catch (_) {
      // Simpanan gagal dibaca: gunakan nilai default sebagai snapshot.
      return const TelegramConfig();
    }
  }

  Future<void> _restoreSnapshot(TelegramConfig snapshot) async {
    // ignore: avoid_catches_without_on_clauses
    try {
      final prefs = await _prefs;
      await prefs.setBool(_keyIsEnabled, snapshot.isEnabled);
      await prefs.setBool(_keyWeeklyReport, snapshot.weeklyReportEnabled);
      await prefs.setBool(_keyAlerts, snapshot.alertsEnabled);
      await prefs.setBool(_keyNotifyNewTx, snapshot.notifyOnNewTransaction);
      await prefs.setInt(_keyNotifyMinAmount, snapshot.notifyMinAmount);
      await _secureStorage.write(
        key: _keyBotToken,
        value: snapshot.botToken.trim(),
      );
      await _secureStorage.write(
        key: _keyChatId,
        value: snapshot.chatId.trim(),
      );
    } catch (_) {}
  }

  /// Memuat tanggal terakhir kali laporan mingguan berhasil dikirim.
  /// Gagal membaca melempar exception (tidak ditelan).
  Future<DateTime?> loadLastWeeklyReportSent() async {
    final prefs = await _prefs;
    final iso = prefs.getString(_keyLastWeeklyReportSent);
    if (iso == null || iso.isEmpty) return null;
    return DateTime.tryParse(iso);
  }

  /// Menyimpan tanggal terakhir kali laporan mingguan berhasil dikirim.
  /// Gagal menyimpan melempar exception (tidak ditelan diam-diam).
  Future<void> saveLastWeeklyReportSent(DateTime time) async {
    final prefs = await _prefs;
    final ok = await prefs.setString(
      _keyLastWeeklyReportSent,
      time.toIso8601String(),
    );
    if (!ok) {
      throw StateError(
        'Gagal menyimpan waktu terakhir laporan mingguan dikirim.',
      );
    }
  }

  /// Klaim atomik pengiriman laporan mingguan untuk [periodKey].
  ///
  /// Melindungi dari pengiriman ganda saat evaluasi berjalan bersamaan
  /// (misal background + eksekusi manual). Klaim `pending` yang masih "segar"
  /// menandakan pengiriman sedang berlangsung; klaim `sent` dalam 6 hari
  /// menandakan laporan sudah terkirim. Klaim lama yang menggantung bisa
  /// diklaim ulang agar tidak selamanya macet.
  Future<bool> claimWeeklyReport({
    required String periodKey,
    required DateTime now,
  }) async {
    if (_weeklyClaimLocks[periodKey] == true) return false;

    final prefs = await _prefs;
    final claimKey = '${_keyWeeklyReportClaim}_$periodKey';
    final raw = prefs.getString(claimKey);
    if (raw != null && raw.isNotEmpty) {
      // ignore: avoid_catches_without_on_clauses
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final status = map['status'] as String?;
        final at = DateTime.tryParse(map['at'] as String? ?? '');
        if (status != null && at != null) {
          final age = now.difference(at);
          if (status == 'pending') {
            if (age.inMinutes < 10) return false;
          } else if (status == 'sent' && age.inDays < 6) {
            return false;
          }
        }
      } catch (_) {}
    }

    await prefs.setString(
      claimKey,
      jsonEncode({'status': 'pending', 'at': now.toIso8601String()}),
    );
    _weeklyClaimLocks[periodKey] = true;
    return true;
  }

  /// Menandai laporan mingguan [periodKey] berhasil terkirim.
  Future<void> completeWeeklyReport({
    required String periodKey,
    required DateTime now,
  }) async {
    final prefs = await _prefs;
    await prefs.setString(
      '${_keyWeeklyReportClaim}_$periodKey',
      jsonEncode({'status': 'sent', 'at': now.toIso8601String()}),
    );
    await prefs.setString(_keyLastWeeklyReportSent, now.toIso8601String());
    _weeklyClaimLocks.remove(periodKey);
  }

  /// Menandai laporan mingguan [periodKey] gagal dikirim (untuk percobaan ulang).
  Future<void> failWeeklyReport({
    required String periodKey,
    required DateTime now,
  }) async {
    final prefs = await _prefs;
    await prefs.setString(
      '${_keyWeeklyReportClaim}_$periodKey',
      jsonEncode({'status': 'failed', 'at': now.toIso8601String()}),
    );
    _weeklyClaimLocks.remove(periodKey);
  }

  /// Menandai insight [insightId] sudah berhasil diteruskan ke Telegram.
  Future<void> markAlertDelivered(String insightId) async {
    final prefs = await _prefs;
    final delivered = prefs.getString(_keyAlertDeliveredIds);
    final ids = delivered == null || delivered.isEmpty
        ? <String>[]
        : delivered.split(',').toSet().toList();
    if (ids.contains(insightId)) return;
    ids.add(insightId);
    if (ids.length > _maxTrackedAlertIds) {
      ids.removeRange(0, ids.length - _maxTrackedAlertIds);
    }
    await prefs.setString(_keyAlertDeliveredIds, ids.join(','));
    await _removeFailedAlertId(prefs, insightId);
  }

  /// Menandai insight [insightId] gagal diteruskan (untuk dicoba ulang).
  Future<void> markAlertFailed(String insightId) async {
    final prefs = await _prefs;
    final failed = prefs.getString(_keyAlertFailedIds);
    final ids = failed == null || failed.isEmpty
        ? <String>[]
        : failed.split(',').toSet().toList();
    if (!ids.contains(insightId)) {
      ids.add(insightId);
      if (ids.length > _maxTrackedAlertIds) {
        ids.removeRange(0, ids.length - _maxTrackedAlertIds);
      }
      await prefs.setString(_keyAlertFailedIds, ids.join(','));
    }
    await _removeDeliveredAlertId(prefs, insightId);
  }

  Future<bool> isAlertDelivered(String insightId) async {
    final prefs = await _prefs;
    final delivered = prefs.getString(_keyAlertDeliveredIds);
    if (delivered == null || delivered.isEmpty) return false;
    return delivered.split(',').contains(insightId);
  }

  /// Daftar id insight yang gagal terkirim dan layak dicoba ulang.
  Future<List<String>> loadFailedAlertIds() async {
    final prefs = await _prefs;
    final failed = prefs.getString(_keyAlertFailedIds);
    if (failed == null || failed.isEmpty) return const [];
    return failed.split(',');
  }

  Future<void> _removeFailedAlertId(
    SharedPreferences prefs,
    String insightId,
  ) async {
    final failed = prefs.getString(_keyAlertFailedIds);
    if (failed == null || failed.isEmpty) return;
    final ids = failed.split(',').where((id) => id != insightId).toList();
    await prefs.setString(_keyAlertFailedIds, ids.isEmpty ? '' : ids.join(','));
  }

  Future<void> _removeDeliveredAlertId(
    SharedPreferences prefs,
    String insightId,
  ) async {
    final delivered = prefs.getString(_keyAlertDeliveredIds);
    if (delivered == null || delivered.isEmpty) return;
    final ids = delivered.split(',').where((id) => id != insightId).toList();
    await prefs.setString(
      _keyAlertDeliveredIds,
      ids.isEmpty ? '' : ids.join(','),
    );
  }

  /// Mengambil izin untuk mencoba ulang alert yang sebelumnya gagal sambil
  /// mencatat waktu percobaan terakhir (cooldown) agar tidak spam saat
  /// evaluasi berjalan berulang akibat perubahan data.
  Future<bool> tryBeginAlertRetry(
    DateTime now, {
    Duration cooldown = const Duration(minutes: 10),
  }) async {
    final prefs = await _prefs;
    final lastRaw = prefs.getString(_keyAlertDeliveryRetryAt);
    if (lastRaw != null && lastRaw.isNotEmpty) {
      final last = DateTime.tryParse(lastRaw);
      if (last != null && now.difference(last) < cooldown) return false;
    }
    await prefs.setString(_keyAlertDeliveryRetryAt, now.toIso8601String());
    return true;
  }

  /// Mencatat hasil verifikasi koneksi terakhir (dipakai halaman setup).
  ///
  /// Bila [botToken]/[chatId] diberikan dan verifikasi berhasil, fingerprint
  /// kredensial ikut disimpan agar status "Terhubung" tidak diwarisi oleh
  /// kredensial yang berbeda.
  Future<void> recordVerificationResult({
    required bool ok,
    required DateTime at,
    String? botToken,
    String? chatId,
    String? message,
  }) async {
    final prefs = await _prefs;
    await prefs.setString(_keyLastVerifiedAt, at.toIso8601String());
    await prefs.setBool(_keyLastVerifiedOk, ok);
    if (botToken != null && chatId != null) {
      await prefs.setString(
        _keyLastVerifiedFingerprint,
        ok ? credentialFingerprintFor(botToken, chatId) : '',
      );
    }
    if (message != null) {
      await prefs.setString(_keyLastDeliveryMessage, message);
    }
  }

  /// Mencatat status pengiriman terakhir (laporan/peringatan).
  Future<void> recordDeliveryStatus({
    required TelegramDeliveryStatus status,
    String? message,
  }) async {
    final prefs = await _prefs;
    await prefs.setString(_keyLastDeliveryStatus, status.name);
    if (message != null) {
      await prefs.setString(_keyLastDeliveryMessage, message);
    }
  }

  /// Memuat status operasional terakhir untuk ditampilkan di halaman setup.
  Future<TelegramOperationalStatus> loadOperationalStatus() async {
    final prefs = await _prefs;
    final atString = prefs.getString(_keyLastVerifiedAt);
    final ok = prefs.getBool(_keyLastVerifiedOk) ?? false;
    final statusName = prefs.getString(_keyLastDeliveryStatus);
    final message = prefs.getString(_keyLastDeliveryMessage);
    final fingerprint = prefs.getString(_keyLastVerifiedFingerprint);
    var status = TelegramDeliveryStatus.none;
    for (final s in TelegramDeliveryStatus.values) {
      if (s.name == statusName) {
        status = s;
        break;
      }
    }
    final fingerprintValue =
        fingerprint == null || fingerprint.isEmpty ? null : fingerprint;
    return TelegramOperationalStatus(
      lastVerifiedAt: atString == null ? null : DateTime.tryParse(atString),
      lastVerifiedOk: ok,
      lastDeliveryStatus: status,
      lastDeliveryMessage: message,
      verificationFingerprint: fingerprintValue,
    );
  }

  /// Menghapus kredensial Telegram jika pengguna ingin mereset.
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
    await prefs.remove(_keyAlertDeliveredIds);
    await prefs.remove(_keyAlertFailedIds);
    await prefs.remove(_keyAlertDeliveryRetryAt);
    await prefs.remove(_keyLastVerifiedAt);
    await prefs.remove(_keyLastVerifiedOk);
    await prefs.remove(_keyLastVerifiedFingerprint);
    await prefs.remove(_keyLastDeliveryStatus);
    await prefs.remove(_keyLastDeliveryMessage);
    _weeklyClaimLocks.clear();
  }
}
