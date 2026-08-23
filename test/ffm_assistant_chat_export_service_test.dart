import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_chat_export_service.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_report_service.dart';

void main() {
  late Directory directory;
  late FfmAssistantReportDraft report;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('ffm-chat-export-test-');
    report = const FfmAssistantReportDraft(
      dataJson: '{"formatVersion":"test","income":1000000}',
      llmPrompt: 'prompt',
      previewMarkdown: '# Laporan FFM\n\n**Pemasukan:** Rp1.000.000',
      periodLabel: 'Agustus 2026',
      moduleCounts: {'transactions': 1},
    );
  });

  tearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  test('membuat JSON valid secara offline dengan nama file aman', () async {
    final service = FfmAssistantChatExportService(
      directoryProvider: () async => directory,
    );
    final result = await service.create(
      FfmAssistantExportRequest(
        report: report,
        format: FfmAssistantExportFormat.json,
        fileName: '../Rahasia Keluarga',
      ),
    );

    expect(result.file.existsSync(), isTrue);
    expect(result.fileName, 'rahasia-keluarga.json');
    expect(
      jsonDecode(await result.file.readAsString()),
      isA<Map<String, dynamic>>(),
    );
  });

  test('membuat Markdown dan PDF tanpa cloud', () async {
    final service = FfmAssistantChatExportService(
      directoryProvider: () async => directory,
    );
    final markdown = await service.create(
      FfmAssistantExportRequest(
        report: report,
        format: FfmAssistantExportFormat.markdown,
      ),
    );
    final pdf = await service.create(
      FfmAssistantExportRequest(
        report: report,
        format: FfmAssistantExportFormat.pdf,
      ),
    );

    expect(await markdown.file.readAsString(), contains('# Laporan FFM'));
    expect(pdf.file.lengthSync(), greaterThan(100));
    expect(pdf.fileName, endsWith('.pdf'));
  });
}
