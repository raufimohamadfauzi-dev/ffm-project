import 'dart:async';
import 'package:flutter/material.dart';

import '../../domain/entities/activity_entity.dart';

/// Horizontal card strip yang tampil di atas input chat Asisten saat ada sesi aktivitas aktif.
///
/// Menampilkan:
/// - Nama root session + kategori
/// - Live duration berbasis timestamp aktual (bukan increment counter)
/// - Sub-sesi aktif yang sedang berjalan di dalamnya
/// - Checkpoint terakhir
/// - Tombol [Update] & [Selesai]
class ActivityLiveBar extends StatefulWidget {
  const ActivityLiveBar({
    super.key,
    required this.snapshot,
    required this.onUpdateCheckpoint,
    required this.onFinishSession,
  });

  final ActivityLiveSnapshot snapshot;
  final ValueChanged<ActivitySessionEntity> onUpdateCheckpoint;
  final ValueChanged<ActivitySessionEntity> onFinishSession;

  @override
  State<ActivityLiveBar> createState() => _ActivityLiveBarState();
}

class _ActivityLiveBarState extends State<ActivityLiveBar> {
  Timer? _timer;
  static const _calculator = ActivityDurationCalculator();

  @override
  void initState() {
    super.initState();
    // Ticker hanya mentrigger rebuild UI setiap 1 detik agar durasi timestamp-based ter-refresh
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.snapshot.hasActiveSessions) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final rootSessions = widget.snapshot.activeSessions
        .where((s) => s.parentSessionId == null)
        .toList();

    // If no root session with null parent, use all active
    final displaySessions = rootSessions.isNotEmpty ? rootSessions : widget.snapshot.activeSessions;

    final primaryColor = isDark ? const Color(0xFF5BBFB5) : const Color(0xFF00727A);
    final bgBar = isDark ? const Color(0xFF1E2829) : const Color(0xFFE6F3F1);
    final borderColor = isDark ? const Color(0xFF2E3F40) : const Color(0xFFCCE4E1);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bgBar,
        border: Border(
          top: BorderSide(color: borderColor, width: 1.2),
          bottom: BorderSide(color: borderColor, width: 1.2),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: displaySessions.map((session) {
          final now = DateTime.now();
          final duration = _calculator.format(session.durationAt(now));
          final activeChildren = widget.snapshot.childrenOf(session.id);
          final lastCp = widget.snapshot.lastCheckpointFor(session.id);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Root row: Running icon, Title, Category, Timer, Action buttons
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: .15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.directions_run, size: 16, color: primaryColor),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                session.title,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.2,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: primaryColor.withValues(alpha: .12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                session.category.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: primaryColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '⏱️ $duration',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: primaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Actions: Update & Selesai
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                          minimumSize: const Size(0, 28),
                          side: BorderSide(color: primaryColor.withValues(alpha: .5)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        onPressed: () => widget.onUpdateCheckpoint(session),
                        icon: const Icon(Icons.add_location_alt_outlined, size: 13),
                        label: const Text('Update', style: TextStyle(fontSize: 11)),
                      ),
                      const SizedBox(width: 6),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: primaryColor,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                          minimumSize: const Size(0, 28),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        onPressed: () => widget.onFinishSession(session),
                        child: const Text('Selesai', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ],
              ),

              // Active child sessions
              if (activeChildren.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 28, top: 4),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: activeChildren.map((child) {
                      final childDur = _calculator.format(child.durationAt(now));
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF162122) : Colors.white,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: borderColor),
                        ),
                        child: Text(
                          '└─ ${child.title} · $childDur',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                        ),
                      );
                    }).toList(),
                  ),
                ),

              // Last checkpoint milestone
              if (lastCp != null)
                Padding(
                  padding: const EdgeInsets.only(left: 28, top: 3),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on_outlined, size: 11, color: Colors.amber),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          '${lastCp.label}${lastCp.place != null ? " (${lastCp.place})" : ""}',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        }).toList(),
      ),
    );
  }
}
