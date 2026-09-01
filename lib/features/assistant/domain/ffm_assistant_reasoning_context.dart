import 'ffm_assistant_models.dart';
import 'ffm_assistant_verified_fact_service.dart';
import 'ffm_assistant_analysis_engine.dart';

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
    final needsHelp = RegExp(
      r'\b(bantuan|help|fitur|apa yang bisa|cara pakai|panduan)\b',
    ).hasMatch(normalized);
    // Help tidak butuh evidence finansial/master.
    if (needsHelp && normalized.length < 60) {
      return const FfmAssistantReasoningEvidenceScope(
        includeFinancialSummary: false,
        includeMasterData: false,
        includeRecentTransactions: false,
      );
    }
    final needsFinancial = RegExp(
      r'\b(saldo|uang|transaksi|pengeluaran|pemasukan|pendapatan|anggaran|laporan|analisa|analisis|hutang|utang|piutang|aset|target|transfer|rekening|ringkasan|rangkuman|rekap)\b',
    ).hasMatch(normalized);
    final needsMasterData = RegExp(
      r'\b(tambah|buat|catat|ubah|ganti|koreksi|transfer|rekening|kategori|toko|data utama|membagi|rencana|kebutuhan|pendapatan|target|goal|anggaran|budget)\b',
    ).hasMatch(normalized);
    final needsRecentTransactions = RegExp(
      r'\b(terakhir|terbaru|riwayat|minggu ini|bulan ini|hari ini|kemarin)\b',
    ).hasMatch(normalized);
    final needsBudget = RegExp(r'\b(anggaran|budget)\b').hasMatch(normalized);
    final needsCategories = RegExp(r'\b(kategori)\b').hasMatch(normalized);
    final needsGoals = RegExp(r'\b(target|goal|tujuan)\b').hasMatch(normalized);
    final needsAccounts = RegExp(r'\b(rekening|akun)\b').hasMatch(normalized);
    // Jika spesifik akun/budget/kategori/goal, tetap butuh financial+master minimal
    final specificMaster =
        needsBudget || needsCategories || needsGoals || needsAccounts;
    return FfmAssistantReasoningEvidenceScope(
      includeFinancialSummary: needsFinancial || specificMaster,
      includeMasterData: needsMasterData || specificMaster,
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
    this.verifiedFacts = '',
    this.analysisResults = '',
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
  final String verifiedFacts;
  final String analysisResults;

  String toBoundedPrompt({int maxCharacters = 6000}) {
    final sections = <String>[
      'Reasoning context FFM (captured ${capturedAt.toIso8601String()}):',
      'Request user: ${_clip(request, 1000)}',
      'Halaman aktif: ${_pageLabel(currentPage)}.',
      if (pageSummary?.trim().isNotEmpty == true)
        'Ringkasan halaman: ${_clip(pageSummary!, 900)}',
      if (verifiedFacts.trim().isNotEmpty)
        'VERIFIED FACTS: ${_clip(verifiedFacts, 2000)}',
      if (analysisResults.trim().isNotEmpty)
        'ANALYSIS RESULTS: ${_clip(analysisResults, 1500)}',
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
      'Evidence hierarchy: verified facts dari database authoritative; analysis results dari analysis engine authoritative; snapshot SQL & halaman authoritative; konteks user hanya konteks; memory cloud & riwayat tidak mengalahkan fakta.',
      'Policy: gunakan verified facts, analysis results, dan fakta adapter lokal sebagai sumber kebenaran; jangan menjalankan SQL; mutation wajib preview dan konfirmasi.',
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
      verifiedFacts: verifiedFacts,
      analysisResults: analysisResults,
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
      verifiedFacts: verifiedFacts,
      analysisResults: analysisResults,
    );
  }

  FfmAssistantReasoningContext withVerifiedFacts(FfmVerifiedFacts facts) {
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
      recentTransactions: recentTransactions,
      verifiedFacts: facts.toLLMContext(),
      analysisResults: analysisResults,
    );
  }

  FfmAssistantReasoningContext withAnalysisResults(dynamic analysisData) {
    String analysisText = '';
    if (analysisData is FfmFrequencyAnalysis) {
      final topCats = analysisData.categoryFrequency.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final topMers = analysisData.merchantFrequency.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      analysisText =
          'Frequency Analysis - ${analysisData.period}: '
          '${analysisData.totalTransactions} transactions. '
          'Most frequent category: ${analysisData.mostFrequentCategory}. '
          'Most frequent merchant: ${analysisData.mostFrequentMerchant}. '
          'Top categories: ${topCats.take(3).map((c) => '${c.key} (${c.value})').join(', ')}. '
          'Top merchants: ${topMers.take(3).map((m) => '${m.key} (${m.value})').join(', ')}.';
    } else if (analysisData is FfmTrendAnalysis) {
      analysisText =
          'Trend Analysis - ${analysisData.period}: '
          'Type: ${analysisData.type.name}, '
          'Trend: ${analysisData.trendDirection}. '
          'Monthly data points: ${analysisData.monthlyData.length}.';
    } else if (analysisData is FfmPatternAnalysis) {
      final patterns = analysisData.categoryPatterns.entries.take(3);
      analysisText =
          'Pattern Analysis - ${analysisData.period}: '
          'Patterns found: ${patterns.length} categories. '
          'Categories: ${patterns.map((p) => '${p.key} (avg: ${p.value.average})').join(', ')}.';
    } else if (analysisData is FfmPeriodAnalysis) {
      analysisText =
          'Period Analysis - ${analysisData.periodLabel}: '
          '${analysisData.transactionCount} transactions, '
          'Total income: ${analysisData.income.toStringAsFixed(0)}, '
          'Total expense: ${analysisData.expense.toStringAsFixed(0)}, '
          'Net cashflow: ${analysisData.netCashflow.toStringAsFixed(0)}. '
          'Top category: ${analysisData.topCategory}.';
    }

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
      recentTransactions: recentTransactions,
      verifiedFacts: verifiedFacts,
      analysisResults: analysisText,
    );
  }

  FfmAssistantReasoningContext copyWith({
    String? request,
    DateTime? capturedAt,
    FfmAssistantDestination? currentPage,
    String? pageSummary,
    Map<String, String>? activeFilters,
    List<String>? capabilityIds,
    String? approvedUserContext,
    String? personalizationContext,
    bool? modelReady,
    List<String>? previousStepResults,
    List<String>? recentTransactions,
    String? verifiedFacts,
    String? analysisResults,
  }) {
    return FfmAssistantReasoningContext(
      request: request ?? this.request,
      capturedAt: capturedAt ?? this.capturedAt,
      currentPage: currentPage ?? this.currentPage,
      pageSummary: pageSummary ?? this.pageSummary,
      activeFilters: activeFilters ?? this.activeFilters,
      capabilityIds: capabilityIds ?? this.capabilityIds,
      approvedUserContext: approvedUserContext ?? this.approvedUserContext,
      personalizationContext:
          personalizationContext ?? this.personalizationContext,
      modelReady: modelReady ?? this.modelReady,
      previousStepResults: previousStepResults ?? this.previousStepResults,
      recentTransactions: recentTransactions ?? this.recentTransactions,
      verifiedFacts: verifiedFacts ?? this.verifiedFacts,
      analysisResults: analysisResults ?? this.analysisResults,
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
