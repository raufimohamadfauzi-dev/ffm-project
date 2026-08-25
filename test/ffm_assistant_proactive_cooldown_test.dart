import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ffm_manager/features/assistant/data/ffm_assistant_proactive_cooldown.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_proactive_service.dart';

void main() {
  late DateTime now;
  late FfmAssistantProactiveCooldown cooldown;

  const transactionSuggestion = FfmAssistantProactiveSuggestion(
    id: 'summarize-transactions',
    message: 'Ringkas transaksi.',
    suggestedPrompt: 'ringkas transaksi di halaman ini',
    destination: FfmAssistantDestination.transactions,
  );
  const budgetSuggestion = FfmAssistantProactiveSuggestion(
    id: 'review-budget',
    message: 'Ringkas anggaran.',
    suggestedPrompt: 'ringkas anggaran di halaman ini',
    destination: FfmAssistantDestination.budget,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    now = DateTime(2026, 8, 25, 10);
    cooldown = FfmAssistantProactiveCooldown(
      preferences: await SharedPreferences.getInstance(),
      clock: () => now,
      duration: const Duration(minutes: 30),
    );
  });

  test(
    'saran pertama dapat muncul lalu saran sama ditahan pada halaman sama',
    () async {
      expect(await cooldown.mayShow(transactionSuggestion), isTrue);

      await cooldown.markShown(transactionSuggestion);

      expect(await cooldown.mayShow(transactionSuggestion), isFalse);
    },
  );

  test('saran pada halaman atau ID lain tetap dapat muncul', () async {
    await cooldown.markShown(transactionSuggestion);

    expect(await cooldown.mayShow(budgetSuggestion), isTrue);
  });

  test('saran sama muncul kembali setelah masa cooldown berlalu', () async {
    await cooldown.markShown(transactionSuggestion);
    now = now.add(const Duration(minutes: 30));

    expect(await cooldown.mayShow(transactionSuggestion), isTrue);
  });

  test('cooldown tidak menyimpan isi pesan atau data keuangan', () async {
    await cooldown.markShown(transactionSuggestion);
    final preferences = await SharedPreferences.getInstance();
    final keys = preferences.getKeys();

    expect(keys, hasLength(1));
    expect(keys.single, contains('summarize-transactions'));
    expect(preferences.get(keys.single), isA<int>());
  });
}
