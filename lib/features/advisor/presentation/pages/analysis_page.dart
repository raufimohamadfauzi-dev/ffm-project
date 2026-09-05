import 'package:flutter/material.dart';

import '../../../../core/database/app_context.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../../asset/data/repositories/market_news_cache_repository.dart';
import '../../../asset/domain/entities/market_news_models.dart';
import '../../../asset/domain/usecases/asset_crud_usecases.dart';
import '../../../assistant/domain/ffm_assistant_models.dart';
import '../../../assistant/data/nfc_card_repository.dart' as nfc_repository;
import '../../../assistant/data/payment_draft_repository.dart';
import '../../../assistant/presentation/widgets/ffm_assistant_page_context.dart';
import '../../../liability/domain/usecases/liability_crud_usecases.dart';
import '../../../transaction/domain/entities/transaction_entity.dart';
import '../../../transaction/domain/usecases/transaction_crud_usecases.dart';
import '../../data/cash_flow_profile_repository.dart';
import '../../domain/entities/cash_flow_profile_models.dart';
import '../../domain/usecases/financial_analysis_intelligence_engine.dart';
import '../../domain/usecases/financial_health_calculator.dart';
import '../../domain/usecases/flexible_cash_flow_calculator.dart';
import 'flexible_cash_flow_page.dart';

class _AnalysisBundle {
  const _AnalysisBundle({
    required this.transactions,
    required this.currentMonthTransactions,
    required this.healthScore,
    required this.activeCycle,
    required this.cycleRunway,
    required this.totalIncome,
    required this.totalExpense,
    required this.projection,
    required this.leaks,
    required this.topCategories,
    required this.marketPrices,
    required this.cycleStressTest,
    required this.nfcAccounts,
    required this.pendingNfcDraftCount,
  });

  final List<TransactionWithItems> transactions;
  final List<TransactionWithItems> currentMonthTransactions;
  final FinancialHealthScore healthScore;
  final CashFlowProfile? activeCycle;
  final CashFlowRunwayResult? cycleRunway;
  final int totalIncome;
  final int totalExpense;
  final BurnRateProjectionResult projection;
  final List<MicroExpenseLeakItem> leaks;
  final List<CategoryExpenseShare> topCategories;
  final MarketPriceSnapshot? marketPrices;
  final CycleStressTestResult? cycleStressTest;
  final List<nfc_repository.NfcCardAccount> nfcAccounts;
  final int pendingNfcDraftCount;
}

class AnalysisPage extends StatefulWidget {
  const AnalysisPage({super.key});

  @override
  State<AnalysisPage> createState() => _AnalysisPageState();
}

