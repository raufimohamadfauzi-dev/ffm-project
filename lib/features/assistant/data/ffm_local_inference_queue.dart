import 'dart:async';

import '../domain/ffm_assistant_execution_limits.dart';

class FfmInferenceCancelledException implements Exception {
  const FfmInferenceCancelledException();

  @override
  String toString() => 'FfmInferenceCancelledException';
}

class FfmInferenceCancellationToken {
  var _cancelled = false;

  bool get isCancelled => _cancelled;

  /// Aman dipanggil berkali-kali; pembatalan tidak menghidupkan kembali request.
  void cancel() => _cancelled = true;

  void throwIfCancelled() {
    if (_cancelled) throw const FfmInferenceCancelledException();
  }
}

class FfmInferenceRequest<T> {
  const FfmInferenceRequest({
    required this.future,
    required void Function() cancel,
  }) : _cancel = cancel;

  final Future<T> future;
  final void Function() _cancel;

  /// Membatalkan request yang belum dimulai atau memberi sinyal ke operasi yang
  /// sedang berjalan. Native callback tetap wajib mengecek token.
  void cancel() => _cancel();
}

/// Serialisasi seluruh request teks/visi. Callback native harus memakai token
/// dan melepas context/pointer/bitmap pada jalur sukses, error, maupun batal.
class FfmSingleInferenceQueue {
  Future<void> _tail = Future<void>.value();
  var _activeCount = 0;
  var _sequence = 0;

  int get activeCount => _activeCount;
  int get queuedCount => _sequence;
  bool get isBusy => _activeCount > 0 || _sequence > 0;

  FfmInferenceRequest<T> enqueueRequest<T>(
    Future<T> Function(FfmInferenceCancellationToken token) operation,
  ) {
    final token = FfmInferenceCancellationToken();
    final requestNumber = ++_sequence;
    final scheduled = _tail.then<T>((_) async {
      var active = false;
      try {
        token.throwIfCancelled();
        if (_activeCount >=
            FfmAssistantExecutionLimits.maxConcurrentInference) {
          throw StateError('Maksimal satu inferensi lokal boleh aktif.');
        }
        _activeCount++;
        active = true;
        final result = await operation(token);
        // Native JNI generation may be non-interruptible; discard its result
        // if cancellation arrived while it was running.
        token.throwIfCancelled();
        return result;
      } finally {
        if (active) _activeCount--;
        _sequence--;
      }
    });

    // Error request sebelumnya tidak boleh memblokir request berikutnya.
    _tail = scheduled.then<void>((_) {}, onError: (Object _) {});

    // ID hanya untuk inspeksi/debugging; tidak pernah diberikan ke model.
    assert(requestNumber > 0);
    return FfmInferenceRequest(future: scheduled, cancel: token.cancel);
  }

  Future<T> enqueue<T>(
    Future<T> Function(FfmInferenceCancellationToken token) operation,
  ) => enqueueRequest(operation).future;
}
