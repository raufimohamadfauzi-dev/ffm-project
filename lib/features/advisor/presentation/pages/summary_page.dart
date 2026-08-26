import 'package:drift/drift.dart' hide Column;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/database/app_context.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/localization/app_copy.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../../../shared/widgets/date_time_components.dart';
import '../../../assistant/data/ffm_assistant_widget_sync_service.dart';
import '../../../assistant/domain/ffm_assistant_models.dart';
import '../../../assistant/presentation/widgets/ffm_assistant_page_context.dart';
import '../../../asset/domain/usecases/asset_crud_usecases.dart';
import '../../../asset/presentation/pages/asset_pages.dart';
import '../../../budget/presentation/pages/budget_page.dart';
import '../../../goal/presentation/pages/goal_pages.dart';
import '../../../liability/domain/usecases/liability_crud_usecases.dart';
import '../../../liability/presentation/pages/liability_pages.dart';
import '../../../hijri/domain/hijri_calendar_service.dart';
import '../../../recurring_transaction/domain/usecases/recurring_transaction_crud_usecases.dart';
import '../../../reminder/presentation/pages/reminder_page.dart';
import '../../../transaction/domain/usecases/transaction_crud_usecases.dart';
import '../../../settings/presentation/pages/master_data_page.dart';
import '../../../transaction/presentation/pages/transaction_pages.dart';
import '../../domain/usecases/advisor_suggestion_generator.dart';
import '../../domain/usecases/budget_guard_service.dart';
import '../../domain/usecases/financial_analysis.dart';
import '../../domain/usecases/financial_health_calculator.dart';
import 'analysis_page.dart';

class SummaryPage extends StatefulWidget {
  const SummaryPage({super.key});

  @override
  State<SummaryPage> createState() => _SummaryPageState();
}

class _SummaryPageState extends State<SummaryPage> {
  late Future<_SummaryData> _summaryFuture;

  @override
  void initState() {
    super.initState();
    _summaryFuture = _loadSummary();
  }