class _AnalysisPageState extends State<AnalysisPage> {
  late Future<_AnalysisBundle> _future;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    _future = _fetchBundle();
  }

  Future<_AnalysisBundle> _fetchBundle() async {
    final householdId = AppContext.householdId;
    final transactions = await getIt<GetTransactions>()(householdId);
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month);
    final nextMonthStart = DateTime(now.year, now.month + 1);
    final currentMonthTransactions = transactions.where((item) {
      final date = item.transaction.date;
      return !date.isBefore(monthStart) && date.isBefore(nextMonthStart);
    }).toList();
    final assets = await getIt<GetAssets>()(householdId);
    final liabilities = await getIt<GetLiabilities>()(householdId);
    final profiles = await getIt<CashFlowProfileRepository>().getAllProfiles(householdId);
    final nfcAccounts = await getIt<nfc_repository.NfcCardRepository>()
      .getCardAccounts();
    final pendingDrafts = await getIt<PaymentDraftRepository>().getPendingDrafts();

    // Ambil nama kategori dari database lokal
    final db = getIt<AppDatabase>();
    final categories = await db.select(db.categories).get();
    final categoryNames = {for (final c in categories) c.id: c.name};

    final income = currentMonthTransactions
        .where((item) => item.transaction.amount > 0)
        .fold<int>(0, (sum, item) => sum + item.transaction.amount);
    final expenses = currentMonthTransactions
        .where((item) => item.transaction.amount < 0)
        .fold<int>(0, (sum, item) => sum + item.transaction.amount.abs());
    final installments = liabilities.fold<int>(
      0,
      (sum, liability) => sum + liability.monthlyInstallment,
    );
    final emergencyFund = assets
        .where((asset) => asset.assetType == 'cash')
        .fold<int>(0, (sum, asset) => sum + asset.value);
    final totalAssetsVal = assets.fold<int>(0, (sum, asset) => sum + asset.value);
    final totalLiabilitiesVal = liabilities.fold<int>(
      0,
      (sum, liability) => sum + liability.remainingBalance,
    );

    final score = const FinancialHealthCalculator().calculate(
      FinancialHealthInput(
        totalIncome: income,
        totalExpenses: expenses,
        totalMonthlyInstallments: installments,
        emergencyFundAmount: emergencyFund,
        averageMonthlyExpenses: expenses,
        totalAssets: totalAssetsVal,
        totalLiabilities: totalLiabilitiesVal,
      ),
    );

    final activeCycle = profiles.where((p) => p.isActive).firstOrNull ?? profiles.firstOrNull;
    CashFlowRunwayResult? runway;
    if (activeCycle != null) {
      final daysRemaining = activeCycle.targetHarvestDate.difference(DateTime.now()).inDays;
      runway = const FlexibleCashFlowCalculator().calculateRunway(
        effectiveLiquidCash: activeCycle.initialCapital > 0
            ? activeCycle.initialCapital
            : emergencyFund,
        dailyLivingBudget: activeCycle.dailyLivingBudget,
        dailyOperationalBudget: activeCycle.dailyOperationalBudget,
        daysRemainingToHarvest: daysRemaining > 0 ? daysRemaining : 0,
      );
    }

    // ── FITUR INTELIJEN FINANSIAL DETERMINISTIK ──────────────────────────────
    const engine = FinancialAnalysisIntelligenceEngine();

    // 1. Burn Rate & Proyeksi Akhir Bulan
    final projection = engine.calculateBurnRateAndProjection(
      transactions: transactions,
      referenceDate: now,
    );

    // 2. Deteksi Kebocoran Mikro (< 50rb dan >= 3x)
    final leaks = engine.detectMicroExpenseLeaks(
      transactions: transactions,
      referenceDate: now,
      categoryNamesById: categoryNames,
      microThreshold: 50000,
      minFrequency: 3,
    );

    // 3. Top Kategori Pengeluaran (Pareto 80/20)
    final topCategories = engine.calculateTopExpenseCategories(
      transactions: transactions,
      referenceDate: now,
      categoryNamesById: categoryNames,
      maxCategories: 4,
    );

    // 4. Harga Pasar Terkini (Emas & Valas) dari Cache Lokal
    MarketPriceSnapshot? marketPrices;
    try {
      marketPrices = await getIt<MarketNewsCacheRepository>().getLatestPriceSnapshot();
    } catch (_) {
      // Graceful degradation
    }

    // 5. Stress-Test Siklus AgroTrack (jika panen mundur 14 hari)
    CycleStressTestResult? stressTest;
    if (activeCycle != null) {
      final liquidCash = activeCycle.initialCapital > 0
          ? activeCycle.initialCapital
          : emergencyFund;
      stressTest = engine.simulateCycleStressTest(
        profile: activeCycle,
        currentLiquidCash: liquidCash,
        delayedDays: 14,
      );
    }

    return _AnalysisBundle(
      transactions: transactions,
      currentMonthTransactions: currentMonthTransactions,
      healthScore: score,
      activeCycle: activeCycle,
      cycleRunway: runway,
      totalIncome: income,
      totalExpense: expenses,
      projection: projection,
      leaks: leaks,
      topCategories: topCategories,
      marketPrices: marketPrices,
      cycleStressTest: stressTest,
      nfcAccounts: nfcAccounts,
      pendingNfcDraftCount: pendingDrafts
          .where((draft) => draft.sourceApp.startsWith('nfc_'))
          .length,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AnalysisBundle>(
      future: _future,
      builder: (context, snapshot) {
        final bundle = snapshot.data;
        final items = bundle?.currentMonthTransactions ?? [];
        final incomeCount = items
            .where((item) => item.transaction.amount > 0)
            .length;
        final expenseCount = items
            .where((item) => item.transaction.amount < 0)
            .length;

        final summary = snapshot.hasData
            ? 'Analisa Keuangan FFM: Skor ${bundle!.healthScore.totalScore}/100 (${bundle.healthScore.statusLabel}), $incomeCount masuk, $expenseCount keluar, Arus Kas Rp ${bundle.healthScore.cashflow}. '
              'Proyeksi Akhir Bulan: ${bundle.projection.isSurplus ? "Surplus" : "Defisit"} Rp ${bundle.projection.projectedNetCashflow} (Laju Belanja Rp ${bundle.projection.dailyBurnRate}/hari, Batas Aman Rp ${bundle.projection.safeDailySpend}/hari). '
              '${bundle.leaks.isNotEmpty ? "Terdeteksi ${bundle.leaks.length} pos bocor mikro (total Rp ${bundle.leaks.fold<int>(0, (s, l) => s + l.totalAmount)}). " : ""}'
              '${bundle.topCategories.isNotEmpty ? "Pos Terbesar: ${bundle.topCategories.map((c) => "${c.categoryName} ${(c.percentage * 100).toStringAsFixed(0)}%").join(", ")}. " : ""}'
              '${bundle.activeCycle != null ? "Siklus ${bundle.activeCycle!.commodityOrBusinessType} Runway ${bundle.cycleRunway?.runwayDays ?? 0} hari. " : ""}'
              '${bundle.nfcAccounts.isNotEmpty ? "${bundle.nfcAccounts.length} kartu NFC terhubung dengan saldo tercatat Rp ${bundle.nfcAccounts.fold<double>(0, (sum, card) => sum + card.lastKnownBalance).round()}. " : ""}'
            : 'Sedang menganalisa kondisi keuangan...';

        return FfmAssistantPageContext(
          destination: FfmAssistantDestination.analysis,
          dataSummary: summary,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Analisa'),
              actions: [
                IconButton(
                  tooltip: 'Segarkan data',
                  onPressed: () => setState(_loadData),
                  icon: const Icon(Icons.refresh_rounded),
                ),
                IconButton(
                  tooltip: 'Info Analisa',
                  onPressed: () => showAppInfoDialog(
                    context,
                    title: 'Pusat Analisa & Kesehatan Finansial',
                    message:
                        'Halaman ini menyajikan diagnosis kesehatan keuangan keluarga 4 pilar, proyeksi kas akhir bulan, deteksi kebocoran mikro, dan ketahanan siklus kas secara deterministik.',
                  ),
                  icon: const Icon(Icons.info_outline),
                ),
              ],
            ),
            body: snapshot.connectionState == ConnectionState.waiting
                ? const Center(child: CircularProgressIndicator())
                : bundle == null
                ? const Center(child: Text('Gagal memuat analisa.'))
                : _buildBody(context, bundle),
          ),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, _AnalysisBundle bundle) {
    final items = bundle.transactions;
    final currentMonthItems = bundle.currentMonthTransactions;
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
        // ── 1. RINGKASAN PEMASUKAN & PENGELUARAN BULANAN ───────────────────
        Row(
          children: [
            Expanded(
              child: _Metric(
                title: 'Total Pemasukan',
                value: bundle.totalIncome,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Metric(
                title: 'Total Pengeluaran',
                value: bundle.totalExpense,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ── 2. HERO CARD: SKOR KESEHATAN FINANSIAL (4 PILAR) ─────────────
        _FinancialHealthHeroCard(score: bundle.healthScore),
        const SizedBox(height: 16),

        // ── 3. [BARU] KARTU PROYEKSI KAS AKHIR BULAN & LAJU BELANJA ─────
        _MonthlyProjectionCard(projection: bundle.projection),
        const SizedBox(height: 16),

        // ── 4. [BARU] DISTRIBUSI POS PENGELUARAN TERBESAR (PARETO) ───────
        if (bundle.topCategories.isNotEmpty) ...[
          _TopExpenseCategoriesCard(categories: bundle.topCategories),
          const SizedBox(height: 16),
        ],

        // ── 5. [BARU] RADAR KEBOCORAN PENGELUARAN MIKRO ──────────────────
        _MicroExpenseLeakCard(leaks: bundle.leaks),
        const SizedBox(height: 16),

        if (bundle.nfcAccounts.isNotEmpty || bundle.pendingNfcDraftCount > 0) ...[
          _NfcAnalysisCard(
            accounts: bundle.nfcAccounts,
            pendingDraftCount: bundle.pendingNfcDraftCount,
          ),
          const SizedBox(height: 16),
        ],

        // ── 6. CARD: SIKLUS KAS & AGROTRACK DENGAN BENCHMARK PASAR ───────
        _AgroTrackCycleCard(
          profile: bundle.activeCycle,
          runway: bundle.cycleRunway,
          stressTest: bundle.cycleStressTest,
          marketPrices: bundle.marketPrices,
          onManage: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const FlexibleCashFlowPage()),
          ).then((_) => setState(_loadData)),
        ),
        const SizedBox(height: 16),

        // ── 7. CARD: KONSULTASI CERDAS ASISTEN AI ────────────────────────
        _AiConsultantCard(
          score: bundle.healthScore,
          projection: bundle.projection,
          hasLeaks: bundle.leaks.isNotEmpty,
        ),
        const SizedBox(height: 16),

        // ── 8. CHART ARUS KAS 6 BULAN TERAKHIR ───────────────────────────
        _MonthlyAnalysisChart(points: monthly),
        const SizedBox(height: 12),

        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Volume Transaksi',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                '${items.length} transaksi tersimpan di perangkat ini. Semua evaluasi dihitung secara deterministik dan terlindungi di perangkat.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (currentMonthItems.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 24),
            child: AppEmptyState(
              icon: Icons.insights_outlined,
              title: 'Belum ada transaksi bulan ini',
              message: 'Catat transaksi pemasukan atau pengeluaran bulan ini agar skor dan analisis periode berjalan lebih akurat.',
            ),
          ),
      ],
    );
  }
}

