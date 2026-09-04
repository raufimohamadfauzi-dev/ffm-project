import 'package:flutter/services.dart';

/// Hasil pembacaan kartu e-Money via NFC.
class NfcCardScanResult {
  const NfcCardScanResult({
    required this.cardId,
    required this.balance,
    required this.cardType,
    required this.success,
    this.error,
  });

  final String cardId;
  final double balance;
  final String cardType;
  final bool success;
  final String? error;

  factory NfcCardScanResult.fromMap(Map<dynamic, dynamic> map) {
    return NfcCardScanResult(
      cardId: map['cardId'] as String? ?? 'UNKNOWN',
      balance: (map['balance'] as num?)?.toDouble() ?? 0.0,
      cardType: map['cardType'] as String? ?? 'emoney_generic',
      success: map['success'] as bool? ?? false,
      error: map['error'] as String?,
    );
  }

  /// Label nama jenis kartu e-Money yang dapat dibaca manusia.
  String get cardTypeLabel {
    switch (cardType) {
      case 'mandiri_emoney':
        return 'Mandiri e-Money';
      case 'flazz_bca':
        return 'BCA Flazz';
      case 'bni_tapcash':
        return 'BNI TapCash';
      case 'bri_brizzi':
        return 'BRI Brizzi';
      default:
        return 'Kartu e-Money';
    }
  }

  /// Format nominal saldo yang rapi (Rp 80.000).
  String get formattedBalance {
    final n = balance.toStringAsFixed(0);
    final buf = StringBuffer();
    int count = 0;
    for (int i = n.length - 1; i >= 0; i--) {
      if (count > 0 && count % 3 == 0) buf.write('.');
      buf.write(n[i]);
      count++;
    }
    return 'Rp ${buf.toString().split('').reversed.join()}';
  }
}

/// Jembatan antara Flutter dan Native Kotlin NFC Reader (`FfmNfcReaderService.kt`).
class NfcBridge {
  NfcBridge();

  static const _channel = MethodChannel('ffm/nfc_reader');

  void Function(NfcCardScanResult result)? _onScanCallback;

  /// Memeriksa apakah HP memiliki sensor fisik NFC.
  Future<bool> isNfcAvailable() async {
    try {
      final res = await _channel.invokeMethod<bool>('isAvailable');
      return res ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Memeriksa apakah sensor NFC sedang diaktifkan di HP.
  Future<bool> isNfcEnabled() async {
    try {
      final res = await _channel.invokeMethod<bool>('isEnabled');
      return res ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Mulai sesi pemindaian kartu e-Money via NFC.
  Future<bool> startScanning(void Function(NfcCardScanResult) onScan) async {
    _onScanCallback = onScan;
    _channel.setMethodCallHandler(_handleMethodCall);
    try {
      final res = await _channel.invokeMethod<bool>('startSession');
      return res ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Hentikan sesi pemindaian NFC.
  Future<void> stopScanning() async {
    _onScanCallback = null;
    _channel.setMethodCallHandler(null);
    try {
      await _channel.invokeMethod('stopSession');
    } on PlatformException {
      // Abaikan jika platform tidak merespons
    }
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method == 'onCardScanned') {
      final args = call.arguments as Map<dynamic, dynamic>?;
      if (args != null && _onScanCallback != null) {
        final result = NfcCardScanResult.fromMap(args);
        _onScanCallback!(result);
      }
    }
  }
}
