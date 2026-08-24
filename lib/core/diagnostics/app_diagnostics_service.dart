import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// Penyimpanan lokal diagnostik yang dapat diganti dengan memori saat test.
abstract interface class FfmDiagnosticsStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SharedPreferencesDiagnosticsStore implements FfmDiagnosticsStore {
  static const _keyPrefix = 'ffm_diagnostics';

  Future<SharedPreferences> get _preferences => SharedPreferences.getInstance();

  String _key(String key) => '$_keyPrefix.$key';

  @override
  Future<void> delete(String key) async {
    await (await _preferences).remove(_key(key));
  }

  @override
  Future<String?> read(String key) async =>
      (await _preferences).getString(_key(key));

  @override
  Future<void> write(String key, String value) async {
    await (await _preferences).setString(_key(key), value);
  }
}

/// Error lokal yang sudah disaring; tidak menyimpan data keuangan atau rahasia.
class FfmDiagnosticEntry {
  const FfmDiagnosticEntry({
    required this.code,
    required this.feature,
    required this.occurredAt,
    required this.summary,
    required this.stackTrace,
    required this.impact,
  });

  final String code;
  final String feature;
  final DateTime occurredAt;
  final String summary;
  final String stackTrace;
  final String impact;

  factory FfmDiagnosticEntry.fromJson(Map<String, dynamic> json) =>
      FfmDiagnosticEntry(
        code: json['code']?.toString() ?? 'UNKNOWN',
        feature: json['feature']?.toString() ?? 'Aplikasi',
        occurredAt:
            DateTime.tryParse(json['occurredAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        summary: json['summary']?.toString() ?? 'Tidak ada ringkasan.',
        stackTrace: json['stackTrace']?.toString() ?? '',
        impact: json['impact']?.toString() ?? 'Perlu dicoba ulang.',
      );

  Map<String, String> toJson() => <String, String>{
    'code': code,
    'feature': feature,
    'occurredAt': occurredAt.toIso8601String(),
    'summary': summary,
    'stackTrace': stackTrace,
    'impact': impact,
  };
}

/// Mencatat error yang benar-benar tertangkap tanpa mengubah alur utama FFM.
///
/// Layanan ini bersifat best effort: semua kesalahan internalnya ditelan agar
/// kegagalan pencatatan tidak pernah membatalkan transaksi atau mengunci UI.
class AppDiagnosticsService {
  AppDiagnosticsService({
    FfmDiagnosticsStore? store,
    DateTime Function()? clock,
  }) : _store = store ?? SharedPreferencesDiagnosticsStore(),
       _clock = clock ?? DateTime.now;

  static const _entriesKey = 'entries.v1';
  static const _startupKey = 'startup.v1';
  static const maxEntries = 20;
  static const _maxSummaryLength = 300;
  static const _maxStackLength = 1800;

  final FfmDiagnosticsStore _store;
  final DateTime Function() _clock;

  Future<void> markStartupStarted({required String phase}) async {
    try {
      await _store.write(
        _startupKey,
        jsonEncode({
          'status': 'started',
          'phase': _sanitize(phase, limit: 80),
          'startedAt': _clock().toIso8601String(),
        }),
      );
    } catch (_) {
      // Startup marker bersifat best effort.
    }
  }

  Future<void> markStartupPhase(String phase) async {
    try {
      final marker = await readStartupMarker() ?? <String, String>{};
      marker['status'] = 'started';
      marker['phase'] = _sanitize(phase, limit: 80);
      marker['updatedAt'] = _clock().toIso8601String();
      await _store.write(_startupKey, jsonEncode(marker));
    } catch (_) {
      // Startup marker bersifat best effort.
    }
  }

  Future<void> markStartupComplete() async {
    try {
      await _store.write(
        _startupKey,
        jsonEncode({
          'status': 'complete',
          'phase': 'first_frame',
          'completedAt': _clock().toIso8601String(),
        }),
      );
    } catch (_) {
      // Startup marker bersifat best effort.
    }
  }

  Future<Map<String, String>?> readStartupMarker() async {
    try {
      final content = await _store.read(_startupKey);
      if (content == null || content.trim().isEmpty) return null;
      final decoded = jsonDecode(content);
      if (decoded is! Map) return null;
      return decoded.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> recordInterruptedStartupIfNeeded() async {
    final marker = await readStartupMarker();
    if (marker?['status'] != 'started') return;
    await recordException(
      code: 'STARTUP_INTERRUPTED',
      feature: 'Bootstrap aplikasi',
      error:
          'Startup sebelumnya berhenti pada fase ${marker?['phase'] ?? 'tidak diketahui'}.',
      impact: 'Aplikasi berhasil dibuka kembali; periksa Bantuan perbaikan bila masalah berulang.',
    );
  }

  Future<void> recordException({
    required String code,
    required String feature,
    required Object error,
    StackTrace? stackTrace,
    required String impact,
  }) async {
    try {
      final entries = await latest();
      final entry = FfmDiagnosticEntry(
        code: _safeCode(code),
        feature: _sanitize(feature, limit: 80),
        occurredAt: _clock(),
        summary: _sanitize(error.toString(), limit: _maxSummaryLength),
        stackTrace: _sanitize(
          stackTrace?.toString() ?? '',
          limit: _maxStackLength,
        ),
        impact: _sanitize(impact, limit: 140),
      );
      final nextEntries = <FfmDiagnosticEntry>[
        entry,
        ...entries,
      ].take(maxEntries).toList(growable: false);
      await _store.write(
        _entriesKey,
        jsonEncode(nextEntries.map((item) => item.toJson()).toList()),
      );
    } catch (_) {
      // Diagnostik tidak boleh menggagalkan alur utama aplikasi.
    }
  }

  Future<List<FfmDiagnosticEntry>> latest() async {
    try {
      final content = await _store.read(_entriesKey);
      if (content == null || content.trim().isEmpty) return const [];
      final decoded = jsonDecode(content);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map(
            (item) =>
                FfmDiagnosticEntry.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<FfmDiagnosticEntry?> latestEntry() async {
    final entries = await latest();
    return entries.isEmpty ? null : entries.first;
  }

  Future<bool> hasEntries() async => (await latest()).isNotEmpty;

  Future<void> clear() async {
    try {
      await _store.delete(_entriesKey);
    } catch (_) {
      // Sama seperti pencatatan, pembersihan tidak boleh melempar ke UI.
    }
  }

  Future<String> buildSafeReport() async {
    final entries = await latest();
    final buffer = StringBuffer()
      ..writeln('LAPORAN DIAGNOSTIK FFM (AMAN)')
      ..writeln('Dibuat: ${_clock().toLocal().toIso8601String()}')
      ..writeln('Platform: ${Platform.operatingSystem}')
      ..writeln('Jumlah error tercatat: ${entries.length}')
      ..writeln(
        'Catatan: laporan ini tidak memuat PIN, token, data keuangan, rekening, atau isi transaksi.',
      );
    if (entries.isEmpty) {
      buffer.writeln('\nBelum ada error teknis yang tercatat.');
      return buffer.toString().trim();
    }
    for (var index = 0; index < entries.length; index++) {
      final entry = entries[index];
      buffer
        ..writeln('\n[${index + 1}] ${entry.code}')
        ..writeln('Fitur: ${entry.feature}')
        ..writeln('Waktu: ${entry.occurredAt.toLocal().toIso8601String()}')
        ..writeln('Dampak: ${entry.impact}')
        ..writeln('Ringkasan: ${entry.summary}');
      if (entry.stackTrace.isNotEmpty) {
        buffer.writeln('Stack tersaring: ${entry.stackTrace}');
      }
    }
    return buffer.toString().trim();
  }

  String _safeCode(String rawCode) {
    final normalized = rawCode
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9_]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return normalized.isEmpty
        ? 'UNKNOWN'
        : normalized.substring(0, normalized.length.clamp(0, 64));
  }

  String _sanitize(String value, {required int limit}) {
    var result = value;
    result = result.replaceAll(
      RegExp(
        r'(pin|password|kata[_ -]?sandi|token|secret|api[_ -]?key|authorization)\s*[:=]\s*([^\s,;]+)',
        caseSensitive: false,
      ),
      r'$1=<disamarkan>',
    );
    result = result.replaceAll(
      RegExp(
        r'(rekening|account|nama|name|catatan|note|nominal|amount|saldo|balance)\s*[:=]\s*("[^"]*"|[^,;\n}]+)',
        caseSensitive: false,
      ),
      r'$1=<disamarkan>',
    );
    result = result.replaceAll(
      RegExp(r'\b[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}\b'),
      '<email disamarkan>',
    );
    result = result.replaceAll(
      RegExp(r'/(?:data|storage|sdcard|home|private)/[^\s\n]+'),
      '<jalur lokal disamarkan>',
    );
    result = result.replaceAll(RegExp(r'\b\d{7,}\b'), '<angka disamarkan>');
    result = result.replaceAll(
      RegExp(r'\{[^{}]{0,1000}\}'),
      '<payload disamarkan>',
    );
    if (result.length > limit) return '${result.substring(0, limit)}…';
    return result;
  }
}