// ── WIDGET: HERO CARD SKOR KESEHATAN FINANSIAL ───────────────────────────────
class _FinancialHealthHeroCard extends StatelessWidget {
  const _FinancialHealthHeroCard({required this.score});

  final FinancialHealthScore score;

  Color _statusColor(FinancialHealthStatus status) => switch (status) {
    FinancialHealthStatus.excellent => const Color(0xFF059669),
    FinancialHealthStatus.good => const Color(0xFF0D9488),
    FinancialHealthStatus.fair => const Color(0xFF2563EB),
    FinancialHealthStatus.warning => const Color(0xFFD97706),
    FinancialHealthStatus.critical => const Color(0xFFDC2626),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color = _statusColor(score.status);
    final progress = (score.totalScore / 100).clamp(0.0, 1.0);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.health_and_safety_outlined, color: color, size: 22),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'KESEHATAN FINANSIAL',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: Text(
                  score.statusLabel,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${score.totalScore}',
                style: TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                  color: color,
                  height: 1.0,
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '/100',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              if (score.headline.isNotEmpty)
                Expanded(
                  flex: 3,
                  child: Text(
                    score.headline,
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isDark ? const Color(0xFFD4C7B8) : const Color(0xFF5A4A3B),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 12),
          const Text(
            'Diagnosis 4 Pilar Utama:',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 8),

          // 4 Pilar visual breakdown
          _PillarRow(
            icon: Icons.savings_outlined,
            title: 'Arus Kas & Rasio Tabungan',
            value: '${(score.savingsRate * 100).toStringAsFixed(0)}%',
            target: 'Ideal: ≥20%',
            isHealthy: score.savingsRate >= 0.2,
          ),
          const SizedBox(height: 6),
          _PillarRow(
            icon: Icons.credit_card_outlined,
            title: 'Beban Cicilan Hutang (DSR)',
            value: '${(score.debtToIncomeRatio * 100).toStringAsFixed(0)}%',
            target: 'Batas aman: ≤30%',
            isHealthy: score.debtToIncomeRatio <= 0.3,
          ),
          const SizedBox(height: 6),
          _PillarRow(
            icon: Icons.shield_outlined,
            title: 'Ketahanan Dana Darurat',
            value: '${score.emergencyMonths.toStringAsFixed(1)} bln',
            target: 'Target: 3-6 bulan',
            isHealthy: score.emergencyMonths >= 3.0,
          ),
          const SizedBox(height: 6),
          _PillarRow(
            icon: Icons.account_balance_outlined,
            title: 'Kekayaan Bersih (Net Worth)',
            value: _formatCompactRupiah(score.netWorth),
            target: 'Total aset - hutang',
            isHealthy: score.netWorth >= 0,
          ),
        ],
      ),
    );
  }
}

