import 'dart:typed_data';

import 'package:flutter/material.dart';
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
  late Future<_MonthlyReportData> _future;
  var _working = false;
  List<MonthlyReportRecord> _history = const [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _future = _load(_month);
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final history = await OfflineToolHistoryService().readMonthlyReports();
    if (mounted) setState(() => _history = history);
  }

  Future<_MonthlyReportData> _load(DateTime month) async {
    final transactions = await getIt<GetTransactions>()(AppContext.householdId);
    final assets = await getIt<GetAssets>()(AppContext.householdId);
    final liabilities = await getIt<GetLiabilities>()(AppContext.householdId);
    final receivables = await getIt<GetReceivables>()(AppContext.householdId);
    final goals = await getIt<GetGoals>()(AppContext.householdId);
    final categories = await getIt<AppDatabase>()
        .select(getIt<AppDatabase>().categories)
        .get();
    final labels = {for (final item in categories) item.id: item.name};
    final current = _monthRows(transactions, month);
    final previous = _monthRows(
      transactions,
      DateTime(month.year, month.month - 1),
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
      month: month,
      transactions: transactions,
      assets: assets,
      liabilities: liabilities,
      receivables: receivables,
      goals: goals,
      categoryLabels: labels,
      currentRows: current,
      income: income,
      expense: expense,
      previousIncome: previousIncome,
      previousExpense: previousExpense,
      score: score,
    );
  }

  List<TransactionWithItems> _monthRows(
    List<TransactionWithItems> rows,
    DateTime month,
  ) => rows
      .where(
        (item) =>
            item.transaction.date.year == month.year &&
            item.transaction.date.month == month.month,
      )
      .toList(growable: false);

  int _income(List<TransactionWithItems> rows) => rows
      .where((item) => item.transaction.amount > 0)
      .fold(0, (sum, item) => sum + item.transaction.amount);

  int _expense(List<TransactionWithItems> rows) => rows
      .where((item) => item.transaction.amount < 0)
      .fold(0, (sum, item) => sum + item.transaction.amount.abs());

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: _month,
      helpText: 'Pilih bulan laporan',
      cancelText: AppCopy.batal,
      confirmText: AppCopy.selesai,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _month = DateTime(picked.year, picked.month);
      _future = _load(_month);
    });
  }

  Future<void> _export(_MonthlyReportData data) async {
    setState(() => _working = true);
    try {
      final bytes = await const PdfReportService().buildMonthlyReport(
        month: data.month,
        transactions: data.transactions,
        assets: data.assets,
        liabilities: data.liabilities,
        receivables: data.receivables,
        goals: data.goals,
        categoryLabels: data.categoryLabels,
        score: data.score,
      );
      await Printing.sharePdf(
        bytes: Uint8List.fromList(bytes),
        filename: 'ffm-ringkasan-${_monthStamp(data.month)}.pdf',
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
          const SnackBar(content: Text('Ringkasan PDF siap dibagikan.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ringkasan belum berhasil dibuat. Coba lagi.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
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
      '${month.year}-${month.month.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_MonthlyReportData>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final summaryText = data != null
            ? 'Melihat laporan ${_monthLabel(data.month)}. Pemasukan: ${_money(data.income)}, Pengeluaran: ${_money(data.expense)}. Surplus/Defisit: ${_money(data.income - data.expense)}.'
            : 'Sedang memuat laporan...';

        return FfmAssistantPageContext(
          destination: FfmAssistantDestination.monthlyReport,
          dataSummary: summaryText,
          child: Scaffold(
            appBar: AppBar(title: const Text('Ringkasan bulanan')),
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
    final net = data.income - data.expense;
    final incomeChange = data.previousIncome == 0
        ? null
        : ((data.income - data.previousIncome) / data.previousIncome * 100);
    final expenseChange = data.previousExpense == 0
        ? null
        : ((data.expense - data.previousExpense) / data.previousExpense * 100);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        AppCard(
          color: scheme.primaryContainer,
          child: Row(
            children: [
              Icon(Icons.calendar_month_outlined, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _monthLabel(_month),
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(color: scheme.onPrimaryContainer),
                ),
              ),
              OutlinedButton(
                onPressed: _pickMonth,
                child: const Text('Ganti bulan'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
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
              const Text('Arus kas bersih', style: AppTextStyles.labelCaps),
              const SizedBox(height: 6),
              AppMoneyText(
                net,
                color: net >= 0 ? positiveColor : negativeColor,
              ),
              const SizedBox(height: 12),
              Text(
                'Dibanding bulan sebelumnya: pemasukan ${_changeLabel(incomeChange)}, pengeluaran ${_changeLabel(expenseChange)}.',
              ),
              const SizedBox(height: 8),
              Text(
                '${data.currentRows.length} transaksi tercatat pada periode ini.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        AppCard(
          child: Row(
            children: [
              Icon(Icons.health_and_safety_outlined, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Skor kesehatan: ${data.score.totalScore}/100\n${_statusLabel(data.score.status)}',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppCard(
          color: scheme.secondaryContainer,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Piutang (tambahan, bukan kas)',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: scheme.onSecondaryContainer),
              ),
              const SizedBox(height: 4),
              Text(
                'Angka ini menunjukkan uang yang masih harus diterima. Belum dihitung sebagai pemasukan sampai benar-benar masuk ke rekening atau dompet.',
                style: TextStyle(color: scheme.onSecondaryContainer),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _MetricCard(
                      label: 'Belum diterima',
                      value: data.receivablesOutstanding,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MetricCard(
                      label: 'Jatuh tempo bulan ini',
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
            ],
          ),
        ),
        const SizedBox(height: 16),
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
            _working ? 'Lagi menyiapkan...' : 'Ekspor dan bagikan PDF',
          ),
        ),
        const SizedBox(height: 24),
        const Text('Riwayat laporan', style: AppTextStyles.labelCaps),
        const SizedBox(height: 8),
        if (_history.isEmpty)
          const Text(
            'Belum ada laporan yang dibuat. Pilih bulan lalu ekspor kalau sudah siap.',
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
                  _month = DateTime(item.month.year, item.month.month);
                  _future = _load(_month);
                }),
              ),
            ),
      ],
    );
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
    FinancialHealthStatus.excellent => 'Kondisi sangat kuat',
    FinancialHealthStatus.good => 'Kondisi baik',
    FinancialHealthStatus.fair => 'Cukup stabil',
    FinancialHealthStatus.warning => 'Perlu perhatian',
    FinancialHealthStatus.critical => 'Perlu dibenahi segera',
  };
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

class _MonthlyReportData {
  const _MonthlyReportData({
    required this.month,
    required this.transactions,
    required this.assets,
    required this.liabilities,
    required this.receivables,
    required this.goals,
    required this.categoryLabels,
    required this.currentRows,
    required this.income,
    required this.expense,
    required this.previousIncome,
    required this.previousExpense,
    required this.score,
  });

  final DateTime month;
  final List<TransactionWithItems> transactions;
  final List<AssetEntity> assets;
  final List<LiabilityEntity> liabilities;
  final List<ReceivableEntity> receivables;
  final List<GoalEntity> goals;
  final Map<String, String> categoryLabels;
  final List<TransactionWithItems> currentRows;
  final int income;
  final int expense;
  final int previousIncome;
  final int previousExpense;
  final FinancialHealthScore score;

  int get receivablesOutstanding =>
      receivables.fold(0, (sum, item) => sum + item.remainingBalance);

  int get receivablesStartedThisMonth => receivables
      .where(
        (item) =>
            item.startDate.year == month.year &&
            item.startDate.month == month.month,
      )
      .fold(0, (sum, item) => sum + item.originalAmount);

  int get receivablesDueThisMonth => receivables
      .where(
        (item) =>
            item.remainingBalance > 0 &&
            item.dueDate.year == month.year &&
            item.dueDate.month == month.month,
      )
      .fold(0, (sum, item) => sum + item.remainingBalance);
}
