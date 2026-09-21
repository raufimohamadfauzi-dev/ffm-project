import 'dart:async';
import 'dart:io';

/// Service untuk mendeteksi ketersediaan internet.
///
/// Service ini digunakan oleh otonom untuk mengecek apakah internet tersedia
/// sebelum menjalankan job yang membutuhkan LLM.
class FfmAssistantAutonomyInternetService {
  FfmAssistantAutonomyInternetService({
    this.checkInterval = const Duration(seconds: 10),
    this.timeout = const Duration(seconds: 5),
  });

  final Duration checkInterval;
  final Duration timeout;

  bool _isOnline = true;
  Timer? _checkTimer;
  final _listeners = <void Function(bool)>[];

  /// Status internet saat ini.
  bool get isOnline => _isOnline;

  /// Mulai monitoring internet.
  void startMonitoring() {
    _checkTimer?.cancel();
    _checkTimer = Timer.periodic(checkInterval, (_) {
      _checkInternet();
    });
  }

  /// Stop monitoring internet.
  void stopMonitoring() {
    _checkTimer?.cancel();
    _checkTimer = null;
  }

  /// Cek internet secara manual.
  Future<bool> checkInternet() async {
    return await _checkInternet();
  }

  /// Cek internet secara internal.
  Future<bool> _checkInternet() async {
    try {
      // Cek internet dengan ping ke Google DNS
      final result = await _checkDns()
          .timeout(timeout)
          .catchError((_) => false);

      final wasOnline = _isOnline;
      _isOnline = result;

      // Notify listeners jika status berubah
      if (wasOnline != _isOnline) {
        _notifyListeners(_isOnline);
      }

      return result;
    } catch (_) {
      final wasOnline = _isOnline;
      _isOnline = false;

      if (wasOnline != _isOnline) {
        _notifyListeners(false);
      }

      return false;
    }
  }

  /// Cek DNS resolution.
  Future<bool> _checkDns() async {
    try {
      final socket = await Socket.connect('dns.google', 53)
          .timeout(const Duration(seconds: 3));
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Subscribe ke perubahan status internet.
  void onStatusChange(void Function(bool isOnline) listener) {
    _listeners.add(listener);
  }

  /// Unsubscribe dari perubahan status internet.
  void offStatusChange(void Function(bool isOnline) listener) {
    _listeners.remove(listener);
  }

  /// Notify semua listeners.
  void _notifyListeners(bool isOnline) {
    for (final listener in _listeners) {
      try {
        listener(isOnline);
      } catch (_) {
        // Ignore error dalam listener
      }
    }
  }

  /// Dispose service.
  void dispose() {
    stopMonitoring();
    _listeners.clear();
  }
}
