/// Performance Monitor untuk Assistant
/// 
/// Monitor berbagai metrik performa untuk assistant operations
library;

class FfmAssistantPerformanceMetric {
  const FfmAssistantPerformanceMetric({
    required this.operation,
    required this.duration,
    required this.timestamp,
    this.metadata,
  });

  final String operation;
  final Duration duration;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;

  Map<String, dynamic> toJson() {
    return {
      'operation': operation,
      'durationMs': duration.inMilliseconds,
      'timestamp': timestamp.toIso8601String(),
      'metadata': metadata,
    };
  }

  static FfmAssistantPerformanceMetric fromJson(Map<String, dynamic> json) {
    return FfmAssistantPerformanceMetric(
      operation: json['operation'] as String,
      duration: Duration(milliseconds: json['durationMs'] as int),
      timestamp: DateTime.parse(json['timestamp'] as String),
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }
}

class FfmAssistantPerformanceSnapshot {
  const FfmAssistantPerformanceSnapshot({
    required this.intentInterpretation,
    required this.verifiedFactsGeneration,
    required this.analysisEngine,
    required this.geminiCall,
    required this.totalResponse,
    required this.timestamp,
  });

  final Duration intentInterpretation;
  final Duration verifiedFactsGeneration;
  final Duration analysisEngine;
  final Duration geminiCall;
  final Duration totalResponse;
  final DateTime timestamp;

