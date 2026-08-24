import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_personalization_repository.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_profile_export_service.dart';

void main() {
  late AppDatabase database;
  late FfmAssistantPersonalizationRepository repository;
  late FfmAssistantProfileExportService exportService;

  setUp(() {
    database = createInMemoryDatabaseForTests();
    repository = FfmAssistantPersonalizationRepository(
      database,
      clock: () => DateTime.utc(2026, 8, 23),
    );
    exportService = FfmAssistantProfileExportService(repository);
  });

  tearDown(() => database.close());

  test('ekspor dan impor profil terenkripsi berhasil serta tidak menggandakan pola', () async {
    const householdId = 'household-1';
    const passphrase = 'password_super_aman_123';

    await repository.setPreference(
      householdId: householdId,
      preferenceKey: 'favorite_account',
      preferenceValue: 'Tunai',
    );
    for (var index = 0; index < 5; index++) {
      await repository.recordCorrection(
        householdId: householdId,
        merchantName: 'Toko A',
        fieldName: 'category',
        slmValue: 'Belanja',
        correctedValue: 'Makan',
      );
    }
    await repository.recalculatePatterns(householdId);

    final encryptedProfile = await exportService.exportProfile(
      householdId: householdId,
      passphrase: passphrase,
    );
    expect(encryptedProfile, isNotEmpty);
    expect(encryptedProfile, isNot(contains('Toko A')));

    await repository.resetLearning(householdId, includePreferences: true);
    expect(await repository.getPreferences(householdId), isEmpty);
    expect(await repository.getAllPatterns(householdId), isEmpty);

    await exportService.importProfile(
      householdId: householdId,
      encryptedPayload: encryptedProfile,
      passphrase: passphrase,
    );

    final prefs = await repository.getPreferences(householdId);
    expect(prefs, hasLength(1));
    expect(prefs.first.preferenceValue, 'Tunai');

    final patterns = await repository.getAllPatterns(householdId);
    expect(patterns, hasLength(1));
    expect(patterns.first.merchantName, 'Toko A');
    expect(patterns.first.mostCommonValue, 'Makan');

    await exportService.importProfile(
      householdId: householdId,
      encryptedPayload: encryptedProfile,
      passphrase: passphrase,
    );
    expect(await repository.getAllPatterns(householdId), hasLength(1));
  });

  test('impor profil gagal jika passphrase salah', () async {
    const householdId = 'household-1';

    await repository.setPreference(
      householdId: householdId,
      preferenceKey: 'mode',
      preferenceValue: 'ringkas',
    );

    final encryptedProfile = await exportService.exportProfile(
      householdId: householdId,
      passphrase: 'password_benar',
    );

    await expectLater(
      () => exportService.importProfile(
        householdId: householdId,
        encryptedPayload: encryptedProfile,
        passphrase: 'password_salah',
      ),
      throwsException,
    );
  });
}
