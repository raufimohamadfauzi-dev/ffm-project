import 'dart:async';

import 'ffm_assistant_memory_repository.dart';
import 'ffm_memory_learning_service.dart';

/// Perawatan berkala memori asisten.
///
/// Menjadwalkan [FfmMemoryLearningService.applyMemoryDecay] sekali saat
/// aplikasi siap lalu berulang setiap 24 jam selama aplikasi hidup. Aturan
/// decay tetap miliki learning service: memori >180 hari yang jarang dipakai
/// dan tidak penting diarsipkan secara lunak; goal dan memori penting selamat.
class FfmMemoryMaintenanceService {
  FfmMemoryMaintenanceService({
    required FfmMemoryLearningService learning,
    required FfmAssistantMemoryRepository repository,
  }) {
    _learning = learning;
    _repository = repository;
  }

  late final FfmMemoryLearningService _learning;
  late final FfmAssistantMemoryRepository _repository;

  Timer? _timer;
  bool _running = false;
  bool _disposed = false;

  /// Menjalankan satu siklus decay sekarang. Idempoten: pemanggilan ganda
  /// saat siklus berjalan akan diabaikan.
  Future<void> runDecayOnce() async {
    if (_running || _disposed) return;
    _running = true;
    try {
      await _learning.applyMemoryDecay(repository: _repository);
    } on Object {
      // Pemeliharaan bersifat best-effort; jangan ganggu aplikasi.
    } finally {
      _running = false;
    }
  }

  /// Mulai jadwal pemeliharaan. Aman dipanggil ulang — jadwal sebelumnya
  /// digantikan, bukan diduplikasi.
  void start({
    Duration initialDelay = const Duration(seconds: 30),
    Duration interval = const Duration(hours: 24),
  }) {
    if (_disposed) return;
    stop();
    _timer = Timer(initialDelay, () {
      unawaited(runDecayOnce());
      _timer = Timer.periodic(interval, (_) => unawaited(runDecayOnce()));
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    _disposed = true;
    stop();
  }
}
