import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_context.dart';
import '../../../../core/di/injection.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../../../shared/widgets/hijri_date_components.dart';
import '../../domain/entities/asset_entity.dart';
import '../../domain/usecases/asset_crud_usecases.dart';

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

  Future<void> _delete(AssetEntity item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus aset?'),
        content: Text(
          'Aset “${item.name}” akan dihapus dari daftar. Aset tidak mengubah saldo rekening dan tidak terkait transaksi kas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await getIt<DeleteAsset>()(AppContext.householdId, item.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Aset sudah dihapus dari daftar.')),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aset keluarga'),
        actions: [
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
                            style: const TextStyle(fontWeight: FontWeight.w800),
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
                              } else if (value == 'delete') {
                                _delete(item);
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
                                value: 'delete',
                                child: ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(Icons.delete_outline),
                                  title: Text('Hapus aset'),
                                ),
                              ),
                            ],
                          ),
                          onTap: () => _edit(item),
                        ),
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}

class AssetFormPage extends StatefulWidget {
  const AssetFormPage({super.key, this.initial});

  final AssetEntity? initial;

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
    _name = TextEditingController(text: initial?.name ?? '');
    _type = TextEditingController(text: initial?.assetType ?? '');
    _value = TextEditingController(
      text: initial == null ? '' : formatRupiahInput(initial.value.toString()),
    );
    _placement = TextEditingController(text: initial?.placement ?? 'Keluarga');
    _note = TextEditingController(text: initial?.note ?? '');
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

  @override
  Widget build(BuildContext context) {
    final editing = widget.initial != null;
    return Scaffold(
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
            TextFormField(
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
    );
  }
}
