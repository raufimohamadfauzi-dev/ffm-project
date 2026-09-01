import 'activity_analysis_engine.dart';
import 'activity_query_layer.dart';

/// Verified Fact / Context Layer untuk Activity Intelligence Upgrade
///
/// Layer ini mengubah hasil query/analisis menjadi context/fact terstruktur
/// sebelum diberikan kepada LLM.
///
/// Prinsip:
/// - LLM tidak boleh mengarang angka/fakta yang seharusnya berasal dari database
/// - Semua fakta dapat ditelusuri ke record sumber
/// - Context terstruktur dan bounded
class ActivityVerifiedFactLayer {
  const ActivityVerifiedFactLayer(this.analysisEngine);

  final ActivityAnalysisEngine analysisEngine;

  /// Membuat verified fact untuk analisis frekuensi
  Future<ActivityVerifiedFact> createFrequencyFact({
    required String householdId,
    required DateTime startDate,
    required DateTime endDate,
    String? activityId,
    String? category,
    String? activityGroupId,
  }) async {
    final analysis = await analysisEngine.analyzeFrequency(
      householdId: householdId,
      startDate: startDate,
      endDate: endDate,
      activityId: activityId,
      category: category,
      activityGroupId: activityGroupId,
    );

    return ActivityVerifiedFact(
      factType: ActivityFactType.frequency,
      period: _formatPeriod(startDate, endDate),
      filters: analysis.filters.toMap(),
      count: analysis.totalActivities,
      sourceRecordIds: analysis.sourceRecordIds,
      metrics: {
        'totalActivities': analysis.totalActivities,
        'categoryFrequency': analysis.categoryFrequency,
        'kindFrequency': analysis.kindFrequency,
        'statusFrequency': analysis.statusFrequency,
        'mostFrequentCategory': analysis.mostFrequentCategory,
        'mostFrequentKind': analysis.mostFrequentKind,
      },
      summary: _generateFrequencySummary(analysis),
    );
  }

  /// Membuat verified fact untuk analisis durasi
  Future<ActivityVerifiedFact> createDurationFact({
    required String householdId,
    required DateTime startDate,
    required DateTime endDate,
    String? activityId,
    String? category,
    String? activityGroupId,
  }) async {
    final analysis = await analysisEngine.analyzeDuration(
      householdId: householdId,
      startDate: startDate,
      endDate: endDate,
      activityId: activityId,
      category: category,
      activityGroupId: activityGroupId,
    );

    return ActivityVerifiedFact(
      factType: ActivityFactType.duration,
      period: _formatPeriod(startDate, endDate),
      filters: analysis.filters.toMap(),
      count: analysis.totalActivities,
      sourceRecordIds: analysis.sourceRecordIds,
      metrics: {
        'totalActivities': analysis.totalActivities,
        'completedActivities': analysis.completedActivities,
        'totalDurationMinutes': analysis.totalDuration.inMinutes,
        'averageDurationMinutes': analysis.averageDuration.inMinutes,
        'medianDurationMinutes': analysis.medianDuration.inMinutes,
        'minDurationMinutes': analysis.minDuration.inMinutes,
        'maxDurationMinutes': analysis.maxDuration.inMinutes,
      },
      summary: _generateDurationSummary(analysis),
    );
  }

  /// Membuat verified fact untuk analisis trend
  Future<ActivityVerifiedFact> createTrendFact({
    required String householdId,
    required DateTime startDate,
    required DateTime endDate,
    String? category,
    ActivityTrendType type = ActivityTrendType.count,
  }) async {
    final analysis = await analysisEngine.analyzeTrend(
      householdId: householdId,
      startDate: startDate,
      endDate: endDate,
      category: category,
      type: type,
    );

    return ActivityVerifiedFact(
      factType: ActivityFactType.trend,
      period: _formatPeriod(startDate, endDate),
      filters: analysis.filters.toMap(),
      count: analysis.sourceRecordIds.length,
      sourceRecordIds: analysis.sourceRecordIds,
      metrics: {
        'trendDirection': analysis.trendDirection,
        'trendType': type.name,
        'dailyDataPoints': analysis.dailyData.length,
      },
      summary: _generateTrendSummary(analysis),
    );
  }

  /// Membuat verified fact untuk analisis periode (7/30/90 hari)
  Future<ActivityVerifiedFact> createPeriodFact({
    required String householdId,
    required ActivityAnalysisPeriod period,
    DateTime? referenceDate,
    String? category,
    String? activityGroupId,
  }) async {
    final analysis = await analysisEngine.analyzePeriod(
      householdId: householdId,
      period: period,
      referenceDate: referenceDate,
      category: category,
      activityGroupId: activityGroupId,
    );

    return ActivityVerifiedFact(
      factType: ActivityFactType.period,
      period: analysis.periodLabel,
      filters: analysis.frequency.filters.toMap(),
      count: analysis.frequency.totalActivities,
      sourceRecordIds: analysis.frequency.sourceRecordIds,
      metrics: {
        'period': period.name,
        'periodLabel': analysis.periodLabel,
        'frequencyMetrics': {
          'totalActivities': analysis.frequency.totalActivities,
          'mostFrequentCategory': analysis.frequency.mostFrequentCategory,
        },
        'durationMetrics': {
          'totalActivities': analysis.duration.totalActivities,
          'completedActivities': analysis.duration.completedActivities,
          'totalDurationMinutes': analysis.duration.totalDuration.inMinutes,
          'averageDurationMinutes': analysis.duration.averageDuration.inMinutes,
        },
      },
      summary: _generatePeriodSummary(analysis),
    );
  }