  Future<_SummaryData> _loadSummary() async {
    final transactions = await getIt<GetTransactions>()(AppContext.householdId);
    final assets = await getIt<GetAssets>()(AppContext.householdId);
    final liabilities = await getIt<GetLiabilities>()(AppContext.householdId);
    final recurring = await getIt<GetRecurringTransactions>()(
      AppContext.householdId,
    );
    final now = DateTime.now();
    final hijriToday = await getIt<HijriCalendarService>().convert(
      AppContext.householdId,
      now,
    );
    final currentMonth = transactions
        .map((item) => item.transaction)
        .where(
          (item) => item.date.year == now.year && item.date.month == now.month,
        )
        .toList();
    final income = currentMonth
        .where((item) => item.amount > 0)
        .fold<int>(0, (sum, item) => sum + item.amount);
    final expenses = currentMonth
        .where((item) => item.amount < 0)
        .fold<int>(0, (sum, item) => sum + item.amount.abs());
    final installments = liabilities.fold<int>(
      0,
      (sum, liability) => sum + liability.monthlyInstallment,
    );
    final emergencyFund = assets
        .where((asset) => asset.assetType == 'cash')
        .fold<int>(0, (sum, asset) => sum + asset.value);
    final hasAnyTransaction = transactions.isNotEmpty;
    final hasIncome = transactions.any((item) => item.transaction.amount > 0);
    final hasExpense = transactions.any((item) => item.transaction.amount < 0);
    final score = const FinancialHealthCalculator().calculate(
      FinancialHealthInput(
        totalIncome: income,
        totalExpenses: expenses,
        totalMonthlyInstallments: installments,
        emergencyFundAmount: emergencyFund,
        averageMonthlyExpenses: expenses,
      ),
    );
    final forecast = FinancialAnalysis.forecast(
      transactions,
      fromMonth: now,
      recurring: recurring,
    );
    final weeklyDigest = FinancialAnalysis.weeklyDigest(
      transactions,
      weekContaining: now,
    );
    final expenseTrend = List<MonthlyExpensePoint>.generate(6, (index) {
      final month = DateTime(now.year, now.month - 5 + index);
      final monthExpenses = transactions
          .map((item) => item.transaction)
          .where(
            (item) =>
                item.amount < 0 &&
                item.date.year == month.year &&
                item.date.month == month.month,
          )
          .toList(growable: false);
      final amount = monthExpenses.fold<int>(
        0,
        (sum, item) => sum + item.amount.abs(),
      );
      return MonthlyExpensePoint(
        month: month,
        amount: amount,
        transactionCount: monthExpenses.length,
      );
    });
    final database = getIt<AppDatabase>();
    final financialSuggestions = await getIt<BudgetGuardService>().check(
      AppContext.householdId,
      at: now,
    );
    final household =
        await (database.select(database.households)
              ..where((item) => item.id.equals(AppContext.householdId)))
            .getSingleOrNull();
    final householdName = household?.name.trim();
    final accounts =
        await (database.select(database.accounts)..where(
              (item) =>
                  item.householdId.equals(AppContext.householdId) &
                  item.isActive.equals(true) &
                  item.isArchived.equals(false),
            ))
            .get();
    final categories =
        await (database.select(database.categories)..where(
              (item) =>
                  item.householdId.equals(AppContext.householdId) &
                  item.isActive.equals(true),
            ))
            .get();
    final hasAccounts = accounts.isNotEmpty;
    final hasExpenseCategory = categories.any((item) => item.type == 'expense');
    final hasIncomeCategory = categories.any((item) => item.type == 'income');
    final hasTransactionBasics =
        hasAccounts && hasExpenseCategory && hasIncomeCategory;
    final missingMasterData = <String>[];
    if (!hasAccounts) missingMasterData.add('Rekening atau dompet');
    if (!hasExpenseCategory) missingMasterData.add('Kategori pengeluaran');
    if (!hasIncomeCategory) missingMasterData.add('Kategori pemasukan');

    final dashboardSuggestion = const AdvisorSuggestionGenerator()
        .generate(
          AdvisorSuggestionInput(
            healthScore: score,
            transactionCount: transactions.length,
            hasIncome: hasIncome,
            hasExpense: hasExpense,
          ),
        )
        .firstWhere((item) => item.placement == SuggestionPlacement.dashboard);
    final summary = _SummaryData(
      score: score,
      financialSuggestions: financialSuggestions,
      income: income,
      expenses: expenses,
      transactionCount: currentMonth.length,
      hasAnyTransaction: hasAnyTransaction,
      suggestion: dashboardSuggestion,
      totalAssets: assets.fold<int>(0, (sum, asset) => sum + asset.value),
      totalLiabilities: liabilities.fold<int>(
        0,
        (sum, liability) => sum + liability.remainingBalance,
      ),
      forecast: forecast,
      weeklyDigest: weeklyDigest,
      expenseTrend: expenseTrend,
      hasAccounts: hasAccounts,
      // Sumber pemasukan akan diminta khusus saat user mencatat pemasukan.
      // Jangan blokir transaksi pertama hanya karena field opsional itu belum ada.
      hasMasterData: hasTransactionBasics,
      missingMasterData: missingMasterData,
      householdName: householdName?.isNotEmpty == true ? householdName : null,
      hijriToday: hijriToday,
    );
    unawaited(
      const FfmAssistantWidgetSyncService().updateSummary(
        title: 'FFM · Ringkasan bulan ini',
        subtitle:
            'Masuk ${formatCompactRupiah(summary.income)} · Keluar ${formatCompactRupiah(summary.expenses)}',
      ),
    );
    return summary;
  }

