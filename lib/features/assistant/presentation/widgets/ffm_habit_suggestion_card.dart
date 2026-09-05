import 'package:flutter/material.dart';

import '../../domain/services/transaction_pattern_miner.dart';

/// Kartu santun rekomendasi kebiasaan rutin di dalam lembar Asisten FFM.
///
/// Didesain rapi, tidak menutupi layar (*anti pop-up liar*), dan memberikan
/// kontrol penuh kepada pengguna untuk mencatat seketika, melewati minggu ini,
/// atau mematikan saran.
class FfmHabitSuggestionCard extends StatelessWidget {
  const FfmHabitSuggestionCard({
    super.key,
    required this.pattern,
    required this.onAccept,
    required this.onSnooze,
    required this.onDismiss,
  });

  final MinedTransactionPattern pattern;
  final VoidCallback onAccept;
  final VoidCallback onSnooze;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF262115) : const Color(0xFFFFF9E6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.amber.shade700.withValues(alpha: 0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.amber.shade700.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('💡', style: TextStyle(fontSize: 16)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Saran Rutin Hari Ini',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                        color: isDark ? Colors.amber.shade300 : Colors.amber.shade900,
                      ),
                    ),
                    Text(
                      'Terdeteksi dari kebiasaan Anda',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                tooltip: 'Sembunyikan',
                visualDensity: VisualDensity.compact,
                onPressed: onSnooze,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            pattern.promptMessage,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: isDark ? Colors.grey[200] : Colors.grey[900],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.tonalIcon(
                onPressed: onAccept,
                icon: const Icon(Icons.add_task_rounded, size: 16),
                label: const Text('Catat Sekarang', style: TextStyle(fontSize: 12)),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: Colors.amber.shade700.withValues(alpha: 0.2),
                  foregroundColor: isDark ? Colors.amber.shade200 : Colors.amber.shade900,
                ),
              ),
              OutlinedButton.icon(
                onPressed: onSnooze,
                icon: const Icon(Icons.update_rounded, size: 15),
                label: const Text('Lewati Minggu Ini', style: TextStyle(fontSize: 11.5)),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  side: BorderSide(color: Colors.amber.shade700.withValues(alpha: 0.4)),
                ),
              ),
              TextButton(
                onPressed: () => _confirmDismiss(context),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: Colors.grey[600],
                ),
                child: const Text('Matikan Saran', style: TextStyle(fontSize: 11.5)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _confirmDismiss(BuildContext context) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Matikan Saran Rutin Ini?'),
        content: Text(
          'Asisten tidak akan lagi menyarankan pengeluaran "${pattern.title}" ini di masa mendatang.',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.of(ctx).pop(true);
              onDismiss();
            },
            child: const Text('Matikan'),
          ),
        ],
      ),
    );
  }
}
