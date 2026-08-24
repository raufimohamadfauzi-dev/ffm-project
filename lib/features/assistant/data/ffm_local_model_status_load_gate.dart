import 'dart:async';

/// Menjaga satu pembacaan status model aktif pada satu waktu. Panggilan yang
/// datang dari lifecycle saat pembacaan sebelumnya belum selesai diabaikan;
/// UI tidak menunggu dua platform call/IO yang saling tumpang tindih.
class FfmLocalModelStatusLoadGate {
  FfmLocalModelStatusLoadGate({this.timeout = const Duration(seconds: 10)});

  final Duration timeout;
  bool _isRunning = false;

  bool get isRunning => _isRunning;

  Future<T?> run<T>(Future<T> Function() operation) async {
    if (_isRunning) return null;
    _isRunning = true;
    try {
      return await operation().timeout(timeout);
    } finally {
      _isRunning = false;
    }
  }
}
