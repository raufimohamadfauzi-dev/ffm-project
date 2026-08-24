import 'dart:convert';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/backup/data/json_export_studio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide Column;

void main() {
  late AppDatabase database;
  late JsonExportStudioService service;

  setUp(() async {
    database = createInMemoryDatabaseForTests();
    service = JsonExportStudioService(database);
    await (database.update(
      database.households,
    )..where((item) => item.id.equals('local-household'))).write(
      const HouseholdsCompanion(
        name: Value('Keluarga Harmonis'),
        husbandName: Value('Bapak'),
        wifeName: Value('Ibu'),
      ),
    );
  });

  tearDown(() => database.close());

  test('membawa profil keluarga dan prompt gaya laporan', () async {
    final bundle = await service.build(
      const JsonStudioOptions(
        includeFinance: false,
        includeActivities: false,
        includeMetadata: false,
        reportStyle: 'ringkasan visual santai',
      ),
    );
    final decoded = jsonDecode(bundle.json) as Map<String, dynamic>;

    expect(decoded['isBackup'], isFalse);
    expect(decoded['profilKeluarga']['namaRumahTangga'], 'Keluarga Harmonis');
    expect(decoded['profilKeluarga']['anggota'], ['Bapak', 'Ibu']);
    expect(bundle.prompt, contains('ringkasan visual santai'));
    expect(bundle.prompt, contains('Jangan mengubah'));
  });

  test(
    'anonimisasi menyamarkan identitas tetapi tetap mempertahankan struktur',
    () async {
      final bundle = await service.build(
        const JsonStudioOptions(
          includeFinance: false,
          includeActivities: false,
          includeMetadata: false,
          anonymizeIdentity: true,
        ),
      );
      final decoded = jsonDecode(bundle.json) as Map<String, dynamic>;

      expect(decoded['profilKeluarga']['namaRumahTangga'], 'Rumah Tangga');
      expect(decoded['profilKeluarga']['suami'], 'Anggota 1');
      expect(decoded['profilKeluarga']['istri'], 'Anggota 2');
      expect(decoded['householdId'], 'household-anonim');
      expect(decoded['pilihanLaporan']['identitasDisamarkan'], isTrue);
    },
  );
}