  /// Membuat verified fact untuk query spesifik (by ID, group, subject)
  Future<ActivityVerifiedFact> createQueryFact({
    required String householdId,
    String? activityId,
    String? activityGroupId,
    String? subjectType,
    String? subjectId,
  }) async {
    // Validasi: minimal satu filter spesifik harus ada
    if (activityId == null &&
        activityGroupId == null &&
        subjectType == null &&
        subjectId == null) {
      throw ArgumentError('Minimal satu filter spesifik harus disediakan');
    }

    // Query dengan filter spesifik
    final queryLayer = analysisEngine.queryLayer;
    final result = await queryLayer.queryForAnalysis(
      householdId: householdId,
      activityId: activityId,
      activityGroupId: activityGroupId,
      subjectType: subjectType,
      subjectId: subjectId,
    );

    return ActivityVerifiedFact(
      factType: ActivityFactType.query,
      period: 'all_time',
      filters: result.filters.toMap(),
      count: result.count,
      sourceRecordIds: result.sourceRecordIds,
      metrics: {
        'queryType': activityId != null
            ? 'by_id'
            : activityGroupId != null
            ? 'by_group'
            : 'by_subject',
        'matchedActivities': result.count,
      },
      summary: _generateQuerySummary(result),
    );
  }

  String _formatPeriod(DateTime start, DateTime end) {
    return '${start.day}/${start.month}/${start.year} - ${end.day}/${end.month}/${end.year}';
  }

  String _generateFrequencySummary(ActivityFrequencyAnalysis analysis) {
    if (analysis.totalActivities == 0) {
      return 'Tidak ada aktivitas dalam periode ini.';
    }
    return 'Ditemukan ${analysis.totalActivities} aktivitas. '
        'Kategori paling sering: ${analysis.mostFrequentCategory}. '
        'Jenis paling sering: ${analysis.mostFrequentKind}.';
  }

  String _generateDurationSummary(ActivityDurationAnalysis analysis) {
    if (analysis.totalActivities == 0) {
      return 'Tidak ada aktivitas dalam periode ini.';
    }
    if (analysis.completedActivities == 0) {
      return 'Ada ${analysis.totalActivities} aktivitas, tetapi belum ada yang selesai.';
    }
    return 'Dari ${analysis.totalActivities} aktivitas, ${analysis.completedActivities} selesai. '
        'Durasi rata-rata: ${_formatDuration(analysis.averageDuration)}. '
        'Durasi median: ${_formatDuration(analysis.medianDuration)}.';
  }

  String _generateTrendSummary(ActivityTrendAnalysis analysis) {
    if (analysis.dailyData.isEmpty) {
      return 'Tidak ada data trend dalam periode ini.';
    }
    return 'Trend aktivitas: ${analysis.trendDirection}. '
        'Berdasarkan ${analysis.dailyData.length} titik data harian.';
  }

  String _generatePeriodSummary(ActivityPeriodAnalysis analysis) {
    if (analysis.frequency.totalActivities == 0) {
      return 'Tidak ada aktivitas dalam ${analysis.periodLabel}.';
    }
    return 'Dalam ${analysis.periodLabel}: '
        '${analysis.frequency.totalActivities} aktivitas total, '
        '${analysis.duration.completedActivities} selesai. '
        'Durasi rata-rata: ${_formatDuration(analysis.duration.averageDuration)}.';
  }

  String _generateQuerySummary(ActivityQueryResult result) {
    if (result.count == 0) {
      return 'Tidak ada aktivitas yang cocok dengan filter.';
    }
    return 'Ditemukan ${result.count} aktivitas yang cocok dengan filter.';
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours == 0) return '${minutes}m';
    if (minutes == 0) return '${hours}j';
    return '${hours}j ${minutes}m';
  }
}

/// Tipe fakta yang dapat dihasilkan
enum ActivityFactType { frequency, duration, trend, period, query }

/// Verified fact yang aman untuk diberikan kepada LLM
class ActivityVerifiedFact {
  const ActivityVerifiedFact({
    required this.factType,
    required this.period,
    required this.filters,
    required this.count,
    required this.sourceRecordIds,
    required this.metrics,
    required this.summary,
  });

  final ActivityFactType factType;
  final String period;
  final Map<String, dynamic> filters;
  final int count;
  final List<String> sourceRecordIds;
  final Map<String, dynamic> metrics;
  final String summary;

  /// Convert ke format yang aman untuk LLM prompt
  Map<String, dynamic> toLLMContext() => {
    'factType': factType.name,
    'period': period,
    'filters': filters,
    'count': count,
    'metrics': metrics,
    'summary': summary,
    'sourceRecordCount': sourceRecordIds.length,
    'note': 'Semua angka dan fakta berasal dari database lokal dan dapat diverifikasi.',
  };

  /// Convert ke JSON untuk logging/debugging
  Map<String, dynamic> toJson() => toLLMContext();
}
