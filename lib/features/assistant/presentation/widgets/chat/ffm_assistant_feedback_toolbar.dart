import 'package:flutter/material.dart';

class FfmAssistantFeedbackToolbar extends StatelessWidget {
  const FfmAssistantFeedbackToolbar({
    super.key,
    required this.onThumbsUp,
    required this.onThumbsDown,
    this.onMarkIncorrect,
    this.onReportIssue,
    this.onProvideCorrection,
  });

  final VoidCallback onThumbsUp;
  final VoidCallback onThumbsDown;
  final VoidCallback? onMarkIncorrect;
  final VoidCallback? onReportIssue;
  final VoidCallback? onProvideCorrection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark 
            ? const Color(0xFF2A2A2A)
            : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildIconButton(
            icon: Icons.thumb_up,
            label: 'Berguna',
            color: isDark 
                ? const Color(0xFF4CAF50)
                : const Color(0xFF2E7D32),
            onTap: onThumbsUp,
          ),
          const SizedBox(width: 8),
          _buildIconButton(
            icon: Icons.thumb_down,
            label: 'Tidak berguna',
            color: isDark 
                ? const Color(0xFFF44336)
                : const Color(0xFFC62828),
            onTap: onThumbsDown,
          ),
          if (onMarkIncorrect != null) ...[
            const SizedBox(width: 8),
            _buildIconButton(
              icon: Icons.error_outline,
              label: 'Salah',
              color: isDark 
                  ? const Color(0xFFFF9800)
                  : const Color(0xFFEF6C00),
              onTap: onMarkIncorrect!,
            ),
          ],
          if (onReportIssue != null) ...[
            const SizedBox(width: 8),
            _buildIconButton(
              icon: Icons.flag,
              label: 'Lapor',
              color: isDark 
                  ? const Color(0xFF2196F3)
                  : const Color(0xFF1565C0),
              onTap: onReportIssue!,
            ),
          ],
          if (onProvideCorrection != null) ...[
            const SizedBox(width: 8),
            _buildIconButton(
              icon: Icons.edit,
              label: 'Koreksi',
              color: isDark 
                  ? const Color(0xFFE1BEE7)
                  : const Color(0xFF6A1B9A),
              onTap: onProvideCorrection!,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: color,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
