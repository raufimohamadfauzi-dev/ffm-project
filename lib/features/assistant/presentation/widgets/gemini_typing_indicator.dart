import 'package:flutter/material.dart';

/// Indikator berpikir ala Claude: pill warm dengan spinner, bukan 3 titik Gemini.
/// Nama class dipertahankan untuk kompatibilitas.
class GeminiTypingIndicator extends StatelessWidget {
  const GeminiTypingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1C) : const Color(0xFFFDFCF9),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(12),
              topRight: Radius.circular(12),
              bottomLeft: Radius.circular(4),
              bottomRight: Radius.circular(12),
            ),
            border: Border.all(
              color: isDark ? const Color(0xFF3A3530) : const Color(0xFFE8E0D0),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: isDark ? const Color(0xFF9A9590) : const Color(0xFFC27B5F),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Sedang berpikir...',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: isDark ? const Color(0xFF9A9590) : const Color(0xFF6B5E4F),
                  fontWeight: FontWeight.w600,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
