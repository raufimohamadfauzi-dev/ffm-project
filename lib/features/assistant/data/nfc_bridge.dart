import 'package:flutter/services.dart';

/// Catatan log transaksi individu yang dibaca dari memori siklik chip kartu e-Money.
class NfcTransactionLogItem {
  const NfcTransactionLogItem({
    required this.recordIndex,
    required this.amount,
    this.rawHex,
  });

  final int recordIndex;
  final double amount;
  final String? rawHex;

  factory NfcTransactionLogItem.fromMap(Map<dynamic, dynamic> map) {
    return NfcTransactionLogItem(
      recordIndex: (map['recordIndex'] as num?)?.toInt() ?? 0,
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      rawHex: map['rawHex'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'recordIndex': recordIndex,
        'amount': amount,
        'rawHex': rawHex,
      };
}

/// Hasil pembacaan kartu e-Money via NFC.
class NfcCardScanResult {
  const NfcCardScanResult({
    required this.cardId,
    required this.balance,
    required this.cardType,
    required this.success,
    this.balanceAvailable = true,
    this.history = const <NfcTransactionLogItem>[],
    this.error,
  });

  final String cardId;
  final double balance;
  final String cardType;
  final bool success;
  /// False untuk kartu yang terdeteksi tetapi tidak memberikan saldo melalui NFC.
  final bool balanceAvailable;
  final List<NfcTransactionLogItem> history;
  final String? error;

  factory NfcCardScanResult.fromMap(Map<dynamic, dynamic> map) {
    final rawHistory = map['history'] as List<dynamic>?;
    final parsedHistory = rawHistory != null
        ? rawHistory
            .whereType<Map<dynamic, dynamic>>()
            .map(NfcTransactionLogItem.fromMap)
            .toList()
        : const <NfcTransactionLogItem>[];

    return NfcCardScanResult(
      cardId: map['cardId'] as String? ?? 'UNKNOWN',
      balance: (map['balance'] as num?)?.toDouble() ?? 0.0,
      cardType: map['cardType'] as String? ?? 'emoney_generic',
      success: map['success'] as bool? ?? false,
      balanceAvailable: map['balanceAvailable'] as bool? ?? true,
      history: parsedHistory,
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
      case 'bank_card':
        return 'Kartu Bank';
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

  void Function(String uri)? _onTagTriggerCallback;

  /// Mendaftarkan listener global saat HP men-tap stiker NFC Smart Tag (NDEF).
  void setTagTriggerListener(void Function(String uri)? onTrigger) {
    _onTagTriggerCallback = onTrigger;
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  /// Mengambil aksi tag pemicu jika aplikasi dibuka dari kondisi tertutup via tap NFC.
  Future<String?> consumePendingTagTrigger() async {
    try {
      return await _channel.invokeMethod<String>('consumePendingTagTrigger');
    } on PlatformException {
      return null;
    }
  }

  /// Memprogram stiker koin NFC fisik dengan URI aksi cepat.
  Future<Map<String, dynamic>> writeTag(String uri) async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(
        'writeTag',
        {'uri': uri},
      );
      return res ?? {'success': false, 'error': 'Tidak ada respon dari NFC'};
    } on PlatformException catch (e) {
      return {'success': false, 'error': e.message ?? 'Gagal menulis tag NFC'};
    }
  }

  /// Membatalkan mode penulisan stiker NFC.
  Future<void> cancelWrite() async {
    try {
      await _channel.invokeMethod('cancelWrite');
    } on PlatformException {
      // Abaikan jika platform tidak merespons
    }
  }

  /// Hentikan sesi pemindaian NFC.
  Future<void> stopScanning() async {
    _onScanCallback = null;
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
    } else if (call.method == 'onTagTriggered') {
      final uri = call.arguments?.toString();
      if (uri != null && _onTagTriggerCallback != null) {
        _onTagTriggerCallback!(uri);
      }
    }
  }
}
