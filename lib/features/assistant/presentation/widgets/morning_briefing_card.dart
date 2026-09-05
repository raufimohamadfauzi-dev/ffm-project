import 'package:flutter/material.dart';

import '../../domain/services/executive_morning_briefing_service.dart';

/// Kartu visual elegan Executive Morning Briefing dengan kendali penuh Audio dan Teks.
class MorningBriefingCard extends StatelessWidget {
  const MorningBriefingCard({
    super.key,
    required this.briefing,
    required this.onPlayAudio,
    required this.onPauseAudio,
    required this.onStopAudio,
    required this.onClose,
    required this.isPlaying,
    required this.isPaused,
  });

  final ExecutiveMorningBriefing briefing;
  final VoidCallback onPlayAudio;
  final VoidCallback onPauseAudio;
  final VoidCallback onStopAudio;
  final VoidCallback onClose;
  final bool isPlaying;
  final bool isPaused;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xFF282015), Color(0xFF1E1A16)]
              : const [Color(0xFFFFFBEB), Color(0xFFFEF3C7)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? Colors.amber.shade700.withValues(alpha: 0.4)
              : Colors.amber.shade400.withValues(alpha: 0.6),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade600.withValues(alpha: 0.25),
                  shape: BoxShape.circle,
                ),
                child: const Text('🌅', style: TextStyle(fontSize: 18)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Executive Morning Briefing',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: isDark
                            ? Colors.amber.shade200
                            : Colors.amber.shade900,
                      ),
                    ),
                    Text(
                      'Rangkuman Finansial Pagi · ${briefing.familyName}',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark ? Colors.grey[400] : Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                tooltip: 'Tutup Briefing',
                visualDensity: VisualDensity.compact,
                onPressed: onClose,
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Metrik Ringkas Finansial
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  title: 'Saldo Kas',
                  value: _formatRupiah(briefing.totalCashBalance),
                  icon: Icons.account_balance_wallet_rounded,
                  color: const Color(0xFF00A876),
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricTile(
                  title: 'Kemarin',
                  value: briefing.yesterdayExpense > 0
                      ? _formatRupiah(briefing.yesterdayExpense)
                      : 'Rp 0',
                  icon: Icons.history_rounded,
                  color: Colors.orangeAccent.shade700,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricTile(
                  title: 'Bulan Ini',
                  value: _formatRupiah(briefing.monthExpenseSoFar),
                  icon: Icons.calendar_today_rounded,
                  color: Colors.blueAccent,
                  isDark: isDark,
                ),
              ),
            ],
          ),

          // Agenda & Pola Hari Ini (jika ada)
          if (briefing.dueItems.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.25)
                    : Colors.white.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.05),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.notifications_active_rounded,
                        size: 14,
                        color: Colors.amber,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Agenda & Pola Hari Ini',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.grey[300] : Colors.grey[800],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ...briefing.dueItems.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        '• $item',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark ? Colors.grey[300] : Colors.grey[700],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),

          // Kontrol Audio Penuh
          Row(
            children: [
              if (!isPlaying && !isPaused)
                FilledButton.icon(
                  onPressed: onPlayAudio,
                  icon: const Icon(Icons.volume_up_rounded, size: 16),
                  label: const Text(
                    'Putar Suara',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: Colors.amber.shade700,
                    foregroundColor: Colors.white,
                  ),
                )
              else if (isPlaying) ...[
                FilledButton.icon(
                  onPressed: onPauseAudio,
                  icon: const Icon(Icons.pause_rounded, size: 16),
                  label: const Text('Jeda', style: TextStyle(fontSize: 12)),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: Colors.amber.shade700,
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: onStopAudio,
                  icon: const Icon(Icons.stop_rounded, size: 16),
                  label: const Text('Berhenti', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ] else if (isPaused) ...[
                FilledButton.icon(
                  onPressed: onPlayAudio,
                  icon: const Icon(Icons.play_arrow_rounded, size: 16),
                  label: const Text('Lanjutkan', style: TextStyle(fontSize: 12)),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: Colors.amber.shade700,
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: onStopAudio,
                  icon: const Icon(Icons.stop_rounded, size: 16),
                  label: const Text('Berhenti', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
              const Spacer(),
              TextButton(
                onPressed: onClose,
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                child: Text(
                  'Tutup',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatRupiah(int val) {
    final s = val.abs().toString();
    final buffer = StringBuffer(val < 0 ? '-Rp ' : 'Rp ');
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write('.');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.isDark,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.black.withValues(alpha: 0.2)
            : Colors.white.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.04),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
