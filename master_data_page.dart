import 'package:flutter/material.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_context.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../shared/widgets/app_components.dart';

class MasterDataPage extends StatefulWidget {
  const MasterDataPage({super.key});
  @override
  State<MasterDataPage> createState() => _MasterDataPageState();
}

class _MasterDataPageState extends State<MasterDataPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _database = getIt<AppDatabase>();
  var _loading = true;
  String _householdName = 'Keluarga';
  String? _husbandName;
  String? _wifeName;

  @override
  void initState() { super.initState(); _tabs = TabController(length: 5, vsync: this); _loadProfile(); }
  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  Future<void> _loadProfile() async {
    final row = await (_database.select(_database.households)..where((item) => item.id.equals(AppContext.householdId))).getSingleOrNull();
    if (mounted) setState(() { _loading = false; _householdName = row?.name ?? 'Keluarga'; _husbandName = row?.husbandName; _wifeName = row?.wifeName; });
  }

  Future<void> _editProfile() async {
    final result = await showDialog<_ProfileValues>(context: context, builder: (_) => _ProfileDialog(initial: _ProfileValues(_householdName, _husbandName ?? '', _wifeName ?? '')));
    if (result == null) return;
    final now = DateTime.now();
    await _database.into(_database.households).insertOnConflictUpdate(HouseholdsCompanion.insert(
      id: AppContext.householdId, name: result.householdName.isEmpty ? 'Keluarga' : result.householdName, husbandName: Value(result.husbandName.isEmpty ? null : result.husbandName), wifeName: Value(result.wifeName.isEmpty ? null : result.wifeName), createdAt: now, updatedAt: Value(now),
    ));
    await _saveParty(result.husbandName, 'husband');
    await _saveParty(result.wifeName, 'wife');
    if (mounted) { setState(() { _householdName = result.householdName.isEmpty ? 'Keluarga' : result.householdName; _husbandName = result.husbandName; _wifeName = result.wifeName; }); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profil keluarga sudah disimpan.'))); }
  }

  Future<void> _saveParty(String name, String kind) async {
    final existing = await (_database.select(_database.transactionParties)..where((row) => row.householdId.equals(AppContext.householdId) & row.kind.equals(kind))).getSingleOrNull();
    if (name.trim().isEmpty) {
      if (existing != null) {
        await (_database.update(_database.transactionParties)..where((row) => row.id.equals(existing.id))).write(const TransactionPartiesCompanion(isArchived: Value(true)));
      }
      return;
    }
    await _database.into(_database.transactionParties).insertOnConflictUpdate(TransactionPartiesCompanion.insert(
      id: existing?.id ?? const Uuid().v4(), householdId: AppContext.householdId, name: name.trim(), role: Value(kind == 'husband' ? 'Suami' : 'Istri'), kind: Value(kind), details: Value(null), isArchived: const Value(false), createdAt: existing?.createdAt ?? DateTime.now(),
    ));
  }

  Future<List<_MasterItem>> _items(int tab) async {
    switch (tab) {
      case 0:
        final rows = await (_database.select(_database.categories)..where((row) => row.householdId.equals(AppContext.householdId) & row.isActive.equals(true))).get();
        return rows.map((row) => _MasterItem(row.id, row.name, row.type == 'income' ? 'Pemasukan' : 'Pengeluaran')).toList();
      case 1:
        final rows = await (_database.select(_database.merchants)..where((row) => row.householdId.equals(AppContext.householdId) & row.isActive.equals(true))).get();
        return rows.map((row) => _MasterItem(row.id, row.name, row.details ?? 'Toko/tempat')).toList();
      case 2:
        final rows = await (_database.select(_database.tags)..where((row) => row.householdId.equals(AppContext.householdId))).get();
        return rows.map((row) => _MasterItem(row.id, row.name, 'Tag transaksi')).toList();
      case 3:
        final rows = await (_database.select(_database.accounts)..where((row) => row.householdId.equals(AppContext.householdId) & row.isArchived.equals(false))).get();
        return rows.map((row) => _MasterItem(row.id, row.name, row.type)).toList();
      default:
        final rows = await (_database.select(_database.transactionParties)..where((row) => row.householdId.equals(AppContext.householdId) & row.isArchived.equals(false) & row.kind.equals('income_source'))).get();
        return rows.map((row) => _MasterItem(row.id, row.name, 'Sumber pemasukan')).toList();
    }
  }

  Future<void> _add(int tab) async {
    final result = await showDialog<String>(context: context, builder: (_) => _TextEntryDialog(title: _tabTitle(tab), hint: tab == 3 ? 'Misal: Tunai, Bank, E-wallet' : 'Tulis nama yang mudah dicari'));
    if (result == null || result.trim().isEmpty) return;
    final id = const Uuid().v4();
    final name = result.trim();
    final now = DateTime.now();
    switch (tab) {
      case 0:
        final type = await showDialog<String>(context: context, builder: (_) => _ChoiceDialog(title: 'Kategori ini buat apa?', choices: const {'income': 'Pemasukan', 'expense': 'Pengeluaran'}));
        if (type == null) return;
        await _database.into(_database.categories).insert(CategoriesCompanion.insert(id: id, householdId: AppContext.householdId, name: name, type: type, createdAt: now));
        return;
      case 1:
        await _database.into(_database.merchants).insert(MerchantsCompanion.insert(id: id, householdId: AppContext.householdId, name: name, createdAt: now));
        return;
      case 2:
        await _database.into(_database.tags).insert(TagsCompanion.insert(id: id, householdId: AppContext.householdId, name: name, createdAt: now));
        return;
      case 3:
        await _database.into(_database.accounts).insert(AccountsCompanion.insert(id: id, householdId: AppContext.householdId, name: name, type: 'cash', createdAt: now));
        return;
      default:
        await _database.into(_database.transactionParties).insert(TransactionPartiesCompanion.insert(id: id, householdId: AppContext.householdId, name: name, kind: const Value('income_source'), role: const Value('Sumber pemasukan'), createdAt: now));
        return;
    }
  }

  String _tabTitle(int tab) => const ['Tambah kategori', 'Tambah toko/tempat', 'Tambah tag', 'Tambah rekening', 'Tambah sumber pemasukan'][tab];

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Data Utama'), actions: [IconButton(onPressed: _editProfile, tooltip: 'Profil keluarga', icon: const Icon(Icons.family_restroom_outlined))]),
    body: Column(children: [
      if (!_loading) Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4), child: AppCard(color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: .45), child: ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.family_restroom_outlined), title: Text(_householdName, style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text([_husbandName, _wifeName].whereType<String>().where((item) => item.trim().isNotEmpty).join(' • ').isEmpty ? 'Profil keluarga belum lengkap' : [_husbandName, _wifeName].whereType<String>().where((item) => item.trim().isNotEmpty).join(' • ')), trailing: const Icon(Icons.edit_outlined), onTap: _editProfile))),
      TabBar(controller: _tabs, isScrollable: true, tabAlignment: TabAlignment.start, tabs: const [Tab(text: 'Kategori'), Tab(text: 'Toko'), Tab(text: 'Tag'), Tab(text: 'Rekening'), Tab(text: 'Sumber')]),
      Expanded(child: TabBarView(controller: _tabs, children: List.generate(5, (index) => _MasterList(tab: index, load: () => _items(index), title: _tabTitle(index), onAdd: () => _add(index))))),
    ]),
  );
}

