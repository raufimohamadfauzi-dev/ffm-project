import 'package:flutter/material.dart';

import '../../../../core/database/app_context.dart';
import '../../../../core/di/injection.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../../assistant/domain/ffm_assistant_models.dart';
import '../../../assistant/presentation/widgets/ffm_assistant_page_context.dart';
import '../../../transaction/domain/entities/transaction_entity.dart';
import '../../../transaction/domain/usecases/transaction_crud_usecases.dart';

class AnalysisPage extends StatefulWidget {
  const AnalysisPage({super.key});
  @override
  State<AnalysisPage> createState() => _AnalysisPageState();
}

class _AnalysisPageState extends State<AnalysisPage> {
  late Future<List<TransactionWithItems>> _future;
  @override
  void initState() {
    super.initState();
    _future = getIt<GetTransactions>()(AppContext.householdId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TransactionWithItems>>(
      future: _future,
      builder: (context, snapshot) {
        final items = snapshot.data ?? [];
        final income = items
            .where((item) => item.transaction.amount > 0)
            .length;
        final expense = items
            .where((item) => item.transaction.amount < 0)
            .length;
        final summary = snapshot.hasData
            ? 'Menganalisa ${items.length} transaksi: $income pemasukan dan $expense pengeluaran.'
            : 'Sedang menganalisa transaksi...';

        return FfmAssistantPageContext(
          destination: FfmAssistantDestination.analysis,
          dataSummary: summary,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Analisa'),
              actions: [
                IconButton(
                  tooltip: 'Info Analisa',
                  onPressed: () => showAppInfoDialog(
                    context,
                    title: 'Baca pola keuangan',
                    message: 'Gunakan kategori, toko, tag, dan tanggal untuk melihat kebiasaan keuangan keluarga. Semua angka di sini berasal dari transaksi yang tersimpan di perangkat.',
                  ),
                  icon: const Icon(Icons.info_outline),
                ),
              ],
            ),
            body: snapshot.connectionState == ConnectionState.waiting
                ? const Center(child: CircularProgressIndicator())
                : _buildBody(items),
          ),
        );
      },
    );
  }

  Widget _buildBody(List<TransactionWithItems> items) {
    final income = items
        .where((item) => item.transaction.amount > 0)
        .fold<int>(0, (sum, item) => sum + item.transaction.amount);
    final expense = items
        .where((item) => item.transaction.amount < 0)
        .fold<int>(0, (sum, item) => sum + item.transaction.amount.abs());
    final now = DateTime.now();
    final monthly = List.generate(6, (index) {
      final month = DateTime(now.year, now.month - 5 + index);
      var income = 0;
      var expense = 0;
      for (final item in items) {
        if (item.transaction.date.year != month.year ||
            item.transaction.date.month != month.month) {
          continue;
        }
        if (item.transaction.amount > 0) {
          income += item.transaction.amount;
        } else {
          expense += item.transaction.amount.abs();
        }
      }
      return _MonthlyAnalysisPoint(
        month: month,
        income: income,
        expense: expense,
      );
    });
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        Row(
          children: [
            Expanded(
              child: _Metric(
                title: 'Pemasukan',
                value: income,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Metric(
                title: 'Pengeluaran',
                value: expense,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _MonthlyAnalysisChart(points: monthly),
        const SizedBox(height: 12),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Jumlah transaksi',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text('${items.length} transaksi tersimpan di perangkat ini.'),
            ],
          ),
        ),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 24),
            child: AppEmptyState(
              icon: Icons.insights_outlined,
              title: 'Belum ada pola yang bisa dibaca',
              message: 'Catat beberapa transaksi dulu. Nanti analisa akan mulai menunjukkan perbandingan nyata.',
            ),
          ),
      ],
    );
  }
}

class _MonthlyAnalysisPoint {
  const _MonthlyAnalysisPoint({
    required this.month,
    required this.income,
    required this.expense,
  });

  final DateTime month;
  final int income;
  final int expense;
}

class _MonthlyAnalysisChart extends StatelessWidget {
  const _MonthlyAnalysisChart({required this.points});

  final List<_MonthlyAnalysisPoint> points;

  static const _labels = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];

  String _compact(int value) {
    if (value >= 1000000) {
      return 'Rp${(value / 1000000).toStringAsFixed(value % 1000000 == 0 ? 0 : 1)} jt';
    }
    if (value >= 1000) {
      return 'Rp${(value / 1000).toStringAsFixed(value % 1000 == 0 ? 0 : 1)} rb';
    }
    return 'Rp$value';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxValue = points.fold<int>(0, (max, point) {
      final value = point.income > point.expense ? point.income : point.expense;
      return value > max ? value : max;
    });
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Arus kas 6 bulan terakhir',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Perbandingan pemasukan dan pengeluaran per bulan.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _LegendDot(color: scheme.primary, label: 'Masuk'),
              const SizedBox(width: 16),
              _LegendDot(color: scheme.error, label: 'Keluar'),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 165,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: points
                  .map((point) {
                    final incomeHeight = maxValue == 0
                        ? 4.0
                        : 92 * point.income / maxValue;
                    final expenseHeight = maxValue == 0
                        ? 4.0
                        : 92 * point.expense / maxValue;
                    return Expanded(
                      child: Semantics(
                        label:
                            '${_labels[point.month.month - 1]}: masuk ${point.income}, keluar ${point.expense}',
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            SizedBox(
                              height: 20,
                              child: point.income == 0
                                  ? null
                                  : FittedBox(
                                      child: Text(
                                        _compact(point.income),
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall,
                                      ),
                                    ),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                _ChartBar(
                                  height: incomeHeight,
                                  color: scheme.primary,
                                ),
                                const SizedBox(width: 3),
                                _ChartBar(
                                  height: expenseHeight,
                                  color: scheme.error,
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _labels[point.month.month - 1],
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                    );
                  })
                  .toList(growable: false),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartBar extends StatelessWidget {
  const _ChartBar({required this.height, required this.color});
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 10,
    height: height,
    decoration: BoxDecoration(
      color: color,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
    ),
  );
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 5),
      Text(label, style: Theme.of(context).textTheme.labelSmall),
    ],
  );
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.title,
    required this.value,
    required this.color,
  });
  final String title;
  final int value;
  final Color color;
  @override
  Widget build(BuildContext context) => AppCard(
    color: color.withValues(alpha: .1),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title),
        const SizedBox(height: 6),
        AppMoneyText(value, compact: true, color: color),
      ],
    ),
  );
}
