import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_feedback_context.dart';

void main() {
  test(
    'developer report contains diagnosis context without auto-send claim',
    () {
      const context = FfmAssistantFeedbackContext(
        userQuestion: 'Berapa saldo kas likuid saya?',
        assistantAnswer: 'Saldo belum dapat diverifikasi.',
        responseOrigin: 'geminiCloud',
        pluginName: 'gemini_cloud',
        pluginCategory: 'gemini_cloud',
        pluginMetadata: {'model': 'gemini-flash', 'groundingBlocked': true},
        verifiedFacts: 'Liquid Cash Balance: Rp1.500.000',
      );

      final report = context.buildDeveloperReport();

      expect(report, contains('PERTANYAAN USER'));
      expect(report, contains('JAWABAN ASISTEN'));
      expect(report, contains('Origin: geminiCloud'));
      expect(report, contains('Model: gemini-flash'));
      expect(report, contains('Status grounding: gagal'));
      expect(report, contains('Liquid Cash Balance: Rp1.500.000'));
      expect(report, contains('tidak mengubah data otomatis'));
    },
  );
}
