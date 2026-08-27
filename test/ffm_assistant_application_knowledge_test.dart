import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';

void main() {
  late AppDatabase database;
  late FfmAssistantInterpreter interpreter;

  setUp(() {
    database = createInMemoryDatabaseForTests();
    interpreter = FfmAssistantInterpreter(
      database,
      slmReadyCheck: () async => false,
    );
  });

  tearDown(() => database.close());

  test('identitas aplikasi dan pembuat memakai deskripsi resmi', () async {
    final intent = await interpreter.interpret(
      'aplikasi apa ini dan siapa pembuatnya',
    );

    expect(intent.type, FfmAssistantIntentType.assistantIdentity);
    expect(intent.response, contains('Family Finance Manager (FFM)'));
    expect(intent.response, contains('Rafi Sinkkat'));
    expect(intent.response, contains('offline-first'));
    expect(intent.response, contains('draft tidak sama dengan data tersimpan'));
  });

  test('frasa developer aplikasi FFM memakai deskripsi resmi', () async {
    final intent = await interpreter.interpret('siapa developer aplikasi FFM');

    expect(intent.type, FfmAssistantIntentType.assistantIdentity);
    expect(intent.response, contains('Rafi Sinkkat'));
  });

  test('pertanyaan fitur dan halaman memakai katalog aplikasi', () async {
    final intent = await interpreter.interpret(
      'fitur apa saja yang ada di aplikasi ini',
    );

    expect(intent.type, FfmAssistantIntentType.listPages);
    expect(intent.response, contains('FFM punya'));
    expect(intent.response, contains('Transaksi'));
    expect(intent.response, contains('Pengetahuan Asisten'));
    expect(intent.response, contains('Intelligence Dashboard'));
  });

  test(
    'panduan awal FFM membaca kondisi data lokal tanpa membuat data',
    () async {
      final intent = await interpreter.interpret('pertama kali saya harus apa');

      expect(intent.type, FfmAssistantIntentType.setupGuide);
      expect(intent.response, contains('belum ada rekening aktif'));
      expect(intent.response, contains('Isi nama keluarga di Data Utama'));
      expect(intent.response, contains('Catat transaksi pertama'));
    },
  );

  test('penjelasan Aktivitas membedakan Catatan Harian dari sesi bertimer', () {
    final detail = FfmAssistantCatalog.detailFor(
      FfmAssistantDestination.activity,
    );

    expect(detail, contains('Catatan Harian'));
    expect(detail, contains('terpisah'));
    expect(detail, contains('tidak mengubah sesi aktivitas'));
  });
}
