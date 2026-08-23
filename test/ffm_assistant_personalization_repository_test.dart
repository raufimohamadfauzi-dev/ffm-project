import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_personalization_repository.dart';

void main() {
  late AppDatabase database;
  late FfmAssistantPersonalizationRepository repository;

  setUp(() {
    database = createInMemoryDatabaseForTests();
    repository = FfmAssistantPersonalizationRepository(
      database,
      clock: () => DateTime.utc(2026, 8, 23),
    );
  });

  tearDown(() => database.close());

  test(
    'membuat pola kuat setelah lima koreksi dengan konsistensi 80 persen',
    () async {
      for (var index = 0; index < 5; index++) {
        await repository.recordCorrection(
          householdId: 'household-1',
          merchantName: 'Toko A',
          fieldName: 'category',
          slmValue: 'Belanja lain',
          correctedValue: index == 0 ? 'Pertanian' : 'Makan',
        );
      }

      final count = await repository.recalculatePatterns('household-1');
      final pattern = await repository.getPatternForMerchant(
        householdId: 'household-1',
        merchantName: 'Toko A',
        fieldName: 'category',
      );

      expect(count, 1);
      expect(pattern, isNotNull);
      expect(pattern!.mostCommonValue, 'Makan');
      expect(pattern.sampleCount, 5);
      expect(pattern.confidenceScore, closeTo(0.8, 0.0001));
      expect(pattern.isStrong, isTrue);
    },
  );

  test('konteks hanya memuat preferensi dan pola kuat yang relevan', () async {
    await repository.setPreference(
      householdId: 'household-1',
      preferenceKey: 'favorite_account',
      preferenceValue: 'Tunai',
    );
    for (var index = 0; index < 5; index++) {
      await repository.recordCorrection(
        householdId: 'household-1',
        merchantName: 'Toko A',
        fieldName: 'category',
        slmValue: 'Belanja lain',
        correctedValue: 'Makan',
      );
      await repository.recordCorrection(
        householdId: 'household-1',
        merchantName: 'Toko B',
        fieldName: 'category',
        slmValue: 'Belanja lain',
        correctedValue: 'Pertanian',
      );
    }
    await repository.recalculatePatterns('household-1');

    final relevant = await repository.buildPersonalizedContext(
      householdId: 'household-1',
      query: 'catat pengeluaran di toko a',
      maxCharacters: 500,
    );
    expect(relevant, contains('favorite_account=Tunai'));
    expect(relevant, contains('merchant=Toko A'));
    expect(relevant, isNot(contains('merchant=Toko B')));
    expect(relevant.length, lessThanOrEqualTo(500));

    final unrelated = await repository.buildPersonalizedContext(
      householdId: 'household-1',
      query: 'buka halaman anggaran',
    );
    expect(unrelated, contains('favorite_account=Tunai'));
    expect(unrelated, isNot(contains('merchant=Toko A')));
  });

  test(
    'field di luar allowlist tidak disimpan dan budget konteks dibatasi',
    () async {
      await repository.recordCorrection(
        householdId: 'household-1',
        merchantName: 'Toko A',
        fieldName: 'raw_note',
        slmValue: 'teks rahasia',
        correctedValue: 'nilai lain',
      );
      expect(await database.select(database.userCorrections).get(), isEmpty);

      await repository.setPreference(
        householdId: 'household-1',
        preferenceKey: 'mode',
        preferenceValue: 'ringkas',
      );
      final context = await repository.buildPersonalizedContext(
        householdId: 'household-1',
        query: 'apa saja',
        maxCharacters: 5000,
      );
      expect(context.length, lessThanOrEqualTo(900));
    },
  );

  test('preferensi diperbarui tanpa membuat duplikat dan reset tidak menyentuh transaksi', () async {
    await repository.setPreference(
      householdId: 'household-1',
      preferenceKey: 'favorite_account',
      preferenceValue: 'Tunai',
    );
    await repository.setPreference(
      householdId: 'household-1',
      preferenceKey: 'favorite_account',
      preferenceValue: 'Bank',
    );
    await repository.recordCorrection(
      householdId: 'household-1',
      merchantName: 'Toko A',
      fieldName: 'category',
      slmValue: null,
      correctedValue: 'Makan',
    );

    final preferences = await repository.getPreferences('household-1');
    expect(preferences, hasLength(1));
    expect(preferences.single.preferenceValue, 'Bank');

    await repository.recalculatePatterns('household-1');
    await repository.resetLearning('household-1');

    expect(await repository.getPreferences('household-1'), hasLength(1));
    expect(
      await repository.getPatternForMerchant(
        householdId: 'household-1',
        merchantName: 'Toko A',
        fieldName: 'category',
      ),
      isNull,
    );
  });
}
