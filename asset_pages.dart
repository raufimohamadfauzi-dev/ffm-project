import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_context.dart';
import '../../../../core/di/injection.dart';
import '../../../../shared/widgets/app_components.dart';
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
    if (mounted) setState(() { _items = items; _loading = false; });
  }

  Future<void> _add() async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const AssetFormPage()));
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Aset keluarga')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Tambah aset')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const AppEmptyState(icon: Icons.inventory_2_outlined, title: 'Belum ada aset', message: 'Tambahkan aset keluarga kalau memang perlu dilacak. Tidak ada data contoh di sini.')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                  itemCount: _items.length,
                  itemBuilder: (_, index) {
                    final item = _items[index];
                    return AppCard(
                      child: ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.inventory_2_outlined)),
                        title: Text(item.name),
                        subtitle: Text('${item.assetType} • ${item.placement}'),
                        trailing: AppMoneyText(item.value, compact: true),
                      ),
                    );
                  },
                ),
    );
  }
}

class AssetFormPage extends StatefulWidget {
  const AssetFormPage({super.key});
  @override
  State<AssetFormPage> createState() => _AssetFormPageState();
}

class _AssetFormPageState extends State<AssetFormPage> {
  final _name = TextEditingController();
  final _type = TextEditingController();
  final _value = TextEditingController();
  final _placement = TextEditingController(text: 'Keluarga');

  @override
  void dispose() { _name.dispose(); _type.dispose(); _value.dispose(); _placement.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || parseRupiah(_value.text) <= 0) return;
    await getIt<SaveAsset>()(AssetEntity(
      id: const Uuid().v4(), householdId: AppContext.householdId,
      name: _name.text.trim(), assetType: _type.text.trim().isEmpty ? 'Lainnya' : _type.text.trim(),
      value: parseRupiah(_value.text), placement: _placement.text.trim().isEmpty ? 'Keluarga' : _placement.text.trim(),
      createdAt: DateTime.now(),
    ));
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Tambah aset')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const AppHelpBanner(title: 'Catat seperlunya', message: 'Aset tidak memengaruhi saldo rekening. Pakai untuk melihat nilai barang atau kekayaan keluarga.', icon: Icons.info_outline),
      const SizedBox(height: 16),
      TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nama aset')),
      const SizedBox(height: 12),
      TextField(controller: _type, decoration: const InputDecoration(labelText: 'Jenis aset')),
      const SizedBox(height: 12),
      TextField(controller: _value, keyboardType: TextInputType.number, inputFormatters: [RupiahInputFormatter()], decoration: const InputDecoration(labelText: 'Nilai perkiraan')),
      const SizedBox(height: 12),
      TextField(controller: _placement, decoration: const InputDecoration(labelText: 'Lokasi')),
      const SizedBox(height: 20),
      FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_outlined), label: const Text('Simpan aset')),
    ]),
  );
}
