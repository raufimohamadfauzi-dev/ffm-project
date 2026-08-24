import 'package:flutter/material.dart';

import '../../data/ffm_personal_memory_service.dart';

/// Kartu nudge kecil yang muncul di atas input bar
/// ketika asisten mendeteksi fakta baru tentang pengguna.
///
/// Mirip dengan "Claude remembered..." prompt tapi dengan konfirmasi.
class FfmMemoryNudgeCard extends StatelessWidget {
  const FfmMemoryNudgeCard({
    super.key,
    required this.insight,
    required this.onSave,
    required this.onDismiss,
  });

  final FfmPersonalMemoryInsight insight;
  final VoidCallback onSave;
  final VoidCallback onDismiss;

  static IconData _kindIcon(FfmPersonalMemoryKind kind) => switch (kind) {
    FfmPersonalMemoryKind.preference => Icons.lightbulb_outline_rounded,
    FfmPersonalMemoryKind.habitChat => Icons.chat_bubble_outline_rounded,
    FfmPersonalMemoryKind.habitData => Icons.bar_chart_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AnimatedSize(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeInOut,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A2B24) : const Color(0xFFE6F4EE),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark
                ? const Color(0xFF00D18F).withValues(alpha: 0.35)
                : const Color(0xFF00A876).withValues(alpha: 0.45),
            width: 0.9,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark
                    ? const Color(0xFF00D18F).withValues(alpha: 0.15)
                    : const Color(0xFF00A876).withValues(alpha: 0.12),
              ),
              child: Center(
                child: Icon(
                  _kindIcon(insight.kind),
                  size: 16,
                  color: isDark ? const Color(0xFF00D18F) : const Color(0xFF00875A),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Boleh aku ingat ini?',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isDark ? const Color(0xFF00D18F) : const Color(0xFF00875A),
                    ),
                  ),
                  const SizedBox(height: 1.5),
                  Text(
                    insight.humanLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.onSurface,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Tombol aksi
            _ActionBtn(
              label: 'Simpan',
              isPrimary: true,
              onTap: onSave,
              isDark: isDark,
            ),
            const SizedBox(width: 6),
            _ActionBtn(
              label: 'Abaikan',
              isPrimary: false,
              onTap: onDismiss,
              isDark: isDark,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.label,
    required this.isPrimary,
    required this.onTap,
    required this.isDark,
  });

  final String label;
  final bool isPrimary;
  final VoidCallback onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final bgColor = isPrimary
        ? (isDark ? const Color(0xFF00D18F) : const Color(0xFF00875A))
        : Colors.transparent;
    final fgColor = isPrimary
        ? Colors.white
        : (isDark ? Colors.white60 : Colors.black54);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: isPrimary
              ? null
              : Border.all(
                  color: isDark ? Colors.white24 : Colors.black12,
                  width: 0.8,
                ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: fgColor,
          ),
        ),
      ),
    );
  }
}