  void _refresh() {
    setState(() => _summaryFuture = _loadSummary());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_SummaryData>(
      future: _summaryFuture,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final summaryText = data != null
            ? 'Kekayaan Bersih: ${formatCompactRupiah(data.netWorth)}. Bulan ini: Masuk ${formatCompactRupiah(data.income)}, Keluar ${formatCompactRupiah(data.expenses)}.'
            : 'Sedang memuat ringkasan...';

        return FfmAssistantPageContext(
          destination: FfmAssistantDestination.summary,
          dataSummary: summaryText,
          child: _buildScaffold(context, snapshot),
        );
      },
    );
  }

  Widget _buildScaffold(
    BuildContext context,
    AsyncSnapshot<_SummaryData> snapshot,
  ) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }
    if (snapshot.hasError) {
      return Scaffold(
        appBar: AppBar(title: const Text(AppCopy.dashboard)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: AppEmptyState(
              icon: Icons.cloud_off,
              title: 'Ringkasan belum siap',
              message: 'Coba muat ulang halaman ini.',
              action: FilledButton(
                onPressed: _refresh,
                child: const Text('Muat ulang'),
              ),
            ),
          ),
        ),
      );
    }
    final data = snapshot.data!;
    return Scaffold(
      body: _SummaryContent(data: data, onRefresh: _refresh),
    );
  }
}

class _SummaryContent extends StatelessWidget {
  const _SummaryContent({required this.data, required this.onRefresh});

