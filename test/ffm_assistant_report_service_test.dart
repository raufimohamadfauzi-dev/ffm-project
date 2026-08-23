import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_report_service.dart';
import 'package:ffm_manager/features/backup/data/json_export_studio_service.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = createInMemoryDatabaseForTests();
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'report service membuat preview dan payload SLM dari exporter lokal',
    () async {
      final service = FfmAssistantReportService(
        JsonExportStudioService(database),
      );
      final report = await service.prepare(
        FfmAssistantReportRequest(
          from: DateTime(2026, 8, 1),
          to: DateTime(2026, 9, 1),
          reportStyle: 'ringkas untuk keluarga',
          anonymizeIdentity: true,
          anonymizeAmounts: true,
        ),
      );

      expect(report.dataJson, contains('ffm-export-studio-v1'));
      expect(
        report.llmPrompt,
        contains('Jangan mengubah, menebak, atau mengarang'),
      );
      expect(report.previewMarkdown, contains('Preview Laporan FFM'));
      expect(report.previewMarkdown, contains('ringkas untuk keluarga'));
      expect(report.periodLabel, isNotEmpty);
    },
  );
}
