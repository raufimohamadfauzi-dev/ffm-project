import '../../../activity/domain/entities/activity_entity.dart';
import '../../domain/ffm_agent_harness.dart';

/// Plugin Logika: Menghitung durasi rinci, relasi parent-child, dan rekap perjalanan/aktivitas.
class FfmActivityContextPlugin extends FfmAgentPlugin {
  FfmActivityContextPlugin();

  static const _calculator = ActivityDurationCalculator();

  @override
  String get name => 'activity_context_logic';

  @override
  FfmPluginCategory get category => FfmPluginCategory.logic;

  @override
  int get priority => 10;

  @override
  List<String> get triggers => [
    'berapa lama makan',
    'berapa lama di kapal',
    'sudah berapa lama di perjalanan',
    'rekap perjalanan',
    'ringkasan hari ini',
    'rekap aktivitas',
    'durasi aktivitas',
    'total waktu makan',
    'berapa lama di',
    'sudah berapa lama',
    'timeline aktivitas',
    'rekap sesi',
  ];

  @override
  Future<FfmHarnessResult?> execute(FfmHarnessContext context) async {
    final snapshot = context.activitySnapshot;
    final now = context.now;

    if (snapshot == null || !snapshot.hasActiveSessions) {
      return const FfmHarnessResult(
        pluginName: 'activity_context_logic',
        category: FfmPluginCategory.logic,
        text: 'Tidak ada sesi aktivitas aktif saat ini untuk direkap.',
        metadata: {'hasActive': false},
      );
    }

    final query = context.normalizedText.toLowerCase();

    // Check if user specifically asked for a sub-activity like "makan", "kapal", etc.
    for (final session in snapshot.activeSessions) {
      final titleLower = session.title.toLowerCase();
      if (query.contains(titleLower) && (query.contains('berapa lama') || query.contains('durasi'))) {
        final dur = _calculator.format(session.durationAt(now));
        final parentInfo = session.parentSessionId != null
            ? () {
                final p = snapshot.activeSessions.where((s) => s.id == session.parentSessionId).firstOrNull;
                return p != null ? ' (di dalam ${p.title})' : '';
              }()
            : '';
        return FfmHarnessResult(
          pluginName: name,
          category: category,
          text: '⏱️ Kamu sedang melakukan **${session.title}**$parentInfo selama **$dur**.',
          metadata: {
            'sessionId': session.id,
            'title': session.title,
            'duration': dur,
            'durationMs': session.durationAt(now).inMilliseconds,
            'isChild': session.parentSessionId != null,
            'activity_payload_type': 'single_duration',
          },
        );
      }
    }

    // Full journey / activity recap
    final rootSessions = snapshot.activeSessions.where((s) => s.parentSessionId == null).toList();
    final childSessions = snapshot.activeSessions.where((s) => s.parentSessionId != null).toList();

    final buffer = StringBuffer();
    final cardPayloads = <Map<String, dynamic>>[];

    for (final root in rootSessions) {
      final rootDuration = _calculator.format(root.durationAt(now));
      buffer.writeln('🚗 **Rekap: ${root.title}**');
      buffer.writeln('• Total durasi berjalan: **$rootDuration**');

      final children = childSessions.where((c) => c.parentSessionId == root.id).toList();
      final childItems = <Map<String, dynamic>>[];
      if (children.isNotEmpty) {
        final subList = children
            .map((c) => '${c.title} (${_calculator.format(c.durationAt(now))})')
            .join(', ');
        buffer.writeln('• Sub-kegiatan: $subList');
        for (final c in children) {
          childItems.add({
            'title': c.title,
            'duration': _calculator.format(c.durationAt(now)),
            'category': c.category,
          });
        }
      }

      final checkpoints = snapshot.checkpoints[root.id] ?? const [];
      final cpItems = <Map<String, dynamic>>[];
      if (checkpoints.isNotEmpty) {
        buffer.writeln('• Checkpoint:');
        for (var i = 0; i < checkpoints.length; i++) {
          final cp = checkpoints[i];
          final prevTime = i == 0 ? root.startedAt : checkpoints[i - 1].occurredAt;
          final diff = _calculator.format(cp.occurredAt.difference(prevTime));
          buffer.writeln('  - ${cp.label} (+ $diff)');
          cpItems.add({
            'label': cp.label,
            'place': cp.place,
            'timeDiff': diff,
            'occurredAt': cp.occurredAt.toIso8601String(),
          });
        }
      }

      cardPayloads.add({
        'id': root.id,
        'title': root.title,
        'category': root.category,
        'duration': rootDuration,
        'children': childItems,
        'checkpoints': cpItems,
      });
      buffer.writeln();
    }

    return FfmHarnessResult(
      pluginName: name,
      category: category,
      text: buffer.toString().trim(),
      metadata: {
        'activity_payload_type': 'journey_recap',
        'recapCards': cardPayloads,
      },
    );
  }
}
