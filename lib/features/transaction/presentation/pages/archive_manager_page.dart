import 'package:flutter/material.dart';
import 'package:drift/drift.dart' hide Column;

import '../../../../core/database/app_context.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/audit_logger.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../data_retention/presentation/pages/data_retention_manager_page.dart';
import '../../domain/entities/transaction_entity.dart';
import '../../domain/usecases/transaction_crud_usecases.dart';

class ArchiveManagerPage extends StatefulWidget {
  const ArchiveManagerPage({super.key});

  @override
  State<ArchiveManagerPage> createState() => _ArchiveManagerPageState();
}

class _ArchiveManagerPageState extends State<ArchiveManagerPage> {
  final _items = <TransactionWithItems>[];
  var _loading = true;
  var _loadingMore = false;
  var _hasMore = true;
  final _selectedIds = <String>{};
  static const _pageSize = 50;

  @override
  void initState() {
    super.initState();
    _loadArchived();
  }

  Future<void> _loadArchived() async {
    setState(() {
      _loading = true;
      _hasMore = true;
      _selectedIds.clear();
    });
    final result = await _fetchPage(0);
    if (!mounted) return;
    setState(() {
      _items
        ..clear()
        ..addAll(result.items);
      _hasMore = result.hasMore;
      _loading = false;
    });
  }

  Future<TransactionPageResult> _fetchPage(int offset) async {
    final database = getIt<AppDatabase>();
    final query = database.select(database.transactions)
      ..where(
        (row) =>
            row.householdId.equals(AppContext.householdId) &
            row.isArchived.equals(true),
      );
    final countQuery = database.selectOnly(database.transactions)
      ..addColumns([database.transactions.id.count()])
      ..where(
        database.transactions.householdId.equals(AppContext.householdId) &
        database.transactions.isArchived.equals(true),
      );
    final countResult = await countQuery.getSingle();
    final totalCount =
        countResult.read(database.transactions.id.count()) ?? 0;
    query
      ..orderBy([
        (row) => OrderingTerm.desc(row.date),
        (row) => OrderingTerm.desc(row.id),
      ])
      ..limit(_pageSize, offset: offset);
    final rows = await query.get();
    if (rows.isEmpty) {
      return TransactionPageResult(
        items: const [],
        hasMore: false,
        totalCount: totalCount,
      );
    }
    final ids = rows.map((row) => row.id).toSet();
    final itemRows = await (database.select(
      database.transactionItems,
    )..where((row) => row.transactionId.isIn(ids))).get();
    final byTx = <String, List<TransactionItem>>{};
    for (final item in itemRows) {
      (byTx[item.transactionId] ??= <TransactionItem>[]).add(item);
    }
    return TransactionPageResult(
      items: rows
          .map(
            (row) => TransactionWithItems(
              transaction: row,
              items: byTx[row.id] ?? const [],
            ),
          )
          .toList(growable: false),
      hasMore: offset + _pageSize < totalCount,
      totalCount: totalCount,
    );
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final result = await _fetchPage(_items.length);
    if (!mounted) return;
    setState(() {
      _items.addAll(result.items);
      _hasMore = result.hasMore;
      _loadingMore = false;
    });
  }

  void _toggleAll() {
    setState(() {
      if (_selectedIds.length == _items.length) {
        _selectedIds.clear();
      } else {
        _selectedIds.addAll(_items.map((e) => e.transaction.id));
      }
    });
  }