  final _SummaryData data;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final score = data.score;
    final scheme = Theme.of(context).colorScheme;
    return CustomScrollView(
      slivers: [
        SliverAppBar.large(
          title: const Text(AppCopy.dashboard),
          actions: [
            IconButton(
              tooltip: 'Info Ringkasan',
              onPressed: () => showAppInfoDialog(
                context,
                title: 'Cara baca Ringkasan',
                message: 'Lihat angka bulan ini, baca Saran Keuangan, lalu pilih tindakan yang dibutuhkan. Semua angka berubah setelah data disimpan.',
              ),
              icon: const Icon(Icons.info_outline),
            ),
            if (data.hasMasterData && data.hasAnyTransaction)
              IconButton(
                tooltip: 'Analisa keuangan',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AnalysisPage()),
                ),
                icon: const Icon(Icons.auto_graph_outlined),
              ),
            IconButton(
              tooltip: 'Pengingat',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ReminderPage()),
              ),
              icon: const Icon(Icons.notifications_none),
            ),
            IconButton(
              tooltip: 'Muat ulang',
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
            ),
            const SizedBox(width: 8),
          ],
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          sliver: SliverList.list(
            children: [
              Text(
                data.householdName == null
                    ? 'Hai, selamat datang di Family Finance Manager (FFM). Yuk lihat kondisi uang keluarga hari ini.'
                    : 'Hai ${data.householdName}, selamat datang di Family Finance Manager (FFM). Yuk lihat kondisi uang keluarga hari ini.',
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              _HijriDateSummaryCard(date: data.hijriToday),
              if (data.financialSuggestions.isNotEmpty) ...[
                const SizedBox(height: 20),
                const AppSectionHeader(
                  title: 'Saran Keuangan',
                  trailing: AppStatusChip(label: 'CEK DULU'),
                ),
                const SizedBox(height: 8),
                _FinancialSuggestionsCard(
                  suggestions: data.financialSuggestions,
                  onTap: (suggestion) =>
                      _openFinancialSuggestion(context, suggestion, onRefresh),
                ),
              ],
              const SizedBox(height: 20),
              if (!data.hasMasterData)
                _SetupGuideCard(
                  missingItems: data.missingMasterData,
                  onSetup: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MasterDataPage()),
                  ).then((_) => onRefresh()),
                )
              else if (!data.hasAnyTransaction) ...[
                _EmptySummaryCard(
                  onStart: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const TransactionListPage(),
                    ),
                  ).then((_) => onRefresh()),
                ),
                const SizedBox(height: 24),
                const AppSectionHeader(
                  title: 'Tren pengeluaran',
                  trailing: AppStatusChip(label: '6 BULAN'),
                ),
                const SizedBox(height: 8),
                _MonthlyExpenseTrendCard(points: data.expenseTrend),
              ] else ...[
                _HealthScoreCard(score: score),
                const SizedBox(height: 24),
                const AppSectionHeader(
                  title: 'Saran buat kamu',
                  trailing: AppStatusChip(label: 'PENTING'),
                ),
                const SizedBox(height: 8),
                _SuggestionCard(
                  suggestion: data.suggestion,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const TransactionListPage(),
                    ),
                  ).then((_) => onRefresh()),
                ),
                const SizedBox(height: 24),
                const AppSectionHeader(
                  title: 'Ringkasan bulan ini',
                  trailing: AppStatusChip(label: 'SANGAT PENTING'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _MoneySummaryCard(
                        label: AppCopy.pemasukan,
                        amount: data.income,
                        icon: Icons.arrow_downward_rounded,
                        color: AppColors.positive,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _MoneySummaryCard(
                        label: AppCopy.pengeluaran,
                        amount: data.expenses,
                        icon: Icons.arrow_upward_rounded,
                        color: AppColors.negative,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '${data.transactionCount} transaksi tercatat bulan ini.',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
                const AppSectionHeader(
                  title: 'Tren pengeluaran',
                  trailing: AppStatusChip(label: '6 BULAN'),
                ),
                const SizedBox(height: 8),
                _MonthlyExpenseTrendCard(points: data.expenseTrend),
                const SizedBox(height: 24),
                AppSectionHeader(
                  title: 'Posisi keuangan',
                  trailing: AppStatusChip(
                    label: 'RANGKUMAN',
                    color: AppColors.inkMuted,
                    backgroundColor: AppColors.surfaceContainer,
                  ),
                ),
                const SizedBox(height: 8),
                _DashboardBalanceCard(data: data),
                const SizedBox(height: 24),
                AppSectionHeader(
                  title: 'Ringkasan cepat',
                  trailing: AppStatusChip(
                    label: 'INFO',
                    color: AppColors.inkMuted,
                    backgroundColor: AppColors.surfaceContainer,
                  ),
                ),
                const SizedBox(height: 8),
                _DashboardInsightCard(data: data),
              ],
              const SizedBox(height: 24),
              const AppSectionHeader(
                title: 'Mulai dari sini',
                trailing: AppStatusChip(
                  label: 'TINDAKAN',
                  color: AppColors.inkMuted,
                  backgroundColor: AppColors.surfaceContainer,
                ),
              ),
              const SizedBox(height: 8),
              _QuickActionsCard(
                onMasterData: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MasterDataPage()),
                ).then((_) => onRefresh()),
                onTransaction: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const TransactionListPage(),
                  ),
                ).then((_) => onRefresh()),
                onAsset: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AssetListPage()),
                ).then((_) => onRefresh()),
                onGoal: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const GoalListPage()),
                ).then((_) => onRefresh()),
                masterDataReady: data.hasMasterData,
                hasAnyTransaction: data.hasAnyTransaction,
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _openFinancialSuggestion(
    BuildContext context,
    FinancialGuardSuggestion suggestion,
    VoidCallback onRefresh,
  ) {
    final page = switch (suggestion.kind) {
      FinancialGuardKind.budgetExceeded ||
      FinancialGuardKind.budgetNearLimit ||
      FinancialGuardKind.budgetFastUse ||
      FinancialGuardKind.budgetLargeRemaining => const EnvelopeBudgetPage(),
      FinancialGuardKind.monthlyCashDeficit => const TransactionListPage(),
      FinancialGuardKind.liabilityDue => const LiabilityReceivablePage(),
    };
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    ).then((_) => onRefresh());
  }
}

class _FinancialSuggestionsCard extends StatelessWidget {
  const _FinancialSuggestionsCard({
    required this.suggestions,
    required this.onTap,
  });

