import 'package:pdf/widgets.dart' as pw;

import '../../../../core/database/app_database.dart';
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
    Iterable<EnvelopeBudget> budgets = const [],
    Iterable<Category> categories = const [],
    Iterable<Tag> tags = const [],
    Iterable<Merchant> merchants = const [],
    Iterable<ActivityEntry> activityEntries = const [],
    Iterable<DailyNote> dailyNotes = const [],
    Iterable<Task> tasks = const [],
    Iterable<HarvestEvent> harvestEvents = const [],
    required Map<String, String> categoryLabels,
    required FinancialHealthScore score,
  }) async {
    final monthRows = transactions
        .where(
          (entry) =>
              entry.transaction.date.year == month.year &&
              entry.transaction.date.month == month.month,
        )
        .toList();

    final monthActivities = activityEntries
        .where(
          (e) => e.startedAt.year == month.year && e.startedAt.month == month.month,
        )
        .toList();

    final monthDailyNotes = dailyNotes
        .where(
          (n) => n.noteDate.year == month.year && n.noteDate.month == month.month,
        )
        .toList();

    final monthHarvests = harvestEvents
        .where(
          (h) => h.harvestedAt.year == month.year && h.harvestedAt.month == month.month,
        )
        .toList();

    return _buildDocument(
      title: 'Laporan Keuangan & Operasional Keluarga',
      subtitle: 'Periode ${month.month}/${month.year}',
      transactions: monthRows,
      assets: assets,
      liabilities: liabilities,
      receivables: receivables,
      goals: goals,
      budgets: budgets,
      activityEntries: monthActivities,
      dailyNotes: monthDailyNotes,
      harvestEvents: monthHarvests,
      categoryLabels: categoryLabels,
      score: score,
    );
  }

  Future<List<int>> buildCustomRangeReport({
    required DateTime from,
    required DateTime to,
    required Iterable<TransactionWithItems> transactions,
    required Iterable<AssetEntity> assets,
    required Iterable<LiabilityEntity> liabilities,
    required Iterable<ReceivableEntity> receivables,
    required Iterable<GoalEntity> goals,
    Iterable<EnvelopeBudget> budgets = const [],
    Iterable<ActivityEntry> activityEntries = const [],
    Iterable<DailyNote> dailyNotes = const [],
    Iterable<HarvestEvent> harvestEvents = const [],
    required Map<String, String> categoryLabels,
    required FinancialHealthScore score,
  }) async {
    final rangeRows = transactions
        .where((entry) {
          final d = entry.transaction.date;
          return !d.isBefore(from) && !d.isAfter(to);
        })
        .toList();

    final rangeActivities = activityEntries
        .where((e) => !e.startedAt.isBefore(from) && !e.startedAt.isAfter(to))
        .toList();

    final rangeDailyNotes = dailyNotes
        .where((n) => !n.noteDate.isBefore(from) && !n.noteDate.isAfter(to))
        .toList();

    final rangeHarvests = harvestEvents
        .where((h) => !h.harvestedAt.isBefore(from) && !h.harvestedAt.isAfter(to))
        .toList();

    final fromStr = '${from.day}/${from.month}/${from.year}';
    final toStr = '${to.day}/${to.month}/${to.year}';

    return _buildDocument(
      title: 'Laporan Keuangan & Operasional Keluarga',
      subtitle: 'Periode $fromStr s/d $toStr',
      transactions: rangeRows,
      assets: assets,
      liabilities: liabilities,
      receivables: receivables,
      goals: goals,
      budgets: budgets,
      activityEntries: rangeActivities,
      dailyNotes: rangeDailyNotes,
      harvestEvents: rangeHarvests,
      categoryLabels: categoryLabels,
      score: score,
    );
  }

  Future<List<int>> buildWeeklyReport({
    required DateTime weekContaining,
    required Iterable<TransactionWithItems> transactions,
    required Map<String, String> categoryLabels,
  }) async {
    final day = DateTime(
      weekContaining.year,
      weekContaining.month,
      weekContaining.day,
    );
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
      title: 'Laporan Mingguan Operasional Keluarga',
      subtitle:
          '${start.day}/${start.month}/${start.year} sampai ${end.subtract(const Duration(days: 1)).day}/${end.subtract(const Duration(days: 1)).month}/${end.subtract(const Duration(days: 1)).year}',
      transactions: rows,
      assets: const [],
      liabilities: const [],
      receivables: const [],
      goals: const [],
      budgets: const [],
      activityEntries: const [],
      dailyNotes: const [],
      harvestEvents: const [],
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
    required Iterable<EnvelopeBudget> budgets,
    required Iterable<ActivityEntry> activityEntries,
    required Iterable<DailyNote> dailyNotes,
    required Iterable<HarvestEvent> harvestEvents,
    required Map<String, String> categoryLabels,
    required FinancialHealthScore score,
  }) async {
    final rows = transactions.toList();
    final income = rows
        .where(
          (item) =>
              item.transaction.amount > 0 &&
              item.transaction.type != 'transfer' &&
              item.transaction.transferId == null,
        )
        .fold<int>(0, (sum, item) => sum + item.transaction.amount);
    final expense = rows
        .where(
          (item) =>
              item.transaction.amount < 0 &&
              item.transaction.type != 'transfer' &&
              item.transaction.transferId == null,
        )
        .fold<int>(0, (sum, item) => sum + item.transaction.amount.abs());

    final categoryTotals = <String, int>{};
    for (final row in rows.where((item) => item.transaction.amount < 0)) {
      final key = categoryLabels[row.transaction.categoryId] ?? 'Tanpa Kategori';
      categoryTotals[key] =
          (categoryTotals[key] ?? 0) + row.transaction.amount.abs();
    }

    final totalAssetsVal = assets.fold<int>(0, (sum, a) => sum + a.value);
    final totalDebtVal = liabilities.fold<int>(0, (sum, l) => sum + l.remainingBalance);
    final netWorth = totalAssetsVal - totalDebtVal;

    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        pageTheme: const pw.PageTheme(margin: pw.EdgeInsets.all(28)),
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Text(
              title,
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Text(subtitle, style: const pw.TextStyle(fontSize: 12)),
          pw.SizedBox(height: 14),

          _section('1. Ringkasan Arus Kas & Eksekutif', [
            'Total Pemasukan: ${_rupiah(income)}',
            'Total Pengeluaran: ${_rupiah(expense)}',
            'Selisih Kas (Surplus/Defisit): ${_rupiah(income - expense)}',
            'Skor Kesehatan Finansial: ${score.totalScore}/100',
            'Perkiraan Kekayaan Bersih (Net Worth): ${_rupiah(netWorth)}',
          ]),

          if (categoryTotals.isNotEmpty)
            _section(
              '2. Pengeluaran per Kategori',
              categoryTotals.entries
                  .map((item) => '${item.key}: ${_rupiah(item.value)}')
                  .toList(),
            ),

          if (budgets.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            pw.Text(
              '3. Anggaran vs Realisasi Pengeluaran',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.TableHelper.fromTextArray(
              headers: const ['Pos Anggaran', 'Alokasi', 'Realisasi', 'Sisa'],
              data: budgets.map((b) {
                final catId = b.categoryId;
                final spent = rows
                    .where((r) => r.transaction.amount < 0 && (catId == null || r.transaction.categoryId == catId))
                    .fold(0, (sum, r) => sum + r.transaction.amount.abs());
                final remaining = b.allocated - spent;
                return [
                  b.name,
                  _rupiah(b.allocated),
                  _rupiah(spent),
                  _rupiah(remaining),
                ];
              }).toList(),
            ),
          ],

          if (activityEntries.isNotEmpty || dailyNotes.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            pw.Text(
              '4. Laporan Aktivitas & Jurnal Operasional',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            if (activityEntries.isNotEmpty)
              pw.TableHelper.fromTextArray(
                headers: const ['Tanggal', 'Aktivitas', 'Tempat', 'Catatan'],
                data: activityEntries.take(10).map((act) {
                  final dateStr = '${act.startedAt.day}/${act.startedAt.month}/${act.startedAt.year}';
                  return [
                    dateStr,
                    act.title,
                    act.place ?? '-',
                    act.notes ?? '-',
                  ];
                }).toList(),
              ),
            if (dailyNotes.isNotEmpty)
              _section(
                'Catatan Harian:',
                dailyNotes.take(5).map((n) => '${n.noteDate.day}/${n.noteDate.month}: ${n.title ?? ""} ${n.body}').toList(),
              ),
          ],

          if (harvestEvents.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            pw.Text(
              '5. Hasil Panen & Usaha Periodik',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.TableHelper.fromTextArray(
              headers: const ['Tanggal', 'Komoditas', 'Jumlah/Volume', 'Total Nominal', 'Pembeli'],
              data: harvestEvents.map((h) {
                final dateStr = '${h.harvestedAt.day}/${h.harvestedAt.month}/${h.harvestedAt.year}';
                return [
                  dateStr,
                  h.commodity,
                  '${h.quantity} ${h.unit}',
                  _rupiah(h.totalAmount ?? 0),
                  h.buyerName ?? '-',
                ];
              }).toList(),
            ),
          ],

          if (assets.isNotEmpty)
            _section(
              '6. Aset',
              assets
                  .map((item) => '${item.name} (${item.assetType}): ${_rupiah(item.value)}')
                  .toList(),
            ),
          if (liabilities.isNotEmpty)
            _section(
              '7. Kewajiban Hutang',
              liabilities
                  .map(
                    (item) =>
                        '${item.name}: sisa ${_rupiah(item.remainingBalance)} (Cicilan: ${_rupiah(item.monthlyInstallment)}/bln)',
                  )
                  .toList(),
            ),
          if (receivables.isNotEmpty)
            _section(
              '8. Piutang (Non-Kas)',
              receivables
                  .map(
                    (item) =>
                        '${item.name}: sisa ${_rupiah(item.remainingBalance)}',
                  )
                  .toList(),
            ),
          if (goals.isNotEmpty)
            _section(
              '9. Target Keuangan',
              goals
                  .map(
                    (item) =>
                        '${item.name}: ${_rupiah(item.currentAmount)} dari ${_rupiah(item.targetAmount)}',
                  )
                  .toList(),
            ),

          pw.SizedBox(height: 10),
          pw.Text(
            'Daftar Transaksi Kas (${rows.length} record)',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.TableHelper.fromTextArray(
            headers: const ['Tanggal', 'Jenis', 'Kategori', 'Catatan', 'Nominal'],
            data: rows
                .take(30)
                .map(
                  (row) => [
                    '${row.transaction.date.day}/${row.transaction.date.month}/${row.transaction.date.year}',
                    row.transaction.amount >= 0 ? 'Masuk' : 'Keluar',
                    categoryLabels[row.transaction.categoryId] ?? 'Tanpa Kategori',
                    row.transaction.note ?? '-',
                    _rupiah(row.transaction.amount.abs()),
                  ],
                )
                .toList(),
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            'Catatan: Transfer antar rekening tidak dihitung sebagai pemasukan atau pengeluaran. Piutang dan hasil panen tidak dianggap pemasukan kas sebelum dana dicatat dalam transaksi kas masuk.',
            style: const pw.TextStyle(fontSize: 9),
          ),
        ],
      ),
    );
    return document.save();
  }

  pw.Widget _section(String title, List<String> lines) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(height: 8),
          pw.Text(
            title,
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          ...lines.map((line) => pw.Text(line, style: const pw.TextStyle(fontSize: 10))),
        ],
      );

  String _rupiah(int value) =>
      'Rp${value.toString().replaceAllMapped(RegExp(r'(?=(\d{3})+(?!\d))'), (_) => '.')}';
}
