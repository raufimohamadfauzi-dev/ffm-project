import 'package:flutter/services.dart';

class ReminderSoundSelection {
  const ReminderSoundSelection({required this.uri, required this.name});

  final String uri;
  final String name;
}

abstract interface class ReminderSoundPicker {
  Future<ReminderSoundSelection?> pick({String? currentUri});
}

class AndroidReminderSoundPicker implements ReminderSoundPicker {
  AndroidReminderSoundPicker({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('ffm/reminder_sound');

  final MethodChannel _channel;

  @override
  Future<ReminderSoundSelection?> pick({String? currentUri}) async {
    final result = await _channel.invokeMethod<Object?>('pick', {
      'currentUri': currentUri,
    });
    if (result == null) return null;
    if (result is String && result.trim().isNotEmpty) {
      return ReminderSoundSelection(uri: result, name: 'Nada pilihan');
    }
    if (result is Map) {
      final uri = '${result['uri'] ?? ''}'.trim();
      if (uri.isEmpty) return null;
      final name = '${result['name'] ?? ''}'.trim();
      return ReminderSoundSelection(
        uri: uri,
        name: name.isEmpty ? 'Nada pilihan' : name,
      );
    }
    return null;
  }
}