  final List<FinancialGuardSuggestion> suggestions;
  final ValueChanged<FinancialGuardSuggestion> onTap;

  @override
  Widget build(BuildContext context) {
    final visible = suggestions.take(3).toList(growable: false);
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var index = 0; index < visible.length; index++) ...[
            if (index > 0) const Divider(height: 1),
            ListTile(
              onTap: () => onTap(visible[index]),
              leading: _FinancialSuggestionIcon(
                severity: visible[index].severity,
              ),
              title: Text(
                visible[index].title,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${visible[index].message}\n${visible[index].trace}',
                ),
              ),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ],
      ),
    );
  }
}

class _FinancialSuggestionIcon extends StatelessWidget {
  const _FinancialSuggestionIcon({required this.severity});

  final FinancialGuardSeverity severity;

  @override
  Widget build(BuildContext context) {
    final color = switch (severity) {
      FinancialGuardSeverity.critical => AppColors.negative,
      FinancialGuardSeverity.warning => AppColors.warning,
      FinancialGuardSeverity.info => AppColors.primary,
    };
    final icon = switch (severity) {
      FinancialGuardSeverity.critical => Icons.warning_amber_rounded,
      FinancialGuardSeverity.warning => Icons.error_outline_rounded,
      FinancialGuardSeverity.info => Icons.info_outline_rounded,
    };
    return Icon(icon, color: color);
  }
}

class _HijriDateSummaryCard extends StatelessWidget {
  const _HijriDateSummaryCard({required this.date});

  final HijriDisplayDate date;

