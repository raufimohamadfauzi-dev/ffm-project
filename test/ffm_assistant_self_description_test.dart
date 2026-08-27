import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/features/assistant/domain/ffm_assistant_self_description.dart';

void main() {
  const service = FfmAssistantSelfDescriptionService();

  test('self-description menyebut kemampuan nyata dan batas keamanan', () {
    final response = service.build(
      slmConfigured: true,
      includeCreatorLinks: true,
    );

    expect(response, contains('baca transaksi'));
    expect(response, contains('preview'));
    expect(response, contains('konfirmasi'));
    expect(response, contains('tidak ada autosave'));
    expect(response, contains('Gemini Cloud digunakan'));
    expect(response, contains('Masih dalam pengembangan'));
    expect(response, contains('Rafi Sinkkat'));
    expect(response, contains('Family Finance Manager (FFM)'));
    expect(
      response,
      contains('aplikasi pengelolaan keuangan keluarga offline-first'),
    );
    expect(response, contains('Catatan Harian'));
    expect(
      response,
      contains('https://youtube.com/@clipsmartt?si=T4-4Zja6FZlcgdDe'),
    );
    expect(
      response,
      contains('https://www.tiktok.com/@clip.smarts?_r=1&_t=ZS-997Uzi7kXma'),
    );
    expect(
      response,
      contains('[https://youtube.com/@clipsmartt?si=T4-4Zja6FZlcgdDe]'),
    );
    expect(
      response,
      contains('[https://www.tiktok.com/@clip.smarts?_r=1&_t=ZS-997Uzi7kXma]'),
    );
  });

  test(
    'capability yang tidak memiliki handler tidak disebut sebagai tersedia',
    () {
      final response = service.build(
        implementedCapabilityIds: const ['read.summary'],
        slmConfigured: false,
      );

      expect(response, contains('baca ringkasan'));
      expect(
        response,
        isNot(contains('Mutation terkonfirmasi yang tersedia: simpan draft')),
      );
      expect(response, contains('baca anggaran'));
      expect(response, contains('Gemini Cloud digunakan'));
    },
  );
}
