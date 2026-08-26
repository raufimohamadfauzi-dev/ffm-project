import '../../../activity/domain/activity_voice.dart';
import '../../../activity/domain/entities/activity_entity.dart';
import '../../domain/ffm_agent_harness.dart';

/// Plugin Pengaman: Mencegah salah menutup sesi induk, mendeteksi ambiguitas hierarki,
/// dan menghasilkan draft terverifikasi sebelum commit mutasi.
class FfmActivityGuardPlugin extends FfmAgentPlugin {
  FfmActivityGuardPlugin();

  static const _voiceParser = ActivityVoiceParser();
  static const _calculator = ActivityDurationCalculator();

  @override
  String get name => 'activity_guard';

  @override
  FfmPluginCategory get category => FfmPluginCategory.logic;

  @override
  int get priority => 10;

  @override
  List<String> get triggers => [
    'selesai aktivitas',
    'tutup aktivitas',
    'selesai perjalanan',
    'stop activity',
    'akhiri aktivitas',
    'selesai makan',
    'beres makan',
    'selesai kapal',
    'beres perjalanan',
    'tutup sesi',
    'selesaikan',
    'sudah beres',
    'sudah selesai',
    'udah beres',
    'stop',
    'berhenti',
    'matikan timer',
    'akhiri',
    'kelar',
    'beresin',
  ];

  @override
  Future<FfmHarnessResult?> execute(FfmHarnessContext context) async {
    final snapshot = context.activitySnapshot;

    if (snapshot == null || !snapshot.hasActiveSessions) {
      return null;
    }

    final parsedIntent = _voiceParser.parse(
      context.rawText,
      activeSessions: snapshot.activeSessions,
    );

    // 1. Ambiguity / Clarification check
    if (parsedIntent.ambiguityReason != null) {
      return FfmHarnessResult(
        pluginName: name,
        category: category,
        text: '⚠️ **Perlu Konfirmasi:**\n${parsedIntent.ambiguityReason}',
        metadata: {
          'isAmbiguous': true,
          'confidence': parsedIntent.confidence,
          'ambiguityReason': parsedIntent.ambiguityReason,
        },
      );
    }

    final targetSessionId = parsedIntent.targetSessionId;
    if (targetSessionId == null) {
      return FfmHarnessResult(
        pluginName: name,
        category: category,
        text: '⚠️ Belum jelas aktivitas mana yang ingin kamu selesaikan. Sebutkan nama aktivitasnya ya.',
        metadata: {'isAmbiguous': true},
      );
    }

    final targetSession = snapshot.activeSessions.where((s) => s.id == targetSessionId).firstOrNull;
    if (targetSession == null) {
      return FfmHarnessResult(
        pluginName: name,
        category: category,
        text: '⚠️ Aktivitas tersebut sudah tidak aktif atau state di layar telah berubah.',
        metadata: {'stale': true},
      );
    }

    // 2. Hierarchy Check: If target is parent, check if it has active child sessions
    final activeChildren = snapshot.childrenOf(targetSession.id);
    if (activeChildren.isNotEmpty) {
      final childNames = activeChildren.map((c) => c.title).join(', ');
      return FfmHarnessResult(
        pluginName: name,
        category: category,
        isDraft: true,
        text: '⚠️ **Perhatian:** Sesi utama **${targetSession.title}** masih memiliki sub-kegiatan aktif: **$childNames**.\n\n'
            'Apakah kamu ingin menyelesaikan **semua sub-kegiatan sekaligus** dan menutup ${targetSession.title}?',
        metadata: {
          'hasActiveChildren': true,
          'activeChildrenCount': activeChildren.length,
          'targetSessionId': targetSession.id,
          'targetTitle': targetSession.title,
          'expectedRevision': snapshot.revision,
          'forceCloseChildren': true,
          'action': 'finish_session_with_children',
        },
      );
    }

    // 3. Safe Draft generation
    final duration = _calculator.format(targetSession.durationAt(context.now));
    final parentTitle = targetSession.parentSessionId != null
        ? snapshot.activeSessions.where((s) => s.id == targetSession.parentSessionId).firstOrNull?.title
        : null;

    final buffer = StringBuffer();
    buffer.writeln('Saya akan menyelesaikan:');
    buffer.writeln('✅ **${targetSession.title}** (${targetSession.category})');
    buffer.writeln('⏱️ Durasi: **$duration**');
    if (parentTitle != null) {
      buffer.writeln('📂 Aktivitas Induk: **$parentTitle**');
    }
    buffer.writeln('\nTekan **Konfirmasi** untuk menyimpan.');

    return FfmHarnessResult(
      pluginName: name,
      category: category,
      isDraft: true,
      text: buffer.toString().trim(),
      metadata: {
        'targetSessionId': targetSession.id,
        'targetTitle': targetSession.title,
        'duration': duration,
        'durationMs': targetSession.durationAt(context.now).inMilliseconds,
        'expectedRevision': snapshot.revision,
        'action': 'finish_session',
        'isSafe': true,
        'confidence': parsedIntent.confidence,
      },
    );
  }
}
