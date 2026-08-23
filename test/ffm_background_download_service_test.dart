import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/features/assistant/data/ffm_background_download_service.dart';

void main() {
  test('memetakan status download selesai beserta path lokal', () {
    final status = FfmBackgroundDownloadStatus.fromMap({
      'role': 'language_model',
      'fileName': 'model.gguf',
      'state': 'complete',
      'receivedBytes': 100,
      'totalBytes': 100,
      'localPath': '/data/user/0/ffm/model.gguf',
    });

    expect(status.role, 'language_model');
    expect(status.isComplete, isTrue);
    expect(status.isFailed, isFalse);
    expect(status.fraction, 1);
    expect(status.localPath, '/data/user/0/ffm/model.gguf');
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
}
