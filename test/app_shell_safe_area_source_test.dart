import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AppShell melindungi layar utama dengan SafeArea atas saja', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(source, contains('body: SafeArea('));
    expect(source, contains('bottom: false,'));
  });
}
