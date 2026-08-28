import 'ffm_assistant_models.dart';

class FfmAssistantReasoningEvidenceScope {
  const FfmAssistantReasoningEvidenceScope({
    required this.includeFinancialSummary,
    required this.includeMasterData,
    required this.includeRecentTransactions,
  });

  final bool includeFinancialSummary;
  final bool includeMasterData;
  final bool includeRecentTransactions;
}

/// Memilih evidence lokal minimum yang relevan sebelum konteks diberikan ke
/// Gemini Cloud. Ini bukan penentu akses: executor tetap memakai allowlist.
abstract final class FfmAssistantReasoningEvidencePolicy {
  static FfmAssistantReasoningEvidenceScope forRequest(String request) {
    final normalized = request.toLowerCase();
    final needsFinancial = RegExp(
      r'\b(saldo|uang|transaksi|pengeluaran|pemasukan|pendapatan|anggaran|laporan|analisa|analisis|hutang|utang|piutang|aset|target|transfer|rekening)\b',
    ).hasMatch(normalized);
    final needsMasterData = RegExp(
      r'\b(tambah|buat|catat|ubah|ganti|koreksi|transfer|rekening|kategori|toko|data utama|membagi|rencana|kebutuhan|pendapatan)\b',
    ).hasMatch(normalized);
    final needsRecentTransactions = RegExp(
      r'\b(terakhir|terbaru|riwayat|minggu ini|bulan ini|hari ini|kemarin)\b',
    ).hasMatch(normalized);
    return FfmAssistantReasoningEvidenceScope(
      includeFinancialSummary: needsFinancial,
      includeMasterData: needsMasterData,
      includeRecentTransactions: needsRecentTransactions && needsFinancial,
    );
  }
}

class FfmAssistantReasoningContext {
  const FfmAssistantReasoningContext({
    required this.request,
    required this.capturedAt,
    this.currentPage,
    this.pageSummary,
    this.activeFilters = const <String, String>{},
    this.capabilityIds = const <String>[],
    this.approvedUserContext = '',
    this.personalizationContext = '',
    this.modelReady = false,
    this.previousStepResults = const <String>[],
    this.recentTransactions = const <String>[],
  });

  final String request;
  final DateTime capturedAt;
  final FfmAssistantDestination? currentPage;
  final String? pageSummary;
  final Map<String, String> activeFilters;
  final List<String> capabilityIds;
  final String approvedUserContext;
  final String personalizationContext;
  final bool modelReady;
  final List<String> previousStepResults;
  final List<String> recentTransactions;

  String toBoundedPrompt({int maxCharacters = 6000}) {
    final sections = <String>[
      'Reasoning context FFM (captured ${capturedAt.toIso8601String()}):',
      'Request user: ${_clip(request, 1000)}',
      'Halaman aktif: ${_pageLabel(currentPage)}.',
      if (pageSummary?.trim().isNotEmpty == true)
        'Ringkasan halaman: ${_clip(pageSummary!, 900)}',
      if (recentTransactions.isNotEmpty)
        'Transaksi terbaru (${recentTransactions.length}): ${_clip(recentTransactions.take(5).join(' | '), 1200)}',
      if (activeFilters.isNotEmpty)
        'Filter aktif: ${_mapToLine(activeFilters, 700)}',
      'Capability allowlist aktif: ${capabilityIds.take(32).join(', ')}',
      'Gemini Cloud siap: ${modelReady ? 'ya' : 'tidak'}',
      if (approvedUserContext.trim().isNotEmpty)
        'Konteks user yang telah disetujui: ${_clip(approvedUserContext, 1200)}',
      if (personalizationContext.trim().isNotEmpty)
        'Personalisasi lokal terbatas: ${_clip(personalizationContext, 900)}',
      if (previousStepResults.isNotEmpty)
        'Hasil step sebelumnya: ${previousStepResults.take(8).map((item) => _clip(item, 500)).join(' | ')}',
      'Evidence hierarchy: snapshot SQL & halaman authoritative; konteks user hanya konteks; memory cloud & riwayat tidak mengalahkan fakta.',
      'Policy: gunakan fakta adapter lokal sebagai sumber kebenaran; jangan menjalankan SQL; mutation wajib preview dan konfirmasi.',
    ];
    final prompt = sections.join('\n');
    return _clip(prompt, maxCharacters);
  }

  FfmAssistantReasoningContext withStepResult(String result) {
    return FfmAssistantReasoningContext(
      request: request,
      capturedAt: capturedAt,
      currentPage: currentPage,
      pageSummary: pageSummary,
      activeFilters: activeFilters,
      capabilityIds: capabilityIds,
      approvedUserContext: approvedUserContext,
      personalizationContext: personalizationContext,
      modelReady: modelReady,
      previousStepResults: [...previousStepResults.take(7), result],
      recentTransactions: recentTransactions,
    );
  }

  FfmAssistantReasoningContext withRecentTransactions(
    List<String> transactions,
  ) {
    return FfmAssistantReasoningContext(
      request: request,
      capturedAt: capturedAt,
      currentPage: currentPage,
      pageSummary: pageSummary,
      activeFilters: activeFilters,
      capabilityIds: capabilityIds,
      approvedUserContext: approvedUserContext,
      personalizationContext: personalizationContext,
      modelReady: modelReady,
      previousStepResults: previousStepResults,
      recentTransactions: transactions.take(5).toList(),
    );
  }

  static String _pageLabel(FfmAssistantDestination? destination) {
    if (destination == null) return 'tidak diketahui';
    return FfmAssistantCatalog.findByDestination(destination)?.name ??
        destination.name;
  }

  static String _mapToLine(Map<String, String> values, int maxLength) => _clip(
    values.entries.map((entry) => '${entry.key}=${entry.value}').join(', '),
    maxLength,
  );

  static String _clip(String value, int maxLength) {
    final normalized = value.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    if (normalized.length <= maxLength) return normalized;
    return '${normalized.substring(0, maxLength - 1)}…';
  }
}