class _PillarRow extends StatelessWidget {
  const _PillarRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.target,
    required this.isHealthy,
  });

  final IconData icon;
  final String title;
  final String value;
  final String target;
  final bool isHealthy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = isHealthy ? const Color(0xFF059669) : const Color(0xFFD97706);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                ),
                Text(
                  target,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── WIDGET: KARTU PROYEKSI KAS AKHIR BULAN & BURN RATE ────────────────────────
class _MonthlyProjectionCard extends StatelessWidget {
  const _MonthlyProjectionCard({required this.projection});

  final BurnRateProjectionResult projection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isSurplus = projection.isSurplus;
    final statusColor = isSurplus ? const Color(0xFF059669) : const Color(0xFFDC2626);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.timeline_rounded, color: statusColor, size: 22),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'PROYEKSI KAS AKHIR BULAN',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  isSurplus ? 'SURPLUS AMAN' : 'POTENSI DEFISIT',
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            isSurplus
                ? 'Dengan pola belanja saat ini, kas bulan ini diproyeksikan surplus.'
                : 'Peringatan: Kecepatan belanja melampaui kas. Batasi pengeluaran harian.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),

          // 3 Kolom Metrik Proyeksi
          Row(
            children: [
              Expanded(
                child: _CycleMetricBox(
                  label: 'Laju Belanja',
                  value: _formatCompactRupiah(projection.dailyBurnRate),
                  caption: 'Rata-rata/Hari',
                  color: isDark ? const Color(0xFFD4C7B8) : const Color(0xFF5A4A3B),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CycleMetricBox(
                  label: 'Batas Aman',
                  value: _formatCompactRupiah(projection.safeDailySpend),
                  caption: 'Sisa ${projection.daysLeftInMonth} Hari',
                  color: const Color(0xFF059669),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CycleMetricBox(
                  label: 'Estimasi Akhir',
                  value: _formatCompactRupiah(projection.projectedNetCashflow),
                  caption: isSurplus ? 'Sisa Kas' : 'Defisit Kas',
                  color: statusColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── WIDGET: DISTRIBUSI POS PENGELUARAN TERBESAR (PARETO 80/20) ────────────────
class _TopExpenseCategoriesCard extends StatelessWidget {
  const _TopExpenseCategoriesCard({required this.categories});

  final List<CategoryExpenseShare> categories;

  static const _palette = [
    Color(0xFFE11D48), // Rose
    Color(0xFFD97706), // Amber
    Color(0xFF2563EB), // Blue
    Color(0xFF0D9488), // Teal
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.pie_chart_outline_rounded, size: 22, color: Color(0xFF2563EB)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'POS PENGELUARAN TERBESAR (PARETO)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Kategori dengan serapan dana terbesar bulan ini. Evaluasi pos ini untuk efisiensi maksimal.',
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),

          // Multi-color segmented progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 10,
              child: Row(
                children: categories.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final item = entry.value;
                  final color = _palette[idx % _palette.length];
                  return Expanded(
                    flex: (item.percentage * 100).round().clamp(1, 100),
                    child: Container(color: color),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // List kategori
          ...categories.asMap().entries.map((entry) {
            final idx = entry.key;
            final item = entry.value;
            final color = _palette[idx % _palette.length];
            final pctText = '${(item.percentage * 100).toStringAsFixed(0)}%';

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.categoryName,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                  Text(
                    _formatCompactRupiah(item.totalAmount),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      pctText,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ── WIDGET: RADAR KEBOCORAN PENGELUARAN MIKRO ─────────────────────────────────
class _MicroExpenseLeakCard extends StatelessWidget {
  const _MicroExpenseLeakCard({required this.leaks});

  final List<MicroExpenseLeakItem> leaks;

  void _askAi(BuildContext context) {
    final open = FfmAssistantContextScope.openAssistantOf(context);
    if (open != null) {
      open(
        initialPrompt:
            'Tolong analisa kebocoran pengeluaran mikro saya dan beri saya 3 strategi hemat agar tidak boncos di pos-pos kecil.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (leaks.isEmpty) {
      return AppCard(
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF059669), size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Radar Kebocoran Mikro Bersih',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  Text(
                    'Tidak ditemukan transaksi kecil berulang (<Rp50rb) yang berpotensi bocor bulan ini.',
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final totalLeak = leaks.fold<int>(0, (sum, it) => sum + it.totalAmount);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.water_drop_outlined, color: Color(0xFFD97706), size: 22),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'RADAR KEBOCORAN KAS (LEAK DETECTOR)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFD97706).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFD97706).withValues(alpha: 0.3)),
                ),
                child: Text(
                  'TOTAL ${_formatCompactRupiah(totalLeak)}',
                  style: const TextStyle(
                    color: Color(0xFFD97706),
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Transaksi nominal kecil (<Rp50.000) yang sering berulang dapat menggerogoti potensi tabungan tanpa disadari.',
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),

          // Daftar item bocor
          ...leaks.map((leak) {
            return Container(
              margin: const EdgeInsets.symmetric(vertical: 3),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          leak.title,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                        Text(
                          '${leak.frequency}x transaksi • Kategori: ${leak.categoryName}',
                          style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _formatCompactRupiah(leak.totalAmount),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: Color(0xFFD97706),
                    ),
                  ),
                ],
              ),
            );
          }),

          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _askAi(context),
              icon: const Icon(Icons.auto_awesome_rounded, size: 15),
              label: const Text('Minta Strategi Solusi dari AI'),
            ),
          ),
        ],
      ),
    );
  }
}

class _NfcAnalysisCard extends StatelessWidget {
  const _NfcAnalysisCard({
    required this.accounts,
    required this.pendingDraftCount,
  });

  final List<nfc_repository.NfcCardAccount> accounts;
  final int pendingDraftCount;

  @override
  Widget build(BuildContext context) {
    final totalBalance = accounts.fold<double>(
      0,
      (sum, account) => sum + account.lastKnownBalance,
    );
    final theme = Theme.of(context);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.nfc_rounded, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'KARTU NFC',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                '${accounts.length} kartu',
                style: theme.textTheme.labelMedium,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text('Total saldo terakhir yang terbaca'),
          const SizedBox(height: 4),
          AppMoneyText(totalBalance.round(), compact: true),
          if (pendingDraftCount > 0) ...[
            const SizedBox(height: 8),
            Text(
              '$pendingDraftCount draft NFC menunggu konfirmasi. Draft belum dihitung sebagai transaksi sampai disetujui.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── WIDGET: CARD SIKLUS KAS & AGROTRACK ───────────────────────────────────────
class _AgroTrackCycleCard extends StatelessWidget {
  const _AgroTrackCycleCard({
    required this.profile,
    required this.runway,
    required this.stressTest,
    required this.marketPrices,
    required this.onManage,
  });

  final CashFlowProfile? profile;
  final CashFlowRunwayResult? runway;
  final CycleStressTestResult? stressTest;
  final MarketPriceSnapshot? marketPrices;
  final VoidCallback onManage;

  Color _healthColor(CycleHealthStatus status) => switch (status) {
    CycleHealthStatus.safe => const Color(0xFF059669),
    CycleHealthStatus.warning => const Color(0xFFD97706),
    CycleHealthStatus.critical => const Color(0xFFDC2626),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (profile == null) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.agriculture_rounded, color: Color(0xFF2E7D32), size: 22),
                const SizedBox(width: 8),
                const Text(
                  'SIKLUS KAS & AGROTRACK',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Punya usaha musiman, tani, panen, atau proyek lepas? Amankan batas belanja harian keluarga agar modal kerja tidak terpakai.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onManage,
              icon: const Icon(Icons.add_chart_rounded, size: 16),
              label: const Text('Buat / Kelola Siklus Kas'),
            ),
          ],
        ),
      );
    }

    final p = profile!;
    final r = runway;
    final statusColor = r != null ? _healthColor(r.healthStatus) : const Color(0xFF2E7D32);
    final daysRemaining = p.targetHarvestDate.difference(DateTime.now()).inDays;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.agriculture_rounded, color: Color(0xFF2E7D32), size: 22),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'SIKLUS KAS (AGROTRACK) AKTIF',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              if (r != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    r.healthStatus.name.toUpperCase(),
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            p.name,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          Text(
            'Komoditas/Bidang: ${p.commodityOrBusinessType}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),

          // Key metrics row
          Row(
            children: [
              Expanded(
                child: _CycleMetricBox(
                  label: 'Sisa Waktu',
                  value: '${daysRemaining > 0 ? daysRemaining : 0} Hari',
                  caption: 'Menuju Panen',
                  color: isDark ? const Color(0xFFC9B8A8) : const Color(0xFF5A4A3B),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CycleMetricBox(
                  label: 'Ketahanan Kas',
                  value: '${r?.runwayDays ?? 0} Hari',
                  caption: 'Runway Kas',
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CycleMetricBox(
                  label: 'Belanja Dapur',
                  value: _formatCompactRupiah(r?.safeToSpendDaily ?? p.dailyLivingBudget),
                  caption: 'Batas Aman/Hari',
                  color: const Color(0xFF059669),
                ),
              ),
            ],
          ),

          // ── SIMULASI STRESS TEST PANEN MUNDUR 14 HARI ──
          if (stressTest != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: stressTest!.isStillSafe
                    ? const Color(0xFF059669).withValues(alpha: 0.08)
                    : const Color(0xFFDC2626).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: stressTest!.isStillSafe
                      ? const Color(0xFF059669).withValues(alpha: 0.25)
                      : const Color(0xFFDC2626).withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    stressTest!.isStillSafe
                        ? Icons.shield_outlined
                        : Icons.warning_amber_rounded,
                    size: 18,
                    color: stressTest!.isStillSafe
                        ? const Color(0xFF059669)
                        : const Color(0xFFDC2626),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Stress-Test (+14 hari): ${stressTest!.message}',
                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── BENCHMARK HARGA EMAS/PASAR DARI RADAR TERKINI ──
          if (marketPrices != null && marketPrices!.goldPrice24K > 0) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.radar_rounded, size: 14, color: Color(0xFFD97706)),
                  const SizedBox(width: 6),
                  Text(
                    'Acuan Pasar: Emas 24K Rp ${_formatCompactRupiah(marketPrices!.goldPrice24K)}/gr • Kurs USD Rp ${_formatCompactRupiah(marketPrices!.usdRate.round())}',
                    style: theme.textTheme.labelSmall?.copyWith(fontSize: 10),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onManage,
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('Buka Halaman Siklus Kas'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CycleMetricBox extends StatelessWidget {
  const _CycleMetricBox({
    required this.label,
    required this.value,
    required this.caption,
    required this.color,
  });

  final String label;
  final String value;
  final String caption;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          Text(
            caption,
            style: TextStyle(
              fontSize: 9,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}

// ── WIDGET: CARD KONSULTASI ASISTEN AI ────────────────────────────────────────
class _AiConsultantCard extends StatelessWidget {
  const _AiConsultantCard({
    required this.score,
    required this.projection,
    required this.hasLeaks,
  });

  final FinancialHealthScore score;
  final BurnRateProjectionResult projection;
  final bool hasLeaks;

  void _ask(BuildContext context, String prompt) {
    final open = FfmAssistantContextScope.openAssistantOf(context);
    if (open != null) {
      open(initialPrompt: prompt);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Buka Asisten AI dari tombol mengambang di pojok kanan bawah.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF2A241E), const Color(0xFF1E1A16)]
              : [const Color(0xFFFFF8E7), const Color(0xFFFBF4E2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF4D3F33) : const Color(0xFFE5D5BA),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_rounded, color: Color(0xFFD97706), size: 20),
              const SizedBox(width: 8),
              const Text(
                'KONSULTASI ANALISIS AI',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: Color(0xFFB45309),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Ingin tahu strategi perbaikan bulan depan, proyeksi akhir bulan, atau deteksi kebocoran kas? Tanyakan langsung ke Asisten AI.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: isDark ? const Color(0xFFD5C7B7) : const Color(0xFF6B5843),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              ActionChip(
                avatar: const Icon(Icons.insights_rounded, size: 14),
                label: const Text('Evaluasi kesehatan saya', style: TextStyle(fontSize: 11)),
                onPressed: () => _ask(
                  context,
                  'Bagaimana evaluasi kesehatan keuangan dan ketahanan kas saya saat ini? Berikan 3 langkah perbaikan.',
                ),
              ),
              ActionChip(
                avatar: const Icon(Icons.timeline_rounded, size: 14),
                label: const Text('Proyeksi akhir bulan', style: TextStyle(fontSize: 11)),
                onPressed: () => _ask(
                  context,
                  'Berdasarkan laju belanja harian saya saat ini, bagaimana proyeksi saldo akhir bulan dan berapa batas belanja harian yang aman?',
                ),
              ),
              ActionChip(
                avatar: const Icon(Icons.search_rounded, size: 14),
                label: const Text('Cek pos paling boros', style: TextStyle(fontSize: 11)),
                onPressed: () => _ask(
                  context,
                  'Kategori mana yang paling boros dan di mana letak kebocoran pengeluaran saya?',
                ),
              ),
              if (hasLeaks)
                ActionChip(
                  avatar: const Icon(Icons.water_drop_outlined, size: 14),
                  label: const Text('Solusi kebocoran mikro', style: TextStyle(fontSize: 11)),
                  onPressed: () => _ask(
                    context,
                    'Tolong berikan strategi untuk menekan kebocoran pengeluaran mikro yang sering berulang.',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── UTILITY: COMPACT RUPIAH FORMATTER ────────────────────────────────────────
String _formatCompactRupiah(int value) {
  final absVal = value.abs();
  final sign = value < 0 ? '-' : '';
  if (absVal >= 1000000000) {
    return '${sign}Rp${(absVal / 1000000000).toStringAsFixed(1)} M';
  }
  if (absVal >= 1000000) {
    return '${sign}Rp${(absVal / 1000000).toStringAsFixed(1)} jt';
  }
  if (absVal >= 1000) {
    return '${sign}Rp${(absVal / 1000).toStringAsFixed(0)} rb';
  }
  return '${sign}Rp$absVal';
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
                                        _formatCompactRupiah(point.income),
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
