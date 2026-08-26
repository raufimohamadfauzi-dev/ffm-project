import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/features/assistant/data/ffm_local_model_service.dart';
import 'package:ffm_manager/features/assistant/data/ffm_staging_status.dart';

class _ExportFixtureService extends FfmLocalModelService {
  _ExportFixtureService(this.info)
      : super(applicationSupportDirectory: () async => Directory.systemTemp);

  final FfmLocalModelInfo info;

  @override
  Future<FfmLocalModelInfo?> verifyInstalled() async => info;
}

void main() {
  group('FfmQwen2VlBundle text-only', () {
    test('hanya mengunci satu aset language model', () {
      expect(FfmQwen2VlBundle.files, hasLength(1));
      expect(FfmQwen2VlBundle.files.single.role, 'language_model');
      expect(FfmQwen2VlBundle.files.single.fileName,
          FfmQwen2VlBundle.modelFileName);
      expect(FfmQwen2VlBundle.modelBytes, 936329984);
      expect(FfmQwen2VlBundle.modelSha256,
          '7df01d764cbb22ce270cd09eb2ff483f7161fcb42b80ea9a93e99d8de4b815e8');
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
  });

  group('FfmStagingStatus', () {
    test('model tunggal menentukan kesiapan staging', () {
      expect(const FfmStagingStatus(hasModel: false).isEmpty, isTrue);
      expect(const FfmStagingStatus(hasModel: false).isReadyToCommit, isFalse);
      expect(const FfmStagingStatus(hasModel: true).isEmpty, isFalse);
      expect(const FfmStagingStatus(hasModel: true).isReadyToCommit, isTrue);
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

    test('hash membaca file secara streaming', () async {
      final file = File('${root.path}/sample.bin');
      await file.writeAsBytes(
        List<int>.generate(700000, (index) => index % 251),
      );

      expect(
        await service.checksum(file),
        'f101963580e7deb59f09073f328223c0f1311e93fddc2b4b1c6b6037590dd5a1',
      );
    });

    test('staging kosong tidak dapat dirakit', () async {
      final status = await service.getStagingStatus();
      expect(status.hasModel, isFalse);
      expect(status.isEmpty, isTrue);
      expect(status.isReadyToCommit, isFalse);
      await expectLater(
        service.commitStaging(),
        throwsA(isA<FfmLocalModelManifestException>()),
      );
    });

    test('export bundle hanya berisi manifest dan model teks', () async {
      final model = File('${root.path}/model.gguf')..writeAsStringSync('model');
      final manifest = File('${root.path}/verified_manifest.json')
        ..writeAsStringSync(jsonEncode({'verificationStatus': 'verified'}));
      final exportService = _ExportFixtureService(
        FfmLocalModelInfo(
          fileName: FfmQwen2VlBundle.modelFileName,
          filePath: model.path,
          bytes: model.lengthSync(),
          sha256: FfmQwen2VlBundle.modelSha256,
          installedAt: DateTime.utc(2026, 8, 22),
          manifestPath: manifest.path,
        ),
      );

      final output = await exportService.exportVerifiedBundle(
        outputDirectory: Directory('${root.path}/exports'),
      );
      final archive = ZipDecoder().decodeBytes(await output.readAsBytes());
      final names = archive.files.map((file) => file.name).toSet();

      expect(output.path, endsWith('.ffmbundle'));
      expect(names, contains(FfmQwen2VlBundle.manifestFileName));
      expect(names, contains(FfmQwen2VlBundle.modelFileName));
      expect(names.where((name) => name.contains('mmproj')), isEmpty);
      expect(names.where((name) => name.contains('projector')), isEmpty);
    });

    test('file background yang tidak dikenal ditolak', () async {
      final file = File('${root.path}/foreign.gguf')
        ..writeAsStringSync('bukan model resmi');

      await expectLater(
        service.importGgufFromPath(
          file.path,
          expectedBytes: file.lengthSync(),
          retryAttempts: 1,
          retryDelay: Duration.zero,
        ),
        throwsA(isA<FfmLocalModelManifestException>()),
      );
    });
  });
}