class _MasterItem { const _MasterItem(this.id, this.name, this.subtitle); final String id; final String name; final String subtitle; }

class _MasterList extends StatelessWidget {
  const _MasterList({required this.tab, required this.load, required this.title, required this.onAdd});
  final int tab; final Future<List<_MasterItem>> Function() load; final String title; final VoidCallback onAdd;
  @override
  Widget build(BuildContext context) => FutureBuilder<List<_MasterItem>>(future: load(), builder: (context, snapshot) {
    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
    final items = snapshot.data!;
    return RefreshIndicator(onRefresh: () async { (context as Element).markNeedsBuild(); }, child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 120), children: [
      AppHelpBanner(title: '${_label(tab)} yang kamu atur sendiri', message: 'Semua pilihan di transaksi berasal dari sini. Kalau kosong, isi sesuai kebutuhanmu.', icon: Icons.tune_outlined),
      const SizedBox(height: 12),
      if (items.isEmpty) AppEmptyState(icon: Icons.inbox_outlined, title: 'Belum ada data', message: 'Tambahkan ${title.toLowerCase()} pertama supaya pilihan transaksi lebih jelas.', action: FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: Text(title))) else ...items.map((item) => Padding(padding: const EdgeInsets.only(bottom: 8), child: AppCard(child: ListTile(title: Text(item.name), subtitle: Text(item.subtitle), trailing: const Icon(Icons.chevron_right))))),
    ]));
  });
  static String _label(int tab) => const ['Kategori', 'Toko', 'Tag', 'Rekening', 'Sumber pemasukan'][tab];
}

class _TextEntryDialog extends StatefulWidget {
  const _TextEntryDialog({required this.title, required this.hint});
  final String title; final String hint;
  @override State<_TextEntryDialog> createState() => _TextEntryDialogState();
}
class _TextEntryDialogState extends State<_TextEntryDialog> {
  final _controller = TextEditingController();
  @override void dispose() { _controller.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AlertDialog(title: Text(widget.title), content: TextField(controller: _controller, autofocus: true, decoration: InputDecoration(hintText: widget.hint)), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')), FilledButton(onPressed: () => Navigator.pop(context, _controller.text), child: const Text('Simpan'))]);
}

class _ChoiceDialog extends StatelessWidget {
  const _ChoiceDialog({required this.title, required this.choices});
  final String title; final Map<String, String> choices;
  @override Widget build(BuildContext context) => AlertDialog(title: Text(title), content: Column(mainAxisSize: MainAxisSize.min, children: choices.entries.map((entry) => ListTile(title: Text(entry.value), onTap: () => Navigator.pop(context, entry.key))).toList()));
}

class _ProfileValues { const _ProfileValues(this.householdName, this.husbandName, this.wifeName); final String householdName; final String husbandName; final String wifeName; }
class _ProfileDialog extends StatefulWidget {
  const _ProfileDialog({required this.initial}); final _ProfileValues initial;
  @override State<_ProfileDialog> createState() => _ProfileDialogState();
}
class _ProfileDialogState extends State<_ProfileDialog> {
  late final TextEditingController _household; late final TextEditingController _husband; late final TextEditingController _wife;
  @override void initState() { super.initState(); _household = TextEditingController(text: widget.initial.householdName); _husband = TextEditingController(text: widget.initial.husbandName); _wife = TextEditingController(text: widget.initial.wifeName); }
  @override void dispose() { _household.dispose(); _husband.dispose(); _wife.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AlertDialog(title: const Text('Profil keluarga'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: _household, decoration: const InputDecoration(labelText: 'Nama rumah tangga')), TextField(controller: _husband, decoration: const InputDecoration(labelText: 'Nama Suami')), TextField(controller: _wife, decoration: const InputDecoration(labelText: 'Nama Istri'))])), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')), FilledButton(onPressed: () => Navigator.pop(context, _ProfileValues(_household.text.trim(), _husband.text.trim(), _wife.text.trim())), child: const Text('Simpan'))]);
}
