import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Layanan Text-to-Speech (TTS) untuk asisten suara cerdas pada pengingat / alarm.
/// Membacakan judul dan catatan pengingat dalam bahasa Indonesia saat alarm berdering.
class ReminderTtsService {
  ReminderTtsService({FlutterTts? tts}) : _tts = tts ?? FlutterTts() {
    _init();
  }

  final FlutterTts _tts;
  bool _isInitialized = false;
  VoidCallback? _onCompletion;

  void setOnCompletionHandler(VoidCallback? callback) {
    _onCompletion = callback;
  }

  Future<void> _init() async {
    if (_isInitialized) return;
    try {
      await _tts.setLanguage('id-ID');
      await _tts.setSpeechRate(0.48);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      _tts.setCompletionHandler(() {
        _onCompletion?.call();
      });
      _tts.setCancelHandler(() {
        _onCompletion?.call();
      });
      _tts.setErrorHandler((_) {
        _onCompletion?.call();
      });
      _isInitialized = true;
    } on Object catch (e) {
      debugPrint('ReminderTtsService init warning: $e');
    }
  }

  /// Membacakan teks secara bebas dalam bahasa Indonesia.
  Future<void> speak(String text) async {
    try {
      await _init();
      final cleanText = _cleanTextForSpeech(text);
      if (cleanText.isEmpty) {
        _onCompletion?.call();
        return;
      }
      await _tts.speak(cleanText);
    } on Object catch (e) {
      debugPrint('ReminderTtsService speak error: $e');
      _onCompletion?.call();
    }
  }

  /// Membacakan pengingat secara terstruktur: Judul dan Catatan.
  Future<void> speakReminder({
    required String title,
    String? note,
    bool isUrgentAlarm = false,
  }) async {
    final prefix = isUrgentAlarm
        ? 'Perhatian, alarm pengingat:'
        : 'Pengingat:';
    final buffer = StringBuffer('$prefix ${_cleanTextForSpeech(title)}.');
    if (note != null && note.trim().isNotEmpty) {
      final cleanNote = _cleanTextForSpeech(note);
      if (!cleanNote.contains('FLUTTER_') && !cleanNote.contains('Exception')) {
        buffer.write(' Catatan: $cleanNote.');
      }
    }
    await speak(buffer.toString());
  }

  /// Menghentikan suara pembacaan.
  Future<void> stop() async {
    try {
      await _tts.stop();
    } on Object catch (e) {
      debugPrint('ReminderTtsService stop error: $e');
    }
  }

  /// Membersihkan karakter markdown atau format teknis agar pelafalan TTS terdengar wajar.
  String _cleanTextForSpeech(String raw) {
    return raw
        .replaceAll(RegExp(r'\*\*|\*|__|#|_|`'), '')
        .replaceAll(RegExp(r'\s*\|\s*'), ', ')
        .replaceAll(RegExp(r'[\r\n]+'), ' ')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
  }
}
