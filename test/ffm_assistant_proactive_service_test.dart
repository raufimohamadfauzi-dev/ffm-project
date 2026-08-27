import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_proactive_service.dart';

void main() {
  const service = FfmAssistantProactiveSuggestionService();

  test('Gemini belum siap memunculkan saran setup Cloud', () {
    final suggestion = service.suggest(
      destination: FfmAssistantDestination.summary,
      modelReady: false,
      hasConversation: false,
    );

    expect(suggestion?.id, 'setup-gemini-cloud');
    expect(suggestion?.suggestedPrompt, 'buka pengaturan Gemini Cloud');
    expect(
      suggestion?.destination,
      FfmAssistantDestination.intelligenceDashboard,
    );
  });

  test('halaman transaksi memberi saran read-only saat chat baru', () {
    final suggestion = service.suggest(
      destination: FfmAssistantDestination.transactions,
      modelReady: true,
      hasConversation: false,
    );

    expect(suggestion?.id, 'summarize-transactions');
    expect(suggestion?.suggestedPrompt, contains('ringkas'));
  });

  test('saran tidak mengganggu percakapan yang sudah berjalan', () {
    expect(
      service.suggest(
        destination: FfmAssistantDestination.transactions,
        modelReady: true,
        hasConversation: true,
      ),
      isNull,
    );
  });

  test('halaman personal manager memberi saran aman sesuai konteks', () {
    final cases = {
      FfmAssistantDestination.masterData: 'review-master-data',
      FfmAssistantDestination.activity: 'review-activities',
      FfmAssistantDestination.reminders: 'review-reminders',
    };

    for (final entry in cases.entries) {
      final suggestion = service.suggest(
        destination: entry.key,
        modelReady: true,
        hasConversation: false,
      );

      expect(suggestion?.id, entry.value);
      expect(suggestion?.message, isNot(contains('langsung menyimpan')));
    }
  });
}
