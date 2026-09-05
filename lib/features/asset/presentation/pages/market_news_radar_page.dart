import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/di/injection.dart';
import '../../../assistant/domain/ffm_assistant_models.dart';
import '../../../assistant/presentation/widgets/ffm_assistant_page_context.dart';
import '../../data/repositories/market_news_cache_repository.dart';
import '../../data/services/market_news_radar_service.dart';
import '../../domain/entities/market_news_models.dart';

/// Halaman Radar Pasar Terkini & Berita Terpilih.
/// Tab 1: Harga Pasar, Valas, Kripto & Kalkulator Karat Emas.
/// Tab 2: Radar Berita & Peringatan Terpilih (Pertanian, Cuaca BMKG, Finansial).
class MarketNewsRadarPage extends StatefulWidget {
  const MarketNewsRadarPage({super.key});

  @override
  State<MarketNewsRadarPage> createState() => _MarketNewsRadarPageState();
}

class _MarketNewsRadarPageState extends State<MarketNewsRadarPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final MarketNewsRadarService _radarService;
  late final MarketNewsCacheRepository _cacheRepository;

  // Market Prices State
  MarketPriceSnapshot? _priceSnapshot;
  bool _isLoadingPrices = false;

  // Karat Calculator State
  double _calcGrams = 5.0;
  GoldKarat _calcKarat = GoldKarat.k24;
  final _gramController = TextEditingController(text: '5');

  // News State
  List<NewsAlertItem> _allNews = [];
  NewsCategory? _selectedCategory; // null = Semua
  bool _isLoadingNews = false;
  List<String> _userKeywords = [];

  final _currencyFormat = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp',
    decimalDigits: 0,
  );

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _radarService = getIt<MarketNewsRadarService>();
    _cacheRepository = getIt<MarketNewsCacheRepository>();

    _loadPrices();
    _loadNews();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _gramController.dispose();
    super.dispose();
  }

  Future<void> _loadPrices() async {
    final cached = await _cacheRepository.getLatestPriceSnapshot();
    if (mounted) setState(() => _priceSnapshot = cached);

    // Refresh if stale or offline fallback
    if (cached.isOfflineCache ||
        DateTime.now().difference(cached.lastUpdated).inHours >= 1) {
      _refreshPrices(silent: true);
    }
  }

  Future<void> _refreshPrices({bool silent = false}) async {
    if (!silent && mounted) setState(() => _isLoadingPrices = true);
    try {
      final fresh = await _radarService.fetchMarketPrices();
      await _cacheRepository.savePriceSnapshot(fresh);
      if (mounted) {
        setState(() {
          _priceSnapshot = fresh;
          _isLoadingPrices = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingPrices = false);
    }
  }

  Future<void> _loadNews() async {
    final cached = await _cacheRepository.getCachedNews();
    final keywords = await _cacheRepository.getUserAlertKeywords();
    if (mounted) {
      setState(() {
        _allNews = cached;
        _userKeywords = keywords;
      });
    }

    if (cached.isEmpty) {
      _refreshNews(silent: true);
    }
  }

  Future<void> _refreshNews({bool silent = false}) async {
    if (!silent && mounted) setState(() => _isLoadingNews = true);
    try {
      final fresh = await _radarService.fetchCuratedNews();
      await _cacheRepository.saveNewsItems(fresh);
      final pruned = await _cacheRepository.getCachedNews();
      if (mounted) {
        setState(() {
          _allNews = pruned;
          _isLoadingNews = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingNews = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return FfmAssistantPageContext(
      destination: FfmAssistantDestination.marketNewsRadar,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Radar Pasar & Berita'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Pengaturan Kata Kunci & Topik',
            onPressed: _showPreferencesModal,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Segarkan Data',
            onPressed: () {
              if (_tabController.index == 0) {
                _refreshPrices();
              } else {
                _refreshNews();
              }
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.trending_up), text: 'Harga & Valas'),
            Tab(icon: Icon(Icons.newspaper), text: 'Berita & Peringatan'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildMarketPricesTab(theme, colorScheme),
          _buildNewsRadarTab(theme, colorScheme),
        ],
      ),
    ),
  );
}

  // ==================== TAB 1: MARKET PRICES ====================
  Widget _buildMarketPricesTab(ThemeData theme, ColorScheme colorScheme) {
    final isDark = theme.brightness == Brightness.dark;
    final snapshot = _priceSnapshot ?? MarketPriceSnapshot.initialFallback();
    final timeStr = DateFormat('HH:mm, dd MMM yyyy').format(snapshot.lastUpdated);

    return RefreshIndicator(
      onRefresh: () => _refreshPrices(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Status banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  snapshot.isOfflineCache ? Icons.cloud_off : Icons.check_circle_outline,
                  size: 18,
                  color: snapshot.isOfflineCache ? Colors.orange : Colors.green,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    snapshot.isOfflineCache
                        ? 'Memakai estimasi cache lokal ($timeStr)'
                        : 'Pembaruan terakhir: $timeStr',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (_isLoadingPrices)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Section Emas
          _buildSectionHeader('Logam Mulia (Emas Batangan & Perhiasan)', Icons.monetization_on),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildPriceCard(
                  title: 'Emas 24K (Antam)',
                  price: _currencyFormat.format(snapshot.goldPerGram24K),
                  subtitle: 'per gram (Jual)',
                  color: isDark ? const Color(0xFFFACC15) : const Color(0xFFB45309),
                  icon: Icons.workspace_premium,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildPriceCard(
                  title: 'Buyback Emas',
                  price: _currencyFormat.format(snapshot.goldPerGramBuyback),
                  subtitle: 'per gram (Beli Balik)',
                  color: isDark ? const Color(0xFFFCD34D) : const Color(0xFF92400E),
                  icon: Icons.swap_horizontal_circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Interactive Karat Calculator
          _buildKaratCalculatorCard(snapshot, theme, colorScheme),
          const SizedBox(height: 20),

          // Section Valuta Asing (Forex)
          _buildSectionHeader('Mata Uang Asing (Valas ke IDR)', Icons.currency_exchange),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 2.1,
            children: [
              _buildPriceCard(
                title: 'USD (Dolar AS)',
                price: _currencyFormat.format(snapshot.usdToIdr),
                subtitle: '1 USD = IDR',
                color: isDark ? const Color(0xFF4ADE80) : Colors.green.shade800,
                icon: Icons.attach_money,
              ),
              _buildPriceCard(
                title: 'SGD (Dolar SG)',
                price: _currencyFormat.format(snapshot.sgdToIdr),
                subtitle: '1 SGD = IDR',
                color: isDark ? const Color(0xFF2DD4BF) : Colors.teal.shade800,
                icon: Icons.account_balance,
              ),
              _buildPriceCard(
                title: 'SAR (Riyal Arab)',
                price: _currencyFormat.format(snapshot.sarToIdr),
                subtitle: '1 SAR = IDR (Haji/Umrah)',
                color: isDark ? const Color(0xFFFBBF24) : Colors.amber.shade900,
                icon: Icons.mosque,
              ),
              _buildPriceCard(
                title: 'EUR (Euro)',
                price: _currencyFormat.format(snapshot.eurToIdr),
                subtitle: '1 EUR = IDR',
                color: isDark ? const Color(0xFF818CF8) : Colors.indigo.shade800,
                icon: Icons.euro,
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Section Aset Kripto
          _buildSectionHeader('Aset Kripto Populer (IDR)', Icons.currency_bitcoin),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildPriceCard(
                  title: 'Bitcoin (BTC)',
                  price: _currencyFormat.format(snapshot.btcToIdr),
                  subtitle: '1 BTC',
                  color: isDark ? const Color(0xFFFB923C) : Colors.deepOrange.shade800,
                  icon: Icons.currency_bitcoin,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildPriceCard(
                  title: 'Ethereum (ETH)',
                  price: _currencyFormat.format(snapshot.ethToIdr),
                  subtitle: '1 ETH',
                  color: isDark ? const Color(0xFFC084FC) : Colors.purple.shade800,
                  icon: Icons.token,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildPriceCard({
    required String title,
    required String price,
    required String subtitle,
    required Color color,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.35)
            : colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            price,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: isDark ? colorScheme.onSurface : colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKaratCalculatorCard(
    MarketPriceSnapshot snapshot,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    final estimatedVal = _calcKarat.calculateValue(
      weightGrams: _calcGrams,
      pricePerGram24K: snapshot.goldPerGram24K,
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calculate, color: colorScheme.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Kalkulator Valuasi Karat Emas',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // Berat Gram Input
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _gramController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Berat (Gram)',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                  onChanged: (val) {
                    final parsed = double.tryParse(val.replaceAll(',', '.'));
                    if (parsed != null && parsed > 0) {
                      setState(() => _calcGrams = parsed);
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              // Karat Dropdown
              Expanded(
                flex: 4,
                child: DropdownButtonFormField<GoldKarat>(
                  initialValue: _calcKarat,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Kadar Karat',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                  items: GoldKarat.values.map((k) {
                    return DropdownMenuItem(
                      value: k,
                      child: Text('${k.label} (${(k.purityFactor * 100).toInt()}%)'),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _calcKarat = val);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Estimasi Nilai Aset:',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  _currencyFormat.format(estimatedVal),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDark ? const Color(0xFFFACC15) : Colors.amber.shade900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== TAB 2: NEWS & ALERTS ====================
  Widget _buildNewsRadarTab(ThemeData theme, ColorScheme colorScheme) {
    final filteredNews = _selectedCategory == null
        ? _allNews
        : _allNews.where((n) => n.category == _selectedCategory).toList();

    return RefreshIndicator(
      onRefresh: () => _refreshNews(),
      child: Column(
        children: [
          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                FilterChip(
                  label: const Text('Semua'),
                  selected: _selectedCategory == null,
                  onSelected: (_) => setState(() => _selectedCategory = null),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('🌾 Pertanian'),
                  selected: _selectedCategory == NewsCategory.agriculture,
                  onSelected: (_) =>
                      setState(() => _selectedCategory = NewsCategory.agriculture),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('🌧️ Cuaca BMKG'),
                  selected: _selectedCategory == NewsCategory.weatherDisaster,
                  onSelected: (_) =>
                      setState(() => _selectedCategory = NewsCategory.weatherDisaster),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('📈 Finansial'),
                  selected: _selectedCategory == NewsCategory.finance,
                  onSelected: (_) =>
                      setState(() => _selectedCategory = NewsCategory.finance),
                ),
              ],
            ),
          ),

          // Database notice banner
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Berita disimpan di memori sementara & dihapus >48 jam (Bebas dari database).',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // News List
          Expanded(
            child: filteredNews.isEmpty
                ? Center(
                    child: _isLoadingNews
                        ? const CircularProgressIndicator()
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.newspaper,
                                  size: 48,
                                  color: colorScheme.outlineVariant),
                              const SizedBox(height: 8),
                              const Text('Belum ada berita dalam kategori ini.'),
                            ],
                          ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredNews.length,
                    itemBuilder: (context, index) {
                      final item = filteredNews[index];
                      return _buildNewsCard(item, theme, colorScheme);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildNewsCard(
    NewsAlertItem item,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    final timeStr = DateFormat('dd MMM, HH:mm').format(item.publishedAt);

    Color tagColor;
    switch (item.category) {
      case NewsCategory.agriculture:
        tagColor = isDark ? const Color(0xFF4ADE80) : const Color(0xFF15803D);
      case NewsCategory.weatherDisaster:
        tagColor = isDark ? const Color(0xFF60A5FA) : const Color(0xFF1D4ED8);
      case NewsCategory.finance:
        tagColor = isDark ? const Color(0xFFFACC15) : const Color(0xFFB45309);
      case NewsCategory.all:
        tagColor = colorScheme.outline;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: item.isHighAlert
              ? Colors.red.withValues(alpha: 0.6)
              : colorScheme.outlineVariant.withValues(alpha: 0.4),
          width: item.isHighAlert ? 1.5 : 1.0,
        ),
      ),
      color: isDark
          ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.3)
          : colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: tagColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    item.category.label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: tagColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (item.isHighAlert) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.warning_amber, size: 12, color: Colors.red),
                        const SizedBox(width: 2),
                        Text(
                          'Peringatan',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const Spacer(),
                Text(
                  timeStr,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              item.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              item.summary,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.source, size: 14, color: colorScheme.outline),
                const SizedBox(width: 4),
                Text(
                  item.source,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.outline,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showPreferencesModal() {
    final keywordCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final theme = Theme.of(ctx);
            final colorScheme = theme.colorScheme;

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Kata Kunci Peringatan Khusus',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  Text(
                    'Berita yang mengandung kata kunci ini akan ditandai dengan badge peringatan merah.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: keywordCtrl,
                          decoration: const InputDecoration(
                            hintText: 'Tambah kata kunci (misal: Pupuk, Kebakaran)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        icon: const Icon(Icons.add),
                        onPressed: () {
                          final text = keywordCtrl.text.trim();
                          if (text.isNotEmpty && !_userKeywords.contains(text)) {
                            final updated = [..._userKeywords, text];
                            _cacheRepository.saveUserAlertKeywords(updated);
                            setModalState(() => _userKeywords = updated);
                            setState(() => _userKeywords = updated);
                            keywordCtrl.clear();
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: _userKeywords.map((kw) {
                      return Chip(
                        label: Text(kw),
                        onDeleted: () {
                          final updated = _userKeywords.where((k) => k != kw).toList();
                          _cacheRepository.saveUserAlertKeywords(updated);
                          setModalState(() => _userKeywords = updated);
                          setState(() => _userKeywords = updated);
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
