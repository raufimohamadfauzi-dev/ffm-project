import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('manifest memiliki permission jaringan untuk fitur online', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(manifest, contains('android.permission.INTERNET'));
  });

  test('manifest mempertahankan exact alarm untuk reminder internal FFM', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(manifest, contains('android.permission.SCHEDULE_EXACT_ALARM'));
  });
}
