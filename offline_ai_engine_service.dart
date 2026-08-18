class OfflineTranscriptionResult {
  const OfflineTranscriptionResult({this.text = ''});
  final String text;
}

class OfflineAiEngineService {
  bool get isWhisperReady => false;
  bool get isWhisperRecording => false;

  Future<bool> startWhisperRecording() async => false;

  Future<OfflineTranscriptionResult> stopWhisperRecording() async =>
      const OfflineTranscriptionResult();

  Future<void> cancelWhisperRecording() async {}
}
