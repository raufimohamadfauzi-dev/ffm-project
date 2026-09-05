import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/features/assistant/domain/services/ffm_follow_up_suggestion_engine.dart';

void main() {
  group('FfmFollowUpSuggestionEngine', () {
    const engine = FfmFollowUpSuggestionEngine();

    test('generates 3 agriculture/harvest questions when topic mentions panen or pupuk', () {
      final suggestions = engine.generateSuggestions(
        userText: 'Berapa modal kebun jagung bulan ini?',
        assistantResponse: 'Estimasi panen masih 25 hari lagi, total belanja pupuk Rp 450.000.',
      );

      expect(suggestions.length, equals(3));
      expect(suggestions[0], contains('runway'));
      expect(suggestions[1], contains('panen'));
      expect(suggestions[2], contains('pupuk'));
    });

    test('generates 3 vehicle/fuel questions when topic mentions bbm or bensin', () {
      final suggestions = engine.generateSuggestions(
        userText: 'Saya baru isi bensin motor Rp 50.000',
        assistantResponse: 'Catatan pengeluaran bensin Pertalite berhasil disimpan.',
      );

      expect(suggestions.length, equals(3));
      expect(suggestions[0], contains('efisiensi BBM (KM/L)'));
      expect(suggestions[1], contains('pengeluaran bensin'));
      expect(suggestions[2], contains('liter'));
    });

    test('generates 3 electricity/token questions when topic mentions token listrik', () {
      final suggestions = engine.generateSuggestions(
        userText: 'Catat beli token listrik ruko 100rb',
        assistantResponse: 'Token PLN sebesar Rp 100.000 untuk meteran Ruko telah dicatat.',
      );

      expect(suggestions.length, equals(3));
      expect(suggestions[0], contains('token listrik'));
      expect(suggestions[1], contains('pembelian token'));
      expect(suggestions[2], contains('nomor meteran'));
    });

    test('generates 3 envelope rebalancing questions when topic mentions rebalance or anggaran', () {
      final suggestions = engine.generateSuggestions(
        userText: 'Seimbangkan anggaran saya',
        assistantResponse: 'Ditemukan surplus pada pos hiburan yang bisa digeser ke pos makanan.',
      );

      expect(suggestions.length, equals(3));
      expect(suggestions[0], contains('defisit'));
      expect(suggestions[1], contains('belanja harian'));
      expect(suggestions[2], contains('surplus'));
    });

    test('generates 3 debt payoff questions when topic mentions hutang or cicilan', () {
      final suggestions = engine.generateSuggestions(
        userText: 'Berapa total hutang dan cicilan saya?',
        assistantResponse: 'Total kewajiban aktif Anda saat ini adalah Rp 12.500.000.',
      );

      expect(suggestions.length, equals(3));
      expect(suggestions[0], contains('pokok hutang'));
      expect(suggestions[1], contains('bunga'));
      expect(suggestions[2], contains('rasio cicilan'));
    });

    test('generates 3 default cash overview questions when topic is generic', () {
      final suggestions = engine.generateSuggestions(
        userText: 'Halo asisten',
        assistantResponse: 'Halo! Ada yang bisa saya bantu untuk keuangan keluarga hari ini?',
      );

      expect(suggestions.length, equals(3));
      expect(suggestions[0], contains('arus kas'));
      expect(suggestions[1], contains('pengeluaran'));
      expect(suggestions[2], contains('saldo kas'));
    });
  });
}
