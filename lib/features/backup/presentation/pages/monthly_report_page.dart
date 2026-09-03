import 'package:flutter/material.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:printing/printing.dart';

import '../../../../core/database/app_context.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/localization/app_copy.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../../advisor/domain/usecases/financial_health_calculator.dart';
import '../../../assistant/domain/ffm_assistant_models.dart';
import '../../../assistant/presentation/widgets/ffm_assistant_page_context.dart';
import '../../../asset/domain/entities/asset_entity.dart';
import '../../../asset/domain/usecases/asset_crud_usecases.dart';
import '../../../goal/domain/entities/goal_entity.dart';
import '../../../goal/domain/usecases/goal_crud_usecases.dart';
import '../../../liability/domain/entities/liability_entity.dart';
import '../../../liability/domain/usecases/liability_crud_usecases.dart';
import '../../../receivable/domain/entities/receivable_entity.dart';
import '../../../receivable/domain/usecases/receivable_crud_usecases.dart';
import '../../../transaction/domain/entities/transaction_entity.dart';
import '../../../transaction/domain/usecases/transaction_crud_usecases.dart';
import '../../data/pdf_report_service.dart';
import '../../../settings/data/offline_tool_history_service.dart';

class MonthlyReportPage extends StatefulWidget {
  const MonthlyReportPage({super.key});

  @override
  State<MonthlyReportPage> createState() => _MonthlyReportPageState();
}

