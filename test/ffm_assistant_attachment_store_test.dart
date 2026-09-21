import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/features/assistant/data/ffm_assistant_attachment_store.dart';

void main() {
  test(
    'menyimpan salinan attachment di folder privat dan membersihkannya',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'ffm-attachment-test-',
      );
      addTearDown(() => root.delete(recursive: true));
      final store = FfmAssistantAttachmentStore(
        directoryProvider: () async => root,
      );
      final original = File('${root.path}${Platform.pathSeparator}gallery.jpg');
      await original.writeAsBytes([9, 8, 7]);

      final managedPath = await store.save(
        Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/jpeg',
      );
      expect(await File(managedPath).readAsBytes(), [1, 2, 3]);

      await store.deleteManagedPaths([managedPath, original.path]);

      expect(await File(managedPath).exists(), isFalse);
      expect(await original.exists(), isTrue);
    },
  );
}
