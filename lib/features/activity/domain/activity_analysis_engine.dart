import 'activity_query_layer.dart';

/// Activity Analysis Engine untuk Activity Intelligence Upgrade
///
/// Engine ini menyediakan kemampuan analisis deterministik di atas data aktivitas
/// yang sudah difilter oleh Query Layer.
///
/// Prinsip:
/// - Semua perhitungan berasal dari data query layer, bukan LLM
/// - Hasil dapat diverifikasi dan ditelusuri ke record sumber
/// - Mendukung 7/30/90 hari dan custom date range
class ActivityAnalysisEngine {
  const ActivityAnalysisEngine(this.queryLayer);

  final ActivityQueryLayer queryLayer;

  /// Analisis frekuensi aktivitas
  Future<ActivityFrequencyAnalysis> analyzeFrequency({
    required String householdId,
    required DateTime startDate,
    required DateTime endDate,
    String? activityId,
    String? category,
    String? activityGroupId,
    String? subjectType,
    String? subjectId,
  }) async {
    final result = await queryLayer.queryForAnalysis(
      householdId: householdId,
      startDate: startDate,
      endDate: endDate,
      activityId: activityId,
      category: category,
      activityGroupId: activityGroupId,
      subjectType: subjectType,
      subjectId: subjectId,
    );

    // Hitung frekuensi per kategori
    final categoryFrequency = <String, int>{};
    // Hitung frekuensi per kind
    final kindFrequency = <String, int>{};
    // Hitung frekuensi per status
    final statusFrequency = <String, int>{};

    for (final activity in result.activities) {
      categoryFrequency[activity.category] =
          (categoryFrequency[activity.category] ?? 0) + 1;
      kindFrequency[activity.kind.value] =
          (kindFrequency[activity.kind.value] ?? 0) + 1;
      statusFrequency[activity.status.value] =
          (statusFrequency[activity.status.value] ?? 0) + 1;
    }

    return ActivityFrequencyAnalysis(
      period:
          '${startDate.day}/${startDate.month}/${startDate.year} - ${endDate.day}/${endDate.month}/${endDate.year}',
      totalActivities: result.count,
      categoryFrequency: categoryFrequency,
      kindFrequency: kindFrequency,
      statusFrequency: statusFrequency,
      sourceRecordIds: result.sourceRecordIds,
      filters: result.filters,
    );
  }

  /// Analisis durasi aktivitas
  Future<ActivityDurationAnalysis> analyzeDuration({
    required String householdId,
    required DateTime startDate,
    required DateTime endDate,
    String? activityId,
    String? category,
    String? activityGroupId,
  }) async {
    final result = await queryLayer.queryForAnalysis(
      householdId: householdId,
      startDate: startDate,
      endDate: endDate,
      activityId: activityId,
      category: category,
      activityGroupId: activityGroupId,
    );

    final durations = <Duration>[];
    var totalDuration = Duration.zero;

    for (final activity in result.activities) {
      if (activity.endedAt != null) {
        final duration = activity.endedAt!.difference(activity.startedAt);
        if (!duration.isNegative) {
          durations.add(duration);
          totalDuration += duration;
        }
      }
    }

    // Hitung statistik durasi
    final averageDuration = durations.isNotEmpty
        ? Duration(
            microseconds: totalDuration.inMicroseconds ~/ durations.length,
          )
        : Duration.zero;

    durations.sort((a, b) => a.inMicroseconds.compareTo(b.inMicroseconds));
    final medianDuration = durations.isNotEmpty
        ? durations.length % 2 == 0
              ? Duration(
                  microseconds:
                      (durations[durations.length ~/ 2 - 1].inMicroseconds +
                          durations[durations.length ~/ 2].inMicroseconds) ~/
                      2,
                )
              : durations[durations.length ~/ 2]
        : Duration.zero;

    final minDuration = durations.isNotEmpty ? durations.first : Duration.zero;
    final maxDuration = durations.isNotEmpty ? durations.last : Duration.zero;

    return ActivityDurationAnalysis(
      period:
          '${startDate.day}/${startDate.month}/${startDate.year} - ${endDate.day}/${endDate.month}/${endDate.year}',
      totalActivities: result.count,
      completedActivities: durations.length,
      totalDuration: totalDuration,
      averageDuration: averageDuration,
      medianDuration: medianDuration,
      minDuration: minDuration,
      maxDuration: maxDuration,
      sourceRecordIds: result.sourceRecordIds,
      filters: result.filters,
    );
  }

