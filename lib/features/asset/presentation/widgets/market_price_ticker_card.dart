import 'package:flutter/material.dart';

import '../../../../core/database/app_context.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../data/repositories/market_news_cache_repository.dart';
import '../../data/services/market_news_radar_service.dart';
import '../../domain/entities/market_news_models.dart';
import '../../domain/usecases/asset_auto_valuation_service.dart';
import '../pages/market_news_radar_page.dart';

/// Widget ticker harga pasar terkini (Emas Karat, USD, SGD, SAR, BTC) di halaman Aset.
class MarketPriceTickerCard extends StatefulWidget {
  const MarketPriceTickerCard({
    super.key,
    this.onPricesUpdated,
  });

  final VoidCallback? onPricesUpdated;

  @override
  State<MarketPriceTickerCard> createState() => _MarketPriceTickerCardState();
}

class _MarketPriceTickerCardState extends State<MarketPriceTickerCard> {
  late final MarketNewsRadarService _service;
  late final MarketNewsCacheRepository _cache;
  late final AssetAutoValuationService _valuationService;

  MarketPriceSnapshot? _snapshot;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _service = getIt<MarketNewsRadarService>();
    _cache = getIt<MarketNewsCacheRepository>();
    _valuationService = getIt<AssetAutoValuationService>();
    _loadPrices();
  }

  Future<void> _loadPrices() async {
    // 1. Ambil dari cache dulu
    final cached = await _cache.getLatestPriceSnapshot();
    if (mounted) setState(() => _snapshot = cached);

    // 2. Jika cache sudah lebih dari 4 jam, refresh di latar belakang
    final age = DateTime.now().difference(cached.lastUpdated);
    if (cached.isOfflineCache || age.inHours >= 4) {
      _refreshPrices(silent: true);
    }
  }

  Future<void> _refreshPrices({bool silent = false}) async {
    if (!silent && mounted) setState(() => _isLoading = true);

    try {
      final fresh = await _service.fetchMarketPrices();
      await _cache.savePriceSnapshot(fresh);

      // Jalankan auto-valuasi aset
      final db = getIt<AppDatabase>();
      final revalueResult = await _valuationService.revalueAssets(
        db: db,
        snapshot: fresh,
        householdId: AppContext.householdId,
      );

      if (mounted) {
        setState(() {
          _snapshot = fresh;
          _isLoading = false;
        });

        if (!silent) {
          final msg = revalueResult.revaluedCount > 0
              ? 'Harga diperbarui! ${revalueResult.revaluedCount} aset disesuaikan (${revalueResult.difference >= 0 ? '+' : ''}Rp ${_formatNumber(revalueResult.difference)}).'
              : 'Harga pasar berhasil diperbarui.';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.teal.shade700,
            ),
          );
        }

        widget.onPricesUpdated?.call();
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot ?? MarketPriceSnapshot.initialFallback();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.4)
            : colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Ticker
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
            child: Row(
              children: [
                Icon(
                  Icons.radar_outlined,
                  size: 18,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Radar Pasar & Valuasi Terkini',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MarketNewsRadarPage(),
                    ),
                  ).then((_) => _loadPrices()),
                  icon: const Icon(Icons.newspaper_outlined, size: 14),
                  label: const Text('Warta & Radar', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                IconButton(
                  icon: _isLoading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 18),
                  tooltip: 'Segarkan Harga Pasar',
                  onPressed: _isLoading ? null : () => _refreshPrices(silent: false),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Horizontal Chips Ticker
          SizedBox(
            height: 80,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                _buildPriceChip(
                  label: 'Emas 24K',
                  price: 'Rp ${_formatNumber(snapshot.goldPrice24K)}/gr',
                  subtitle: 'Buyback: Rp ${_formatNumber(snapshot.goldBuybackPrice)}',
                  color: Colors.amber.shade700,
                  icon: Icons.savings_outlined,
                ),
                const SizedBox(width: 8),
                _buildPriceChip(
                  label: 'USD / IDR',
                  price: 'Rp ${_formatNumber(snapshot.usdRate.round())}',
                  subtitle: 'Dolar AS',
                  color: Colors.green.shade700,
                  icon: Icons.attach_money,
                ),
                const SizedBox(width: 8),
                _buildPriceChip(
                  label: 'SGD / IDR',
                  price: 'Rp ${_formatNumber(snapshot.sgdRate.round())}',
                  subtitle: 'Dolar Singapura',
                  color: Colors.blue.shade700,
                  icon: Icons.monetization_on_outlined,
                ),
                const SizedBox(width: 8),
                _buildPriceChip(
                  label: 'SAR / IDR',
                  price: 'Rp ${_formatNumber(snapshot.sarRate.round())}',
                  subtitle: 'Riyal (Haji/Umrah)',
                  color: Colors.teal.shade700,
                  icon: Icons.mosque_outlined,
                ),
                const SizedBox(width: 8),
                _buildPriceChip(
                  label: 'BTC / IDR',
                  price: 'Rp ${_formatNumber((snapshot.btcPrice / 1000000).round())} Jt',
                  subtitle: 'Bitcoin',
                  color: Colors.deepOrange.shade700,
                  icon: Icons.currency_bitcoin,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceChip({
    required String label,
    required String price,
    required String subtitle,
    required Color color,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: 140,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDark
            ? color.withValues(alpha: 0.12)
            : color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            price,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 9,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
