import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AppShell melindungi indikator Asisten dengan SafeArea atas saja', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(source, contains('body: SafeArea('));
    expect(source, contains('bottom: false,'));
    expect(
      source.indexOf('body: SafeArea('),
      lessThan(source.indexOf('FfmAgentStatusIndicator')),
    );
  });
}
