import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/di/injection.dart';
import '../../data/repositories/market_news_cache_repository.dart';
import '../../data/services/market_news_radar_service.dart';
import '../../domain/entities/market_news_models.dart';
import '../pages/market_news_radar_page.dart';

/// Drawer kiri geser (slide dari kiri ke kanan) untuk pantauan cepat Radar Berita & Pasar.
class MarketNewsRadarDrawer extends StatefulWidget {
  const MarketNewsRadarDrawer({super.key});

  @override
  State<MarketNewsRadarDrawer> createState() => _MarketNewsRadarDrawerState();
}

class _MarketNewsRadarDrawerState extends State<MarketNewsRadarDrawer> {
  late final MarketNewsRadarService _service;
  late final MarketNewsCacheRepository _cache;

  MarketPriceSnapshot? _snapshot;
  List<NewsAlertItem> _news = [];
  NewsCategory? _selectedCategory;
  bool _isLoading = false;

  final _currencyFormat = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp',
    decimalDigits: 0,
  );

  @override
  void initState() {
    super.initState();
    _service = getIt<MarketNewsRadarService>();
    _cache = getIt<MarketNewsCacheRepository>();
    _loadData();
  }

  Future<void> _loadData() async {
    final cachedPrice = await _cache.getLatestPriceSnapshot();
    final cachedNews = await _cache.getCachedNews();

    if (mounted) {
      setState(() {
        _snapshot = cachedPrice;
        _news = cachedNews;
      });
    }

    if (cachedPrice.isOfflineCache || cachedNews.isEmpty) {
      _refresh(silent: true);
    }
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent && mounted) setState(() => _isLoading = true);
    try {
      final freshPrices = await _service.fetchMarketPrices();
      await _cache.savePriceSnapshot(freshPrices);

      final freshNews = await _service.fetchCuratedNews();
      await _cache.saveNewsItems(freshNews);

      final prunedNews = await _cache.getCachedNews();

      if (mounted) {
        setState(() {
          _snapshot = freshPrices;
          _news = prunedNews;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final snapshot = _snapshot ?? MarketPriceSnapshot.initialFallback();

    final filteredNews = _selectedCategory == null
        ? _news
        : _news.where((n) => n.category == _selectedCategory).toList();

    return Drawer(
      width: MediaQuery.of(context).size.width * 0.85,
      child: SafeArea(
        child: Column(
          children: [
            // Drawer Header
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                border: Border(
                  bottom: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: colorScheme.primaryContainer,
                    child: Icon(Icons.radar, color: colorScheme.primary, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Radar Warta & Pasar',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Pantauan Cepat Terkini',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_isLoading)
                    const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 20),
                      tooltip: 'Segarkan data',
                      onPressed: () => _refresh(silent: false),
                    ),
                  IconButton(
                    icon: const Icon(Icons.open_in_new, size: 20),
                    tooltip: 'Buka Halaman Penuh',
                    onPressed: () {
                      Navigator.pop(context); // close drawer
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const MarketNewsRadarPage(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            // Mini Price Bar (Quick Glance)
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(vertical: 6),
              color: isDark ? Colors.black12 : Colors.grey.shade100,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _buildMiniChip(
                    'Emas 24K',
                    _currencyFormat.format(snapshot.goldPrice24K),
                    const Color(0xFFCA8A04),
                  ),
                  const SizedBox(width: 8),
                  _buildMiniChip(
                    'USD',
                    _currencyFormat.format(snapshot.usdRate),
                    Colors.green,
                  ),
                  const SizedBox(width: 8),
                  _buildMiniChip(
                    'SGD',
                    _currencyFormat.format(snapshot.sgdRate),
                    Colors.teal,
                  ),
                  const SizedBox(width: 8),
                  _buildMiniChip(
                    'SAR',
                    _currencyFormat.format(snapshot.sarRate),
                    Colors.amber.shade700,
                  ),
                  const SizedBox(width: 8),
                  _buildMiniChip(
                    'BTC',
                    _currencyFormat.format(snapshot.btcPrice),
                    Colors.deepOrange,
                  ),
                ],
              ),
            ),

            // Category Filter Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('Semua', style: TextStyle(fontSize: 11)),
                    selected: _selectedCategory == null,
                    onSelected: (_) => setState(() => _selectedCategory = null),
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    label: const Text('🌾 Tani', style: TextStyle(fontSize: 11)),
                    selected: _selectedCategory == NewsCategory.agriculture,
                    onSelected: (_) =>
                        setState(() => _selectedCategory = NewsCategory.agriculture),
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    label: const Text('🌧️ Cuaca', style: TextStyle(fontSize: 11)),
                    selected: _selectedCategory == NewsCategory.weatherDisaster,
                    onSelected: (_) =>
                        setState(() => _selectedCategory = NewsCategory.weatherDisaster),
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    label: const Text('📈 Finansial', style: TextStyle(fontSize: 11)),
                    selected: _selectedCategory == NewsCategory.finance,
                    onSelected: (_) =>
                        setState(() => _selectedCategory = NewsCategory.finance),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // News Feed List
            Expanded(
              child: filteredNews.isEmpty
                  ? Center(
                      child: Text(
                        'Belum ada warta dalam kategori ini.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      itemCount: filteredNews.length,
                      itemBuilder: (ctx, idx) {
                        final item = filteredNews[idx];
                        return _buildDrawerNewsItem(item, theme, colorScheme);
                      },
                    ),
            ),

            // Footer info
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
              child: Row(
                children: [
                  Icon(Icons.history_toggle_off, size: 14, color: colorScheme.outline),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Cache sementara 48 jam • Bebas database',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.outline,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerNewsItem(
    NewsAlertItem item,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final timeStr = DateFormat('dd MMM, HH:mm').format(item.publishedAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: item.isHighAlert
              ? Colors.red.withValues(alpha: 0.5)
              : colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                item.category.label,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                ),
              ),
              if (item.isHighAlert) ...[
                const SizedBox(width: 4),
                const Icon(Icons.warning, size: 12, color: Colors.red),
              ],
              const Spacer(),
              Text(
                timeStr,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.outline,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            item.title,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            item.snippet,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
