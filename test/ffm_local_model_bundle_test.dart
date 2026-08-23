import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/features/assistant/data/ffm_local_model_service.dart';

Future<File> _makeBundle(
  Directory directory, {
  required Map<String, dynamic> manifest,
  bool includeModel = false,
  String? unsafeName,
}) async {
  final file = File('${directory.path}/test.ffmbundle');
  final encoder = ZipFileEncoder()
    ..create(file.path, level: ZipFileEncoder.STORE);
  await encoder.addFile(
    File('${directory.path}/manifest.json')
      ..writeAsStringSync(jsonEncode(manifest)),
    FfmQwen2VlBundle.manifestFileName,
    ZipFileEncoder.STORE,
  );
  if (includeModel) {
    final model = File('${directory.path}/small.bin')
      ..writeAsBytesSync([1, 2, 3]);
    await encoder.addFile(
      model,
      unsafeName ?? FfmQwen2VlBundle.modelFileName,
      ZipFileEncoder.STORE,
    );
  }
  await encoder.close();
  return file;
}

void main() {
  late Directory root;
  late FfmLocalModelService service;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ffm-bundle-test-');
    service = FfmLocalModelService(
      applicationSupportDirectory: () async => root,
    );
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('menolak bundle yang tidak memiliki dua aset GGUF wajib', () async {
    final bundle = await _makeBundle(
      root,
      manifest: {
        'formatVersion': 'ffm-verified-model-manifest-v1',
        'bundleId': FfmQwen2VlBundle.bundleId,
      },
    );

    expect(
      () => service.importBundle(bundle),
      throwsA(isA<FfmLocalModelManifestException>()),
    );
  });

  test('menolak entry ZIP dengan path traversal', () async {
    final bundle = await _makeBundle(
      root,
      manifest: {'formatVersion': 'invalid'},
      includeModel: true,
      unsafeName: '../outside.gguf',
    );

    expect(
      () => service.importBundle(bundle),
      throwsA(isA<FfmLocalModelManifestException>()),
    );
    expect(await File('${root.parent.path}/outside.gguf').exists(), isFalse);
  });
}
