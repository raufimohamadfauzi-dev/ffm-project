import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'bridge Android memakai COLUMN_LOCAL_URI sebelum fallback path manual',
    () {
      final source = File(
        'android/app/src/main/kotlin/com/ffm_manager/FfmLocalModelBridgePlugin.kt',
      ).readAsStringSync();

      expect(source, contains('DownloadManager.COLUMN_LOCAL_URI'));
      expect(source, contains('fileFromDownloadManagerUri'));
      expect(source, contains('val file = uriFile ?: fallbackFile'));
      expect(source, contains('"download_manager_local_uri"'));
      expect(source, contains('"manual_destination_fallback"'));
    },
  );
}
