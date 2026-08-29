import 'package:flutter/material.dart';

/// Card khusus untuk menampilkan visualisasi kaya hierarki aktivitas, sub-kegiatan, dan checkpoint
/// langsung di dalam bubble chat asisten.
class ActivitySessionChatCard extends StatelessWidget {
  const ActivitySessionChatCard({
    super.key,
    required this.title,
    required this.category,
    required this.duration,
    this.sessionId,
    this.isActive = true,
    this.checkpoints = const [],
    this.childSessions = const [],
    this.lastCheckpoint,
    this.onFinish,
    this.onUpdate,
    this.onChat,
  });

  final String title;
  final String category;
  final String duration;
  final String? sessionId;
  final bool isActive;
  final List<Map<String, dynamic>> checkpoints;
  final List<Map<String, dynamic>> childSessions;
  final String? lastCheckpoint;
  final VoidCallback? onFinish;
  final VoidCallback? onUpdate;
  final VoidCallback? onChat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final primaryColor = isDark ? const Color(0xFF5BBFB5) : const Color(0xFF00727A);
    final bgCard = isDark ? const Color(0xFF1E2627) : const Color(0xFFF0F7F6);
    final borderCard = isDark ? const Color(0xFF2C393A) : const Color(0xFFD3E7E5);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderCard, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Icon + Title + Status Pill
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: .15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isActive ? Icons.directions_run : Icons.check_circle_outline,
                  size: 18,
                  color: primaryColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      category.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isActive
                      ? (isDark ? const Color(0xFF1E3A2F) : const Color(0xFFD4EDDA))
                      : (isDark ? const Color(0xFF2A2E33) : const Color(0xFFE2E3E5)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isActive ? Colors.green : Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isActive ? 'Berjalan' : 'Selesai',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: isActive
                            ? (isDark ? const Color(0xFF75D89B) : const Color(0xFF155724))
                            : Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Total Duration Pill
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF252F30) : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: borderCard),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.timer_outlined, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      'Total Durasi',
                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                    ),
                  ],
                ),
                Text(
                  duration,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: primaryColor,
                  ),
                ),
              ],
            ),
          ),

          // Sub-kegiatan (Child Sessions)
          if (childSessions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Sub-Kegiatan (${childSessions.length})',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            ...childSessions.map((c) => Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF172021) : const Color(0xFFE8F2F0),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const Text(' └─ ', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  Expanded(
                    child: Text(
                      c['title'] as String? ?? 'Sub-kegiatan',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    c['duration'] as String? ?? '',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: primaryColor,
                    ),
                  ),
                ],
              ),
            )),
          ],

          // Checkpoints timeline
          if (checkpoints.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Milestone / Checkpoint',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            ...checkpoints.map((cp) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2, right: 6),
                    child: Icon(Icons.location_on_outlined, size: 12, color: Colors.amber),
                  ),
                  Expanded(
                    child: Text(
                      '${cp['label']}${cp['place'] != null ? " (${cp['place']})" : ""}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  if (cp['timeDiff'] != null)
                    Text(
                      '+${cp['timeDiff']}',
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                ],
              ),
            )),
          ] else if (lastCheckpoint != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 12, color: Colors.amber),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Update: $lastCheckpoint',
                    style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
                  ),
                ),
              ],
            ),
          ],

          // Quick-Action Buttons (hanya untuk sesi aktif)
          if (isActive && (onFinish != null || onUpdate != null || onChat != null)) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF252F30) : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: borderCard),
              ),
              child: Row(
                children: [
                  if (onFinish != null)
                    Expanded(
                      child: _QuickActionButton(
                        icon: Icons.check_circle_outline,
                        label: 'Selesai',
                        color: const Color(0xFF4CAF50),
                        onPressed: onFinish!,
                      ),
                    ),
                  if (onFinish != null && onUpdate != null) const SizedBox(width: 6),
                  if (onUpdate != null)
                    Expanded(
                      child: _QuickActionButton(
                        icon: Icons.edit_note,
                        label: 'Update',
                        color: primaryColor,
                        onPressed: onUpdate!,
                      ),
                    ),
                  if ((onFinish != null || onUpdate != null) && onChat != null) const SizedBox(width: 6),
                  if (onChat != null)
                    Expanded(
                      child: _QuickActionButton(
                        icon: Icons.chat_bubble_outline,
                        label: 'Chat',
                        color: isDark ? const Color(0xFFC9B8A8) : const Color(0xFF8B6F47),
                        onPressed: onChat!,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
