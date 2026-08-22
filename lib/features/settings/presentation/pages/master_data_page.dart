import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_context.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../assistant/domain/ffm_assistant_models.dart';
import '../../../assistant/presentation/widgets/ffm_assistant_page_context.dart';
import '../../../../shared/widgets/app_components.dart';

class MasterDataPage extends StatefulWidget {
  const MasterDataPage({
    super.key,
    this.assistantTab,
    this.assistantName,
    this.assistantProfileName,
  });

  final int? assistantTab;
  final String? assistantName;
  final String? assistantProfileName;

  @override
  State<MasterDataPage> createState() => _MasterDataPageState();
}

class _MasterDataPageState extends State<MasterDataPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _database = getIt<AppDatabase>();
  var _loading = true;
  var _refreshTick = 0;
  var _activeTab = 0;
  String _householdName = 'Keluarga';
  String? _husbandName;
  String? _wifeName;

  static const _tabLabels = [
    'Kategori',
    'Toko/tempat',
    'Tag',
    'Rekening',
    'Sumber pemasukan',
  ];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _tabLabels.length, vsync: this)
      ..addListener(_onTabChanged);
    _loadProfile();
    if (widget.assistantProfileName?.trim().isNotEmpty == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _editProfile(initialHouseholdName: widget.assistantProfileName);
        }
      });
    }
    final tab = widget.assistantTab;
    if (tab != null && tab >= 0 && tab < _tabLabels.length) {
      _tabs.index = tab;
      _activeTab = tab;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _edit(tab, null, assistantName: widget.assistantName);
        }
      });
    }
  }

  @override
  void dispose() {
    _tabs
      ..removeListener(_onTabChanged)
      ..dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabs.indexIsChanging || _activeTab == _tabs.index) return;
    setState(() => _activeTab = _tabs.index);
  }

  Future<void> _loadProfile() async {
    final row =
        await (_database.select(_database.households)
              ..where((item) => item.id.equals(AppContext.householdId)))
            .getSingleOrNull();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _householdName = row?.name ?? 'Keluarga';
      _husbandName = row?.husbandName;
      _wifeName = row?.wifeName;
    });
  }

  Future<void> _editProfile({String? initialHouseholdName}) async {
    final result = await showDialog<_ProfileValues>(
      context: context,
      builder: (_) => _ProfileDialog(
        initial: _ProfileValues(
          initialHouseholdName?.trim().isNotEmpty == true
              ? initialHouseholdName!.trim()
              : _householdName,
          _husbandName ?? '',
          _wifeName ?? '',
        ),
      ),
    );
    if (result == null) return;
    final now = DateTime.now();
    await _database
        .into(_database.households)
        .insertOnConflictUpdate(
          HouseholdsCompanion.insert(
            id: AppContext.householdId,
            name: result.householdName.isEmpty
                ? 'Keluarga'
                : result.householdName,
            husbandName: Value(
              result.husbandName.isEmpty ? null : result.husbandName,
            ),
            wifeName: Value(result.wifeName.isEmpty ? null : result.wifeName),
            createdAt: now,
            updatedAt: Value(now),
          ),
        );
    await _saveParty(result.husbandName, 'husband');
    await _saveParty(result.wifeName, 'wife');
    if (!mounted) return;
    setState(() {
      _householdName = result.householdName.isEmpty
          ? 'Keluarga'
          : result.householdName;
      _husbandName = result.husbandName;
      _wifeName = result.wifeName;
      _refreshTick++;
    });
    _showMessage('Profil keluarga sudah disimpan.');
  }

  Future<void> _saveParty(String name, String kind) async {
    final existing =
        await (_database.select(_database.transactionParties)..where(
              (row) =>
                  row.householdId.equals(AppContext.householdId) &
                  row.kind.equals(kind),
            ))
            .getSingleOrNull();
    if (name.trim().isEmpty) {
      if (existing != null) {
        await (_database.update(_database.transactionParties)
              ..where((row) => row.id.equals(existing.id)))
            .write(const TransactionPartiesCompanion(isArchived: Value(true)));
      }
      return;
    }
    await _database
        .into(_database.transactionParties)
        .insertOnConflictUpdate(
          TransactionPartiesCompanion.insert(
            id: existing?.id ?? const Uuid().v4(),
            householdId: AppContext.householdId,
            name: name.trim(),
            role: Value(kind == 'husband' ? 'Suami' : 'Istri'),
            kind: Value(kind),
            details: const Value(null),
            isArchived: const Value(false),
            createdAt: existing?.createdAt ?? DateTime.now(),
          ),
        );
  }

  Future<List<_MasterItem>> _items(int tab) async {
    switch (tab) {
      case 0:
        final rows =
            await (_database.select(_database.categories)
                  ..where(
                    (row) =>
                        row.householdId.equals(AppContext.householdId) &
                        row.isActive.equals(true),
                  )
                  ..orderBy([(row) => OrderingTerm.asc(row.name)]))
                .get();
        final parents = {for (final row in rows) row.id: row.name};
        return rows
            .map(
              (row) => _MasterItem(
                id: row.id,
                name: row.name,
                subtitle:
                    '${row.type == 'income' ? 'Pemasukan' : 'Pengeluaran'}${row.parentId == null ? '' : ' · ${parents[row.parentId] ?? 'Subkategori'}'}${_budgetPeriodLabel(row.defaultBudgetPeriod)}',
              ),
            )
            .toList();
      case 1:
        final rows =
            await (_database.select(_database.merchants)
                  ..where(
                    (row) =>
                        row.householdId.equals(AppContext.householdId) &
                        row.isActive.equals(true),
                  )
                  ..orderBy([(row) => OrderingTerm.asc(row.name)]))
                .get();
        return rows
            .map(
              (row) => _MasterItem(
                id: row.id,
                name: row.name,
                subtitle: row.details?.trim().isNotEmpty == true
                    ? row.details!
                    : 'Toko/tempat aktif',
              ),
            )
            .toList();
      case 2:
        final rows =
            await (_database.select(_database.tags)
                  ..where(
                    (row) =>
                        row.householdId.equals(AppContext.householdId) &
                        row.isArchived.equals(false),
                  )
                  ..orderBy([(row) => OrderingTerm.asc(row.name)]))
                .get();
        return rows
            .map(
              (row) => _MasterItem(
                id: row.id,
                name: row.name,
                subtitle: 'Penanda tambahan transaksi',
              ),
            )
            .toList();
      case 3:
        final rows =
            await (_database.select(_database.accounts)
                  ..where(
                    (row) =>
                        row.householdId.equals(AppContext.householdId) &
                        row.isArchived.equals(false),
                  )
                  ..orderBy([(row) => OrderingTerm.asc(row.name)]))
                .get();
        return rows
            .map(
              (row) => _MasterItem(
                id: row.id,
                name: row.name,
                subtitle:
                    '${_accountTypeLabel(row.type)} · Saldo awal ${_formatRupiah(row.openingBalance)}',
              ),
            )
            .toList();
      default:
        final rows =
            await (_database.select(_database.transactionParties)
                  ..where(
                    (row) =>
                        row.householdId.equals(AppContext.householdId) &
                        row.isArchived.equals(false) &
                        row.kind.equals('income_source'),
                  )
                  ..orderBy([(row) => OrderingTerm.asc(row.name)]))
                .get();
        return rows
            .map(
              (row) => _MasterItem(
                id: row.id,
                name: row.name,
                subtitle: row.details?.trim().isNotEmpty == true
                    ? row.details!
                    : 'Sumber uang masuk',
              ),
            )
            .toList();
    }
  }

  Future<List<_CategoryParent>> _categoryParents({String? excludeId}) async {
    final rows =
        await (_database.select(_database.categories)
              ..where(
                (row) =>
                    row.householdId.equals(AppContext.householdId) &
                    row.isActive.equals(true),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.name)]))
            .get();
    return rows
        .where((row) => row.id != excludeId)
        .map((row) => _CategoryParent(row.id, row.name, row.type))
        .toList();
  }

  Future<void> _add(int tab) async {
    await _edit(tab, null);
  }

  Future<void> _edit(
    int tab,
    _MasterItem? item, {
    String? assistantName,
  }) async {
    final initial = await _loadFormValues(tab, item?.id);
    if (!mounted) return;
    final parents = tab == 0
        ? await _categoryParents(excludeId: item?.id)
        : const <_CategoryParent>[];
    if (!mounted) return;
    final result = await showDialog<_MasterFormValues>(
      context: context,
      builder: (_) => _MasterEditorDialog(
        tab: tab,
        initial: assistantName?.trim().isNotEmpty == true
            ? _MasterFormValues(
                name: assistantName!.trim(),
                type: initial.type,
                parentId: initial.parentId,
                details: initial.details,
                accountType: initial.accountType,
                openingBalance: initial.openingBalance,
                defaultBudgetPeriod: initial.defaultBudgetPeriod,
              )
            : initial,
        parents: parents,
      ),
    );
    if (result == null) return;
    final duplicate = await _hasDuplicate(tab, result, item?.id);
    if (duplicate) {
      _showMessage('Nama itu sudah ada di Data Utama. Coba nama lain.');
      return;
    }
    await _saveMaster(tab, result, item?.id);
    if (!mounted) return;
    setState(() => _refreshTick++);
    _showMessage(
      item == null ? 'Data sudah ditambahkan.' : 'Data sudah diperbarui.',
    );
  }

  Future<_MasterFormValues> _loadFormValues(int tab, String? id) async {
    if (id == null) return _MasterFormValues.forTab(tab);
    switch (tab) {
      case 0:
        final row = await (_database.select(
          _database.categories,
        )..where((item) => item.id.equals(id))).getSingle();
        return _MasterFormValues(
          name: row.name,
          type: row.type,
          parentId: row.parentId,
          defaultBudgetPeriod: row.defaultBudgetPeriod,
        );
      case 1:
        final row = await (_database.select(
          _database.merchants,
        )..where((item) => item.id.equals(id))).getSingle();
        return _MasterFormValues(name: row.name, details: row.details ?? '');
      case 2:
        final row = await (_database.select(
          _database.tags,
        )..where((item) => item.id.equals(id))).getSingle();
        return _MasterFormValues(name: row.name);
      case 3:
        final row = await (_database.select(
          _database.accounts,
        )..where((item) => item.id.equals(id))).getSingle();
        return _MasterFormValues(
          name: row.name,
          accountType: row.type,
          openingBalance: row.openingBalance,
        );
      default:
        final row = await (_database.select(
          _database.transactionParties,
        )..where((item) => item.id.equals(id))).getSingle();
        return _MasterFormValues(name: row.name, details: row.details ?? '');
    }
  }

  Future<bool> _hasDuplicate(
    int tab,
    _MasterFormValues values,
    String? currentId,
  ) async {
    final normalized = values.name.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    switch (tab) {
      case 0:
        final rows =
            await (_database.select(_database.categories)..where(
                  (row) =>
                      row.householdId.equals(AppContext.householdId) &
                      row.isActive.equals(true),
                ))
                .get();
        return rows.any(
          (row) =>
              row.id != currentId &&
              row.name.trim().toLowerCase() == normalized &&
              row.type == values.type,
        );
      case 1:
        final rows =
            await (_database.select(_database.merchants)..where(
                  (row) =>
                      row.householdId.equals(AppContext.householdId) &
                      row.isActive.equals(true),
                ))
                .get();
        return rows.any(
          (row) =>
              row.id != currentId &&
              row.name.trim().toLowerCase() == normalized,
        );
      case 2:
        final rows =
            await (_database.select(_database.tags)..where(
                  (row) =>
                      row.householdId.equals(AppContext.householdId) &
                      row.isArchived.equals(false),
                ))
                .get();
        return rows.any(
          (row) =>
              row.id != currentId &&
              row.name.trim().toLowerCase() == normalized,
        );
      case 3:
        final rows =
            await (_database.select(_database.accounts)..where(
                  (row) =>
                      row.householdId.equals(AppContext.householdId) &
                      row.isArchived.equals(false),
                ))
                .get();
        return rows.any(
          (row) =>
              row.id != currentId &&
              row.name.trim().toLowerCase() == normalized,
        );
      default:
        final rows =
            await (_database.select(_database.transactionParties)..where(
                  (row) =>
                      row.householdId.equals(AppContext.householdId) &
                      row.isArchived.equals(false) &
                      row.kind.equals('income_source'),
                ))
                .get();
        return rows.any(
          (row) =>
              row.id != currentId &&
              row.name.trim().toLowerCase() == normalized,
        );
    }
  }

  Future<void> _saveMaster(
    int tab,
    _MasterFormValues values,
    String? existingId,
  ) async {
    final id = existingId ?? const Uuid().v4();
    final now = DateTime.now();
    switch (tab) {
      case 0:
        final companion = CategoriesCompanion(
          id: Value(id),
          householdId: const Value(AppContext.householdId),
          name: Value(values.name.trim()),
          type: Value(values.type),
          parentId: Value(values.parentId),
          defaultBudgetPeriod: Value(values.defaultBudgetPeriod),
          createdAt: Value(now),
        );
        if (existingId == null) {
          await _database.into(_database.categories).insert(companion);
        } else {
          await (_database.update(
            _database.categories,
          )..where((row) => row.id.equals(existingId))).write(
            CategoriesCompanion(
              name: Value(values.name.trim()),
              type: Value(values.type),
              parentId: Value(values.parentId),
              defaultBudgetPeriod: Value(values.defaultBudgetPeriod),
            ),
          );
        }
      case 1:
        if (existingId == null) {
          await _database
              .into(_database.merchants)
              .insert(
                MerchantsCompanion.insert(
                  id: id,
                  householdId: AppContext.householdId,
                  name: values.name.trim(),
                  details: Value(_nullableText(values.details)),
                  createdAt: now,
                ),
              );
        } else {
          await (_database.update(
            _database.merchants,
          )..where((row) => row.id.equals(existingId))).write(
            MerchantsCompanion(
              name: Value(values.name.trim()),
              details: Value(_nullableText(values.details)),
            ),
          );
        }
      case 2:
        if (existingId == null) {
          await _database
              .into(_database.tags)
              .insert(
                TagsCompanion.insert(
                  id: id,
                  householdId: AppContext.householdId,
                  name: values.name.trim(),
                  createdAt: now,
                ),
              );
        } else {
          await (_database.update(_database.tags)
                ..where((row) => row.id.equals(existingId)))
              .write(TagsCompanion(name: Value(values.name.trim())));
        }
      case 3:
        if (existingId == null) {
          await _database
              .into(_database.accounts)
              .insert(
                AccountsCompanion.insert(
                  id: id,
                  householdId: AppContext.householdId,
                  name: values.name.trim(),
                  type: values.accountType,
                  openingBalance: Value(values.openingBalance),
                  createdAt: now,
                ),
              );
        } else {
          await (_database.update(
            _database.accounts,
          )..where((row) => row.id.equals(existingId))).write(
            AccountsCompanion(
              name: Value(values.name.trim()),
              type: Value(values.accountType),
              openingBalance: Value(values.openingBalance),
            ),
          );
        }
      default:
        if (existingId == null) {
          await _database
              .into(_database.transactionParties)
              .insert(
                TransactionPartiesCompanion.insert(
                  id: id,
                  householdId: AppContext.householdId,
                  name: values.name.trim(),
                  role: const Value('Sumber pemasukan'),
                  kind: const Value('income_source'),
                  details: Value(_nullableText(values.details)),
                  createdAt: now,
                ),
              );
        } else {
          await (_database.update(
            _database.transactionParties,
          )..where((row) => row.id.equals(existingId))).write(
            TransactionPartiesCompanion(
              name: Value(values.name.trim()),
              details: Value(_nullableText(values.details)),
            ),
          );
        }
    }
  }

  Future<void> _archive(int tab, _MasterItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Sembunyikan ${item.name}?'),
        content: const Text(
          'Data ini tidak akan muncul di transaksi baru, tetapi histori transaksi lama tetap aman.',
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
    switch (tab) {
      case 0:
        await (_database.update(_database.categories)
              ..where((row) => row.id.equals(item.id)))
            .write(const CategoriesCompanion(isActive: Value(false)));
      case 1:
        await (_database.update(_database.merchants)
              ..where((row) => row.id.equals(item.id)))
            .write(const MerchantsCompanion(isActive: Value(false)));
      case 2:
        await (_database.update(_database.tags)
              ..where((row) => row.id.equals(item.id)))
            .write(const TagsCompanion(isArchived: Value(true)));
      case 3:
        await (_database.update(_database.accounts)
              ..where((row) => row.id.equals(item.id)))
            .write(const AccountsCompanion(isArchived: Value(true)));
      default:
        await (_database.update(_database.transactionParties)
              ..where((row) => row.id.equals(item.id)))
            .write(const TransactionPartiesCompanion(isArchived: Value(true)));
    }
    if (!mounted) return;
    setState(() => _refreshTick++);
    _showMessage('${item.name} sudah diarsipkan.');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final profileNames = [
      _husbandName,
      _wifeName,
    ].whereType<String>().where((item) => item.trim().isNotEmpty).join(' • ');
    return FfmAssistantPageContext(
      destination: FfmAssistantDestination.masterData,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Data Utama'),
          actions: [
            IconButton(
              onPressed: _editProfile,
              tooltip: 'Atur profil keluarga',
              icon: const Icon(Icons.family_restroom_outlined),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _add(_activeTab),
          icon: const Icon(Icons.add),
          label: Text('Tambah ${_shortTabLabel(_activeTab)}'),
        ),
        body: Column(
          children: [
            if (!_loading)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: AppCard(
                  color: Theme.of(context).colorScheme.primaryContainer
                      .withValues(alpha: .45),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.family_restroom_outlined),
                    title: Text(
                      _householdName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      profileNames.isEmpty
                          ? 'Profil keluarga belum lengkap'
                          : profileNames,
                    ),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: _editProfile,
                  ),
                ),
              ),
            TabBar(
              controller: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: _tabLabels.map((label) => Tab(text: label)).toList(),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: List.generate(
                  _tabLabels.length,
                  (index) => _MasterList(
                    key: ValueKey('master-$index-$_refreshTick'),
                    tab: index,
                    load: () => _items(index),
                    title: _tabLabels[index],
                    onAdd: () => _add(index),
                    onEdit: (item) => _edit(index, item),
                    onArchive: (item) => _archive(index, item),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _shortTabLabel(int tab) {
    switch (tab) {
      case 1:
        return 'toko';
      case 2:
        return 'tag';
      case 3:
        return 'rekening';
      case 4:
        return 'sumber';
      default:
        return 'kategori';
    }
  }

  static String _budgetPeriodLabel(String period) {
    switch (period) {
      case 'weekly':
        return ' · saran mingguan';
      case 'monthly':
        return ' · saran bulanan';
      default:
        return ' · sesuai kebutuhan';
    }
  }

  static String _accountTypeLabel(String type) {
    switch (type) {
      case 'bank':
        return 'Bank';
      case 'ewallet':
        return 'E-Wallet';
      default:
        return 'Tunai';
    }
  }

  static String _formatRupiah(int value) {
    final digits = value.abs().toString();
    final groups = <String>[];
    for (var end = digits.length; end > 0; end -= 3) {
      final start = (end - 3).clamp(0, end);
      groups.insert(0, digits.substring(start, end));
    }
    return '${value < 0 ? '-' : ''}Rp${groups.join('.')}';
  }

  static String? _nullableText(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

class _MasterItem {
  const _MasterItem({
    required this.id,
    required this.name,
    required this.subtitle,
  });

  final String id;
  final String name;
  final String subtitle;
}

class _MasterList extends StatefulWidget {
  const _MasterList({
    required this.tab,
    required this.load,
    required this.title,
    required this.onAdd,
    required this.onEdit,
    required this.onArchive,
    super.key,
  });

  final int tab;
  final Future<List<_MasterItem>> Function() load;
  final String title;
  final VoidCallback onAdd;
  final ValueChanged<_MasterItem> onEdit;
  final ValueChanged<_MasterItem> onArchive;

  @override
  State<_MasterList> createState() => _MasterListState();
}

class _MasterListState extends State<_MasterList> {
  late Future<List<_MasterItem>> _future;
  final _searchController = TextEditingController();
  var _query = '';

  @override
  void initState() {
    super.initState();
    _future = widget.load();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final next = _searchController.text.trim().toLowerCase();
    if (next == _query) return;
    setState(() => _query = next);
  }

  Future<void> _reload() async {
    setState(() => _future = widget.load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_MasterItem>>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snapshot.data!
            .where(
              (item) =>
                  _query.isEmpty ||
                  item.name.toLowerCase().contains(_query) ||
                  item.subtitle.toLowerCase().contains(_query),
            )
            .toList();
        return RefreshIndicator(
          onRefresh: _reload,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 128),
            children: [
              AppHelpBanner(
                title: '${_label(widget.tab)} kamu',
                message: 'Semua pilihan di transaksi berasal dari sini. Tambahkan seperlunya, lalu arsipkan data yang sudah tidak dipakai supaya histori lama tetap aman.',
                icon: Icons.tune_outlined,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  labelText: 'Cari ${widget.title.toLowerCase()}',
                  hintText: 'Ketik nama atau keterangan',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Bersihkan pencarian',
                          onPressed: _searchController.clear,
                          icon: const Icon(Icons.clear),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              if (snapshot.data!.isEmpty)
                AppEmptyState(
                  icon: Icons.inbox_outlined,
                  title: 'Belum ada data',
                  message:
                      'Tambahkan ${widget.title.toLowerCase()} pertama supaya pilihan transaksi lebih jelas.',
                  action: FilledButton.icon(
                    onPressed: widget.onAdd,
                    icon: const Icon(Icons.add),
                    label: Text('Tambah ${widget.title.toLowerCase()}'),
                  ),
                )
              else if (items.isEmpty)
                AppEmptyState(
                  icon: Icons.search_off_outlined,
                  title: 'Tidak ketemu',
                  message: 'Coba kata kunci lain atau bersihkan pencarian.',
                )
              else
                ...items.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(item.name),
                        subtitle: Text(item.subtitle),
                        trailing: PopupMenuButton<_MasterAction>(
                          tooltip: 'Aksi ${item.name}',
                          onSelected: (action) {
                            switch (action) {
                              case _MasterAction.edit:
                                widget.onEdit(item);
                              case _MasterAction.archive:
                                widget.onArchive(item);
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: _MasterAction.edit,
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.edit_outlined),
                                title: Text('Edit'),
                              ),
                            ),
                            PopupMenuItem(
                              value: _MasterAction.archive,
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.archive_outlined),
                                title: Text('Arsipkan'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  static String _label(int tab) => const [
    'Kategori',
    'Toko/tempat',
    'Tag',
    'Rekening',
    'Sumber pemasukan',
  ][tab];
}

enum _MasterAction { edit, archive }

class _MasterFormValues {
  const _MasterFormValues({
    required this.name,
    this.type = 'expense',
    this.parentId,
    this.details = '',
    this.accountType = 'cash',
    this.openingBalance = 0,
    this.defaultBudgetPeriod = 'none',
  });

  factory _MasterFormValues.forTab(int tab) {
    switch (tab) {
      case 0:
        return const _MasterFormValues(name: '');
      case 3:
        return const _MasterFormValues(name: '', accountType: 'cash');
      default:
        return const _MasterFormValues(name: '');
    }
  }

  final String name;
  final String type;
  final String? parentId;
  final String details;
  final String accountType;
  final int openingBalance;
  final String defaultBudgetPeriod;
}

class _CategoryParent {
  const _CategoryParent(this.id, this.name, this.type);

  final String id;
  final String name;
  final String type;
}

class _MasterEditorDialog extends StatefulWidget {
  const _MasterEditorDialog({
    required this.tab,
    required this.initial,
    required this.parents,
  });

  final int tab;
  final _MasterFormValues initial;
  final List<_CategoryParent> parents;

  @override
  State<_MasterEditorDialog> createState() => _MasterEditorDialogState();
}

class _MasterEditorDialogState extends State<_MasterEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _details;
  late final TextEditingController _openingBalance;
  late String _type;
  late String _accountType;
  late String _defaultBudgetPeriod;
  String? _parentId;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initial.name);
    _details = TextEditingController(text: widget.initial.details);
    _openingBalance = TextEditingController(
      text: widget.initial.openingBalance == 0
          ? ''
          : formatRupiahInput(widget.initial.openingBalance.toString()),
    );
    _type = widget.initial.type;
    _accountType = widget.initial.accountType;
    _defaultBudgetPeriod = widget.initial.defaultBudgetPeriod;
    _parentId = widget.initial.parentId;
  }

  @override
  void dispose() {
    _name.dispose();
    _details.dispose();
    _openingBalance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title =
        '${widget.initial.name.isEmpty ? 'Tambah' : 'Edit'} ${_title(widget.tab)}';
    return AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: _nameLabel(widget.tab),
                  hintText: _hint(widget.tab),
                ),
              ),
              if (widget.tab == 0) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Jenis'),
                  items: const [
                    DropdownMenuItem(
                      value: 'expense',
                      child: Text('Pengeluaran'),
                    ),
                    DropdownMenuItem(value: 'income', child: Text('Pemasukan')),
                  ],
                  onChanged: (value) => setState(() {
                    _type = value ?? 'expense';
                    if (_type == 'income') _defaultBudgetPeriod = 'none';
                  }),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _defaultBudgetPeriod,
                  decoration: const InputDecoration(
                    labelText: 'Saran frekuensi Anggaran',
                    helperText: 'Saran saja, bukan target otomatis. Pilih sesuai kebutuhan kalau tidak rutin.',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'none',
                      child: Text('Sesuai kebutuhan / tidak rutin'),
                    ),
                    DropdownMenuItem(value: 'weekly', child: Text('Mingguan')),
                    DropdownMenuItem(value: 'monthly', child: Text('Bulanan')),
                  ],
                  onChanged: _type == 'income'
                      ? null
                      : (value) => setState(
                          () => _defaultBudgetPeriod = value ?? 'none',
                        ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: _parentId,
                  decoration: const InputDecoration(
                    labelText: 'Induk kategori (opsional)',
                    helperText: 'Kosongkan kalau ini kategori utama.',
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Tidak ada induk'),
                    ),
                    ...widget.parents
                        .where((parent) => parent.type == _type)
                        .map(
                          (parent) => DropdownMenuItem<String?>(
                            value: parent.id,
                            child: Text(parent.name),
                          ),
                        ),
                  ],
                  onChanged: (value) => setState(() => _parentId = value),
                ),
              ],
              if (widget.tab == 1 || widget.tab == 4) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _details,
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: widget.tab == 1
                        ? 'Keterangan tempat (opsional)'
                        : 'Keterangan sumber (opsional)',
                    hintText: widget.tab == 1
                        ? 'Contoh: pasar dekat rumah'
                        : 'Contoh: pemasukan panen mingguan',
                  ),
                ),
              ],
              if (widget.tab == 3) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _accountType,
                  decoration: const InputDecoration(
                    labelText: 'Jenis rekening',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('Tunai')),
                    DropdownMenuItem(value: 'bank', child: Text('Bank')),
                    DropdownMenuItem(value: 'ewallet', child: Text('E-Wallet')),
                  ],
                  onChanged: (value) =>
                      setState(() => _accountType = value ?? 'cash'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _openingBalance,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    RupiahInputFormatter(),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Saldo awal (opsional)',
                    prefixText: 'Rp ',
                    helperText:
                        'Isi hanya jika memang ada saldo sebelum memakai FFM.',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(onPressed: _save, child: const Text('Simpan')),
      ],
    );
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Nama belum diisi.')));
      return;
    }
    Navigator.pop(
      context,
      _MasterFormValues(
        name: name,
        type: _type,
        parentId: _parentId,
        defaultBudgetPeriod: _defaultBudgetPeriod,
        details: _details.text.trim(),
        accountType: _accountType,
        openingBalance: parseRupiah(_openingBalance.text),
      ),
    );
  }

  static String _title(int tab) => const [
    'kategori',
    'toko/tempat',
    'tag',
    'rekening',
    'sumber pemasukan',
  ][tab];

  static String _nameLabel(int tab) => const [
    'Nama kategori',
    'Nama toko/tempat',
    'Nama tag',
    'Nama rekening',
    'Nama sumber pemasukan',
  ][tab];

  static String _hint(int tab) => const [
    'Contoh: Belanja dapur',
    'Contoh: Pasar atau Gojek',
    'Contoh: Wajib atau bisa ditunda',
    'Contoh: Tunai rumah',
    'Contoh: Gaji atau panen pepaya',
  ][tab];
}

class _ProfileValues {
  const _ProfileValues(this.householdName, this.husbandName, this.wifeName);

  final String householdName;
  final String husbandName;
  final String wifeName;
}

class _ProfileDialog extends StatefulWidget {
  const _ProfileDialog({required this.initial});

  final _ProfileValues initial;

  @override
  State<_ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<_ProfileDialog> {
  late final TextEditingController _household;
  late final TextEditingController _husband;
  late final TextEditingController _wife;

  @override
  void initState() {
    super.initState();
    _household = TextEditingController(text: widget.initial.householdName);
    _husband = TextEditingController(text: widget.initial.husbandName);
    _wife = TextEditingController(text: widget.initial.wifeName);
  }

  @override
  void dispose() {
    _household.dispose();
    _husband.dispose();
    _wife.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Profil keluarga'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _household,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Nama rumah tangga'),
          ),
          TextField(
            controller: _husband,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Nama Suami (opsional)',
            ),
          ),
          TextField(
            controller: _wife,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Nama Istri (opsional)',
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Batal'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(
          context,
          _ProfileValues(
            _household.text.trim(),
            _husband.text.trim(),
            _wife.text.trim(),
          ),
        ),
        child: const Text('Simpan'),
      ),
    ],
  );
}
