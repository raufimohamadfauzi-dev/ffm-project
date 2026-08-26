import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('halaman model menampilkan tahap dan tindakan pemulihan rakit', () {
    final source = File(
      'lib/features/assistant/presentation/pages/local_model_page.dart',
    ).readAsStringSync();

    expect(source, contains('Memverifikasi Model GGUF...'));
    expect(source, contains('Tahap 1 dari 1'));
    expect(source, contains('Jangan tutup atau tinggalkan halaman ini'));
    expect(source, isNot(contains('Buka Chat & Coba Asisten')));
    expect(source, isNot(contains('Kembali & coba Asisten')));
    expect(source, contains('Lihat Detail Teknis'));
    expect(source, contains('Unduh komponen yang kurang'));
    expect(source, contains('Unduh kurang di background'));
    expect(
      source,
      contains('Komponen model yang belum ada sedang diunduh di background.'),
    );
  });
}
