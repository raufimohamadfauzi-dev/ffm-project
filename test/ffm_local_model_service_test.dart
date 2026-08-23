import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/features/assistant/data/ffm_local_model_service.dart';
import 'package:ffm_manager/features/assistant/data/ffm_staging_status.dart';

void main() {
  group('FfmQwen2VlBundle', () {
    test('mengunci aset dan hash hasil Fase 0', () {
      expect(FfmQwen2VlBundle.bundleId, 'qwen2-vl-2b-instruct-iq4-nl-v1');
      expect(FfmQwen2VlBundle.files, hasLength(2));
      expect(FfmQwen2VlBundle.modelBytes, 936329984);
      expect(FfmQwen2VlBundle.projectorBytes, 1331656192);
      expect(
        FfmQwen2VlBundle.modelSha256,
        '7df01d764cbb22ce270cd09eb2ff483f7161fcb42b80ea9a93e99d8de4b815e8',
      );
      expect(
        FfmQwen2VlBundle.projectorSha256,
        '05cc3ae461a7b6aa4023312ccab549ecab77cf8677efee04f049fcbab55b8bc3',
      );
    });

    test('progress menghitung fraction tanpa membagi nol', () {
      expect(
        const FfmModelProgress(
          fileName: 'model.gguf',
          receivedBytes: 25,
          totalBytes: 100,
        ).fraction,
        .25,
      );
      expect(
        const FfmModelProgress(
          fileName: 'model.gguf',
          receivedBytes: 0,
          totalBytes: 0,
        ).fraction,
        isNull,
      );
    });

    test('error DNS menawarkan coba lagi tanpa memaksa mulai ulang', () {
      const error = FfmLocalModelDownloadException(
        'Tidak bisa menghubungi GitHub dari HP ini.',
        canRetry: true,
      );

      expect(error.canRetry, isTrue);
      expect(error.canRestart, isFalse);
    });
  });

  group('FfmStagingStatus', () {
    test('status logika isReadyToCommit dan isEmpty', () {
      expect(
        const FfmStagingStatus(hasModel: false, hasProjector: false).isEmpty,
        isTrue,
      );
      expect(
        const FfmStagingStatus(
          hasModel: false,
          hasProjector: false,
        ).isReadyToCommit,
        isFalse,
      );

      expect(
        const FfmStagingStatus(hasModel: true, hasProjector: false).isEmpty,
        isFalse,
      );
      expect(
        const FfmStagingStatus(
          hasModel: true,
          hasProjector: false,
        ).isReadyToCommit,
        isFalse,
      );

      expect(
        const FfmStagingStatus(hasModel: true, hasProjector: true).isEmpty,
        isFalse,
      );
      expect(
        const FfmStagingStatus(
          hasModel: true,
          hasProjector: true,
        ).isReadyToCommit,
        isTrue,
      );
    });
  });

  group('FfmLocalModelService', () {
    late Directory root;
    late FfmLocalModelService service;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('ffm-model-test-');
      service = FfmLocalModelService(
        applicationSupportDirectory: () async => root,
        clock: () => DateTime.utc(2026, 8, 22, 12),
      );
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('hash membaca file dan menghasilkan SHA-256 yang benar', () async {
      final file = File('${root.path}/sample.bin');
      await file.writeAsBytes(
        List<int>.generate(700000, (index) => index % 251),
      );

      final digest = await service.checksum(file);

      expect(
        digest,
        'f101963580e7deb59f09073f328223c0f1311e93fddc2b4b1c6b6037590dd5a1',
      );
    });

    test('model belum siap tanpa manifest verified', () async {
      expect(await service.getInstalled(), isNull);
      expect(
        await service.matchesSha256(FfmQwen2VlBundle.modelSha256),
        isFalse,
      );
    });

    test('commitStaging menolak jika file di staging belum lengkap', () async {
      final status = await service.getStagingStatus();
      expect(status.isEmpty, isTrue);
      expect(
        () => service.commitStaging(),
        throwsA(isA<FfmLocalModelManifestException>()),
      );
    });

    test(
      'manifest dengan hash, header, atau bundle yang tidak cocok ditolak',
      () async {
        final finalDirectory = Directory(
          '${root.path}/models/qwen2-vl/${FfmQwen2VlBundle.bundleId}',
        )..createSync(recursive: true);
        final model = File(
          '${finalDirectory.path}/${FfmQwen2VlBundle.modelFileName}',
        )..writeAsStringSync('not-a-gguf');
        final projector = File(
          '${finalDirectory.path}/${FfmQwen2VlBundle.projectorFileName}',
        )..writeAsStringSync('not-a-gguf');
        final manifest = {
          'formatVersion': 'ffm-verified-model-manifest-v1',
          'bundleId': FfmQwen2VlBundle.bundleId,
          'bundleVersion': FfmQwen2VlBundle.bundleVersion,
          'modelFamily': FfmQwen2VlBundle.modelFamily,
          'verificationStatus': 'verified',
          'verifiedAtUtc': '2026-08-22T12:00:00Z',
          'files': [
            {
              'role': 'language_model',
              'fileName': model.uri.pathSegments.last,
              'expectedSha256': FfmQwen2VlBundle.modelSha256,
              'actualSha256': FfmQwen2VlBundle.modelSha256,
              'actualSizeBytes': '${model.lengthSync()}',
              'ggufHeaderVerified': true,
            },
            {
              'role': 'multimodal_projector',
              'fileName': projector.uri.pathSegments.last,
              'expectedSha256': FfmQwen2VlBundle.projectorSha256,
              'actualSha256': FfmQwen2VlBundle.projectorSha256,
              'actualSizeBytes': '${projector.lengthSync()}',
              'ggufHeaderVerified': true,
            },
          ],
        };
        File('${finalDirectory.path}/${FfmQwen2VlBundle.manifestFileName}')
            .writeAsStringSync(
              const JsonEncoder.withIndent('  ').convert(manifest),
            );

        expect(await service.getInstalled(), isNull);
      },
    );
  });
}
