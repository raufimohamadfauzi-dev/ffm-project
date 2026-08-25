import '../../../activity/domain/entities/activity_entity.dart';
import '../../domain/ffm_agent_harness.dart';

/// Plugin Mata: Membaca status aktivitas yang sedang berjalan di layar secara live dari [ActivityLiveSnapshot].
///
/// Membaca state in-memory (RAM) bukan database, sehingga setiap perubahan di UI
/// (mulai sesi, checkpoint, tutup sesi) langsung terbaca oleh Asisten secara real-time.
class FfmLiveActivitySensePlugin extends FfmAgentPlugin {
  FfmLiveActivitySensePlugin();

  static const _calculator = ActivityDurationCalculator();

  @override
  String get name => 'live_activity_sense';

  @override
  FfmPluginCategory get category => FfmPluginCategory.sense;

  @override
  int get priority => 10;

  @override
  List<String> get triggers => [
    'aktivitas sekarang',
    'sedang apa sekarang',
    'lagi ngapain',
    'sesi aktif',
    'berapa lama perjalanan',
    'berapa lama makan',
    'durasi sesi',
    'kegiatan sekarang',
    'lagi ngapain sekarang',
    'ada aktivitas apa',
    'aktivitas yang sedang berjalan',
    'status aktivitas',
  ];

  @override
  Future<FfmHarnessResult?> execute(FfmHarnessContext context) async {
    final snapshot = context.activitySnapshot;

    if (snapshot == null || !snapshot.hasActiveSessions) {
      final text = context.normalizedText.toLowerCase();
      if (!text.contains('aktivitas') && !text.contains('kegiatan') && !text.contains('sesi')) {
        return null;
      }
      return const FfmHarnessResult(
        pluginName: 'live_activity_sense',
        category: FfmPluginCategory.sense,
        text: 'Saat ini belum ada aktivitas yang sedang berjalan. '
            'Kamu bisa memulai aktivitas baru dengan perintah seperti: *"Mulai aktivitas Perjalanan ke Bandung"*.',
        metadata: {'hasActive': false, 'activeCount': 0},
      );
    }

    final now = context.now;
    final rootSessions = snapshot.activeSessions.where((s) => s.parentSessionId == null).toList();
    final childSessions = snapshot.activeSessions.where((s) => s.parentSessionId != null).toList();

    final buffer = StringBuffer();
    buffer.writeln('📋 **Aktivitas yang Sedang Berjalan:**');

    final structuredSessions = <Map<String, dynamic>>[];

    for (final root in rootSessions) {
      final duration = _calculator.format(root.durationAt(now));
      buffer.writeln('\n🏃 **${root.title}** (${root.category}) — berjalan **$duration**');

      final lastCp = snapshot.lastCheckpointFor(root.id);
      if (lastCp != null) {
        buffer.writeln('  📍 Update terakhir: ${lastCp.label}${lastCp.place != null ? " di ${lastCp.place}" : ""}');
      }

      final children = childSessions.where((c) => c.parentSessionId == root.id).toList();
      final childData = <Map<String, dynamic>>[];
      for (final child in children) {
        final childDur = _calculator.format(child.durationAt(now));
        buffer.writeln('  └─ ⏳ **${child.title}** — $childDur');
        childData.add({
          'id': child.id,
          'title': child.title,
          'category': child.category,
          'duration': childDur,
          'durationMs': child.durationAt(now).inMilliseconds,
        });
      }

      structuredSessions.add({
        'id': root.id,
        'title': root.title,
        'category': root.category,
        'duration': duration,
        'durationMs': root.durationAt(now).inMilliseconds,
        'startedAt': root.startedAt.toIso8601String(),
        'lastCheckpoint': lastCp?.label,
        'children': childData,
      });
    }

    // Include orphaned active child sessions if any
    final orphanedChildren = childSessions.where((c) => !rootSessions.any((r) => r.id == c.parentSessionId)).toList();
    for (final orphan in orphanedChildren) {
      final duration = _calculator.format(orphan.durationAt(now));
      buffer.writeln('\n⏳ **${orphan.title}** (${orphan.category}) — $duration (sub-kegiatan)');
      structuredSessions.add({
        'id': orphan.id,
        'title': orphan.title,
        'category': orphan.category,
        'duration': duration,
        'durationMs': orphan.durationAt(now).inMilliseconds,
        'startedAt': orphan.startedAt.toIso8601String(),
        'parentSessionId': orphan.parentSessionId,
      });
    }

    return FfmHarnessResult(
      pluginName: name,
      category: category,
      text: buffer.toString().trim(),
      metadata: {
        'revision': snapshot.revision,
        'hasActive': true,
        'activeCount': snapshot.activeSessions.length,
        'sessions': structuredSessions,
        'activity_payload_type': 'live_activity',
      },
    );
  }
}
