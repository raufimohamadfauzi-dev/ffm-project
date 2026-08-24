import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_runtime_knowledge.dart';

void main() {
  final registry = FfmAssistantRuntimeKnowledgeRegistry();

  test('registry mencakup seluruh destination katalog dan schema database', () {
    for (final page in FfmAssistantCatalog.pages) {
      expect(registry.containsDestination(page.destination), isTrue);
    }
    expect(FfmAssistantRuntimeKnowledgeRegistry.databaseTables, hasLength(31));
    expect(registry.entries, isNotEmpty);
  });

  test(
    'prompt context bounded menyertakan aturan safety dan halaman aktif',
    () {
      final prompt = registry.buildPromptContext(
        query: 'bagaimana membuat laporan',
        currentDestination: FfmAssistantDestination.monthlyReport,
        capabilityIds: const ['read.transactions', 'mutate.save_draft'],
      );

      expect(prompt, contains('Ringkasan bulanan'));
      expect(prompt, contains('mutate.save_draft'));
      expect(prompt, contains('preview dan konfirmasi'));
      expect(prompt.length, lessThan(5000));
    },
  );

  test('self-check workflow menjelaskan transaction dan report', () {
    expect(registry.find('preview'), isNotNull);
    expect(registry.find('laporan'), isNotNull);
    expect(registry.find('transfer'), isNotNull);
  });
}
