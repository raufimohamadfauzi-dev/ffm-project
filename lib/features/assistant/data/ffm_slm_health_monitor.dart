import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Status kesehatan SLM
enum FfmSlmHealthStatus {
  healthy,
  degraded,
  unhealthy,
  circuitOpen,
}

/// Health entry untuk satu inference attempt.
class FfmSlmHealthEntry {
  const FfmSlmHealthEntry({
    required this.timestamp,
    required this.success,
    required this.latencyMs,
    this.errorType,
    this.responseLength,
  });

  final DateTime timestamp;
  final bool success;
  final int latencyMs;
  final String? errorType;
  final int? responseLength;

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'success': success,
    'latencyMs': latencyMs,
    if (errorType != null) 'errorType': errorType,
    if (responseLength != null) 'responseLength': responseLength,
  };

  factory FfmSlmHealthEntry.fromJson(Map<String, dynamic> json) {
    return FfmSlmHealthEntry(
      timestamp: DateTime.parse(json['timestamp'] as String),
      success: json['success'] as bool,
      latencyMs: (json['latencyMs'] as num?)?.toInt() ?? 0,
      errorType: json['errorType'] as String?,
      responseLength: (json['responseLength'] as num?)?.toInt(),
    );
  }
}

/// Health monitoring dan circuit breaker untuk SLM inference.
///
/// Melacak latency, success rate, dan error patterns.
/// Circuit breaker berfungsi skip inference jika terlalu banyak gagal.
class FfmSlmHealthMonitor {
  FfmSlmHealthMonitor({SharedPreferences? preferences})
      : _preferences = preferences;

  static const _key = 'ffm_slm_health_v1';
  static const maxEntries = 100;
  static const _circuitBreakerThreshold = 5;
  static const _circuitBreakerDuration = Duration(minutes: 5);

  SharedPreferences? _preferences;
  List<FfmSlmHealthEntry> _recentEntries = [];
  DateTime? _circuitOpenAt;
  bool _loaded = false;

  FfmSlmHealthStatus get status {
    if (_circuitOpenAt != null) {
      final elapsed = DateTime.now().difference(_circuitOpenAt!);
      if (elapsed < _circuitBreakerDuration) {
        return FfmSlmHealthStatus.circuitOpen;
      }
      _circuitOpenAt = null;
    }

    if (_recentEntries.isEmpty) return FfmSlmHealthStatus.healthy;

    final recent = _recentEntries.length > 20
        ? _recentEntries.sublist(_recentEntries.length - 20)
        : _recentEntries;

    final successRate = recent.where((e) => e.success).length / recent.length;
    final avgLatency = recent.fold<int>(
          0,
          (sum, e) => sum + e.latencyMs,
        ) /
        recent.length;

    if (successRate < 0.5) return FfmSlmHealthStatus.unhealthy;
    if (successRate < 0.8 || avgLatency > 30000) {
      return FfmSlmHealthStatus.degraded;
    }
    return FfmSlmHealthStatus.healthy;
  }

  bool get isCircuitOpen => status == FfmSlmHealthStatus.circuitOpen;
  bool get shouldSkipInference => isCircuitOpen;

  double get successRate {
    if (_recentEntries.isEmpty) return 1.0;
    return _recentEntries.where((e) => e.success).length /
        _recentEntries.length;
  }

  int get averageLatencyMs {
    if (_recentEntries.isEmpty) return 0;
    return _recentEntries.fold<int>(0, (sum, e) => sum + e.latencyMs) ~/
        _recentEntries.length;
  }

  /// Load persisted health data.
  Future<void> load() async {
    if (_loaded) return;
    final prefs = _preferences ?? await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          _recentEntries = (decoded['entries'] as List?)
                  ?.map((e) => FfmSlmHealthEntry.fromJson(
                      Map<String, dynamic>.from(e as Map)))
                  .toList() ??
              [];
          final circuitOpenStr = decoded['circuitOpenAt'] as String?;
          if (circuitOpenStr != null) {
            _circuitOpenAt = DateTime.tryParse(circuitOpenStr);
          }
        }
      } on FormatException {
        // Ignore
      }
    }
    _loaded = true;
  }

  Future<void> _persist() async {
    final prefs = _preferences ?? await SharedPreferences.getInstance();
    final trimmed = _recentEntries.length > maxEntries
        ? _recentEntries.sublist(_recentEntries.length - maxEntries)
        : _recentEntries;
    await prefs.setString(
      _key,
      jsonEncode({
        'entries': trimmed.map((e) => e.toJson()).toList(),
        if (_circuitOpenAt != null) 'circuitOpenAt': _circuitOpenAt!.toIso8601String(),
      }),
    );
  }

  /// Record inference attempt berhasil.
  Future<void> recordSuccess({
    required int latencyMs,
    int? responseLength,
  }) async {
    await load();
    _circuitOpenAt = null;

    _recentEntries.add(FfmSlmHealthEntry(
      timestamp: DateTime.now(),
      success: true,
      latencyMs: latencyMs,
      responseLength: responseLength,
    ));

    if (_recentEntries.length > maxEntries) {
      _recentEntries = _recentEntries.sublist(
        _recentEntries.length - maxEntries,
      );
    }

    await _persist();
  }

  /// Record inference attempt gagal.
  Future<void> recordFailure({
    required int latencyMs,
    required String errorType,
  }) async {
    await load();

    _recentEntries.add(FfmSlmHealthEntry(
      timestamp: DateTime.now(),
      success: false,
      latencyMs: latencyMs,
      errorType: errorType,
    ));

    if (_recentEntries.length > maxEntries) {
      _recentEntries = _recentEntries.sublist(
        _recentEntries.length - maxEntries,
      );
    }

    final recentFailures = _recentEntries.length > _circuitBreakerThreshold
        ? _recentEntries
            .sublist(_recentEntries.length - _circuitBreakerThreshold)
        : _recentEntries;

    if (recentFailures.length >= _circuitBreakerThreshold &&
        recentFailures.every((e) => !e.success)) {
      _circuitOpenAt = DateTime.now();
    }

    await _persist();
  }

  /// Force reset circuit breaker.
  Future<void> resetCircuitBreaker() async {
    _circuitOpenAt = null;
    await _persist();
  }

  /// Clear all health data.
  Future<void> clear() async {
    _recentEntries = [];
    _circuitOpenAt = null;
    await _persist();
  }

  /// Format health status untuk debugging.
  String formatDiagnostics() {
    final s = status;
    final buffer = StringBuffer('=== SLM Health ===\n');
    buffer.writeln('Status: ${s.name}');
    buffer.writeln('Success Rate: ${(successRate * 100).toStringAsFixed(1)}%');
    buffer.writeln('Avg Latency: ${averageLatencyMs}ms');
    buffer.writeln('Total Records: ${_recentEntries.length}');
    if (_circuitOpenAt != null) {
      buffer.writeln(
          'Circuit Open Since: ${_circuitOpenAt!.toIso8601String()}');
      final remaining = _circuitBreakerDuration -
          DateTime.now().difference(_circuitOpenAt!);
      if (remaining.isNegative) {
        buffer.writeln('Circuit Will Reset: NOW');
      } else {
        buffer.writeln(
            'Circuit Resets In: ${remaining.inMinutes}m ${remaining.inSeconds % 60}s');
      }
    }
    return buffer.toString();
  }
}
