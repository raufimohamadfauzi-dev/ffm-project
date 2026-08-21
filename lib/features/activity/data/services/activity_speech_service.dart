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
}
