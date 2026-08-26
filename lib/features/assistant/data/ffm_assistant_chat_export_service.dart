import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;

import 'ffm_assistant_report_service.dart';

enum FfmAssistantExportFormat { json, markdown, pdf }

class FfmAssistantExportRequest {
  const FfmAssistantExportRequest({
    required this.report,
    required this.format,
    this.fileName,
  });

  final FfmAssistantReportDraft report;
  final FfmAssistantExportFormat format;
  final String? fileName;
}

class FfmAssistantExportResult {
  const FfmAssistantExportResult({required this.file, required this.format});

  final File file;
  final FfmAssistantExportFormat format;

  String get fileName => file.uri.pathSegments.last;
}

class FfmAssistantChatExportService {
  FfmAssistantChatExportService({
    Future<Directory> Function()? directoryProvider,
  }) : _directoryProvider =
           directoryProvider ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _directoryProvider;

  Future<FfmAssistantExportResult> create(
    FfmAssistantExportRequest request,
  ) async {
    final directory = await _directoryProvider();
    await directory.create(recursive: true);
    final stem = _safeStem(
      request.fileName ?? 'laporan-ffm-${_slug(request.report.periodLabel)}',
    );
    final extension = switch (request.format) {
      FfmAssistantExportFormat.json => 'json',
      FfmAssistantExportFormat.markdown => 'md',
      FfmAssistantExportFormat.pdf => 'pdf',
    };
    final file = File('${directory.path}/$stem.$extension');
    final temporary = File('${file.path}.part');
    final bytes = await _bytesFor(request);
    await temporary.writeAsBytes(bytes, flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
    return FfmAssistantExportResult(file: file, format: request.format);
  }

  Future<List<int>> _bytesFor(FfmAssistantExportRequest request) async {
    switch (request.format) {
      case FfmAssistantExportFormat.json:
        final decoded = jsonDecode(request.report.dataJson);
        return utf8.encode(const JsonEncoder.withIndent('  ').convert(decoded));
      case FfmAssistantExportFormat.markdown:
        return utf8.encode(request.report.previewMarkdown);
      case FfmAssistantExportFormat.pdf:
        final document = pw.Document();
        final font = pw.Font.ttf(
          await rootBundle.load('assets/fonts/DejaVuSans.ttf'),
        );
        final boldFont = pw.Font.ttf(
          await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf'),
        );
        final lines = request.report.previewMarkdown.split('\n');
        document.addPage(
          pw.MultiPage(
            theme: pw.ThemeData.withFont(base: font, bold: boldFont),
            build: (_) => [
              pw.Text(
                'Laporan FFM',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 12),
              for (final line in lines)
                if (line.trim().isEmpty)
                  pw.SizedBox(height: 6)
                else
                  pw.Text(
                    _plainMarkdown(line),
                    style: const pw.TextStyle(fontSize: 10),
                  ),
            ],
          ),
        );
        return document.save();
    }
  }

  String _plainMarkdown(String value) => value
      .replaceAll(RegExp(r'^#{1,6}\s*'), '')
      .replaceAll(RegExp(r'\*\*([^*]+)\*\*'), r'$1')
      .replaceAll(RegExp(r'`([^`]+)`'), r'$1');

  String _safeStem(String value) {
    final normalized = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    if (normalized.isEmpty) return 'laporan-ffm';
    final end = normalized.length < 80 ? normalized.length : 80;
    return normalized.substring(0, end);
  }

  String _slug(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
}
