import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_context.dart';
import '../../../../core/di/injection.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../../../shared/widgets/hijri_date_components.dart';
import '../../../assistant/domain/ffm_assistant_models.dart';
import '../../../assistant/presentation/widgets/ffm_assistant_page_context.dart';
import '../../data/repositories/market_news_cache_repository.dart';
import '../../domain/entities/asset_entity.dart';
import '../../domain/entities/market_news_models.dart';
import '../../domain/usecases/asset_auto_valuation_service.dart';
import '../../domain/usecases/asset_crud_usecases.dart';
import '../widgets/market_price_ticker_card.dart';

class AssetListPage extends StatefulWidget {
  const AssetListPage({super.key});

  @override
  State<AssetListPage> createState() => _AssetListPageState();
}

class _AssetListPageState extends State<AssetListPage> {
  var _items = <AssetEntity>[];
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await getIt<GetAssets>()(AppContext.householdId);
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _add() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AssetFormPage()),
    );
    if (saved == true) await _load();
  }

  Future<void> _edit(AssetEntity item) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AssetFormPage(initial: item)),
    );
    if (saved == true) await _load();
  }

  Future<void> _openDetail(AssetEntity item) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AssetDetailPage(asset: item)),
    );
    if (changed == true) await _load();
  }

  Future<void> _archive(AssetEntity item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Arsipkan aset?'),
        content: Text(
          'Aset “${item.name}” akan disembunyikan dari daftar aktif, tetapi datanya tetap tersimpan. Aset tidak mengubah saldo rekening dan tidak terkait transaksi kas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Arsipkan'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await getIt<ArchiveAsset>()(AppContext.householdId, item.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Aset sudah diarsipkan. Data tetap aman.')),
    );
    await _load();
  }

  Future<void> _syncMarketValuation() async {
    final snapshot = await getIt<MarketNewsCacheRepository>().getLatestPriceSnapshot();
    final updatedCount = await getIt<AssetAutoValuationService>().revalueAllAssets(
      AppContext.householdId,
      snapshot,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          updatedCount > 0
              ? 'Berhasil memperbarui nilai $updatedCount aset emas/valas dengan kurs pasar.'
              : 'Tidak ada aset berlabel emas/valas yang perlu disinkronkan.',
        ),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return FfmAssistantPageContext(
      destination: FfmAssistantDestination.assets,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Aset keluarga'),
          actions: [
            IconButton(
              tooltip: 'Sinkronkan nilai emas & valas',
              icon: const Icon(Icons.sync),
              onPressed: _syncMarketValuation,
            ),
            IconButton(
              tooltip: 'Apa fungsi aset?',
              onPressed: () => showDialog<void>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Fungsi aset'),
                  content: const Text(
                    'Aset dipakai untuk mencatat barang atau kekayaan keluarga, misalnya motor, perhiasan, tanah, atau peralatan. Nilainya hanya untuk gambaran kekayaan dan tidak otomatis menambah atau mengurangi saldo Tunai, Bank, atau E-Wallet.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Oke, paham'),
                    ),
                  ],
                ),
              ),
              icon: const Icon(Icons.info_outline),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'asset_add_fab',
          onPressed: _add,
          icon: const Icon(Icons.add),
          label: const Text('Tambah aset'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                children: [
                  const AppHelpBanner(
                    title: 'Aset itu bukan rekening',
                    message: 'Pakai bagian ini untuk memantau nilai barang atau kekayaan keluarga. Saldo rekening tetap dihitung dari transaksi dan transfer, bukan dari aset.',
                    icon: Icons.inventory_2_outlined,
                  ),
                  const SizedBox(height: 16),
                  MarketPriceTickerCard(
                    onPricesUpdated: _load,
                  ),
                  if (_items.isEmpty)
                    const AppEmptyState(
                      icon: Icons.inventory_2_outlined,
                      title: 'Belum ada aset',
                      message: 'Belum ada data contoh. Tambahkan aset keluarga kalau memang perlu dipantau.',
                    )
                  else ...[
                    Text(
                      '${_items.length} aset tercatat',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    for (final item in _items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: AppCard(
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            leading: CircleAvatar(
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer,
                              child: Icon(
                                Icons.inventory_2_outlined,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            title: Text(
                              item.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(
                              '${item.assetType} • ${item.placement}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: PopupMenuButton<String>(
                              tooltip: 'Kelola aset',
                              onSelected: (value) {
                                if (value == 'edit') {
                                  _edit(item);
                                } else if (value == 'archive') {
                                  _archive(item);
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(Icons.edit_outlined),
                                    title: Text('Ubah aset'),
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'archive',
                                  child: ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(Icons.archive_outlined),
                                    title: Text('Arsipkan aset'),
                                  ),
                                ),
                              ],
                            ),
                            onTap: () => _openDetail(item),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
      ),
    );
  }
}

class AssetDetailPage extends StatelessWidget {
  const AssetDetailPage({super.key, required this.asset});

  final AssetEntity asset;

  Future<void> _edit(BuildContext context) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AssetFormPage(initial: asset)),
    );
    if (!context.mounted || saved != true) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _archive(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Arsipkan aset?'),
        content: Text(
          'Aset “${asset.name}” akan disembunyikan dari daftar aktif, tetapi datanya tetap tersimpan. Tindakan ini tidak mengubah saldo rekening atau transaksi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Arsipkan'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await getIt<ArchiveAsset>()(AppContext.householdId, asset.id);
    if (!context.mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => FfmAssistantPageContext(
    destination: FfmAssistantDestination.assets,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Detail aset'),
        actions: [
          IconButton(
            tooltip: 'Ubah aset',
            onPressed: () => _edit(context),
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          const AppHelpBanner(
            title: 'Aset bukan rekening',
            message: 'Nilai aset membantu memantau gambaran kekayaan keluarga. Nilai ini tidak otomatis menambah, mengurangi, atau memindahkan saldo rekening.',
            icon: Icons.inventory_2_outlined,
          ),
          const SizedBox(height: 20),
          Center(
            child: CircleAvatar(
              radius: 30,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              foregroundColor: Theme.of(context).colorScheme.primary,
              child: const Icon(Icons.inventory_2_outlined, size: 32),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            asset.name,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Center(child: AppMoneyText(asset.value, compact: false)),
          const SizedBox(height: 24),
          const AppSectionHeader(title: 'Informasi aset'),
          const SizedBox(height: 8),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.category_outlined),
                  title: const Text('Jenis aset'),
                  subtitle: Text(asset.assetType),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.place_outlined),
                  title: const Text('Lokasi atau penempatan'),
                  subtitle: Text(asset.placement),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.event_note_outlined),
                  title: const Text('Tanggal dicatat'),
                  subtitle: HijriDateText(
                    date: asset.createdAt,
                    includeSeconds: true,
                    compact: true,
                  ),
                ),
                if (asset.updatedAt != null) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.update_outlined),
                    title: const Text('Terakhir diperbarui'),
                    subtitle: HijriDateText(
                      date: asset.updatedAt!,
                      includeSeconds: true,
                      compact: true,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (asset.note?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 20),
            const AppSectionHeader(title: 'Catatan'),
            const SizedBox(height: 8),
            AppCard(child: Text(asset.note!.trim())),
          ],
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: () => _edit(context),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Ubah aset'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _archive(context),
            icon: const Icon(Icons.archive_outlined),
            label: const Text('Arsipkan aset'),
          ),
        ],
      ),
    ),
  );
}

class AssetFormPage extends StatefulWidget {
  const AssetFormPage({
    super.key,
    this.initial,
    this.initialName,
    this.initialType,
    this.initialValue,
    this.initialPlacement,
    this.initialNote,
  });

  final AssetEntity? initial;
  final String? initialName;
  final String? initialType;
  final int? initialValue;
  final String? initialPlacement;
  final String? initialNote;

  @override
  State<AssetFormPage> createState() => _AssetFormPageState();
}

class _AssetFormPageState extends State<AssetFormPage> {
  late final TextEditingController _name;
  late final TextEditingController _type;
  late final TextEditingController _value;
  late final TextEditingController _placement;
  late final TextEditingController _note;
  final _formKey = GlobalKey<FormState>();
  var _saving = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _name = TextEditingController(
      text: initial?.name ?? widget.initialName ?? '',
    );
    _type = TextEditingController(
      text: initial?.assetType ?? widget.initialType ?? '',
    );
    _value = TextEditingController(
      text: initial != null
          ? formatRupiahInput(initial.value.toString())
          : widget.initialValue == null
          ? ''
          : formatRupiahInput(widget.initialValue.toString()),
    );
    _placement = TextEditingController(
      text: initial?.placement ?? widget.initialPlacement ?? 'Keluarga',
    );
    _note = TextEditingController(
      text: initial?.note ?? widget.initialNote ?? '',
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _type.dispose();
    _value.dispose();
    _placement.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() => _saving = true);
    final initial = widget.initial;
    await getIt<SaveAsset>()(
      AssetEntity(
        id: initial?.id ?? const Uuid().v4(),
        householdId: AppContext.householdId,
        name: _name.text.trim(),
        assetType: _type.text.trim().isEmpty ? 'Lainnya' : _type.text.trim(),
        value: parseRupiah(_value.text),
        placement: _placement.text.trim().isEmpty
            ? 'Keluarga'
            : _placement.text.trim(),
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        createdAt: initial?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Future<void> _showMarketValuationHelper() async {
    final snapshot = await getIt<MarketNewsCacheRepository>().getLatestPriceSnapshot();
    if (!mounted) return;

    var selectedMode = 0; // 0: Emas, 1: Valas
    var selectedKarat = GoldKarat.k24;
    var grams = 5.0;
    var selectedCurrency = 'USD';
    var foreignAmount = 100.0;

    final gramCtrl = TextEditingController(text: '5');
    final foreignCtrl = TextEditingController(text: '100');

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            int calculatedRupiah;
            if (selectedMode == 0) {
              calculatedRupiah = selectedKarat.calculateValue(
                weightGrams: grams,
                pricePerGram24K: snapshot.goldPerGram24K,
              );
            } else {
              double rate;
              switch (selectedCurrency) {
                case 'SGD':
                  rate = snapshot.sgdToIdr;
                  break;
                case 'EUR':
                  rate = snapshot.eurToIdr;
                  break;
                case 'SAR':
                  rate = snapshot.sarToIdr;
                  break;
                case 'USD':
                default:
                  rate = snapshot.usdToIdr;
                  break;
              }
              calculatedRupiah = (foreignAmount * rate).round();
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Kalkulator Valuasi Pasar',
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
                  const SizedBox(height: 8),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(
                        value: 0,
                        icon: Icon(Icons.workspace_premium),
                        label: Text('Emas Karat'),
                      ),
                      ButtonSegment(
                        value: 1,
                        icon: Icon(Icons.currency_exchange),
                        label: Text('Valuta Asing'),
                      ),
                    ],
                    selected: {selectedMode},
                    onSelectionChanged: (val) {
                      setSheetState(() => selectedMode = val.first);
                    },
                  ),
                  const SizedBox(height: 16),
                  if (selectedMode == 0) ...[
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: gramCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Berat (Gram)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (v) {
                              final parsed = double.tryParse(v.replaceAll(',', '.'));
                              if (parsed != null && parsed > 0) {
                                setSheetState(() => grams = parsed);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 4,
                          child: DropdownButtonFormField<GoldKarat>(
                            initialValue: selectedKarat,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Kadar Karat',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: GoldKarat.values.map((k) {
                              return DropdownMenuItem(
                                value: k,
                                child: Text('${k.label} (${(k.purityFactor * 100).toInt()}%)'),
                              );
                            }).toList(),
                            onChanged: (k) {
                              if (k != null) setSheetState(() => selectedKarat = k);
                            },
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: foreignCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Jumlah Valas',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (v) {
                              final parsed = double.tryParse(v.replaceAll(',', '.'));
                              if (parsed != null && parsed > 0) {
                                setSheetState(() => foreignAmount = parsed);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 4,
                          child: DropdownButtonFormField<String>(
                            initialValue: selectedCurrency,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Mata Uang',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: const [
                              DropdownMenuItem(value: 'USD', child: Text('USD (Dolar AS)')),
                              DropdownMenuItem(value: 'SGD', child: Text('SGD (Dolar SG)')),
                              DropdownMenuItem(value: 'EUR', child: Text('EUR (Euro)')),
                              DropdownMenuItem(value: 'SAR', child: Text('SAR (Riyal Haji)')),
                            ],
                            onChanged: (c) {
                              if (c != null) setSheetState(() => selectedCurrency = c);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Hasil Konversi:'),
                        Text(
                          'Rp ${formatRupiahInput(calculatedRupiah.toString())}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).brightness == Brightness.dark
                                ? const Color(0xFF4ADE80)
                                : Colors.green.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    icon: const Icon(Icons.check),
                    label: const Text('Terapkan ke Formulir'),
                    onPressed: () {
                      setState(() {
                        _value.text = formatRupiahInput(calculatedRupiah.toString());
                        if (selectedMode == 0) {
                          if (_name.text.trim().isEmpty) {
                            _name.text = 'Emas ${selectedKarat.label} (${grams}g)';
                          }
                          if (_type.text.trim().isEmpty) {
                            _type.text = 'Logam Mulia';
                          }
                          final tag = '[Emas ${selectedKarat.name.toUpperCase()}, ${grams}g]';
                          if (!_note.text.contains('[Emas')) {
                            _note.text = _note.text.trim().isEmpty ? tag : '${_note.text.trim()} $tag';
                          }
                        } else {
                          if (_name.text.trim().isEmpty) {
                            _name.text = 'Simpanan $selectedCurrency ($foreignAmount)';
                          }
                          if (_type.text.trim().isEmpty) {
                            _type.text = 'Valuta Asing';
                          }
                          final tag = '[$selectedCurrency $foreignAmount]';
                          if (!_note.text.contains('[$selectedCurrency')) {
                            _note.text = _note.text.trim().isEmpty ? tag : '${_note.text.trim()} $tag';
                          }
                        }
                      });
                      Navigator.pop(ctx);
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initial != null;
    return FfmAssistantPageContext(
      destination: FfmAssistantDestination.assets,
      child: Scaffold(
        appBar: AppBar(title: Text(editing ? 'Ubah aset' : 'Tambah aset')),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              const AppHelpBanner(
                title: 'Catat seperlunya',
                message: 'Nilai aset hanya untuk melihat gambaran kekayaan keluarga. Data ini tidak mengubah saldo rekening dan tidak dianggap sebagai pemasukan.',
                icon: Icons.info_outline,
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_note_outlined),
                title: const Text('Tanggal dicatat'),
                subtitle: HijriDateText(
                  date: widget.initial?.createdAt ?? DateTime.now(),
                  includeSeconds: true,
                  compact: true,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _name,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Nama aset',
                  hintText: 'Misalnya motor atau tanah',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Nama aset wajib diisi.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _type,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Jenis aset (opsional)',
                  hintText: 'Kendaraan, tanah, elektronik, dan lainnya',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _value,
                      keyboardType: TextInputType.number,
                      inputFormatters: [RupiahInputFormatter()],
                      decoration: const InputDecoration(
                        labelText: 'Nilai perkiraan',
                        prefixText: 'Rp ',
                      ),
                      validator: (value) => parseRupiah(value ?? '') <= 0
                          ? 'Isi nilai aset lebih dari nol.'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: IconButton.filledTonal(
                      tooltip: 'Hitung otomatis dari harga pasar (Emas / Valas)',
                      icon: const Icon(Icons.calculate_outlined),
                      onPressed: _showMarketValuationHelper,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _placement,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Lokasi atau penempatan',
                  hintText: 'Rumah, gudang, kebun, atau lainnya',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _note,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Catatan (opsional)',
                  alignLabelWithHint: true,
                  hintText: 'Kondisi, tahun beli, atau keterangan lain',
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Menyimpan…' : 'Simpan aset'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