  void _toggleItem(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  String _money(int value) {
    final abs = value.abs();
    final formatted = abs.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]}.',
    );
    return 'Rp $formatted';
  }

  Future<void> _restoreSelected() async {
    if (_selectedIds.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pulihkan Transaksi'),
        content: Text(
          'Pulihkan ${_selectedIds.length} transaksi terarsip? '
          'Data akan muncul kembali di daftar utama.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Pulihkan'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final database = getIt<AppDatabase>();
    final auditLogger = AuditLogger(database);
    var count = 0;
    for (final id in _selectedIds) {
      try {
        await (database.update(database.transactions)..where(
              (row) =>
                  row.householdId.equals(AppContext.householdId) &
                  row.id.equals(id),
            ))
            .write(
              const TransactionsCompanion(
                isArchived: Value(false),
                isDeleted: Value(false),
              ),
            );
        await auditLogger.record(
          action: 'pulihkan',
          entity: 'transaksi',
          newValue: {'id': id},
        );
        count++;
      } catch (_) {}
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$count transaksi dipulihkan.')),
    );
    await _loadArchived();
  }

  Future<void> _permanentDeleteSelected() async {
    if (_selectedIds.isEmpty) return;
    final confirmed1 = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(
          Icons.warning_amber_rounded,
          color: AppColors.negative,
        ),
        title: const Text('Hapus Permanen?'),
        content: Text(
          'Anda akan menghapus ${_selectedIds.length} transaksi secara '
          'permanen. Tindakan ini tidak dapat dibatalkan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.negative,
            ),
            child: const Text('Lanjutkan'),
          ),
        ],
      ),
    );
    if (confirmed1 != true || !mounted) return;
    final confirmed2 = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(
          Icons.delete_forever,
          color: AppColors.negative,
        ),
        title: const Text('Konfirmasi Akhir'),
        content: const Text(
          'Anda yakin ingin menghapus transaksi ini secara permanen?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.negative,
            ),
            child: const Text('Hapus Sekarang'),
          ),
        ],
      ),
    );
    if (confirmed2 != true || !mounted) return;
    final database = getIt<AppDatabase>();
    final auditLogger = AuditLogger(database);
    var count = 0;
    for (final id in _selectedIds) {
      try {
        await (database.update(database.transactions)..where(
              (row) =>
                  row.householdId.equals(AppContext.householdId) &
                  row.id.equals(id),
            ))
            .write(
              const TransactionsCompanion(
                isDeleted: Value(true),
              ),
            );
        await auditLogger.record(
          action: 'hapus_permanen',
          entity: 'transaksi',
          oldValue: {'id': id},
        );
        count++;
      } catch (_) {}
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$count transaksi dihapus permanen.')),
    );
    await _loadArchived();
  }

  @override
  Widget build(BuildContext context) {
    final hasSelection = _selectedIds.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          hasSelection
              ? '${_selectedIds.length} dipilih'
              : 'Arsip Transaksi',
        ),
        leading: hasSelection
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _selectedIds.clear()),
              )
            : null,
        actions: [
          if (hasSelection) ...[
            IconButton(
              tooltip: 'Pulihkan',
              onPressed: _restoreSelected,
              icon: const Icon(Icons.restore),
            ),
            IconButton(
              tooltip: 'Hapus permanen',
              onPressed: _permanentDeleteSelected,
              icon: const Icon(Icons.delete_forever),
            ),
          ] else ...[
            IconButton(
              tooltip: 'Pilih semua',
              onPressed: _items.isEmpty ? null : _toggleAll,
              icon: Icon(
                _selectedIds.length == _items.length
                    ? Icons.check_box
                    : Icons.check_box_outline_blank,
              ),
            ),
            IconButton(
              tooltip: 'Retensi & Arsip',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const DataRetentionManagerPage(),
                ),
              ),
              icon: const Icon(Icons.inventory_rounded),
            ),
          ],
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
          ? ListView(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
              children: const [
                Center(
                  child: Text(
                    'Tidak ada transaksi terarsip.',
                    style: TextStyle(color: AppColors.inkMuted),
                  ),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 56),
              itemCount: _items.length + (_hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _items.length) {
                  if (_loadingMore) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    );
                  }
                  return TextButton(
                    onPressed: _loadMore,
                    child: const Text('Muat lebih banyak'),
                  );
                }
                final entry = _items[index];
                final item = entry.transaction;
                final isIncome = item.amount >= 0;
                final isDeleted = item.isDeleted;
                final isSelected = _selectedIds.contains(item.id);
                final color = isIncome
                    ? AppColors.positive
                    : AppColors.negative;
                return Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  color: isSelected
                      ? Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withValues(alpha: .3)
                      : null,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: color.withValues(alpha: .14),
                      foregroundColor: color,
                      child: Icon(
                        isIncome
                            ? Icons.south_west_rounded
                            : Icons.north_east_rounded,
                        size: 18,
                      ),
                    ),
                    title: Text(
                      _money(item.amount.abs()),
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      '${item.date.day}/${item.date.month}/${item.date.year}'
                      '${isDeleted ? ' (dihapus)' : ''}',
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check_circle, color: AppColors.primary)
                        : null,
                    onTap: () => _toggleItem(item.id),
                    onLongPress: () => _toggleItem(item.id),
                  ),
                );
              },
            ),
      floatingActionButton: hasSelection
          ? null
          : FloatingActionButton.extended(
              heroTag: 'archive_back',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Kembali'),
            ),
    );
  }
}