class _MonthlyReportPageState extends State<MonthlyReportPage> {
  late DateTime _month;
  bool _isWeekly = false;
  late Future<_MonthlyReportData> _future;
  var _working = false;
  List<MonthlyReportRecord> _history = const [];
  double _simulatorPercentage = 10.0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month, now.day);
    _future = _load(_month, _isWeekly);
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final history = await OfflineToolHistoryService().readMonthlyReports();
    if (mounted) setState(() => _history = history);
  }

  List<DateTime> _recentMonths() {
    final now = DateTime.now();
    final list = <DateTime>[];
    for (var i = 0; i < 24; i++) {
      list.add(DateTime(now.year, now.month - i));
    }
    if (!list.contains(_month)) {
      list.add(_month);
      list.sort((a, b) => b.compareTo(a));
    }
    return list;
  }

  Future<_MonthlyReportData> _load(DateTime refDate, bool isWeekly) async {
    final db = getIt<AppDatabase>();
    final householdId = AppContext.householdId;

    final transactions = await getIt<GetTransactions>()(householdId);
    final assets = await getIt<GetAssets>()(householdId);
    final liabilities = await getIt<GetLiabilities>()(householdId);
    final receivables = await getIt<GetReceivables>()(householdId);
    final goals = await getIt<GetGoals>()(householdId);

    final categories = await db.select(db.categories).get();
    final tags = await db.select(db.tags).get();
    final merchants = await db.select(db.merchants).get();

    final budgets = await (db.select(db.envelopeBudgets)
          ..where(
            (r) =>
                r.householdId.equals(householdId) &
                r.isActive.equals(true),
          ))
        .get();

    final activitySessions = await (db.select(db.activitySessions)
          ..where(
            (r) =>
                r.householdId.equals(householdId) &
                r.isArchived.equals(false),
          ))
        .get();

    final activityEntries = await (db.select(db.activityEntries)
          ..where(
            (r) =>
                r.householdId.equals(householdId) &
                r.isArchived.equals(false),
          ))
        .get();

    final dailyNotes = await (db.select(db.dailyNotes)
          ..where(
            (r) =>
                r.householdId.equals(householdId) &
                r.isArchived.equals(false),
          ))
        .get();

    final tasks = await (db.select(db.tasks)
          ..where(
            (r) =>
                r.householdId.equals(householdId) &
                r.isArchived.equals(false),
          ))
        .get();

    final dailyRoutines = await (db.select(db.dailyRoutines)
          ..where(
            (r) =>
                r.householdId.equals(householdId) &
                r.isActive.equals(true) &
                r.isArchived.equals(false),
          ))
        .get();

    final routineCompletions = await (db.select(db.dailyRoutineCompletions)
          ..where((r) => r.householdId.equals(householdId)))
        .get();

    final harvestEvents = await (db.select(db.harvestEvents)
          ..where(
            (r) =>
                r.householdId.equals(householdId) &
                r.isArchived.equals(false),
          ))
        .get();

    final categoryLabels = {for (final item in categories) item.id: item.name};
    final merchantLabels = {for (final item in merchants) item.id: item.name};
    final tagLabels = {for (final item in tags) item.id: item.name};

    final current = _periodRows(transactions, refDate, isWeekly);
    final previous = _periodRows(
      transactions,
      _previousPeriodDate(refDate, isWeekly),
      isWeekly,
    );

    final income = _income(current);
    final expense = _expense(current);
    final previousIncome = _income(previous);
    final previousExpense = _expense(previous);

    final score = const FinancialHealthCalculator().calculate(
      FinancialHealthInput(
        totalIncome: income,
        totalExpenses: expense,
        totalMonthlyInstallments: liabilities.fold(
          0,
          (sum, item) => sum + item.monthlyInstallment,
        ),
        emergencyFundAmount: assets
            .where((item) => item.assetType == 'cash')
            .fold(0, (sum, item) => sum + item.value),
        averageMonthlyExpenses: expense,
      ),
    );

    return _MonthlyReportData(
      month: refDate,
      isWeekly: isWeekly,
      transactions: transactions,
      assets: assets,
      liabilities: liabilities,
      receivables: receivables,
      goals: goals,
      budgets: budgets,
      categories: categories,
      tags: tags,
      merchants: merchants,
      activitySessions: activitySessions,
      activityEntries: activityEntries,
      dailyNotes: dailyNotes,
      tasks: tasks,
      dailyRoutines: dailyRoutines,
      routineCompletions: routineCompletions,
      harvestEvents: harvestEvents,
      categoryLabels: categoryLabels,
      merchantLabels: merchantLabels,
      tagLabels: tagLabels,
      currentRows: current,
      income: income,
      expense: expense,
      previousIncome: previousIncome,
      previousExpense: previousExpense,
      score: score,
    );
  }

  DateTime _previousPeriodDate(DateTime refDate, bool isWeekly) {
    if (isWeekly) {
      return refDate.subtract(const Duration(days: 7));
    } else {
      return DateTime(refDate.year, refDate.month - 1);
    }
  }

  List<TransactionWithItems> _periodRows(
    List<TransactionWithItems> rows,
    DateTime refDate,
    bool isWeekly,
  ) {
    if (isWeekly) {
      final start = DateTime(refDate.year, refDate.month, refDate.day)
          .subtract(Duration(days: refDate.weekday - 1));
      final end = start.add(const Duration(days: 7));
      return rows.where((item) {
        final d = item.transaction.date;
        return !d.isBefore(start) && d.isBefore(end);
      }).toList(growable: false);
    } else {
      return rows
          .where(
            (item) =>
                item.transaction.date.year == refDate.year &&
                item.transaction.date.month == refDate.month,
          )
          .toList(growable: false);
    }
  }

  int _income(List<TransactionWithItems> rows) => rows
      .where(
        (item) =>
            item.transaction.amount > 0 &&
            item.transaction.type != 'transfer' &&
            item.transaction.transferId == null,
      )
      .fold(0, (sum, item) => sum + item.transaction.amount);

  int _expense(List<TransactionWithItems> rows) => rows
      .where(
        (item) =>
            item.transaction.amount < 0 &&
            item.transaction.type != 'transfer' &&
            item.transaction.transferId == null,
      )
      .fold(0, (sum, item) => sum + item.transaction.amount.abs());

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: _month,
      helpText: _isWeekly ? 'Pilih tanggal acuan minggu' : 'Pilih bulan laporan',
      cancelText: AppCopy.batal,
      confirmText: AppCopy.selesai,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _month = picked;
      _future = _load(_month, _isWeekly);
    });
  }

  Future<void> _export(_MonthlyReportData data) async {
    setState(() => _working = true);
    try {
      final List<int> bytes;
      if (data.isWeekly) {
        final start = DateTime(data.month.year, data.month.month, data.month.day)
            .subtract(Duration(days: data.month.weekday - 1));
        final end = start.add(const Duration(days: 6));
        bytes = await const PdfReportService().buildCustomRangeReport(
          from: start,
          to: end,
          transactions: data.transactions,
          assets: data.assets,
          liabilities: data.liabilities,
          receivables: data.receivables,
          goals: data.goals,
          budgets: data.budgets,
          activityEntries: data.activityEntries,
          dailyNotes: data.dailyNotes,
          harvestEvents: data.harvestEvents,
          categoryLabels: data.categoryLabels,
          score: data.score,
        );
      } else {
        bytes = await const PdfReportService().buildMonthlyReport(
          month: data.month,
          transactions: data.transactions,
          assets: data.assets,
          liabilities: data.liabilities,
          receivables: data.receivables,
          goals: data.goals,
          budgets: data.budgets,
          categories: data.categories,
          tags: data.tags,
          merchants: data.merchants,
          activityEntries: data.activityEntries,
          dailyNotes: data.dailyNotes,
          tasks: data.tasks,
          harvestEvents: data.harvestEvents,
          categoryLabels: data.categoryLabels,
          score: data.score,
        );
      }

      await Printing.sharePdf(
        bytes: Uint8List.fromList(bytes),
        filename: 'ffm-laporan-${_isWeekly ? "mingguan" : "bulanan"}-${_monthStamp(data.month)}.pdf',
      );
      await OfflineToolHistoryService().saveMonthlyReport(
        MonthlyReportRecord(
          createdAt: DateTime.now(),
          month: data.month,
          income: data.income,
          expense: data.expense,
          net: data.income - data.expense,
        ),
      );
      await _loadHistory();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Laporan PDF siap dibagikan.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Laporan belum berhasil dibuat: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  String _periodTitle(_MonthlyReportData data) {
    if (data.isWeekly) {
      final start = DateTime(data.month.year, data.month.month, data.month.day)
          .subtract(Duration(days: data.month.weekday - 1));
      final end = start.add(const Duration(days: 6));
      return 'Minggu (${start.day}/${start.month} - ${end.day}/${end.month}/${end.year})';
    }
    return _monthLabel(data.month);
  }

  String _monthLabel(DateTime month) {
    const names = [
      'Januari',
      'Februari',
      'Maret',
      'April',
      'Mei',
      'Juni',
      'Juli',
      'Agustus',
      'September',
      'Oktober',
      'November',
      'Desember',
    ];
    return '${names[month.month - 1]} ${month.year}';
  }

  String _monthStamp(DateTime month) =>
      '${month.year}-${month.month.toString().padLeft(2, '0')}-${month.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_MonthlyReportData>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final summaryText = data != null
            ? 'Laporan ${_periodTitle(data)}: Pemasukan ${_money(data.income)}, Pengeluaran ${_money(data.expense)}, Surplus/Defisit ${_money(data.netCashflow)}. Rasio Tabungan: ${data.savingsRate.toStringAsFixed(1)}%, Rasio Cicilan: ${data.debtToIncomeRatio.toStringAsFixed(1)}%. Pos Terbesar: ${data.topExpenseCategories.take(2).map((e) => "${e.key} ${_money(e.value)}").join(", ")}. Evaluasi: ${data.keyLearningPoints.join(" ")}'
            : 'Sedang memuat laporan...';

        return FfmAssistantPageContext(
          destination: FfmAssistantDestination.monthlyReport,
          dataSummary: summaryText,
          child: Scaffold(
            appBar: AppBar(title: Text(_isWeekly ? 'Laporan Mingguan & Operasional' : 'Laporan Bulanan & Operasional')),
            body: !snapshot.hasData
                ? const Center(child: CircularProgressIndicator())
                : _buildBody(context, snapshot.data!),
          ),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, _MonthlyReportData data) {
    final scheme = Theme.of(context).colorScheme;
    final positiveColor = AppSemanticColors.positive(context);
    final negativeColor = AppSemanticColors.negative(context);
    final warningColor = AppSemanticColors.warning(context);

    final net = data.netCashflow;
    final incomeChange = data.previousIncome == 0
        ? null
        : ((data.income - data.previousIncome) / data.previousIncome * 100);
    final expenseChange = data.previousExpense == 0
        ? null
        : ((data.expense - data.previousExpense) / data.previousExpense * 100);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        // Mode Segmented Control: Bulanan vs Mingguan
        Center(
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment<bool>(
                value: false,
                label: Text('Laporan Bulanan'),
                icon: Icon(Icons.calendar_month),
              ),
              ButtonSegment<bool>(
                value: true,
                label: Text('Laporan Mingguan'),
                icon: Icon(Icons.view_week_outlined),
              ),
            ],
            selected: {_isWeekly},
            onSelectionChanged: (Set<bool> selection) {
              final newIsWeekly = selection.first;
              if (newIsWeekly == _isWeekly) return;
              setState(() {
                _isWeekly = newIsWeekly;
                _future = _load(_month, _isWeekly);
              });
            },
          ),
        ),
        const SizedBox(height: 12),

        // Header & Period Navigator
        AppCard(
          color: scheme.primaryContainer,
          child: Column(
            children: [
              Row(
                children: [
                  Icon(_isWeekly ? Icons.view_week_outlined : Icons.calendar_month_outlined, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _isWeekly
                        ? Text(
                            _periodTitle(data),
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(color: scheme.onPrimaryContainer, fontWeight: FontWeight.bold),
                          )
                        : DropdownButton<DateTime>(
                            value: _recentMonths().firstWhere(
                              (m) => m.year == _month.year && m.month == _month.month,
                              orElse: () => _month,
                            ),
                            isExpanded: true,
                            underline: const SizedBox.shrink(),
                            icon: Icon(Icons.arrow_drop_down, color: scheme.onPrimaryContainer),
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(color: scheme.onPrimaryContainer, fontWeight: FontWeight.bold),
                            dropdownColor: scheme.surface,
                            items: _recentMonths().map((m) {
                              final isSelected = m.year == _month.year && m.month == _month.month;
                              return DropdownMenuItem<DateTime>(
                                value: m,
                                child: Text(
                                  _monthLabel(m),
                                  style: TextStyle(
                                    color: isSelected ? scheme.primary : scheme.onSurface,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val == null || (val.year == _month.year && val.month == _month.month)) return;
                              setState(() {
                                _month = val;
                                _future = _load(_month, _isWeekly);
                              });
                            },
                          ),
                  ),
                  IconButton(
                    tooltip: 'Buka Kalender',
                    icon: Icon(Icons.date_range_outlined, color: scheme.primary),
                    onPressed: _pickMonth,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      final prev = _isWeekly
                          ? _month.subtract(const Duration(days: 7))
                          : DateTime(_month.year, _month.month - 1);
                      setState(() {
                        _month = prev;
                        _future = _load(_month, _isWeekly);
                      });
                    },
                    icon: const Icon(Icons.chevron_left),
                    label: Text(_isWeekly ? 'Minggu Lalu' : 'Bulan Lalu'),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () {
                      final now = DateTime.now();
                      setState(() {
                        _month = now;
                        _future = _load(_month, _isWeekly);
                      });
                    },
                    icon: const Icon(Icons.today_outlined),
                    label: Text(_isWeekly ? 'Minggu Ini' : 'Bulan Ini'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Financial Overview Card
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                label: 'Pemasukan',
                value: data.income,
                color: positiveColor,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MetricCard(
                label: 'Pengeluaran',
                value: data.expense,
                color: negativeColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Arus Kas Bersih', style: AppTextStyles.labelCaps),
              const SizedBox(height: 6),
              AppMoneyText(
                net,
                color: net >= 0 ? positiveColor : negativeColor,
              ),
              const SizedBox(height: 12),
              Text(
                'Dibanding periode sebelumnya: Pemasukan ${_changeLabel(incomeChange)}, Pengeluaran ${_changeLabel(expenseChange)}.',
              ),
              const SizedBox(height: 8),
              Text(
                '${data.currentRows.length} transaksi kas tercatat pada periode ini.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Health Score & Net Worth Card
        AppCard(
          child: Column(
            children: [
              Row(
                children: [
                  Icon(Icons.health_and_safety_outlined, color: scheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Skor Kesehatan Finansial: ${data.score.totalScore}/100\n${_statusLabel(data.score.status)}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              Row(
                children: [
                  Icon(Icons.account_balance_outlined, color: scheme.secondary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Perkiraan Kekayaan Bersih (Net Worth)',
                            style: AppTextStyles.labelCaps),
                        const SizedBox(height: 4),
                        AppMoneyText(
                          data.netWorth,
                          color: data.netWorth >= 0 ? positiveColor : negativeColor,
                          compact: true,
                        ),
                        Text(
                          'Total Aset (${_money(data.totalAssetsValue)}) - Total Hutang (${_money(data.liabilitiesTotal)})',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildLearningInsightsCard(context, data),
        const SizedBox(height: 12),
        _buildWhatIfSimulatorCard(context, data),
        const SizedBox(height: 12),
        _buildConsultAssistantCard(context, data),
        const SizedBox(height: 16),

        // Top Categories & Merchants Analytics Section
        _buildSectionHeader(context, 'Analisis Pengeluaran & Merchant', Icons.pie_chart_outline),
        const SizedBox(height: 8),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Pengeluaran Terbesar per Kategori', style: AppTextStyles.labelCaps),
              const SizedBox(height: 8),
              if (data.topExpenseCategories.isEmpty)
                const Text('Belum ada pengeluaran tercatat pada periode ini.')
              else
                ...data.topExpenseCategories.map((entry) {
                  final pct = data.expense > 0 ? (entry.value / data.expense) : 0.0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text(_money(entry.value)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: pct.clamp(0.0, 1.0),
                          color: negativeColor,
                          backgroundColor: scheme.surfaceContainerHighest,
                        ),
                      ],
                    ),
                  );
                }),
              if (data.topMerchants.isNotEmpty) ...[
                const Divider(height: 24),
                const Text('Toko / Merchant Teratas', style: AppTextStyles.labelCaps),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: data.topMerchants.map((entry) {
                    return Chip(
                      avatar: const Icon(Icons.storefront_outlined, size: 16),
                      label: Text('${entry.key}: ${_money(entry.value)}'),
                    );
                  }).toList(),
                ),
              ],
              if (data.topTags.isNotEmpty) ...[
                const Divider(height: 24),
                const Text('Tag Teratas', style: AppTextStyles.labelCaps),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: data.topTags.map((entry) {
                    return Chip(
                      avatar: const Icon(Icons.local_offer_outlined, size: 16),
                      label: Text('${entry.key}: ${_money(entry.value)}'),
                    );
                  }).toList(),
                ),
              ],
              if (data.topExpenses.isNotEmpty) ...[
                const Divider(height: 24),
                const Text('Transaksi Pengeluaran Terbesar', style: AppTextStyles.labelCaps),
                const SizedBox(height: 8),
                ...data.topExpenses.map((row) {
                  final catName = data.categoryLabels[row.transaction.categoryId] ?? 'Tanpa Kategori';
                  final dateStr = '${row.transaction.date.day}/${row.transaction.date.month}';
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(row.transaction.note ?? catName, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('$dateStr · $catName'),
                    trailing: Text(_money(row.transaction.amount.abs()), style: TextStyle(color: negativeColor, fontWeight: FontWeight.bold)),
                  );
                }),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Budgets & Goals Section
        _buildSectionHeader(context, 'Anggaran & Target Keuangan', Icons.flag_outlined),
        const SizedBox(height: 8),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Kepatuhan Pos Anggaran', style: AppTextStyles.labelCaps),
              const SizedBox(height: 8),
              if (data.budgets.isEmpty)
                const Text('Belum ada pos anggaran aktif disiapkan.')
              else
                ...data.budgets.map((b) {
                  final catId = b.categoryId;
                  final spent = data.currentRows
                      .where((r) => r.transaction.amount < 0 && (catId == null || r.transaction.categoryId == catId))
                      .fold(0, (sum, r) => sum + r.transaction.amount.abs());
                  final allocated = b.allocated;
                  final pct = allocated > 0 ? (spent / allocated) : 0.0;
                  final isOver = spent > allocated;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(b.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text('${_money(spent)} / ${_money(allocated)}',
                                style: TextStyle(color: isOver ? negativeColor : scheme.onSurface)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: pct.clamp(0.0, 1.0),
                          color: isOver ? negativeColor : (pct > 0.8 ? warningColor : positiveColor),
                          backgroundColor: scheme.surfaceContainerHighest,
                        ),
                      ],
                    ),
                  );
                }),
              if (data.goals.isNotEmpty) ...[
                const Divider(height: 24),
                const Text('Progres Target Keuangan', style: AppTextStyles.labelCaps),
                const SizedBox(height: 8),
                ...data.goals.map((g) {
                  final pct = g.targetAmount > 0 ? (g.currentAmount / g.targetAmount) : 0.0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(g.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text('${_money(g.currentAmount)} / ${_money(g.targetAmount)} (${(pct * 100).toStringAsFixed(0)}%)'),
                          ],
                        ),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: pct.clamp(0.0, 1.0),
                          color: scheme.primary,
                          backgroundColor: scheme.surfaceContainerHighest,
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Liabilities, Receivables & Asset Portfolio
        _buildSectionHeader(context, 'Hutang, Piutang & Portofolio Aset', Icons.account_balance_wallet_outlined),
        const SizedBox(height: 8),
        AppCard(
          color: scheme.secondaryContainer,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Piutang (Tambahan, Bukan Kas)',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: scheme.onSecondaryContainer),
              ),
              const SizedBox(height: 4),
              Text(
                'Uang yang masih harus diterima. Belum dihitung sebagai pemasukan kas sampai benar-benar masuk ke rekening.',
                style: TextStyle(color: scheme.onSecondaryContainer),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _MetricCard(
                      label: 'Sisa Belum Diterima',
                      value: data.receivablesOutstanding,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MetricCard(
                      label: 'Jatuh Tempo Periode Ini',
                      value: data.receivablesDueThisMonth,
                      color: warningColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Piutang baru periode ini: ${_money(data.receivablesStartedThisMonth)}',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSecondaryContainer),
              ),
              const Divider(height: 24),
              Text(
                'Kewajiban Hutang',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: scheme.onSecondaryContainer),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _MetricCard(
                      label: 'Total Sisa Hutang',
                      value: data.liabilitiesTotal,
                      color: negativeColor,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MetricCard(
                      label: 'Cicilan Bulanan',
                      value: data.totalMonthlyInstallments,
                      color: warningColor,
                    ),
                  ),
                ],
              ),
              if (data.assets.isNotEmpty) ...[
                const Divider(height: 24),
                Text(
                  'Portofolio Aset',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(color: scheme.onSecondaryContainer),
                ),
                const SizedBox(height: 8),
                ...data.assets.map((asset) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('${asset.name} (${asset.assetType})',
                            style: TextStyle(color: scheme.onSecondaryContainer)),
                        Text(_money(asset.value),
                            style: TextStyle(
                                fontWeight: FontWeight.bold, color: scheme.onSecondaryContainer)),
                      ],
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Activity Logs, Daily Notes & Harvest Report Section
        _buildSectionHeader(context, 'Catatan Aktivitas, Jurnal & Panen', Icons.assignment_outlined),
        const SizedBox(height: 8),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Catatan Aktivitas & Operasional Periode Ini', style: AppTextStyles.labelCaps),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _StatSummaryBox(
                      title: 'Aktivitas Selesai',
                      value: '${data.currentMonthActivities.length} kegiatan',
                      icon: Icons.check_circle_outline,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _StatSummaryBox(
                      title: 'Catatan Harian',
                      value: '${data.currentMonthDailyNotes.length} jurnal',
                      icon: Icons.book_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _StatSummaryBox(
                      title: 'Tugas Selesai',
                      value: '${data.tasksCompletedThisMonth} tugas',
                      icon: Icons.task_alt,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _StatSummaryBox(
                      title: 'Rutinitas Tercapai',
                      value: '${data.routineCompletionsThisMonth} kali',
                      icon: Icons.repeat,
                    ),
                  ),
                ],
              ),
              if (data.currentMonthActivities.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Kegiatan Penting Periode Ini:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                ...data.currentMonthActivities.take(5).map((act) {
                  final dateStr = '${act.startedAt.day}/${act.startedAt.month}';
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.event_note, size: 20),
                    title: Text(act.title),
                    subtitle: Text('$dateStr ${act.place != null ? "· ${act.place}" : ""}'),
                  );
                }),
              ],
              if (data.currentMonthDailyNotes.isNotEmpty) ...[
                const Divider(height: 24),
                const Text('Jurnal / Refleksi Harian:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                ...data.currentMonthDailyNotes.take(3).map((note) {
                  final dateStr = '${note.noteDate.day}/${note.noteDate.month}';
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.notes, size: 20),
                    title: Text(note.title ?? 'Catatan $dateStr'),
                    subtitle: Text(note.body, maxLines: 2, overflow: TextOverflow.ellipsis),
                  );
                }),
              ],
              const Divider(height: 24),
              const Text('Hasil Panen & Usaha Periodik', style: AppTextStyles.labelCaps),
              const SizedBox(height: 8),
              if (data.currentMonthHarvests.isEmpty)
                const Text('Belum ada data hasil panen atau usaha tercatat pada periode ini.')
              else ...[
                Row(
                  children: [
                    Expanded(
                      child: _StatSummaryBox(
                        title: 'Total Bobot/Volume',
                        value: '${data.currentMonthHarvestTotalQuantity.toStringAsFixed(1)} kg/unit',
                        icon: Icons.agriculture_outlined,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatSummaryBox(
                        title: 'Total Nominal Panen',
                        value: _money(data.currentMonthHarvestTotalValue),
                        icon: Icons.monetization_on_outlined,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...data.currentMonthHarvests.map((h) {
                  final dateStr = '${h.harvestedAt.day}/${h.harvestedAt.month}';
                  final buyerStr = h.buyerName != null && h.buyerName!.isNotEmpty ? ' · Pembeli: ${h.buyerName}' : '';
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.eco_outlined, color: Colors.green),
                    title: Text('${h.commodity} (${h.quantity} ${h.unit})'),
                    subtitle: Text('$dateStr$buyerStr'),
                    trailing: Text(_money(h.totalAmount ?? 0), style: const TextStyle(fontWeight: FontWeight.bold)),
                  );
                }),
                const SizedBox(height: 6),
                Text(
                  'Catatan: Hasil panen adalah fakta produksi. Pastikan penerimaan uang dilaporkan sebagai transaksi pemasukan kas.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Deterministic Executive Summary Narrative Card
        AppCard(
          color: scheme.surfaceContainerLow,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome, color: scheme.primary),
                  const SizedBox(width: 8),
                  Text('Ringkasan Narasi Eksekutif', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _generateExecutiveNarrative(data),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Export PDF Button
        FilledButton.icon(
          onPressed: _working ? null : () => _export(data),
          icon: _working
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.share_outlined),
          label: Text(
            _working ? 'Lagi menyiapkan...' : 'Ekspor dan Bagikan Laporan PDF',
          ),
        ),
        const SizedBox(height: 24),

        // History
        const Text('Riwayat Laporan Terbuat', style: AppTextStyles.labelCaps),
        const SizedBox(height: 8),
        if (_history.isEmpty)
          const Text(
            'Belum ada riwayat laporan ekspor disave. Pilih bulan/minggu lalu klik ekspor PDF.',
          ),
        ..._history
            .take(12)
            .map(
              (item) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.description_outlined),
                title: Text(_monthLabel(item.month)),
                subtitle: Text(
                  'Dibuat ${item.createdAt.day}/${item.createdAt.month}/${item.createdAt.year} · Arus kas ${_money(item.net)}',
                ),
                onTap: () => setState(() {
                  _month = DateTime(item.month.year, item.month.month, item.month.day);
                  _future = _load(_month, _isWeekly);
                }),
              ),
            ),
      ],
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }

  String _generateExecutiveNarrative(_MonthlyReportData data) {
    final net = data.netCashflow;
    final statusText = net >= 0
        ? 'mengalami surplus sebesar ${_money(net)}'
        : 'mengalami defisit sebesar ${_money(net.abs())}';

    final topCategory = data.topExpenseCategories.isNotEmpty
        ? data.topExpenseCategories.first.key
        : 'belum tercatat';

    final actCount = data.currentMonthActivities.length;
    final harvestCount = data.currentMonthHarvests.length;

    final periodLabelStr = _periodTitle(data);

    return 'Pada periode $periodLabelStr, keuangan keluarga $statusText dengan total pemasukan ${_money(data.income)} dan pengeluaran ${_money(data.expense)}. Pengeluaran terbesar dialokasikan pada kategori "$topCategory". Di bidang operasional, tercatat $actCount kegiatan selesai, $harvestCount fakta panen/usaha, serta total sisa kewajiban hutang ${_money(data.liabilitiesTotal)}.';
  }

  String _changeLabel(double? value) {
    if (value == null) return 'belum ada pembanding';
    return '${value >= 0 ? '+' : ''}${value.toStringAsFixed(1)}%';
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

  String _statusLabel(FinancialHealthStatus status) => switch (status) {
        FinancialHealthStatus.excellent => 'Kondisi Sangat Kuat',
        FinancialHealthStatus.good => 'Kondisi Baik',
        FinancialHealthStatus.fair => 'Cukup Stabil',
        FinancialHealthStatus.warning => 'Perlu Perhatian Khusus',
        FinancialHealthStatus.critical => 'Perlu Dibenahi Segera',
      };

  Widget _buildLearningInsightsCard(BuildContext context, _MonthlyReportData data) {
    final scheme = Theme.of(context).colorScheme;
    final positiveColor = AppSemanticColors.positive(context);
    final negativeColor = AppSemanticColors.negative(context);
    final warningColor = AppSemanticColors.warning(context);

    Color savingsColor;
    String savingsStatus;
    if (data.savingsRate >= 20.0) {
      savingsColor = positiveColor;
      savingsStatus = 'Sangat Sehat (≥20%)';
    } else if (data.savingsRate > 0.0) {
      savingsColor = warningColor;
      savingsStatus = 'Cukup (<20%)';
    } else {
      savingsColor = negativeColor;
      savingsStatus = 'Defisit';
    }

    final debtColor = data.debtToIncomeRatio <= 30.0 ? positiveColor : negativeColor;
    final debtStatus = data.debtToIncomeRatio <= 30.0 ? 'Aman (≤30%)' : 'Waspada (>30%)';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.school_outlined, color: scheme.primary, size: 20),
              ),
              const SizedBox(width: 8),
              Text(
                'Pelajaran & Rasio Finansial',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                  decoration: BoxDecoration(
                    color: savingsColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: savingsColor.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Rasio Tabungan',
                        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${data.savingsRate.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: savingsColor,
                        ),
                      ),
                      Text(
                        savingsStatus,
                        style: TextStyle(fontSize: 10, color: savingsColor),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                  decoration: BoxDecoration(
                    color: debtColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: debtColor.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Beban Cicilan (DTI)',
                        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${data.debtToIncomeRatio.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: debtColor,
                        ),
                      ),
                      Text(
                        debtStatus,
                        style: TextStyle(fontSize: 10, color: debtColor),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Text(
            'Catatan Evaluasi Penting:',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          if (data.keyLearningPoints.isEmpty)
            const Text('Data belum cukup untuk merumuskan catatan evaluasi.')
          else
            ...data.keyLearningPoints.map(
              (point) => Padding(
                padding: const EdgeInsets.only(bottom: 6.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lightbulb_outline, size: 16, color: scheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        point,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              height: 1.35,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWhatIfSimulatorCard(BuildContext context, _MonthlyReportData data) {
    final scheme = Theme.of(context).colorScheme;
    final positiveColor = AppSemanticColors.positive(context);

    if (data.topExpenseCategories.isEmpty || data.expense <= 0) {
      return const SizedBox.shrink();
    }

    final topCategory = data.topExpenseCategories.first;
    final int topAmount = topCategory.value;
    final int monthlySavings = (topAmount * (_simulatorPercentage / 100)).round();
    final int yearlySavings = monthlySavings * 12;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.auto_graph, color: Colors.amber, size: 20),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Simulator Penghematan Bulan Depan',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Eksperimen: Jika Anda menekan pengeluaran pada pos terbesar "${topCategory.key}" sebesar ${_simulatorPercentage.toInt()}% bulan depan:',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Slider(
            value: _simulatorPercentage,
            min: 5,
            max: 30,
            divisions: 5,
            label: '${_simulatorPercentage.toInt()}%',
            onChanged: (val) => setState(() => _simulatorPercentage = val),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: positiveColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: positiveColor.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Potensi Hemat Bulanan:', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                    Text(_money(monthlySavings), style: TextStyle(fontWeight: FontWeight.bold, color: positiveColor, fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Akumulasi 1 Tahun:', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                    Text(_money(yearlySavings), style: TextStyle(fontWeight: FontWeight.bold, color: positiveColor, fontSize: 14)),
                  ],
                ),
                if (data.goals.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    '💡 Penghematan ini dapat dialihkan ke target "${data.goals.first.name}" agar tercapai lebih cepat!',
                    style: TextStyle(fontSize: 11, color: scheme.onSurface),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConsultAssistantCard(BuildContext context, _MonthlyReportData data) {
    final scheme = Theme.of(context).colorScheme;

    void openWith(String prompt) {
      final open = FfmAssistantContextScope.openAssistantOf(context);
      if (open != null) {
        open(initialPrompt: prompt);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tekan ikon Asisten melayang di pojok kanan bawah untuk memulai konsultasi.'),
          ),
        );
      }
    }

    return AppCard(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.psychology_outlined, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Konsultasi Laporan ke Asisten AI',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: () => openWith('Analisis laporan ${_periodTitle(data)} ini dan beri saya evaluasi pembelajaran untuk bulan depan.'),
                icon: const Icon(Icons.chat_bubble_outline, size: 16),
                label: const Text('Buka AI'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Asisten akan membaca laporan periode ini dan memberikan strategi keuangan personal untuk Anda:',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              ActionChip(
                avatar: const Icon(Icons.insights, size: 16),
                label: const Text('Evaluasi & Saran'),
                onPressed: () => openWith('Evaluasi laporan ${_periodTitle(data)} ini: apa yang bagus dan apa yang harus saya perbaiki di bulan depan?'),
              ),
              ActionChip(
                avatar: const Icon(Icons.search, size: 16),
                label: const Text('Cari Kebocoran Uang'),
                onPressed: () => openWith('Berdasarkan laporan ${_periodTitle(data)}, di pos mana kebocoran uang terbesar saya dan bagaimana cara menambalnya?'),
              ),
              ActionChip(
                avatar: const Icon(Icons.wallet, size: 16),
                label: const Text('Rekomendasi Anggaran'),
                onPressed: () => openWith('Dari laporan ${_periodTitle(data)} ini, buatkan rekomendasi plafon anggaran belanja untuk bulan depan.'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatSummaryBox extends StatelessWidget {
  const _StatSummaryBox({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.bodySmall),
                Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.labelCaps),
          const SizedBox(height: 6),
          AppMoneyText(value, color: color, compact: true),
        ],
      ),
    );
  }
}

class MonthlyReportLearningMetrics {
  const MonthlyReportLearningMetrics({
    required this.savingsRate,
    required this.debtToIncomeRatio,
    required this.topExpenseCategoryShare,
    required this.keyLearningPoints,
  });

  final double savingsRate;
  final double debtToIncomeRatio;
  final double topExpenseCategoryShare;
  final List<String> keyLearningPoints;

  factory MonthlyReportLearningMetrics.calculate({
    required int income,
    required int expense,
    required int totalMonthlyInstallments,
    required int totalAssetsValue,
    required List<MapEntry<String, int>> topExpenseCategories,
  }) {
    final netCashflow = income - expense;
    final savingsRate =
        income > 0 ? (netCashflow / income * 100).clamp(-100.0, 100.0) : 0.0;
    final debtToIncomeRatio = income > 0
        ? (totalMonthlyInstallments / income * 100).clamp(0.0, 100.0)
        : 0.0;
    final topExpenseCategoryShare =
        (expense > 0 && topExpenseCategories.isNotEmpty)
            ? (topExpenseCategories.first.value / expense * 100).clamp(0.0, 100.0)
            : 0.0;

    final points = <String>[];
    if (savingsRate >= 20.0) {
      points.add(
        'Rasio tabungan sehat di angka ${savingsRate.toStringAsFixed(1)}% (di atas target minimal 20%). Pertahankan konsistensi ini.',
      );
    } else if (savingsRate > 0) {
      points.add(
        'Rasio tabungan periode ini ${savingsRate.toStringAsFixed(1)}%. Masih di bawah batas ideal 20%, disarankan menyisihkan tabungan di awal gajian.',
      );
    } else if (income > 0) {
      points.add(
        'Arus kas mengalami defisit Rp ${(expense - income)}. Prioritaskan evaluasi pos non-primer agar tidak menggerus tabungan.',
      );
    }

    if (topExpenseCategories.isNotEmpty) {
      final top = topExpenseCategories.first;
      points.add(
        'Pos "${top.key}" mendominasi ${topExpenseCategoryShare.toStringAsFixed(1)}% pengeluaran. Pemangkasan 10% di pos ini dapat menghemat Rp ${(top.value * 0.1).round()}.',
      );
    }

    if (debtToIncomeRatio > 30.0) {
      points.add(
        'Perhatian: Beban cicilan (${debtToIncomeRatio.toStringAsFixed(1)}%) di atas ambang aman 30%. Hindari komitmen hutang baru.',
      );
    } else if (totalMonthlyInstallments > 0) {
      points.add(
        'Beban cicilan bulanan aman di angka ${debtToIncomeRatio.toStringAsFixed(1)}% dari pemasukan.',
      );
    } else if (totalAssetsValue > 0) {
      points.add(
        'Bebas cicilan dengan estimasi nilai aset Rp $totalAssetsValue.',
      );
    }

    return MonthlyReportLearningMetrics(
      savingsRate: savingsRate,
      debtToIncomeRatio: debtToIncomeRatio,
      topExpenseCategoryShare: topExpenseCategoryShare,
      keyLearningPoints: points,
    );
  }
}

class _MonthlyReportData {
  const _MonthlyReportData({
    required this.month,
    required this.isWeekly,
    required this.transactions,
    required this.assets,
    required this.liabilities,
    required this.receivables,
    required this.goals,
    required this.budgets,
    required this.categories,
    required this.tags,
    required this.merchants,
    required this.activitySessions,
    required this.activityEntries,
    required this.dailyNotes,
    required this.tasks,
    required this.dailyRoutines,
    required this.routineCompletions,
    required this.harvestEvents,
    required this.categoryLabels,
    required this.merchantLabels,
    required this.tagLabels,
    required this.currentRows,
    required this.income,
    required this.expense,
    required this.previousIncome,
    required this.previousExpense,
    required this.score,
  });

  final DateTime month;
  final bool isWeekly;
  final List<TransactionWithItems> transactions;
  final List<AssetEntity> assets;
  final List<LiabilityEntity> liabilities;
  final List<ReceivableEntity> receivables;
  final List<GoalEntity> goals;
  final List<EnvelopeBudget> budgets;
  final List<Category> categories;
  final List<Tag> tags;
  final List<Merchant> merchants;
  final List<ActivitySession> activitySessions;
  final List<ActivityEntry> activityEntries;
  final List<DailyNote> dailyNotes;
  final List<Task> tasks;
  final List<DailyRoutine> dailyRoutines;
  final List<DailyRoutineCompletion> routineCompletions;
  final List<HarvestEvent> harvestEvents;

  final Map<String, String> categoryLabels;
  final Map<String, String> merchantLabels;
  final Map<String, String> tagLabels;

  final List<TransactionWithItems> currentRows;
  final int income;
  final int expense;
  final int previousIncome;
  final int previousExpense;
  final FinancialHealthScore score;

  int get netCashflow => income - expense;

  int get receivablesOutstanding =>
      receivables.fold(0, (sum, item) => sum + item.remainingBalance);

  int get receivablesStartedThisMonth => receivables
      .where((item) => _isCurrentPeriod(item.startDate))
      .fold(0, (sum, item) => sum + item.originalAmount);

  int get receivablesDueThisMonth => receivables
      .where((item) => item.remainingBalance > 0 && _isCurrentPeriod(item.dueDate))
      .fold(0, (sum, item) => sum + item.remainingBalance);

  int get liabilitiesTotal =>
      liabilities.fold(0, (sum, item) => sum + item.remainingBalance);

  int get totalMonthlyInstallments =>
      liabilities.fold(0, (sum, item) => sum + item.monthlyInstallment);

  int get totalAssetsValue => assets.fold(0, (sum, item) => sum + item.value);

  int get netWorth => totalAssetsValue - liabilitiesTotal;

  MonthlyReportLearningMetrics get learningMetrics =>
      MonthlyReportLearningMetrics.calculate(
        income: income,
        expense: expense,
        totalMonthlyInstallments: totalMonthlyInstallments,
        totalAssetsValue: totalAssetsValue,
        topExpenseCategories: topExpenseCategories,
      );

  double get savingsRate => learningMetrics.savingsRate;
  double get debtToIncomeRatio => learningMetrics.debtToIncomeRatio;
  double get topExpenseCategoryShare => learningMetrics.topExpenseCategoryShare;
  List<String> get keyLearningPoints => learningMetrics.keyLearningPoints;

  bool _isCurrentPeriod(DateTime d) {
    if (isWeekly) {
      final start = DateTime(month.year, month.month, month.day)
          .subtract(Duration(days: month.weekday - 1));
      final end = start.add(const Duration(days: 7));
      return !d.isBefore(start) && d.isBefore(end);
    } else {
      return d.year == month.year && d.month == month.month;
    }
  }

  List<MapEntry<String, int>> get topExpenseCategories {
    final totals = <String, int>{};
    for (final row in currentRows.where(
      (r) =>
          r.transaction.amount < 0 &&
          r.transaction.type != 'transfer' &&
          r.transaction.transferId == null,
    )) {
      final name =
          categoryLabels[row.transaction.categoryId] ?? 'Tanpa Kategori';
      totals[name] = (totals[name] ?? 0) + row.transaction.amount.abs();
    }
    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(5).toList();
  }

  List<MapEntry<String, int>> get topIncomeCategories {
    final totals = <String, int>{};
    for (final row in currentRows.where(
      (r) =>
          r.transaction.amount > 0 &&
          r.transaction.type != 'transfer' &&
          r.transaction.transferId == null,
    )) {
      final name =
          categoryLabels[row.transaction.categoryId] ?? 'Tanpa Kategori';
      totals[name] = (totals[name] ?? 0) + row.transaction.amount;
    }
    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(5).toList();
  }

  List<MapEntry<String, int>> get topTags {
    final totals = <String, int>{};
    for (final row in currentRows.where((r) => r.transaction.amount < 0)) {
      for (final tagId in row.tags) {
        final label = tagLabels[tagId] ?? tagId;
        totals[label] = (totals[label] ?? 0) + row.transaction.amount.abs();
      }
    }
    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(5).toList();
  }

  List<MapEntry<String, int>> get topMerchants {
    final totals = <String, int>{};
    for (final row in currentRows.where((r) => r.transaction.amount < 0)) {
      final mId = row.transaction.merchantId;
      if (mId != null && mId.isNotEmpty) {
        final label = merchantLabels[mId] ?? mId;
        totals[label] = (totals[label] ?? 0) + row.transaction.amount.abs();
      }
    }
    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(5).toList();
  }

  List<TransactionWithItems> get topExpenses {
    final expenses = currentRows
        .where(
          (r) =>
              r.transaction.amount < 0 &&
              r.transaction.type != 'transfer' &&
              r.transaction.transferId == null,
        )
        .toList();
    expenses.sort(
      (a, b) =>
          a.transaction.amount.abs().compareTo(b.transaction.amount.abs()),
    );
    return expenses.reversed.take(5).toList();
  }

  List<ActivityEntry> get currentMonthActivities => activityEntries
      .where((e) => _isCurrentPeriod(e.startedAt))
      .toList();

  List<DailyNote> get currentMonthDailyNotes => dailyNotes
      .where((n) => _isCurrentPeriod(n.noteDate))
      .toList();

  List<HarvestEvent> get currentMonthHarvests => harvestEvents
      .where((h) => _isCurrentPeriod(h.harvestedAt))
      .toList();

  int get currentMonthHarvestTotalValue => currentMonthHarvests.fold(
        0,
        (sum, item) => sum + (item.totalAmount ?? 0),
      );

  double get currentMonthHarvestTotalQuantity => currentMonthHarvests.fold(
        0.0,
        (sum, item) => sum + item.quantity,
      );

  int get tasksCompletedThisMonth => tasks
      .where((t) => t.completedAt != null && _isCurrentPeriod(t.completedAt!))
      .length;

  int get routineCompletionsThisMonth => routineCompletions
      .where((c) => _isCurrentPeriod(c.routineDate))
      .length;
}
