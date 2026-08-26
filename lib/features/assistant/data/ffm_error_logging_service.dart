import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Error entry yang tercatat untuk debugging.
class FfmErrorLogEntry {
  const FfmErrorLogEntry({
    required this.id,
    required this.feature,
    required this.errorType,
    required this.message,
    required this.timestamp,
    this.stackTrace,
    this.context,
  });

  final String id;
  final String feature;
  final String errorType;
  final String message;
  final DateTime timestamp;
  final String? stackTrace;
  final Map<String, dynamic>? context;

  Map<String, dynamic> toJson() => {
    'id': id,
    'feature': feature,
    'errorType': errorType,
    'message': message,
    'timestamp': timestamp.toIso8601String(),
    if (stackTrace != null) 'stackTrace': stackTrace,
    if (context != null) 'context': context,
  };

  factory FfmErrorLogEntry.fromJson(Map<String, dynamic> json) {
    return FfmErrorLogEntry(
      id: json['id'] as String,
      feature: json['feature'] as String,
      errorType: json['errorType'] as String,
      message: json['message'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      stackTrace: json['stackTrace'] as String?,
      context: json['context'] as Map<String, dynamic>?,
    );
  }
}

/// Service untuk mencatat error yang terjadi di assistant/SLM pipeline.
///
/// Error dicatat ke SharedPreferences untuk debugging. Tidak ada network call.
class FfmErrorLoggingService {
  FfmErrorLoggingService({this._preferences});

  static const _key = 'ffm_error_logs_v1';
  static const maxEntries = 200;

  SharedPreferences? _preferences;

  Future<SharedPreferences> _prefs() async =>
      _preferences ??= await SharedPreferences.getInstance();

  /// Catat error baru.
  Future<void> logError({
    required String feature,
    required String errorType,
    required String message,
    String? stackTrace,
    Map<String, dynamic>? context,
  }) async {
    final prefs = await _prefs();
    final entries = await _loadEntries();

    final entry = FfmErrorLogEntry(
      id: 'err-${DateTime.now().microsecondsSinceEpoch}',
      feature: feature,
      errorType: errorType,
      message: message,
      timestamp: DateTime.now(),
      stackTrace: stackTrace,
      context: context,
    );

    entries.add(entry);

    final trimmed = entries.length > maxEntries
        ? entries.sublist(entries.length - maxEntries)
        : entries;

    await prefs.setString(
      _key,
      jsonEncode(trimmed.map((e) => e.toJson()).toList()),
    );
  }

  /// Ambil semua error entries.
  Future<List<FfmErrorLogEntry>> getAllEntries() async {
    return _loadEntries();
  }

  /// Ambil error entries untuk feature tertentu.
  Future<List<FfmErrorLogEntry>> getEntriesForFeature(String feature) async {
    final entries = await _loadEntries();
    return entries.where((e) => e.feature == feature).toList();
  }

  /// Ambil error entries terakhir (limit tertentu).
  Future<List<FfmErrorLogEntry>> getRecentEntries({int limit = 50}) async {
    final entries = await _loadEntries();
    if (entries.length <= limit) return entries;
    return entries.sublist(entries.length - limit);
  }

  /// Hitung jumlah error per feature.
  Future<Map<String, int>> getErrorCountsByFeature() async {
    final entries = await _loadEntries();
    final counts = <String, int>{};
    for (final entry in entries) {
      counts[entry.feature] = (counts[entry.feature] ?? 0) + 1;
    }
    return counts;
  }

  /// Hapus semua error logs.
  Future<void> clear() async {
    final prefs = await _prefs();
    await prefs.remove(_key);
  }

  /// Format error log untuk debugging / copy-paste.
  Future<String> formatForDiagnostics({int limit = 30}) async {
    final entries = await getRecentEntries(limit: limit);
    if (entries.isEmpty) return 'Tidak ada error yang tercatat.';

    final buffer = StringBuffer('=== FFM Error Log ===\n');
    for (final entry in entries) {
      buffer.writeln('[${entry.timestamp.toIso8601String()}]');
      buffer.writeln('  Feature: ${entry.feature}');
      buffer.writeln('  Error: ${entry.errorType}');
      buffer.writeln('  Message: ${entry.message}');
      if (entry.context != null) {
        buffer.writeln('  Context: ${jsonEncode(entry.context)}');
      }
      buffer.writeln();
    }
    return buffer.toString();
  }

  Future<List<FfmErrorLogEntry>> _loadEntries() async {
    final prefs = await _prefs();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((m) {
            try {
              return FfmErrorLogEntry.fromJson(
                Map<String, dynamic>.from(m),
              );
            } on Object {
              return null;
            }
          })
          .whereType<FfmErrorLogEntry>()
          .toList();
    } on FormatException {
      return [];
    }
  }
}
