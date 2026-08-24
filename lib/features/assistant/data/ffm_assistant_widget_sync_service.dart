import 'package:flutter/services.dart';

/// Sinkronisasi ringkasan aman ke native Home Screen widget.
/// Widget tidak menerima database mentah dan tidak menjalankan mutation.
class FfmAssistantWidgetSyncService {
  const FfmAssistantWidgetSyncService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('ffm/widget');

  final MethodChannel _channel;

  Future<bool> updateSummary({
    required String title,
    required String subtitle,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('updateWidgetState', {
        'title': _sanitize(title, 80),
        'subtitle': _sanitize(subtitle, 140),
      });
      return result == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  String _sanitize(String value, int maxLength) {
    final compact = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.length <= maxLength) return compact;
    return '${compact.substring(0, maxLength - 1)}…';
  }
}
