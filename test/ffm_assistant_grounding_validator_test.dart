import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_grounding_validator.dart';

void main() {
  group('FfmAssistantGroundingValidator', () {
    test('memblokir klaim sudah tersimpan', () {
      final error = FfmAssistantGroundingValidator.validatePlainText(
        geminiText: 'Data sudah tersimpan ke database.',
        verifiedFacts: 'income=5000',
        analysisFacts: null,
        capabilityEvidence: null,
      );
      expect(error, isNotNull);
      expect(error, contains('tidak dapat menampilkan klaim penyimpanan'));
    });

    test('memblokir angka besar tanpa evidence', () {
      final error = FfmAssistantGroundingValidator.validatePlainText(
        geminiText: 'Saldo Anda Rp 5.000.000',
        verifiedFacts: null,
        analysisFacts: null,
        capabilityEvidence: null,
      );
      expect(error, isNotNull);
      expect(error, contains('belum tersedia'));
    });

    test('mengizinkan angka yang ada di evidence', () {
      final error = FfmAssistantGroundingValidator.validatePlainText(
        geminiText: 'Pemasukan 5000000 pada bulan ini.',
        verifiedFacts: 'income=5000000; expenses=3000000',
        analysisFacts: null,
        capabilityEvidence: null,
      );
      expect(error, isNull);
    });

    test('mengizinkan angka berformat rupiah yang sama dengan evidence', () {
      final error = FfmAssistantGroundingValidator.validatePlainText(
        geminiText: 'Kas likuid saat ini Rp 1.234.567.',
        verifiedFacts: 'Liquid Cash Balance: Rp1.234.567',
        analysisFacts: null,
        capabilityEvidence: null,
      );
      expect(error, isNull);
    });

    test('mengizinkan jawaban tanpa angka/tanggal', () {
      final error = FfmAssistantGroundingValidator.validatePlainText(
        geminiText: 'Halo, ada yang bisa dibantu?',
        verifiedFacts: null,
        analysisFacts: null,
        capabilityEvidence: null,
      );
      expect(error, isNull);
    });

    test('memblokir tanggal tanpa evidence', () {
      final error = FfmAssistantGroundingValidator.validatePlainText(
        geminiText: 'Transaksi pada 2026-08-15 sebesar 100000',
        verifiedFacts: '',
        analysisFacts: null,
        capabilityEvidence: null,
      );
      expect(error, isNotNull);
    });

    test('memblokir tanggal yang tidak ada dalam evidence', () {
      final error = FfmAssistantGroundingValidator.validatePlainText(
        geminiText: 'Jatuh tempo pada 2026-08-15.',
        verifiedFacts: 'Jatuh tempo pada 2026-08-20.',
        analysisFacts: null,
        capabilityEvidence: null,
      );

      expect(error, isNotNull);
      expect(error, contains('Tanggal pada jawaban'));
    });

    test('mengizinkan angka pada percakapan umum atau edukasi ketika isGeneralOrHelp true', () {
      final error = FfmAssistantGroundingValidator.validatePlainText(
        geminiText: 'Inflasi di Indonesia pada tahun 2024 diproyeksikan sekitar 2,5% sampai 3,0%.',
        verifiedFacts: null,
        analysisFacts: null,
        capabilityEvidence: null,
        isGeneralOrHelp: true,
      );
      expect(error, isNull);
    });

    test('mengizinkan angka yang bersumber dari riwayat percakapan sebelumnya', () {
      final error = FfmAssistantGroundingValidator.validatePlainText(
        geminiText:
            'Tadi Anda menyebutkan ingin membeli sepeda seharga Rp 2.500.000.',
        verifiedFacts: null,
        analysisFacts: null,
        capabilityEvidence: null,
        conversationHistory:
            'Pengguna: Rencana beli sepeda 2500000 bulan depan.',
      );
      expect(error, isNull);
    });

    test(
      'tetap memblokir klaim penyimpanan data meskipun isGeneralOrHelp true',
      () {
        final error = FfmAssistantGroundingValidator.validatePlainText(
          geminiText: 'Data sudah tersimpan ke aplikasi.',
          verifiedFacts: null,
          analysisFacts: null,
          capabilityEvidence: null,
          isGeneralOrHelp: true,
        );
        expect(error, isNotNull);
        expect(error, contains('tidak dapat menampilkan klaim penyimpanan'));
      },
    );
  });
}
