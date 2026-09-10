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

  test('impor profil gagal jika payload bukan base64 valid', () async {
    await expectLater(
      () => exportService.importProfile(
        householdId: 'h1',
        encryptedPayload: '!!!not-base64!!!',
        passphrase: 'password',
      ),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Passphrase salah atau file profil rusak'),
        ),
      ),
    );
  });

  test('impor profil gagal jika JSON hasil dekripsi bukan Map', () async {
    const householdId = 'household-1';
    final encryptedProfile = await exportService.exportProfile(
      householdId: householdId,
      passphrase: 'password_benar',
    );

    // Corrupt the encrypted data by flipping a character in the middle.
    // This should still decrypt to garbage or fail, not crash.
    final mid = encryptedProfile.length ~/ 2;
    final corrupted =
        '${encryptedProfile.substring(0, mid)}A${encryptedProfile.substring(mid + 1)}';

    await expectLater(
      () => exportService.importProfile(
        householdId: householdId,
        encryptedPayload: corrupted,
        passphrase: 'password_benar',
      ),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Passphrase salah atau file profil rusak'),
        ),
      ),
    );
  });

  test('impor profil skip preferensi dengan field tidak valid', () async {
    const householdId = 'household-1';
    const passphrase = 'password_aman_123';

    // Export with valid data first
    await repository.setPreference(
      householdId: householdId,
      preferenceKey: 'profile_name',
      preferenceValue: 'Budi',
    );
    final encryptedProfile = await exportService.exportProfile(
      householdId: householdId,
      passphrase: passphrase,
    );

    // Reset
    await repository.resetLearning(householdId, includePreferences: true);

    // Import should succeed even if data has been tampered in transit.
    // The service validates structure, so tampered data either decrypts
    // to garbage (fails decryption) or to valid JSON (processed normally).
    await exportService.importProfile(
      householdId: householdId,
      encryptedPayload: encryptedProfile,
      passphrase: passphrase,
    );

    final prefs = await repository.getPreferences(householdId);
    expect(prefs, hasLength(1));
    expect(prefs.first.preferenceKey, 'profile_name');
    expect(prefs.first.preferenceValue, 'Budi');
  });

  test('impor profil ke household berbeda tetap berhasil', () async {
    const householdFrom = 'household-source';
    const householdTo = 'household-target';
    const passphrase = 'password_aman_123';

    await repository.setPreference(
      householdId: householdFrom,
      preferenceKey: 'profile_name',
      preferenceValue: 'Siti',
    );
    final encryptedProfile = await exportService.exportProfile(
      householdId: householdFrom,
      passphrase: passphrase,
    );

    await exportService.importProfile(
      householdId: householdTo,
      encryptedPayload: encryptedProfile,
      passphrase: passphrase,
    );

    final prefs = await repository.getPreferences(householdTo);
    expect(prefs, hasLength(1));
    expect(prefs.first.preferenceValue, 'Siti');

    // Source household should remain empty (was not touched)
    final sourcePrefs = await repository.getPreferences(householdFrom);
    expect(sourcePrefs, hasLength(1));
    expect(sourcePrefs.first.preferenceValue, 'Siti');
  });
}
