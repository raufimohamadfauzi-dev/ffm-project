import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/features/assistant/data/ffm_background_download_service.dart';
import 'package:ffm_manager/features/assistant/data/ffm_local_model_readiness.dart';
import 'package:ffm_manager/features/assistant/data/ffm_staging_status.dart';

void main() {
  test('status staging lengkap mengarahkan pengguna merakit SLM', () {
    final info = FfmLocalModelReadiness.resolve(
      model: null,
      staging: const FfmStagingStatus(hasModel: true, hasProjector: true),
      backgroundStatuses: const [],
    );

    expect(info.state, FfmLocalModelReadinessState.stagingReady);
    expect(info.nextStep, contains('Rakit dan Pasang SLM'));
    expect(info.canUseAssistant, isFalse);
  });

  test('staging lengkap tetap diprioritaskan setelah dua download selesai', () {
    final info = FfmLocalModelReadiness.resolve(
      model: null,
      staging: const FfmStagingStatus(hasModel: true, hasProjector: true),
      backgroundStatuses: const [
        FfmBackgroundDownloadStatus(
          role: 'language_model',
          fileName: 'model.gguf',
          state: 'complete',
        ),
        FfmBackgroundDownloadStatus(
          role: 'multimodal_projector',
          fileName: 'projector.gguf',
          state: 'complete',
        ),
      ],
    );

    expect(info.state, FfmLocalModelReadinessState.stagingReady);
    expect(info.nextStep, contains('Rakit dan Pasang SLM'));
  });

  test('status download background memberi tindakan perbarui status', () {
    final info = FfmLocalModelReadiness.resolve(
      model: null,
      staging: const FfmStagingStatus(hasModel: false, hasProjector: false),
      backgroundStatuses: const [
        FfmBackgroundDownloadStatus(
          role: 'model',
          fileName: 'model.gguf',
          state: 'running',
          receivedBytes: 1,
          totalBytes: 2,
        ),
      ],
    );

    expect(info.state, FfmLocalModelReadinessState.downloadingBackground);
    expect(info.nextStep, contains('Perbarui status'));
  });

  test('status gagal memberi jalur jaringan atau impor offline', () {
    final info = FfmLocalModelReadiness.resolve(
      model: null,
      staging: const FfmStagingStatus(hasModel: false, hasProjector: false),
      backgroundStatuses: const [
        FfmBackgroundDownloadStatus(
          role: 'projector',
          fileName: 'mmproj.gguf',
          state: 'failed',
          reason: 'DNS gagal',
        ),
      ],
    );

    expect(info.state, FfmLocalModelReadinessState.downloadFailed);
    expect(info.message, 'DNS gagal');
    expect(info.nextStep, contains('impor bundle offline'));
  });
}
