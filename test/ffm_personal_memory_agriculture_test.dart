import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/features/assistant/data/ffm_personal_memory_service.dart';

void main() {
  test('Mengekstrak informasi pertanian dan kebun dari pesan user', () {
    final service = FfmPersonalMemoryService();

    // 1. Luas lahan
    final insightLahan = service.extractFromMessage('lahan sawah saya seluas 2 hektar');
    expect(insightLahan, isNotNull);
    expect(insightLahan!.key, 'agriculture_field');
    expect(insightLahan.humanLabel, contains('2 hektar'));

    // 2. Komoditas pertanian
    final insightKomoditas = service.extractFromMessage('tanam padi dan jagung di kebun');
    expect(insightKomoditas, isNotNull);
    expect(insightKomoditas!.key, 'commodity');
    expect(insightKomoditas.humanLabel, contains('padi'));

    // 3. Perkiraan panen
    final insightPanen = service.extractFromMessage('perkiraan panen pada 20 Oktober 2026');
    expect(insightPanen, isNotNull);
    expect(insightPanen!.key, 'harvest_target');
    expect(insightPanen.humanLabel, contains('20 Oktober 2026'));

    // 4. Nomor meteran PLN
    final insightMeteran = service.extractFromMessage('nomor meteran listrik sawah adalah 14238765432');
    expect(insightMeteran, isNotNull);
    expect(insightMeteran!.key, 'electricity_meter');
    expect(insightMeteran.humanLabel, contains('14238765432'));
  });
}
