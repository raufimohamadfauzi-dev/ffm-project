import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_proposal_json_service.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';

void main() {
  group('F3.4 Online Monitoring Job Proposal Parsing Tests', () {
    final now = DateTime(2026, 9, 12, 10, 0);

    test('parses weekly evaluation monitoring proposal from Gemini JSON', () {
      final jsonRaw = '''
{
  "formatVersion": "ffm-assistant-proposal-v1",
  "proposal": {
    "type": "monitoring_job",
    "preset": "weeklyEvaluation",
    "cadence": "weekly",
    "targetTimeMinutes": 540
  }
}
''';

      final result = FfmAssistantProposalJsonService.parse(
        jsonRaw,
        createdAt: now,
      );

      expect(result.draft, isNotNull);
      final draft = result.draft!;
      expect(draft.kind, FfmAssistantDraftKind.monitoringJob);
      expect(draft.title, 'Evaluasi Mingguan');
      expect(draft.formValues['preset'], 'weeklyEvaluation');
      expect(draft.formValues['cadence'], 'weekly');
      expect(draft.formValues['targetTimeMinutes'], 540);
      expect(draft.formValues['source'], 'gemini_proposal');
    });

    test('parses budget monitor proposal with category filter', () {
      final jsonRaw = '''
{
  "formatVersion": "ffm-assistant-proposal-v1",
  "proposal": {
    "type": "monitoring_job",
    "preset": "budgetMonitor",
    "cadence": "daily",
    "hour": 20,
    "minute": 0,
    "category": "Makanan"
  }
}
''';

      final result = FfmAssistantProposalJsonService.parse(
        jsonRaw,
        createdAt: now,
      );

      expect(result.draft, isNotNull);
      final draft = result.draft!;
      expect(draft.kind, FfmAssistantDraftKind.monitoringJob);
      expect(draft.title, 'Pemantauan Anggaran Kategori');
      expect(draft.formValues['preset'], 'budgetMonitor');
      expect(draft.formValues['cadence'], 'daily');
      expect(draft.formValues['targetTimeMinutes'], 1200); // 20 * 60
      expect(draft.formValues['categoryFilter'], 'Makanan');
    });
  });
}
