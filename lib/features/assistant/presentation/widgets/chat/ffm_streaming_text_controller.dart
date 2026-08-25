import 'dart:async';

/// Menampilkan teks secara bertahap (progressive reveal) untuk simulasi streaming.
///
/// Digunakan oleh chat UI untuk menampilkan response SLM seolah-olah streaming,
/// padahal teks sudah lengkap dari native bridge.
class FfmStreamingTextController {
  FfmStreamingTextController({
    this.charsPerTick = 3,
    this.tickInterval = const Duration(milliseconds: 30),
  });

  final int charsPerTick;
  final Duration tickInterval;

  String _fullText = '';
  int _currentIndex = 0;
  Timer? _timer;
  bool _isStreaming = false;

  /// Stream yang emit teks saat reveal.
  final StreamController<String> _textController =
      StreamController<String>.broadcast();
  Stream<String> get textStream => _textController.stream;

  /// Current visible text.
  String get currentText =>
      _fullText.isEmpty ? '' : _fullText.substring(0, _currentIndex);

  /// Whether streaming is in progress.
  bool get isStreaming => _isStreaming;

  /// Whether all text has been revealed.
  bool get isComplete => _currentIndex >= _fullText.length;

  /// Start streaming fullText ke listener.
  void startStreaming(String fullText) {
    stop();
    _fullText = fullText;
    _currentIndex = 0;
    _isStreaming = true;

    _textController.add('');

    if (fullText.isEmpty) {
      _isStreaming = false;
      _textController.add('');
      return;
    }

    _timer = Timer.periodic(tickInterval, (_) {
      _advance();
    });
  }

  void _advance() {
    if (_currentIndex >= _fullText.length) {
      _isStreaming = false;
      _timer?.cancel();
      _timer = null;
      _textController.add(currentText);
      return;
    }

    _currentIndex = (_currentIndex + charsPerTick).clamp(
      0,
      _fullText.length,
    );

    _textController.add(currentText);

    if (_currentIndex >= _fullText.length) {
      _isStreaming = false;
      _timer?.cancel();
      _timer = null;
    }
  }

  /// Skip langsung ke full text (reveal semua sekaligus).
  void skipToEnd() {
    _timer?.cancel();
    _timer = null;
    _currentIndex = _fullText.length;
    _isStreaming = false;
    _textController.add(currentText);
  }

  /// Stop streaming dan reset.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _isStreaming = false;
    _currentIndex = 0;
    _fullText = '';
  }

  /// Dispose resources.
  void dispose() {
    stop();
    _textController.close();
  }
}
