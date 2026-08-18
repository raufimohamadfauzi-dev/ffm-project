import 'package:pdf/widgets.dart' as pw;

import '../../advisor/domain/usecases/financial_health_calculator.dart';
import '../../asset/domain/entities/asset_entity.dart';
import '../../goal/domain/entities/goal_entity.dart';
import '../../liability/domain/entities/liability_entity.dart';
import '../../receivable/domain/entities/receivable_entity.dart';
import '../../transaction/domain/entities/transaction_entity.dart';

class PdfReportService {
  const PdfReportService();

  Future<List<int>> buildMonthlyReport({
    required DateTime month,
    required Iterable<TransactionWithItems> transactions,
    required Iterable<AssetEntity> assets,
    required Iterable<LiabilityEntity> liabilities,
    required Iterable<ReceivableEntity> receivables,
    required Iterable<GoalEntity> goals,
    required Map<String, String> categoryLabels,
    required FinancialHealthScore score,
  }) async {
    final monthRows = transactions.where((entry) => entry.transaction.date.year == month.year && entry.transaction.date.month == month.month).toList();
    return _buildDocument(
      title: 'Laporan keuangan keluarga',
      subtitle: 'Periode ${month.month}/${month.year}',
      transactions: monthRows,
      assets: assets,
      liabilities: liabilities,
      receivables: receivables,
      goals: goals,
      categoryLabels: categoryLabels,
      score: score,
    );
  }

  Future<List<int>> buildWeeklyReport({
    required DateTime weekContaining,
    required Iterable<TransactionWithItems> transactions,
    required Map<String, String> categoryLabels,
  }) async {
    final day = DateTime(weekContaining.year, weekContaining.month, weekContaining.day);
    final start = day.subtract(Duration(days: day.weekday - 1));
    final end = start.add(const Duration(days: 7));
    final rows = transactions.where((entry) {
      final date = entry.transaction.date;
      return !date.isBefore(start) && date.isBefore(end);
    }).toList();
    final score = const FinancialHealthScore(
      totalScore: 0,
      status: FinancialHealthStatus.fair,
      cashflow: 0,
      expenseRatio: 0,
    );
    return _buildDocument(
      title: 'Laporan mingguan keluarga',
      subtitle: '${start.day}/${start.month}/${start.year} sampai ${end.subtract(const Duration(days: 1)).day}/${end.subtract(const Duration(days: 1)).month}/${end.subtract(const Duration(days: 1)).year}',
      transactions: rows,
      assets: const [],
      liabilities: const [],
      receivables: const [],
      goals: const [],
      categoryLabels: categoryLabels,
      score: score,
    );
  }

  Future<List<int>> _buildDocument({
    required String title,
    required String subtitle,
    required Iterable<TransactionWithItems> transactions,
    required Iterable<AssetEntity> assets,
    required Iterable<LiabilityEntity> liabilities,
    required Iterable<ReceivableEntity> receivables,
    required Iterable<GoalEntity> goals,
    required Map<String, String> categoryLabels,
    required FinancialHealthScore score,
  }) async {
    final rows = transactions.toList();
    final income = rows.where((item) => item.transaction.amount > 0).fold<int>(0, (sum, item) => sum + item.transaction.amount);
    final expense = rows.where((item) => item.transaction.amount < 0).fold<int>(0, (sum, item) => sum + item.transaction.amount.abs());
    final categoryTotals = <String, int>{};
    for (final row in rows.where((item) => item.transaction.amount < 0)) {
      final key = categoryLabels[row.transaction.categoryId] ?? 'Belum diatur';
      categoryTotals[key] = (categoryTotals[key] ?? 0) + row.transaction.amount.abs();
    }
    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(margin: const pw.EdgeInsets.all(28)),
        build: (context) => [
          pw.Header(level: 0, child: pw.Text(title, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold))),
          pw.Text(subtitle),
          pw.SizedBox(height: 16),
          _section('Ringkasan arus kas', [
            'Pemasukan: ${_rupiah(income)}',
            'Pengeluaran: ${_rupiah(expense)}',
            'Selisih: ${_rupiah(income - expense)}',
            'Skor kesehatan: ${score.totalScore}/100',
          ]),
          _section('Pengeluaran per kategori', categoryTotals.entries.map((item) => '${item.key}: ${_rupiah(item.value)}').toList()),
          pw.SizedBox(height: 8),
          pw.Text('Daftar transaksi', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.TableHelper.fromTextArray(
            headers: const ['Tanggal', 'Jenis', 'Kategori', 'Nominal'],
            data: rows.map((row) => [
              '${row.transaction.date.day}/${row.transaction.date.month}/${row.transaction.date.year}',
              row.transaction.amount >= 0 ? 'Masuk' : 'Keluar',
              categoryLabels[row.transaction.categoryId] ?? 'Belum diatur',
              _rupiah(row.transaction.amount.abs()),
            ]).toList(),
          ),
          if (assets.isNotEmpty) _section('Aset', assets.map((item) => '${item.name}: ${_rupiah(item.value)}').toList()),
          if (liabilities.isNotEmpty) _section('Hutang', liabilities.map((item) => '${item.name}: sisa ${_rupiah(item.remainingBalance)}').toList()),
          if (receivables.isNotEmpty) _section('Piutang', receivables.map((item) => '${item.name}: sisa ${_rupiah(item.remainingBalance)}').toList()),
          if (goals.isNotEmpty) _section('Target keuangan', goals.map((item) => '${item.name}: ${_rupiah(item.currentAmount)} dari ${_rupiah(item.targetAmount)}').toList()),
          pw.SizedBox(height: 18),
          pw.Text('Catatan: transfer antar rekening tidak dihitung sebagai pemasukan atau pengeluaran. Piutang juga tidak dianggap pemasukan kas sebelum penerimaan dicatat sebagai transaksi.'),
        ],
      ),
    );
    return document.save();
  }

  pw.Widget _section(String title, List<String> lines) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(height: 10),
          pw.Text(title, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          ...lines.map((line) => pw.Text(line)),
        ],
      );

  String _rupiah(int value) => 'Rp${value.toString().replaceAllMapped(RegExp(r'(?=(\d{3})+(?!\d))'), (_) => '.')}' ;
}
