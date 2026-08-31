import 'package:flutter/material.dart';

/// Indikator berpikir ala Claude: pill warm dengan spinner, bukan 3 titik Gemini.
/// Nama class dipertahankan untuk kompatibilitas.
class GeminiTypingIndicator extends StatelessWidget {
  const GeminiTypingIndicator({
    super.key,
    required this.message,
    this.onTap,
    this.steps,
    this.currentStepIndex = 0,
  });

  final String message;
  final VoidCallback? onTap;
  final List<String>? steps;
  final int currentStepIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Semantics(
          button: onTap != null,
          label: '$message. Ketuk untuk melihat detail proses.',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(12),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E1E1C)
                      : const Color(0xFFFDFCF9),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                    bottomLeft: Radius.circular(4),
                    bottomRight: Radius.circular(12),
                  ),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF3A3530)
                        : const Color(0xFFE8E0D0),
                    width: 0.8,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: isDark
                                ? const Color(0xFF9A9590)
                                : const Color(0xFFC27B5F),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          message,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: isDark
                                ? const Color(0xFF9A9590)
                                : const Color(0xFF6B5E4F),
                            fontWeight: FontWeight.w600,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        if (onTap != null) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.keyboard_arrow_up_rounded, size: 17),
                        ],
                      ],
                    ),
                    if (steps != null && steps!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ...steps!.asMap().entries.map((entry) {
                        final index = entry.key;
                        final step = entry.value;
                        final isCompleted = index < currentStepIndex;
                        final isCurrent = index == currentStepIndex;
                        
                        return Padding(
                          padding: const EdgeInsets.only(left: 2, top: 4),
                          child: Row(
                            children: [
                              Icon(
                                isCompleted
                                    ? Icons.check_circle
                                    : isCurrent
                                        ? Icons.radio_button_checked
                                        : Icons.radio_button_unchecked,
                                size: 12,
                                color: isCompleted
                                    ? (isDark
                                        ? const Color(0xFF4CAF50)
                                        : const Color(0xFF2E7D32))
                                    : isCurrent
                                        ? (isDark
                                            ? const Color(0xFF9A9590)
                                            : const Color(0xFFC27B5F))
                                        : (isDark
                                            ? Colors.white24
                                            : Colors.black26),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  step,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: isCompleted
                                        ? (isDark
                                            ? const Color(0xFF4CAF50)
                                            : const Color(0xFF2E7D32))
                                        : isCurrent
                                            ? (isDark
                                                ? const Color(0xFF9A9590)
                                                : const Color(0xFF6B5E4F))
                                            : (isDark
                                                ? Colors.white38
                                                : Colors.black38),
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
