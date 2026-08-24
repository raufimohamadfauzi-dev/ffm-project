import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/features/assistant/data/ffm_personal_memory_service.dart';

void main() {
  group('FfmPersonalMemoryService Pattern Matching', () {
    const service = FfmPersonalMemoryService();

    test('mendeteksi tanggal gajian dari kalimat user', () {
      final insight = service.extractFromMessage('gajianku tiap tanggal 25');
      expect(insight, isNotNull);
      expect(insight?.kind, FfmPersonalMemoryKind.preference);
      expect(insight?.key, 'payday');
      expect(insight?.value, '25');
      expect(insight?.humanLabel, 'Tanggal gaji: 25 setiap bulan');
    });

    test('mendeteksi variasi frasa tanggal gajian', () {
      final insight = service.extractFromMessage('gaji saya per tanggal 1');
      expect(insight, isNotNull);
      expect(insight?.key, 'payday');
      expect(insight?.value, '1');
      expect(insight?.humanLabel, 'Tanggal gaji: 1 setiap bulan');
    });

    test('mendeteksi nama panggilan dari chat', () {
      final insight = service.extractFromMessage('panggilanku adalah Rafi');
      expect(insight, isNotNull);
      expect(insight?.kind, FfmPersonalMemoryKind.preference);
      expect(insight?.key, 'name');
      expect(insight?.value, 'Rafi');
      expect(insight?.humanLabel, 'Nama panggilanmu: Rafi');
    });

    test('mendeteksi pekerjaan dari chat', () {
      final insight = service.extractFromMessage('aku bekerja sebagai Software Engineer');
      expect(insight, isNotNull);
      expect(insight?.kind, FfmPersonalMemoryKind.preference);
      expect(insight?.key, 'occupation');
      expect(insight?.value, 'Software Engineer');
      expect(insight?.humanLabel, 'Pekerjaan: Software Engineer');
    });

    test('mendeteksi target tabungan dari chat', () {
      final insight = service.extractFromMessage('target nabung 50 juta');
      expect(insight, isNotNull);
      expect(insight?.kind, FfmPersonalMemoryKind.habitChat);
      expect(insight?.key, 'savings_target');
      expect(insight?.value, '50 juta');
      expect(insight?.humanLabel, 'Target tabungan: 50 juta');
    });

    test('mendeteksi budget makanan bulanan', () {
      final insight = service.extractFromMessage('budget makan perbulan 3 juta');
      expect(insight, isNotNull);
      expect(insight?.kind, FfmPersonalMemoryKind.habitChat);
      expect(insight?.key, 'budget_food');
      expect(insight?.value, '3 juta');
      expect(insight?.humanLabel, 'Anggaran makan/bulan: 3 juta');
    });

    test('mendeteksi jumlah anggota keluarga', () {
      final insight = service.extractFromMessage('keluarga kami ada 4 orang');
      expect(insight, isNotNull);
      expect(insight?.kind, FfmPersonalMemoryKind.habitChat);
      expect(insight?.key, 'family_members');
      expect(insight?.value, '4');
      expect(insight?.humanLabel, 'Jumlah anggota keluarga: 4 orang');
    });

    test('mengembalikan null untuk kalimat umum tanpa fakta profil', () {
      expect(service.extractFromMessage('catat makan siang 25 ribu'), isNull);
      expect(service.extractFromMessage('berapa sisa saldo bca?'), isNull);
      expect(service.extractFromMessage('halo selamat pagi'), isNull);
      expect(service.extractFromMessage(''), isNull);
    });
  });
}
