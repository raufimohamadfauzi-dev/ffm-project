import '../../backup/data/json_export_studio_service.dart';

class FfmAssistantReportRequest {
  const FfmAssistantReportRequest({
    this.from,
    this.to,
    this.reportStyle = 'ringkas dan praktis',
    this.includeFinance = true,
    this.includeActivities = true,
    this.includeMetadata = true,
    this.includeFamilyProfile = false,
    this.includeNotes = false,
    this.anonymizeIdentity = false,
    this.anonymizeAmounts = false,
  });

  final DateTime? from;
  final DateTime? to;
  final String reportStyle;
  final bool includeFinance;
  final bool includeActivities;
  final bool includeMetadata;
  final bool includeFamilyProfile;
  final bool includeNotes;
  final bool anonymizeIdentity;
  final bool anonymizeAmounts;
}

class FfmAssistantReportDraft {
  const FfmAssistantReportDraft({
    required this.dataJson,
    required this.llmPrompt,
    required this.previewMarkdown,
    required this.periodLabel,
    required this.moduleCounts,
  });

  final String dataJson;
  final String llmPrompt;
  final String previewMarkdown;
  final String periodLabel;
  final Map<String, int> moduleCounts;
}

/// Menyiapkan laporan dari aggregator lokal. SLM hanya dipakai untuk narasi.
class FfmAssistantReportService {
  const FfmAssistantReportService(this._exporter);

  final JsonExportStudioService _exporter;

  Future<FfmAssistantReportDraft> prepare(
    FfmAssistantReportRequest request,
  ) async {
    final bundle = await _exporter.build(
      JsonStudioOptions(
        from: request.from,
        to: request.to,
        reportStyle: request.reportStyle,
        includeFinance: request.includeFinance,
        includeActivities: request.includeActivities,
        includeMetadata: request.includeMetadata,
        includeFamilyProfile: request.includeFamilyProfile,
        includeNotes: request.includeNotes,
        anonymizeIdentity: request.anonymizeIdentity,
        anonymizeAmounts: request.anonymizeAmounts,
      ),
    );
    return FfmAssistantReportDraft(
      dataJson: bundle.json,
      llmPrompt: bundle.prompt,
      previewMarkdown: _preview(bundle, request),
      periodLabel: bundle.periodLabel,
      moduleCounts: bundle.moduleCounts,
    );
  }

  String _preview(JsonStudioBundle bundle, FfmAssistantReportRequest request) {
    final modules = bundle.moduleCounts.entries
        .map((entry) => '- ${entry.key}: ${entry.value} record/section')
        .join('\n');
    return '''# Preview Laporan FFM

**Periode:** ${bundle.periodLabel}
**Gaya:** ${request.reportStyle}

## Modul yang dipakai
$modules

Angka laporan berasal dari agregator lokal FFM. SLM hanya boleh membantu menyusun narasi dari data JSON ini; angka, periode, dan fakta tidak boleh diubah oleh narasi.

## Status
Laporan ini masih berupa preview. Ekspor atau penyimpanan akhir menunggu aksi eksplisit pengguna.''';
  }
}
