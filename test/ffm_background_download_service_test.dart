import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/features/assistant/data/ffm_background_download_service.dart';
import 'package:ffm_manager/features/assistant/data/ffm_staging_status.dart';

void main() {
  test('memetakan status download selesai beserta path lokal', () {
    final status = FfmBackgroundDownloadStatus.fromMap({
      'role': 'language_model',
      'fileName': 'model.gguf',
      'state': 'complete',
      'receivedBytes': 100,
      'totalBytes': 100,
      'localPath': '/data/user/0/ffm/model.gguf',
      'downloadManagerUri': 'file:///data/user/0/ffm/model.gguf',
      'pathSource': 'download_manager_local_uri',
      'pathMismatch': false,
      'diskBytes': 100,
      'parentExists': true,
    });

    expect(status.role, 'language_model');
    expect(status.isComplete, isTrue);
    expect(status.isFailed, isFalse);
    expect(status.fraction, 1);
    expect(status.localPath, '/data/user/0/ffm/model.gguf');
    expect(status.downloadManagerUri, 'file:///data/user/0/ffm/model.gguf');
    expect(status.pathSource, 'download_manager_local_uri');
    expect(status.pathMismatch, isFalse);
    expect(status.diskBytes, 100);
    expect(status.parentExists, isTrue);
  });

  test('status gagal menyimpan alasan dan tidak dianggap selesai', () {
    final status = FfmBackgroundDownloadStatus.fromMap({
      'role': 'multimodal_projector',
      'fileName': 'projector.gguf',
      'state': 'failed',
      'reason': 'Kode DownloadManager 1006',
    });

    expect(status.isFailed, isTrue);
    expect(status.isComplete, isFalse);
    expect(status.reason, 'Kode DownloadManager 1006');
    expect(status.fraction, isNull);
  });

  test('file selesai yang sudah ada di staging tidak diimpor ulang', () {
    const status = FfmBackgroundDownloadStatus(
      role: 'multimodal_projector',
      fileName: 'mmproj.gguf',
      state: 'complete',
      localPath: '/storage/emulated/0/Android/data/ffm/mmproj.gguf',
    );
    const staging = FfmStagingStatus(hasModel: true, hasProjector: true);

    expect(status.isAlreadyInStaging(staging), isTrue);
    expect(status.needsStagingImport(staging), isFalse);
  });

  test(
    'metadata menandai fallback manual dan mismatch path untuk diagnostik',
    () {
      final status = FfmBackgroundDownloadStatus.fromMap({
        'role': 'language_model',
        'fileName': 'model.gguf',
        'state': 'complete',
        'localPath': '/fallback/model.gguf',
        'pathSource': 'manual_destination_fallback',
        'pathMismatch': true,
      });

      expect(status.pathSource, 'manual_destination_fallback');
      expect(status.pathMismatch, isTrue);
    },
  );
}
