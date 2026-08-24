import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('halaman model menampilkan tahap dan tindakan pemulihan rakit', () {
    final source = File(
      'lib/features/assistant/presentation/pages/local_model_page.dart',
    ).readAsStringSync();

    expect(source, contains('Memverifikasi Model GGUF...'));
    expect(source, contains('Memverifikasi Projector GGUF...'));
    expect(source, contains('Tahap 1 dari 2'));
    expect(source, contains('Tahap 2 dari 2'));
    expect(source, contains('Jangan tutup atau tinggalkan halaman ini'));
    expect(source, contains('Buka Asisten'));
    expect(source, contains('Lihat Detail Teknis'));
  });
}
