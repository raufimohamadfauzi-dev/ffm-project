import 'package:flutter/material.dart';

import '../../../../core/database/app_context.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../data/cash_flow_profile_repository.dart';
import '../../domain/entities/cash_flow_profile_models.dart';
import '../../domain/usecases/flexible_cash_flow_calculator.dart';
import '../pages/flexible_cash_flow_page.dart';

/// Kartu cerdas di Beranda untuk menampilkan status siklus kas adaptif
/// (Pertanian / AgroTrack, Pemilik Bisnis, dan Freelancer).
///
/// Jika pengguna belum mengaktifkan profil siklus non-gajian, widget ini
/// otomatis tersembunyi (SizedBox.shrink).
class AdaptiveCashFlowCard extends StatefulWidget {
  const AdaptiveCashFlowCard({
    super.key,
    this.onProfileChanged,
  });

  final VoidCallback? onProfileChanged;

  @override
  State<AdaptiveCashFlowCard> createState() => _AdaptiveCashFlowCardState();
}

class _AdaptiveCashFlowCardState extends State<AdaptiveCashFlowCard> {
  late final CashFlowProfileRepository _repo;
  late final FlexibleCashFlowCalculator _calculator;

  CashFlowProfile? _activeProfile;
  CashFlowRunwayResult? _runwayResult;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _repo = getIt<CashFlowProfileRepository>();
    _calculator = getIt<FlexibleCashFlowCalculator>();
    _loadActiveProfile();
  }

  Future<void> _loadActiveProfile() async {
    try {
      final profile = await _repo.getActiveProfile(AppContext.householdId);
      if (profile == null ||
          !profile.isActive ||
          profile.profileType == CashFlowProfileType.salaried) {
        if (mounted) {
          setState(() {
            _activeProfile = null;
            _isLoading = false;
          });
        }
        return;
      }

      // Hitung total kas likuid riil dari akun perbankan / tunai
      final db = getIt<AppDatabase>();
      final accounts = await (db.select(db.accounts)
            ..where((a) => a.isArchived.equals(false)))
          .get();

      final totalLiquidCash = accounts.fold<int>(
        0,
        (sum, a) => sum + (a.openingBalance > 0 ? a.openingBalance : 0),
      );

      final runway = _calculator.calculateRunway(
        effectiveLiquidCash: totalLiquidCash,
        dailyLivingBudget: profile.dailyLivingBudget,
        dailyOperationalBudget: profile.dailyOperationalBudget,
        daysRemainingToHarvest: profile.daysRemaining,
      );

      if (mounted) {
        setState(() {
          _activeProfile = profile;
          _runwayResult = runway;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _activeProfile == null || _runwayResult == null) {
      return const SizedBox.shrink();
    }

    final profile = _activeProfile!;
    final runway = _runwayResult!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final (statusColor, statusBg, statusIcon) = switch (runway.healthStatus) {
      CycleHealthStatus.safe => (
          Colors.green.shade600,
          Colors.green.shade50,
          Icons.check_circle_outline,
        ),
      CycleHealthStatus.warning => (
          Colors.orange.shade700,
          Colors.orange.shade50,
          Icons.warning_amber_rounded,
        ),
      CycleHealthStatus.critical => (
          Colors.red.shade700,
          Colors.red.shade50,
          Icons.error_outline,
        ),
    };

    final profileIcon = switch (profile.profileType) {
      CashFlowProfileType.agriculture => Icons.eco_outlined,
      CashFlowProfileType.business => Icons.storefront_outlined,
      CashFlowProfileType.freelance => Icons.work_outline,
      CashFlowProfileType.salaried => Icons.account_balance_outlined,
    };

    final profileTypeTitle = switch (profile.profileType) {
      CashFlowProfileType.agriculture => 'Siklus Pertanian / Panen',
      CashFlowProfileType.business => 'Siklus Usaha & Modal Kerja',
      CashFlowProfileType.freelance => 'Siklus Termin Proyek',
      CashFlowProfileType.salaried => 'Profil Gaji Bulanan',
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.4)
            : colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: statusColor.withValues(alpha: isDark ? 0.4 : 0.3),
          width: 1.5,
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header profil siklus
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(profileIcon, size: 20, color: statusColor),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '$profileTypeTitle • ${profile.commodityOrBusinessType}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.tune_outlined, size: 20),
                  tooltip: 'Kelola Siklus Arus Kas',
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const FlexibleCashFlowPage(),
                      ),
                    );
                    _loadActiveProfile();
                    widget.onProfileChanged?.call();
                  },
                ),
              ],
            ),
          ),

          // Progress bar siklus
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        'Fase: ${profile.phaseLabel}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.primary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Hari ke-${profile.daysElapsed} dari ${profile.totalDays} (${(profile.progress * 100).round()}%)',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.end,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: profile.progress,
                    minHeight: 7,
                    backgroundColor:
                        colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
                    valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Baris Metrik Kunci: Runway & Batas Belanja Aman
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                // Kotak 1: Ketahanan Kas (Runway)
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? statusColor.withValues(alpha: 0.12)
                          : statusBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(statusIcon, size: 14, color: statusColor),
                            const SizedBox(width: 4),
                            Text(
                              'Runway Kas',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: statusColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${runway.runwayDays} Hari',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: statusColor,
                          ),
                        ),
                        Text(
                          profile.daysRemaining > 0
                              ? 'Sisa ${profile.daysRemaining} hari ke panen'
                              : 'Waktu panen telah tiba',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 10,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Kotak 2: Batas Belanja Aman Harian
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
                          : colorScheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.security_outlined,
                              size: 14,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Batas Aman Dapur',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Rp ${_formatNumber(runway.safeToSpendDaily)}',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'per hari tanpa sentuh modal',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 10,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Pesan / Rekomendasi ringkas
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.tips_and_updates_outlined,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    runway.recommendation,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatNumber(int val) {
    return val.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]}.',
        );
  }
}
