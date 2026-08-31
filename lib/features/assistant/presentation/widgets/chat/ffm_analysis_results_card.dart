import 'package:flutter/material.dart';

class FfmAnalysisResultsCard extends StatelessWidget {
  const FfmAnalysisResultsCard({
    super.key,
    required this.results,
    this.onToggle,
    this.isExpanded = false,
  });

  final String results;
  final VoidCallback? onToggle;
  final bool isExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark 
            ? const Color(0xFF2A2A2A)
            : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark 
              ? const Color(0xFF2196F3).withValues(alpha: 0.3)
              : const Color(0xFF2196F3).withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    Icons.analytics,
                    size: 16,
                    color: isDark 
                        ? const Color(0xFF2196F3)
                        : const Color(0xFF1976D2),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Hasil Analisis',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark 
                            ? const Color(0xFF2196F3)
                            : const Color(0xFF1976D2),
                      ),
                    ),
                  ),
                  Icon(
                    isExpanded 
                        ? Icons.expand_less 
                        : Icons.expand_more,
                    size: 16,
                    color: isDark 
                        ? Colors.white70
                        : Colors.black54,
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Text(
                results,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark 
                      ? Colors.white70
                      : Colors.black87,
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
