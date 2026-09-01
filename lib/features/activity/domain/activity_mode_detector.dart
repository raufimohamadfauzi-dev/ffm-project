import 'entities/activity_entity.dart';

class ActivityModeDecision {
  const ActivityModeDecision({
    required this.mode,
    required this.confidence,
    required this.reason,
    this.requiresClarification = false,
  });

  final ActivityMode mode;
  final double confidence;
  final String reason;
  final bool requiresClarification;
}

/// Memilih mode aktivitas secara lokal dan deterministik.
///
/// Gemini boleh mengusulkan mode, tetapi nilai akhirnya selalu dinormalisasi
/// menjadi [ActivityKind.timer] atau [ActivityKind.note] sebelum disimpan.
class ActivityModeDetector {
  const ActivityModeDetector();

  ActivityModeDecision detect(String input) {
    final text = _normalize(input);
    if (text.isEmpty) {
      return const ActivityModeDecision(
        mode: ActivityMode.history,
        confidence: 0,
        reason: 'Perintah aktivitas masih kosong.',
        requiresClarification: true,
      );
    }

    final explicitHistory = _containsAny(text, const <String>[
      'catat ',
      'catatkan ',
      'buat riwayat',
      'simpan riwayat',
      'log ',
      'jurnal ',
    ]);
    final explicitTimer = _containsAny(text, const <String>[
      'mulai ',
      'mulai aktivitas',
      'sedang ',
      'lagi ',
      'lanjut ',
      'jalankan ',
      'pakai timer',
      'hentikan ',
      'stop ',
      'selesai ',
    ]);

    if (explicitHistory && !explicitTimer) {
      return const ActivityModeDecision(
        mode: ActivityMode.history,
        confidence: .98,
        reason: 'Pengguna meminta aktivitas dicatat sebagai riwayat.',
      );
    }
    if (explicitTimer && !explicitHistory) {
      return const ActivityModeDecision(
        mode: ActivityMode.timeTracking,
        confidence: .98,
        reason: 'Perintah menyatakan aktivitas sedang atau mulai berjalan.',
      );
    }
    if (explicitHistory && explicitTimer) {
      return const ActivityModeDecision(
        mode: ActivityMode.timeTracking,
        confidence: .45,
        reason: 'Perintah memuat sinyal timer dan catatan sekaligus.',
        requiresClarification: true,
      );
    }

    if (RegExp(r'\b(?:selama|durasi)\s+\d+|\bdari\s+jam\b|\bsampai\s+jam\b')
        .hasMatch(text)) {
      return const ActivityModeDecision(
        mode: ActivityMode.timeTracking,
        confidence: .94,
        reason: 'Perintah menyebut rentang atau durasi aktivitas.',
      );
    }

    if (_containsAny(text, const <String>[
      'tanam ',
      'nanam ',
      'menanam ',
      'bayar ',
      'membayar ',
      'terima ',
      'menerima ',
      'beli ',
      'membeli ',
      'panen ',
      'kirim ',
      'mengirim ',
    ])) {
      return const ActivityModeDecision(
        mode: ActivityMode.history,
        confidence: .86,
        reason: 'Perintah menggambarkan kejadian satu kali.',
      );
    }

    return const ActivityModeDecision(
      mode: ActivityMode.history,
      confidence: .4,
      reason: 'Belum ada petunjuk apakah aktivitas perlu dihitung waktunya.',
      requiresClarification: true,
    );
  }

  ActivityMode detectMode(
    String input, {
    ActivityKind? suggestedKind,
    bool hasDuration = false,
    bool hasStartTime = false,
    bool hasEndTime = false,
  }) {
    if (suggestedKind != null && suggestedKind != ActivityKind.timer) {
      return ActivityMode.defaultForKind(suggestedKind);
    }
    if (hasDuration || hasStartTime || hasEndTime) {
      return ActivityMode.timeTracking;
    }
    return detect(input).mode;
  }

  String getDetectionReason(
    String input,
    ActivityMode detectedMode, {
    ActivityKind? suggestedKind,
    bool hasDuration = false,
    bool hasStartTime = false,
    bool hasEndTime = false,
  }) => detect(input).reason;

  bool isAmbiguous(String input) => detect(input).requiresClarification;

  String getClarificationPrompt(String input) =>
      'Aktivitas ini mau dihitung waktunya atau cukup disimpan sebagai catatan riwayat?';

  ActivityKind recommendKindForMode(ActivityMode mode, String input) =>
      mode.activityKind;

  static bool _containsAny(String text, List<String> values) =>
      values.any(text.contains);

  static String _normalize(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ');
}
