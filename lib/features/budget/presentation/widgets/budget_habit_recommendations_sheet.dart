import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../data/budget_habit_analyzer.dart';

/// Read-only presentation of deterministic monthly budget recommendations.
class BudgetHabitRecommendationsSheet extends StatefulWidget {
  const BudgetHabitRecommendationsSheet({
    required this.loadAnalysis,
    super.key,
  });

  final Future<BudgetHabitAnalysis> Function() loadAnalysis;

  @override
  State<BudgetHabitRecommendationsSheet> createState() =>
      _BudgetHabitRecommendationsSheetState();
}

class _BudgetHabitRecommendationsSheetState
    extends State<BudgetHabitRecommendationsSheet> {
  Future<BudgetHabitAnalysis>? _analysis;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final analysis = Future.sync(widget.loadAnalysis);
    setState(() {
      _analysis = analysis;
    });
  }

  String _money(int value) {
    final digits = value.abs().toString();
    final groups = <String>[];
    for (var end = digits.length; end > 0; end -= 3) {
      final start = (end - 3).clamp(0, end);
      groups.insert(0, digits.substring(start, end));
    }
    return '${value < 0 ? '-' : ''}Rp${groups.join('.')}';
  }

  String _trendLabel(BudgetHabitTrend trend) => switch (trend) {
    BudgetHabitTrend.increasing => 'Meningkat',
    BudgetHabitTrend.stable => 'Stabil',
    BudgetHabitTrend.decreasing => 'Menurun',
  };

  IconData _trendIcon(BudgetHabitTrend trend) => switch (trend) {
    BudgetHabitTrend.increasing => Icons.trending_up_outlined,
    BudgetHabitTrend.stable => Icons.trending_flat_outlined,
    BudgetHabitTrend.decreasing => Icons.trending_down_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: FutureBuilder<BudgetHabitAnalysis>(
          future: _analysis,
          builder: (context, snapshot) {
            return ListView(
              shrinkWrap: true,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Rekomendasi kebiasaan',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Tutup rekomendasi kebiasaan',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Bersifat baca saja. Tidak ada anggaran atau data yang disimpan dari layar ini.',
                ),
                const SizedBox(height: 16),
                if (snapshot.connectionState != ConnectionState.done)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (snapshot.hasError)
                  _ErrorState(onRetry: _reload)
                else if (!snapshot.hasData ||
                    snapshot.data!.recommendations.isEmpty)
                  _InsufficientDataState(
                    historicalPeriodCount:
                        snapshot.data?.historicalPeriodCount ?? 3,
                  )
                else
                  ...snapshot.data!.recommendations.map(
                    (recommendation) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: AppCard(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              recommendation.categoryName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Sampel: ${recommendation.sampleCount} dari ${recommendation.historicalPeriodCount} bulan terakhir',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 8),
                            _RecommendationValue(
                              label: 'Median pengeluaran',
                              value: _money(recommendation.medianMonthlySpend),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(
                                  _trendIcon(recommendation.trend),
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Tren: ${_trendLabel(recommendation.trend)}',
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            _RecommendationValue(
                              label: 'Rekomendasi bulanan',
                              value: _money(
                                recommendation.recommendedMonthlyAmount,
                              ),
                              color: AppColors.primary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RecommendationValue extends StatelessWidget {
  const _RecommendationValue({
    required this.label,
    required this.value,
    this.color,
  });

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(label)),
      Text(
        value,
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
      ),
    ],
  );
}

class _InsufficientDataState extends StatelessWidget {
  const _InsufficientDataState({required this.historicalPeriodCount});

  final int historicalPeriodCount;

  @override
  Widget build(BuildContext context) => AppEmptyState(
    icon: Icons.insights_outlined,
    title: 'Data belum cukup',
    message:
        'Butuh pengeluaran pada setidaknya 2 bulan dari $historicalPeriodCount bulan terakhir untuk membuat rekomendasi.',
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => AppEmptyState(
    icon: Icons.error_outline,
    title: 'Rekomendasi belum dapat dimuat',
    message: 'Periksa koneksi atau data Anda, lalu coba lagi.',
    action: OutlinedButton.icon(
      onPressed: onRetry,
      icon: const Icon(Icons.refresh),
      label: const Text('Coba lagi'),
    ),
  );
}
