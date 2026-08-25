import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_capability_adapters.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_personalization_repository.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_plan.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_capability_executor.dart';

void main() {
  late AppDatabase db;
  late FfmAssistantCapabilityAdapterRegistry registry;
  late FfmAssistantPersonalizationRepository personalization;

  setUp(() async {
    db = createInMemoryDatabaseForTests();
    personalization = FfmAssistantPersonalizationRepository(db);
    registry = FfmAssistantCapabilityAdapterRegistry(
      database: db,
      householdId: 'local-household',
      personalization: personalization,
    );
    // Seed rekening + dua kategori expense.
    await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            id: 'acc-bri',
            householdId: 'local-household',
            name: 'BRI',
            type: 'bank',
            createdAt: DateTime(2026, 1, 1),
          ),
        );
    for (final name in ['Jajan', 'Belanja']) {
      await db
          .into(db.categories)
          .insert(
            CategoriesCompanion.insert(
              id: 'cat-$name',
              householdId: 'local-household',
              name: name,
              type: 'expense',
              createdAt: DateTime(2026, 1, 1),
            ),
          );
    }
  });

  tearDown(() async {
    await db.close();
  });

  Future<FfmAssistantCapabilityExecutionResult> saveExpense(
    Map<String, Object?> extra, {
    String key = 'k1',
  }) {
    final handler = registry.handlers['mutate.save_draft']!;
    return handler(
      FfmAssistantActionStep(
        id: 'save',
        capabilityId: 'mutate.save_draft',
        parameters: {
          'kind': 'expense',
          '_idempotencyKey': key,
          'amount': 20000,
          'fromAccount': 'BRI',
          'category': 'Belanja',
          ...extra,
        },
      ),
    );
  }

  test('draft terkoreksi: beda kategori tercatat dan pola merchant terbentuk',
      () async {
    final result = await saveExpense({
      'assistantMerchantName': 'Indomaret',
      'assistantSlmFieldValues': {'category': 'Jajan', 'account': 'BRI'},
    });

    expect(result.isSuccess, isTrue);

    final corrections = await (db.select(db.userCorrections)).get();
    expect(corrections.map((c) => c.fieldName), ['category']);
    expect(corrections.single.slmValue, 'Jajan');
    expect(corrections.single.correctedValue, 'Belanja');
    expect(corrections.single.merchantName, 'Indomaret');

    final patterns = await personalization.getPatternForMerchant(
      householdId: 'local-household',
      merchantName: 'Indomaret',
      fieldName: 'category',
      strongOnly: false,
    );
    expect(patterns, isNotNull);
    expect(patterns!.mostCommonValue, 'Belanja');
  });

  test('nilai identik dengan tebakan: tidak ada koreksi tercatat', () async {
    final result = await saveExpense({
      'assistantMerchantName': 'Alfamart',
      'assistantSlmFieldValues': {'category': 'Belanja', 'account': 'BRI'},
    }, key: 'k2');

    expect(result.isSuccess, isTrue);
    final corrections = await (db.select(db.userCorrections)).get();
    expect(corrections.where((c) => c.merchantName == 'Alfamart'), isEmpty);
  });

  test('draft tanpa merchant tidak direkam sebagai pola', () async {
    final result = await saveExpense({
      'assistantSlmFieldValues': {'category': 'Jajan'},
    }, key: 'k3');

    expect(result.isSuccess, isTrue);
    final corrections = await (db.select(db.userCorrections)).get();
    expect(corrections, isEmpty);
  });
}

