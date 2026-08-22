import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart';

class ActivitySpeechService {
  ActivitySpeechService({SpeechToText? recognizer})
    : _recognizer = recognizer ?? SpeechToText();

  final SpeechToText _recognizer;
  static const _ttsChannel = MethodChannel('ffm/activity_speech');

  bool get isListening => _recognizer.isListening;

  Future<bool> initialize({
    required void Function(String message) onError,
    void Function(String status)? onStatus,
  }) => _recognizer.initialize(
    onError: (error) => onError(error.errorMsg),
    onStatus: onStatus,
  );

  Future<void> listen({
    required void Function(String text, bool isFinal) onResult,
    void Function(double level)? onSoundLevel,
  }) async {
    await _recognizer.listen(
      onResult: (result) =>
          onResult(result.recognizedWords, result.finalResult),
      onSoundLevelChange: onSoundLevel,
      listenOptions: SpeechListenOptions(
        partialResults: true,
        listenMode: ListenMode.dictation,
        pauseFor: Duration(seconds: 3),
        listenFor: Duration(seconds: 30),
        cancelOnError: true,
      ),
    );
  }

  Future<void> stop() => _recognizer.stop();

  Future<void> cancel() => _recognizer.cancel();

  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    await _ttsChannel.invokeMethod<void>('speak', {'text': text});
  }

  Future<void> stopSpeaking() => _ttsChannel.invokeMethod<void>('stop');

  Future<bool> resumeSpeaking() async =>
      await _ttsChannel.invokeMethod<bool>('resume') ?? false;

  Future<bool> isSpeaking() async =>
      await _ttsChannel.invokeMethod<bool>('isSpeaking') ?? false;

  Future<List<ActivitySpeechVoice>> availableVoices() async {
    final voices = await _ttsChannel.invokeListMethod<Map<Object?, Object?>>(
      'voices',
    );
    return (voices ?? const [])
        .map(ActivitySpeechVoice.fromPlatformMap)
        .where((voice) => voice.name.isNotEmpty)
        .toList(growable: false);
  }

  Future<String?> selectedVoiceName() =>
      _ttsChannel.invokeMethod<String>('selectedVoice');

  Future<bool> selectVoice(String name) async =>
      await _ttsChannel.invokeMethod<bool>('selectVoice', {'name': name}) ??
      false;
}

class ActivitySpeechVoice {
  const ActivitySpeechVoice({
    required this.name,
    required this.locale,
    required this.quality,
  });

  factory ActivitySpeechVoice.fromPlatformMap(Map<Object?, Object?> map) =>
      ActivitySpeechVoice(
        name: map['name'] as String? ?? '',
        locale: map['locale'] as String? ?? 'id-ID',
        quality: map['quality'] as String? ?? '',
      );

  final String name;
  final String locale;
  final String quality;

  String get label => quality.isEmpty ? name : '$name • $quality';
}