  /// Analisis trend aktivitas
  Future<ActivityTrendAnalysis> analyzeTrend({
    required String householdId,
    required DateTime startDate,
    required DateTime endDate,
    String? category,
    String? activityGroupId,
    ActivityTrendType type = ActivityTrendType.count,
  }) async {
    final result = await queryLayer.queryForAnalysis(
      householdId: householdId,
      startDate: startDate,
      endDate: endDate,
      category: category,
      activityGroupId: activityGroupId,
    );

    // Group by day
    final dailyData = <String, int>{};
    for (final activity in result.activities) {
      final dayKey =
          '${activity.startedAt.year}-${activity.startedAt.month.toString().padLeft(2, '0')}-${activity.startedAt.day.toString().padLeft(2, '0')}';
      dailyData[dayKey] = (dailyData[dayKey] ?? 0) + 1;
    }

    // Urutkan berdasarkan hari
    final sortedDays = dailyData.keys.toList()..sort();
    final dailyTrend = sortedDays
        .map((key) => ActivityDailyData(day: key, count: dailyData[key]!))
        .toList();

    // Hitung trend direction
    String trendDirection = 'stabil';
    if (dailyTrend.length >= 2) {
      final firstHalf = dailyTrend.take(dailyTrend.length ~/ 2).toList();
      final secondHalf = dailyTrend.skip(dailyTrend.length ~/ 2).toList();

      final firstAvg = firstHalf.isEmpty
          ? 0
          : firstHalf.map((d) => d.count).reduce((a, b) => a + b) /
                firstHalf.length;
      final secondAvg = secondHalf.isEmpty
          ? 0
          : secondHalf.map((d) => d.count).reduce((a, b) => a + b) /
                secondHalf.length;

      if (secondAvg > firstAvg * 1.1) {
        trendDirection = 'naik';
      } else if (secondAvg < firstAvg * 0.9) {
        trendDirection = 'turun';
      }
    }

    return ActivityTrendAnalysis(
      period:
          '${startDate.day}/${startDate.month}/${startDate.year} - ${endDate.day}/${endDate.month}/${endDate.year}',
      type: type,
      trendDirection: trendDirection,
      dailyData: dailyTrend,
      sourceRecordIds: result.sourceRecordIds,
      filters: result.filters,
    );
  }

  /// Analisis distribusi lokasi
  Future<ActivityLocationAnalysis> analyzeLocationDistribution({
    required String householdId,
    required DateTime startDate,
    required DateTime endDate,
    String? category,
  }) async {
    final result = await queryLayer.queryForAnalysis(
      householdId: householdId,
      startDate: startDate,
      endDate: endDate,
      category: category,
    );

    // Extract location dari notes dan checkpoints (jika ada)
    final locationDistribution = <String, int>{};

    for (final activity in result.activities) {
      // Simple extraction: cari pola lokasi di notes
      if (activity.notes != null) {
        final notes = activity.notes!.toLowerCase();
        // Pattern sederhana untuk lokasi umum
        final locations = [
          'lahan',
          'kebun',
          'rumah',
          'kantor',
          'pasar',
          'toko',
        ];
        for (final loc in locations) {
          if (notes.contains(loc)) {
            locationDistribution[loc] = (locationDistribution[loc] ?? 0) + 1;
          }
        }
      }
    }

    return ActivityLocationAnalysis(
      period:
          '${startDate.day}/${startDate.month}/${startDate.year} - ${endDate.day}/${endDate.month}/${endDate.year}',
      totalActivities: result.count,
      locationDistribution: locationDistribution,
      sourceRecordIds: result.sourceRecordIds,
      filters: result.filters,
    );
  }

  /// Analisis komprehensif untuk periode spesifik (7/30/90 hari)
  Future<ActivityPeriodAnalysis> analyzePeriod({
    required String householdId,
    required ActivityAnalysisPeriod period,
    DateTime? referenceDate,
    String? category,
    String? activityGroupId,
  }) async {
    final now = referenceDate ?? DateTime.now();
    final (start, end) = _getPeriodRange(period, now);

    final frequencyResult = await analyzeFrequency(
      householdId: householdId,
      startDate: start,
      endDate: end,
      category: category,
      activityGroupId: activityGroupId,
    );

    final durationResult = await analyzeDuration(
      householdId: householdId,
      startDate: start,
      endDate: end,
      category: category,
      activityGroupId: activityGroupId,
    );

    return ActivityPeriodAnalysis(
      period: period,
      periodLabel: _getPeriodLabel(period),
      start: start,
      end: end,
      frequency: frequencyResult,
      duration: durationResult,
    );
  }

