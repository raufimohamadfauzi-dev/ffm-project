import 'package:flutter/material.dart';

import '../../../../core/database/app_context.dart';
import '../../../../core/di/injection.dart';
import '../../../../shared/widgets/app_components.dart';
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Analisa')),
    body: FutureBuilder<List<TransactionWithItems>>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final items = snapshot.data!;
        final income = items
            .where((item) => item.transaction.amount > 0)
            .fold<int>(0, (sum, item) => sum + item.transaction.amount);
        final expense = items
            .where((item) => item.transaction.amount < 0)
            .fold<int>(0, (sum, item) => sum + item.transaction.amount.abs());
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          children: [
            const AppHelpBanner(
              title: 'Baca polanya, bukan cuma totalnya',
              message: 'Gunakan kategori, toko, tag, dan tanggal untuk belajar dari kebiasaan keuangan keluarga.',
              icon: Icons.insights_outlined,
            ),
            const SizedBox(height: 12),
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
      },
    ),
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