  Map<String, dynamic> toJson() {
    return {
      'intentInterpretationMs': intentInterpretation.inMilliseconds,
      'verifiedFactsGenerationMs': verifiedFactsGeneration.inMilliseconds,
      'analysisEngineMs': analysisEngine.inMilliseconds,
      'geminiCallMs': geminiCall.inMilliseconds,
      'totalResponseMs': totalResponse.inMilliseconds,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  static FfmAssistantPerformanceSnapshot fromJson(Map<String, dynamic> json) {
    return FfmAssistantPerformanceSnapshot(
      intentInterpretation: Duration(milliseconds: json['intentInterpretationMs'] as int),
      verifiedFactsGeneration: Duration(milliseconds: json['verifiedFactsGenerationMs'] as int),
      analysisEngine: Duration(milliseconds: json['analysisEngineMs'] as int),
      geminiCall: Duration(milliseconds: json['geminiCallMs'] as int),
      totalResponse: Duration(milliseconds: json['totalResponseMs'] as int),
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
}

class FfmAssistantPerformanceMonitor {
  FfmAssistantPerformanceMonitor();

  final List<FfmAssistantPerformanceMetric> _metrics = [];
  final List<FfmAssistantPerformanceSnapshot> _snapshots = [];
  final Stopwatch _stopwatch = Stopwatch();

  /// Mulai mengukur performa untuk sebuah operasi
  void startOperation() {
    _stopwatch
      ..reset()
      ..start();
  }

  /// Selesai mengukur operasi dan simpan metrik
  void endOperation(String operation, {Map<String, dynamic>? metadata}) {
    _stopwatch.stop();
    final metric = FfmAssistantPerformanceMetric(
      operation: operation,
      duration: _stopwatch.elapsed,
      timestamp: DateTime.now(),
      metadata: metadata,
    );
    _metrics.add(metric);
  }

  /// Catat snapshot performa lengkap untuk sebuah response
  void recordSnapshot({
    required Duration intentInterpretation,
    required Duration verifiedFactsGeneration,
    required Duration analysisEngine,
    required Duration geminiCall,
    required Duration totalResponse,
  }) {
    final snapshot = FfmAssistantPerformanceSnapshot(
      intentInterpretation: intentInterpretation,
      verifiedFactsGeneration: verifiedFactsGeneration,
      analysisEngine: analysisEngine,
      geminiCall: geminiCall,
      totalResponse: totalResponse,
      timestamp: DateTime.now(),
    );
    _snapshots.add(snapshot);
  }

  /// Ambil semua metrik
  List<FfmAssistantPerformanceMetric> get metrics => List.unmodifiable(_metrics);

  /// Ambil semua snapshot
  List<FfmAssistantPerformanceSnapshot> get snapshots => List.unmodifiable(_snapshots);

  /// Hitung statistik untuk operasi tertentu
  Map<String, double> getStatisticsForOperation(String operation) {
    final operationMetrics = _metrics.where((m) => m.operation == operation).toList();
    
    if (operationMetrics.isEmpty) {
      return {
        'count': 0,
        'avgMs': 0,
        'minMs': 0,
        'maxMs': 0,
        'p50Ms': 0,
        'p90Ms': 0,
        'p95Ms': 0,
        'p99Ms': 0,
      };
    }

    final durations = operationMetrics.map((m) => m.duration.inMilliseconds).toList();
    durations.sort();

    return {
      'count': operationMetrics.length.toDouble(),
      'avgMs': durations.reduce((a, b) => a + b) / durations.length,
      'minMs': durations.first.toDouble(),
      'maxMs': durations.last.toDouble(),
      'p50Ms': _percentile(durations, 50),
      'p90Ms': _percentile(durations, 90),
      'p95Ms': _percentile(durations, 95),
      'p99Ms': _percentile(durations, 99),
    };
  }

  /// Hitung statistik untuk total response time
  Map<String, double> getTotalResponseStatistics() {
    if (_snapshots.isEmpty) {
      return {
        'count': 0,
        'avgMs': 0,
        'minMs': 0,
        'maxMs': 0,
        'p50Ms': 0,
        'p90Ms': 0,
        'p95Ms': 0,
        'p99Ms': 0,
      };
    }

    final durations = _snapshots.map((s) => s.totalResponse.inMilliseconds).toList();
    durations.sort();

    return {
      'count': _snapshots.length.toDouble(),
      'avgMs': durations.reduce((a, b) => a + b) / durations.length,
      'minMs': durations.first.toDouble(),
      'maxMs': durations.last.toDouble(),
      'p50Ms': _percentile(durations, 50),
      'p90Ms': _percentile(durations, 90),
      'p95Ms': _percentile(durations, 95),
      'p99Ms': _percentile(durations, 99),
    };
  }

  /// Hitung rata-rata durasi untuk setiap komponen
  Map<String, double> getComponentAverages() {
    if (_snapshots.isEmpty) {
      return {
        'intentInterpretation': 0,
        'verifiedFactsGeneration': 0,
        'analysisEngine': 0,
        'geminiCall': 0,
      };
    }

    return {
      'intentInterpretation': _snapshots
          .map((s) => s.intentInterpretation.inMilliseconds)
          .reduce((a, b) => a + b) / _snapshots.length,
      'verifiedFactsGeneration': _snapshots
          .map((s) => s.verifiedFactsGeneration.inMilliseconds)
          .reduce((a, b) => a + b) / _snapshots.length,
      'analysisEngine': _snapshots
          .map((s) => s.analysisEngine.inMilliseconds)
          .reduce((a, b) => a + b) / _snapshots.length,
      'geminiCall': _snapshots
          .map((s) => s.geminiCall.inMilliseconds)
          .reduce((a, b) => a + b) / _snapshots.length,
    };
  }

  /// Identifikasi bottleneck berdasarkan rata-rata komponen
  String identifyBottleneck() {
    final averages = getComponentAverages();
    final maxComponent = averages.entries
        .reduce((a, b) => a.value > b.value ? a : b);
    
    final percentage = averages.values.isNotEmpty
        ? (maxComponent.value / averages.values.reduce((a, b) => a + b) * 100)
        : 0;
    
    return '${maxComponent.key} (${percentage.toStringAsFixed(1)}% of total)';
  }

  /// Bersihkan metrik lama
  void clearMetrics() {
    _metrics.clear();
    _snapshots.clear();
  }

  /// Bersihkan metrik yang lebih lama dari durasi tertentu
  void clearOldMetrics({Duration maxAge = const Duration(hours: 24)}) {
    final cutoff = DateTime.now().subtract(maxAge);
    _metrics.removeWhere((m) => m.timestamp.isBefore(cutoff));
    _snapshots.removeWhere((s) => s.timestamp.isBefore(cutoff));
  }

  double _percentile(List<int> sortedList, int percentile) {
    if (sortedList.isEmpty) return 0;
    final index = ((sortedList.length - 1) * percentile / 100).round();
    return sortedList[index].toDouble();
  }
}