  (DateTime, DateTime) _getPeriodRange(
    ActivityAnalysisPeriod period,
    DateTime now,
  ) {
    switch (period) {
      case ActivityAnalysisPeriod.last7Days:
        return (now.subtract(const Duration(days: 7)), now);
      case ActivityAnalysisPeriod.last30Days:
        return (now.subtract(const Duration(days: 30)), now);
      case ActivityAnalysisPeriod.last90Days:
        return (now.subtract(const Duration(days: 90)), now);
    }
  }

  String _getPeriodLabel(ActivityAnalysisPeriod period) {
    switch (period) {
      case ActivityAnalysisPeriod.last7Days:
        return '7 hari terakhir';
      case ActivityAnalysisPeriod.last30Days:
        return '30 hari terakhir';
      case ActivityAnalysisPeriod.last90Days:
        return '90 hari terakhir';
    }
  }
}

// Data models untuk analysis results

class ActivityFrequencyAnalysis {
  const ActivityFrequencyAnalysis({
    required this.period,
    required this.totalActivities,
    required this.categoryFrequency,
    required this.kindFrequency,
    required this.statusFrequency,
    required this.sourceRecordIds,
    required this.filters,
  });

  final String period;
  final int totalActivities;
  final Map<String, int> categoryFrequency;
  final Map<String, int> kindFrequency;
  final Map<String, int> statusFrequency;
  final List<String> sourceRecordIds;
  final ActivityQueryFilters filters;

  String get mostFrequentCategory {
    if (categoryFrequency.isEmpty) return 'tidak ada data';
    return categoryFrequency.entries
        .reduce((a, b) => a.value > b.value ? a : b)
        .key;
  }

  String get mostFrequentKind {
    if (kindFrequency.isEmpty) return 'tidak ada data';
    return kindFrequency.entries
        .reduce((a, b) => a.value > b.value ? a : b)
        .key;
  }
}

class ActivityDurationAnalysis {
  const ActivityDurationAnalysis({
    required this.period,
    required this.totalActivities,
    required this.completedActivities,
    required this.totalDuration,
    required this.averageDuration,
    required this.medianDuration,
    required this.minDuration,
    required this.maxDuration,
    required this.sourceRecordIds,
    required this.filters,
  });

  final String period;
  final int totalActivities;
  final int completedActivities;
  final Duration totalDuration;
  final Duration averageDuration;
  final Duration medianDuration;
  final Duration minDuration;
  final Duration maxDuration;
  final List<String> sourceRecordIds;
  final ActivityQueryFilters filters;
}

enum ActivityTrendType { count, duration }

class ActivityTrendAnalysis {
  const ActivityTrendAnalysis({
    required this.period,
    required this.type,
    required this.trendDirection,
    required this.dailyData,
    required this.sourceRecordIds,
    required this.filters,
  });

  final String period;
  final ActivityTrendType type;
  final String trendDirection; // 'naik', 'turun', 'stabil'
  final List<ActivityDailyData> dailyData;
  final List<String> sourceRecordIds;
  final ActivityQueryFilters filters;
}

class ActivityDailyData {
  const ActivityDailyData({required this.day, required this.count});

  final String day;
  final int count;
}

class ActivityLocationAnalysis {
  const ActivityLocationAnalysis({
    required this.period,
    required this.totalActivities,
    required this.locationDistribution,
    required this.sourceRecordIds,
    required this.filters,
  });

  final String period;
  final int totalActivities;
  final Map<String, int> locationDistribution;
  final List<String> sourceRecordIds;
  final ActivityQueryFilters filters;
}

enum ActivityAnalysisPeriod { last7Days, last30Days, last90Days }

class ActivityPeriodAnalysis {
  const ActivityPeriodAnalysis({
    required this.period,
    required this.periodLabel,
    required this.start,
    required this.end,
    required this.frequency,
    required this.duration,
  });

  final ActivityAnalysisPeriod period;
  final String periodLabel;
  final DateTime start;
  final DateTime end;
  final ActivityFrequencyAnalysis frequency;
  final ActivityDurationAnalysis duration;
}