  static const _monthNames = [
    'Muharam',
    'Safar',
    'Rabiulawal',
    'Rabiulakhir',
    'Jumadilawal',
    'Jumadilakhir',
    'Rajab',
    'Syaban',
    'Ramadan',
    'Syawal',
    'Zulkaidah',
    'Zulhijah',
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final month = date.hijri.month.clamp(1, _monthNames.length);
    return AppCard(
      color: scheme.surfaceContainerHighest,
      child: Row(
        children: [
          Icon(Icons.calendar_month_outlined, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tanggal hari ini',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  formatTanggalLengkap(date.gregorian, includeSeconds: false),
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '${date.hijri.day} ${_monthNames[month - 1]} ${date.hijri.year} H',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryData {
  const _SummaryData({
    required this.score,
    required this.financialSuggestions,
    required this.income,
    required this.expenses,
    required this.transactionCount,
    required this.hasAnyTransaction,
    required this.suggestion,
    required this.totalAssets,
    required this.totalLiabilities,
    required this.forecast,
    required this.weeklyDigest,
    required this.expenseTrend,
    required this.hasAccounts,
    required this.hasMasterData,
    required this.missingMasterData,
    required this.householdName,
    required this.hijriToday,
  });

  final FinancialHealthScore score;
  final List<FinancialGuardSuggestion> financialSuggestions;
  final int income;
  final int expenses;
  final int transactionCount;
  final bool hasAnyTransaction;
  final AdvisorSuggestion suggestion;
  final int totalAssets;
  final int totalLiabilities;
  final List<ForecastPoint> forecast;
  final WeeklyDigest weeklyDigest;
  final List<MonthlyExpensePoint> expenseTrend;
  final bool hasAccounts;
  final bool hasMasterData;
  final List<String> missingMasterData;
  final String? householdName;
  final HijriDisplayDate hijriToday;

  int get netWorth => totalAssets - totalLiabilities;
}

class MonthlyExpensePoint {
  const MonthlyExpensePoint({
    required this.month,
    required this.amount,
    required this.transactionCount,
  });

  final DateTime month;
  final int amount;
  final int transactionCount;
}

String formatCompactRupiah(int amount) {
  if (amount >= 1000000) {
    final millions = amount / 1000000;
    final decimal = millions % 1 == 0 ? '' : millions.toStringAsFixed(1);
    return 'Rp${decimal.isEmpty ? millions.toStringAsFixed(0) : decimal.replaceAll('.', ',')} jt';
  }
  if (amount >= 1000) {
    final thousands = amount / 1000;
    final decimal = thousands % 1 == 0 ? '' : thousands.toStringAsFixed(1);
    return 'Rp${decimal.isEmpty ? thousands.toStringAsFixed(0) : decimal.replaceAll('.', ',')} rb';
  }
  return 'Rp$amount';
}

class _MonthlyExpenseTrendCard extends StatelessWidget {
  const _MonthlyExpenseTrendCard({required this.points});

  final List<MonthlyExpensePoint> points;

  static const _monthLabels = [
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxAmount = points.fold<int>(
      0,
      (max, point) => point.amount > max ? point.amount : max,
    );
    final hasExpense = maxAmount > 0;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bar_chart_rounded, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hasExpense
                      ? 'Tertinggi ${formatRupiahInput(maxAmount.toString())}'
                      : 'Belum ada pengeluaran',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
          if (!hasExpense) ...[
            const SizedBox(height: 14),
            Text(
              'Belum ada data pengeluaran',
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Nanti grafik ini terisi otomatis setelah kamu menyimpan pengeluaran.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ] else ...[
            const SizedBox(height: 16),
            SizedBox(
              height: 154,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: points
                    .map((point) {
                      final ratio = maxAmount == 0
                          ? 0.0
                          : point.amount / maxAmount;
                      final barHeight = hasExpense ? 8 + (108 * ratio) : 8.0;
                      return Expanded(
                        child: Semantics(
                          label: point.amount == 0
                              ? '${_monthLabels[point.month.month - 1]}, belum ada pengeluaran'
                              : '${_monthLabels[point.month.month - 1]}, ${formatRupiahInput(point.amount.toString())} dari ${point.transactionCount} transaksi pengeluaran',
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                SizedBox(
                                  height: 22,
                                  child: point.amount == 0
                                      ? null
                                      : FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            formatCompactRupiah(point.amount),
                                            maxLines: 1,
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(
                                                  color: scheme.onSurface,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                          ),
                                        ),
                                ),
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.bottomCenter,
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 220,
                                      ),
                                      height: barHeight,
                                      decoration: BoxDecoration(
                                        color:
                                            point.amount == maxAmount &&
                                                hasExpense
                                            ? scheme.primary
                                            : scheme.primaryContainer,
                                        borderRadius:
                                            const BorderRadius.vertical(
                                              top: Radius.circular(8),
                                            ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _monthLabels[point.month.month - 1],
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    })
                    .toList(growable: false),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Setiap batang berasal dari transaksi pengeluaran yang tersimpan. Transfer antar rekening tidak ikut dihitung.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class _SetupGuideCard extends StatelessWidget {
  const _SetupGuideCard({required this.missingItems, required this.onSetup});

  final List<String> missingItems;
  final VoidCallback onSetup;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      color: scheme.primaryContainer.withValues(alpha: .45),
      border: BorderSide(color: scheme.primary, width: 1.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.star, color: scheme.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'LANGKAH AWAL',
                style: AppTextStyles.labelCaps.copyWith(color: scheme.primary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Lengkapi Data Utama dulu, ya',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Sebelum catat transaksi, isi dulu: ${missingItems.join(', ')}. Toko, Tag, dan Dipakai oleh bisa kamu tambah belakangan sesuai kebutuhan.',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onSetup,
            icon: const Icon(Icons.settings_outlined),
            label: const Text('Buka Data Utama'),
          ),
        ],
      ),
    );
  }
}

class _EmptySummaryCard extends StatelessWidget {
  const _EmptySummaryCard({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.waving_hand_outlined, color: scheme.primary),
          const SizedBox(height: 12),
          Text(
            'Belum ada angka yang perlu dihitung',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Mulai dari satu transaksi dulu. Setelah itu pemasukan, pengeluaran, dan saran akan ikut berubah otomatis.',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onStart,
            icon: const Icon(Icons.add),
            label: const Text('Catat transaksi pertama'),
          ),
        ],
      ),
    );
  }
}

class _DashboardBalanceCard extends StatelessWidget {
  const _DashboardBalanceCard({required this.data});

  final _SummaryData data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _DashboardMetric(
                  label: 'Total aset',
                  amount: data.totalAssets,
                  color: AppColors.positive,
                  icon: Icons.account_balance_wallet_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DashboardMetric(
                  label: 'Total hutang',
                  amount: data.totalLiabilities,
                  color: AppColors.negative,
                  icon: Icons.credit_card_outlined,
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          Row(
            children: [
              Icon(Icons.balance_outlined, color: scheme.primary),
              const SizedBox(width: 10),
              const Expanded(child: Text('Kekayaan bersih')),
              AppMoneyText(
                data.netWorth,
                compact: true,
                color: data.netWorth >= 0
                    ? AppColors.positive
                    : AppColors.negative,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DashboardMetric extends StatelessWidget {
  const _DashboardMetric({
    required this.label,
    required this.amount,
    required this.color,
    required this.icon,
  });

  final String label;
  final int amount;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 8),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 3),
        AppMoneyText(amount, compact: true, color: color),
      ],
    );
  }
}

class _DashboardInsightCard extends StatelessWidget {
  const _DashboardInsightCard({required this.data});

  final _SummaryData data;

  String _dateLabel(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';

  String _weekLabel(WeeklyDigest digest) {
    final end = digest.endExclusive.subtract(const Duration(days: 1));
    if (digest.start.month == end.month) {
      return '${digest.start.day}–${end.day}/${end.month.toString().padLeft(2, '0')}';
    }
    return '${_dateLabel(digest.start)}–${_dateLabel(end)}';
  }

  @override
  Widget build(BuildContext context) {
    final nextForecast = data.forecast.isEmpty ? null : data.forecast.first;
    final digest = data.weeklyDigest;
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      color: scheme.primaryContainer.withValues(alpha: .42),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.date_range_outlined, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  digest.transactionCount == 0
                      ? 'Belum ada transaksi tersimpan pada minggu ini.'
                      : 'Minggu ini (${_weekLabel(digest)}): ${formatRupiahInput(digest.expense.toString())} pengeluaran dari ${digest.transactionCount} transaksi tersimpan.',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.insights_outlined, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  nextForecast == null
                      ? 'Belum cukup data buat perkiraan. Catat transaksi nyata di minimal 3 bulan dulu, ya.'
                      : 'Perkiraan arus kas bersih bulan depan ${formatRupiahInput(nextForecast.balance.toString())}.',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Semua angka di sini adalah gabungan Keuangan Keluarga. Penanda Dipakai oleh hanya membantu melihat rincian transaksi, bukan saldo terpisah.',
          ),
          if (nextForecast != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Perkiraan periode ${_dateLabel(nextForecast.month)}.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: AppColors.inkMuted),
              ),
            ),
        ],
      ),
    );
  }
}

class _HealthScoreCard extends StatelessWidget {
  const _HealthScoreCard({required this.score});

  final FinancialHealthScore score;

  String get _statusLabel {
    switch (score.status) {
      case FinancialHealthStatus.excellent:
        return 'Mantap';
      case FinancialHealthStatus.good:
        return 'Sehat';
      case FinancialHealthStatus.fair:
        return 'Lumayan';
      case FinancialHealthStatus.warning:
        return 'Perlu dijaga';
      case FinancialHealthStatus.critical:
        return 'Perlu dibenahi';
    }
  }

  Color get _statusColor {
    if (score.totalScore >= 70) return AppColors.positive;
    if (score.totalScore >= 50) return AppColors.warning;
    return AppColors.negative;
  }

  @override
  Widget build(BuildContext context) {
    final value = score.totalScore / 100;
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  AppCopy.skorKesehatan,
                  style: AppTextStyles.labelCaps,
                ),
              ),
              AppStatusChip(
                label: _statusLabel,
                color: _statusColor,
                backgroundColor: _statusColor.withValues(alpha: .12),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${score.totalScore}',
                style: AppTextStyles.moneyLarge.copyWith(fontSize: 40),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  'dari 100',
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 10,
              backgroundColor: scheme.surfaceContainerHighest,
              color: _statusColor,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            score.cashflow >= 0
                ? 'Arus kas bulan ini masih positif. Pertahankan ritmenya.'
                : 'Bulan ini agak seret. Yuk cek lagi pengeluaran yang bisa dirapikan.',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({required this.suggestion, required this.onTap});

  final AdvisorSuggestion suggestion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      color: scheme.tertiaryContainer.withValues(alpha: .65),
      padding: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.lightbulb_outline, color: scheme.primary),
        ),
        title: Text(suggestion.title),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(suggestion.message),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _MoneySummaryCard extends StatelessWidget {
  const _MoneySummaryCard({
    required this.label,
    required this.amount,
    required this.icon,
    required this.color,
  });

  final String label;
  final int amount;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isIncome = label == AppCopy.pemasukan;
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      padding: EdgeInsets.zero,
      color: (isIncome ? scheme.tertiaryContainer : scheme.errorContainer)
          .withValues(alpha: .65),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const Spacer(),
                Text(
                  isIncome ? 'Uang masuk' : 'Uang keluar',
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: color, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(label, style: AppTextStyles.labelCaps),
            const SizedBox(height: 5),
            AppMoneyText(amount, compact: true, color: color),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  isIncome
                      ? Icons.trending_up_rounded
                      : Icons.trending_down_rounded,
                  size: 16,
                  color: color,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    isIncome
                        ? 'Yang diterima bulan ini'
                        : 'Yang dipakai bulan ini',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionsCard extends StatelessWidget {
  const _QuickActionsCard({
    required this.onMasterData,
    required this.onTransaction,
    required this.onAsset,
    required this.onGoal,
    required this.masterDataReady,
    required this.hasAnyTransaction,
  });

  final VoidCallback onMasterData;
  final VoidCallback onTransaction;
  final VoidCallback onAsset;
  final VoidCallback onGoal;
  final bool masterDataReady;
  final bool hasAnyTransaction;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        children: [
          if (!masterDataReady)
            _QuickActionRow(
              icon: Icons.settings_outlined,
              label: 'Atur Data Utama',
              message: 'Kelola Kategori, Rekening, Toko, dan Penanda.',
              onTap: onMasterData,
            ),
          if (masterDataReady) ...[
            _QuickActionRow(
              icon: Icons.add_circle_outline,
              label: hasAnyTransaction
                  ? AppCopy.tambahTransaksi
                  : 'Catat transaksi pertama',
              message: hasAnyTransaction
                  ? 'Catat pemasukan atau pengeluaran.'
                  : 'Mulai dari satu pemasukan atau pengeluaran.',
              onTap: onTransaction,
            ),
            const Divider(height: 24),
            _QuickActionRow(
              icon: Icons.account_balance_wallet_outlined,
              label: AppCopy.tambahAset,
              message: 'Masukkan aset yang kamu punya.',
              onTap: onAsset,
            ),
            const Divider(height: 24),
            _QuickActionRow(
              icon: Icons.flag_outlined,
              label: AppCopy.tambahGoal,
              message: 'Bikin target yang mau kamu kejar.',
              onTap: onGoal,
            ),
          ],
        ],
      ),
    );
  }
}

class _QuickActionRow extends StatelessWidget {
  const _QuickActionRow({
    required this.icon,
    required this.label,
    required this.message,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String message;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: scheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      message,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
