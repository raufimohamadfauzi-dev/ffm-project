import 'dart:async';

import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart';

class ActivitySpeechService {
  ActivitySpeechService({SpeechToText? recognizer})
    : _recognizer = recognizer ?? SpeechToText() {
    _installTtsStateHandler();
  }

  final SpeechToText _recognizer;
  final ActivitySpeechFinalGate _finalGate = ActivitySpeechFinalGate();
  static const _ttsChannel = MethodChannel('ffm/activity_speech');
  static final _ttsStates =
      StreamController<ActivitySpeechPlaybackState>.broadcast();
  static var _ttsStateHandlerInstalled = false;

  static void _installTtsStateHandler() {
    if (_ttsStateHandlerInstalled) return;
    _ttsStateHandlerInstalled = true;
    _ttsChannel.setMethodCallHandler((call) async {
      if (call.method != 'ttsState') return;
      final arguments = Map<Object?, Object?>.from(call.arguments as Map);
      _ttsStates.add(ActivitySpeechPlaybackState.fromPlatformMap(arguments));
    });
  }

  bool get isListening => _recognizer.isListening;
  Stream<ActivitySpeechPlaybackState> get playbackStates => _ttsStates.stream;

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
    final session = _finalGate.begin();
    await _recognizer.listen(
      onResult: (result) {
        if (!_finalGate.accept(
          session: session,
          text: result.recognizedWords,
          isFinal: result.finalResult,
        )) {
          return;
        }
        onResult(result.recognizedWords, result.finalResult);
      },
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

  Future<void> stop() async {
    _finalGate.invalidate();
    await _recognizer.stop();
  }

  Future<void> cancel() async {
    _finalGate.invalidate();
    await _recognizer.cancel();
  }

  Future<String?> speak(String text) async {
    if (text.trim().isEmpty) return null;
    final sessionId = 'ffm-tts-${DateTime.now().microsecondsSinceEpoch}';
    final accepted =
        await _ttsChannel.invokeMethod<bool>('speak', {
          'text': text,
          'sessionId': sessionId,
        }) ??
        false;
    return accepted ? sessionId : null;
  }

  Future<void> stopSpeaking({String? sessionId}) =>
      _ttsChannel.invokeMethod<void>('stop', {
        if (sessionId != null) 'sessionId': sessionId,
      });

  Future<void> cancelSpeaking() => _ttsChannel.invokeMethod<void>('cancel');

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

class ActivitySpeechFinalGate {
  int _generation = 0;
  int? _acceptedFinalGeneration;
  String? _acceptedFinalFingerprint;

  int begin() {
    _generation += 1;
    _acceptedFinalGeneration = null;
    _acceptedFinalFingerprint = null;
    return _generation;
  }

  bool accept({
    required int session,
    required String text,
    required bool isFinal,
  }) {
    if (session != _generation) return false;
    if (!isFinal) return true;
    final fingerprint = _canonicalize(text);
    if (fingerprint.isEmpty || _acceptedFinalGeneration == session) {
      return false;
    }
    _acceptedFinalGeneration = session;
    _acceptedFinalFingerprint = fingerprint;
    return true;
  }

  String? get acceptedFinalFingerprint => _acceptedFinalFingerprint;

  String _canonicalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  void invalidate() {
    _generation += 1;
    _acceptedFinalGeneration = null;
    _acceptedFinalFingerprint = null;
  }
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

enum ActivitySpeechPlaybackStatus { started, stopped, completed, error }

class ActivitySpeechPlaybackState {
  const ActivitySpeechPlaybackState({
    required this.sessionId,
    required this.status,
  });

  factory ActivitySpeechPlaybackState.fromPlatformMap(
    Map<Object?, Object?> map,
  ) {
    final rawStatus = map['status'] as String? ?? '';
    final status = switch (rawStatus) {
      'started' => ActivitySpeechPlaybackStatus.started,
      'stopped' => ActivitySpeechPlaybackStatus.stopped,
      'completed' => ActivitySpeechPlaybackStatus.completed,
      _ => ActivitySpeechPlaybackStatus.error,
    };
    return ActivitySpeechPlaybackState(
      sessionId: map['sessionId'] as String? ?? '',
      status: status,
    );
  }

  final String sessionId;
  final ActivitySpeechPlaybackStatus status;
}
