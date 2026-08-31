import 'package:flutter/material.dart';

class FfmVerifiedFactsCard extends StatelessWidget {
  const FfmVerifiedFactsCard({
    super.key,
    required this.facts,
    this.onToggle,
    this.isExpanded = false,
  });

  final String facts;
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
              ? const Color(0xFF4CAF50).withValues(alpha: 0.3)
              : const Color(0xFF4CAF50).withValues(alpha: 0.5),
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
                    Icons.verified,
                    size: 16,
                    color: isDark 
                        ? const Color(0xFF4CAF50)
                        : const Color(0xFF2E7D32),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Fakta Terverifikasi',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark 
                            ? const Color(0xFF4CAF50)
                            : const Color(0xFF2E7D32),
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
                facts,
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
