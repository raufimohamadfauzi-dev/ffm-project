import 'package:flutter/material.dart';

import '../../../../core/database/app_context.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../../assistant/domain/ffm_assistant_models.dart';
import '../../../assistant/presentation/widgets/ffm_assistant_page_context.dart';
import '../../domain/services/debt_payoff_strategist_service.dart';

class DebtPayoffStrategyPage extends StatefulWidget {
  const DebtPayoffStrategyPage({
    super.key,
    this.initialExtraPayment,
    this.initialStrategy = DebtPayoffStrategy.snowball,
  });

  final int? initialExtraPayment;
  final DebtPayoffStrategy initialStrategy;

  @override
  State<DebtPayoffStrategyPage> createState() => _DebtPayoffStrategyPageState();
}

class _DebtPayoffStrategyPageState extends State<DebtPayoffStrategyPage> {
  late DebtPayoffStrategy _selectedStrategy;
  late int _extraPayment;
  final _customExtraController = TextEditingController();

  List<AdaptiveLiability> _liabilities = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedStrategy = widget.initialStrategy;
    _extraPayment = widget.initialExtraPayment ?? 250000;
    _customExtraController.text = _extraPayment > 0 ? _extraPayment.toString() : '';
    _loadData();
  }

  @override
  void dispose() {
    _customExtraController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final service = getIt<DebtPayoffStrategistService>();
      final items = await service.getAdaptiveLiabilities(AppContext.householdId);
      final suggested = await service.estimateSuggestedExtraPayment(AppContext.householdId);

      if (!mounted) return;
      setState(() {
        _liabilities = items;
        if (widget.initialExtraPayment == null && suggested > 0) {
          _extraPayment = suggested;
          _customExtraController.text = suggested.toString();
        }
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  String _moneyLabel(int value) {
    final digits = value.abs().toString();
    final groups = <String>[];
    for (var end = digits.length; end > 0; end -= 3) {
      final start = (end - 3).clamp(0, end);
      groups.insert(0, digits.substring(start, end));
    }
    return 'Rp ${groups.join('.')}';
  }

  String _monthName(int month) {
    const months = [
      '',
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
    if (month >= 1 && month <= 12) return months[month];
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final service = getIt<DebtPayoffStrategistService>();

    DebtPayoffComparison? comparison;
    DebtPayoffSimulationResult? activeResult;

    if (_liabilities.isNotEmpty) {
      comparison = service.compareStrategies(
        liabilities: _liabilities,
        extraMonthlyPayment: _extraPayment,
      );
      activeResult = _selectedStrategy == DebtPayoffStrategy.snowball
          ? comparison.snowballResult
          : comparison.avalancheResult;
    }

    return FfmAssistantPageContext(
      destination: FfmAssistantDestination.liabilities,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Simulator Bebas Hutang'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline,
                              size: 48, color: AppColors.negative),
                          const SizedBox(height: 12),
                          Text('Gagal memuat simulasi: $_error'),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _loadData,
                            child: const Text('Coba Lagi'),
                          ),
                        ],
                      ),
                    ),
                  )
                : _liabilities.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CircleAvatar(
                                radius: 40,
                                backgroundColor: AppColors.positiveSoft,
                                child: Icon(Icons.celebration,
                                    size: 40, color: AppColors.positive),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Bebas Hutang! 🎉',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Keluarga Anda tidak memiliki catatan hutang aktif. Pertahankan kondisi ini dan fokus perbesar pos tabungan!',
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(color: AppColors.inkMuted),
                              ),
                            ],
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                          children: [
                            // 1. Selector Strategi
                            SegmentedButton<DebtPayoffStrategy>(
                              segments: const [
                                ButtonSegment(
                                  value: DebtPayoffStrategy.snowball,
                                  icon: Icon(Icons.ac_unit),
                                  label: Text('Debt Snowball'),
                                ),
                                ButtonSegment(
                                  value: DebtPayoffStrategy.avalanche,
                                  icon: Icon(Icons.bolt),
                                  label: Text('Debt Avalanche'),
                                ),
                              ],
                              selected: {_selectedStrategy},
                              onSelectionChanged: (set) {
                                setState(() => _selectedStrategy = set.first);
                              },
                            ),

                            const SizedBox(height: 12),

                            // Penjelasan Strategi Terpilih
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _selectedStrategy ==
                                        DebtPayoffStrategy.snowball
                                    ? AppColors.primarySoft
                                    : AppColors.warningSoft,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    _selectedStrategy ==
                                            DebtPayoffStrategy.snowball
                                        ? Icons.psychology_outlined
                                        : Icons.savings_outlined,
                                    size: 20,
                                    color: _selectedStrategy ==
                                            DebtPayoffStrategy.snowball
                                        ? AppColors.primary
                                        : AppColors.warning,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _selectedStrategy ==
                                              DebtPayoffStrategy.snowball
                                          ? 'Snowball melunasi saldo terkecil lebih dulu. Cocok untuk dorongan motivasi mental dan kemenangan cepat!'
                                          : 'Avalanche melunasi bunga tertinggi lebih dulu. Pilihan paling hemat untuk memangkas total beban bunga!',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: _selectedStrategy ==
                                                    DebtPayoffStrategy.snowball
                                                ? AppColors.primary
                                                : AppColors.ink,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 16),

                            // 2. Kartu Hasil Proyeksi Utama
                            if (activeResult != null && comparison != null)
                              _buildResultCard(context, activeResult, comparison),

                            const SizedBox(height: 16),

                            // 3. Simulasi Alokasi Dana Ekstra
                            _buildExtraPaymentCard(context),

                            const SizedBox(height: 20),

                            // 4. Urutan Prioritas Pelunasan
                            Text(
                              'Urutan Prioritas Pelunasan',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Alokasikan cicilan minimum ke semua hutang, lalu pusatkan dana ekstra ke Prioritas #1 sampai lunas!',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppColors.inkMuted),
                            ),
                            const SizedBox(height: 12),

                            ..._buildPriorityList(context, activeResult),
                          ],
                        ),
                      ),
      ),
    );
  }

  Widget _buildResultCard(
    BuildContext context,
    DebtPayoffSimulationResult result,
    DebtPayoffComparison comparison,
  ) {
    final monthsSaved = _selectedStrategy == DebtPayoffStrategy.snowball
        ? comparison.monthsSavedSnowball
        : comparison.monthsSavedAvalanche;
    final interestSaved = _selectedStrategy == DebtPayoffStrategy.snowball
        ? comparison.interestSavedSnowball
        : comparison.interestSavedAvalanche;

    final debtFreeDate = result.debtFreeDate;
    final dateStr = '${_monthName(debtFreeDate.month)} ${debtFreeDate.year}';

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withAlpha(230),
            const Color(0xFF003838),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withAlpha(60),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flag_outlined, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                'Estimasi 100% Bebas Hutang',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            dateStr,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            '${result.totalMonths} bulan dari sekarang',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 14),
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Total Bunga',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _moneyLabel(result.totalInterestPaid),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
              if (_extraPayment > 0 && monthsSaved > 0)
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.green.withAlpha(50),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.greenAccent.withAlpha(120)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '🎉 Lebih Cepat',
                          style: TextStyle(
                            color: Colors.greenAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                        Text(
                          '$monthsSaved bulan',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        if (interestSaved > 0)
                          Text(
                            'Hemat ${_moneyLabel(interestSaved)}',
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 10,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExtraPaymentCard(BuildContext context) {
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.add_circle_outline,
                    size: 20, color: AppColors.positive),
                const SizedBox(width: 8),
                Text(
                  'Alokasi Ekstra Tiap Bulan',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Gunakan kelebihan uang belanja atau pos tabungan bebas untuk memotong pokok hutang lebih cepat.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.inkMuted),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildExtraChip('Rp 0', 0),
                _buildExtraChip('+100 rb', 100000),
                _buildExtraChip('+250 rb', 250000),
                _buildExtraChip('+500 rb', 500000),
                _buildExtraChip('+1 jt', 1000000),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExtraChip(String label, int value) {
    final isSelected = _extraPayment == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _extraPayment = value;
            _customExtraController.text = value > 0 ? value.toString() : '';
          });
        }
      },
    );
  }

  List<Widget> _buildPriorityList(
    BuildContext context,
    DebtPayoffSimulationResult? result,
  ) {
    if (_liabilities.isEmpty) return const [];

    final sorted = List<AdaptiveLiability>.of(_liabilities);
    if (_selectedStrategy == DebtPayoffStrategy.snowball) {
      sorted.sort((a, b) => a.remainingBalance.compareTo(b.remainingBalance));
    } else {
      sorted.sort((a, b) {
        final r = b.interestRate.compareTo(a.interestRate);
        if (r != 0) return r;
        return a.remainingBalance.compareTo(b.remainingBalance);
      });
    }

    final widgets = <Widget>[];

    for (var i = 0; i < sorted.length; i++) {
      final item = sorted[i];
      final isTopPriority = i == 0;

      // Cari milestone lunas untuk hutang ini jika ada
      DebtPayoffMilestone? milestone;
      if (result != null) {
        final matches = result.milestones.where((m) => m.debtId == item.id);
        if (matches.isNotEmpty) milestone = matches.first;
      }

      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AppCard(
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              leading: CircleAvatar(
                backgroundColor: isTopPriority
                    ? AppColors.primary
                    : AppColors.surfaceContainer,
                foregroundColor:
                    isTopPriority ? Colors.white : AppColors.ink,
                child: Text(
                  '#${i + 1}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              title: Text(
                item.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        'Sisa: ${_moneyLabel(item.remainingBalance)}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        item.interestRate > 0
                            ? 'Bunga: ${item.interestRate}%'
                            : 'Bunga: 0%',
                        style: TextStyle(
                          color: item.interestRate > 0
                              ? AppColors.warning
                              : AppColors.inkMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        'Cicilan: ${_moneyLabel(item.monthlyInstallment)}/bln',
                        style: const TextStyle(fontSize: 12),
                      ),
                      if (!item.isExplicitInstallment) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primarySoft,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'adaptif',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (milestone != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '✨ Estimasi Lunas: Bulan ke-${milestone.paidOffMonth} (${_monthName(milestone.paidOffDate.month)} ${milestone.paidOffDate.year})',
                      style: const TextStyle(
                        color: AppColors.positive,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ],
              ),
              trailing: isTopPriority
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primarySoft,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'SERANG!',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    )
                  : null,
            ),
          ),
        ),
      );
    }

    return widgets;
  }
}
