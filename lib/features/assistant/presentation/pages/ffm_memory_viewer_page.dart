import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/supabase_client_provider.dart';
import '../../../../core/network/supabase_service.dart';
import '../../../settings/presentation/pages/supabase_setup_page.dart';
import '../../data/ffm_assistant_memory_repository.dart';
import '../../data/ffm_personal_memory_control_service.dart';

/// Pusat kontrol untuk memori tahan lama yang telah disetujui dan eligible
/// untuk context engine. Riwayat chat mentah dan draft tidak pernah tampil.
class FfmMemoryViewerPage extends StatefulWidget {
  const FfmMemoryViewerPage({super.key});

  @override
  State<FfmMemoryViewerPage> createState() => _FfmMemoryViewerPageState();
}

class _FfmMemoryViewerPageState extends State<FfmMemoryViewerPage> {
  late final FfmPersonalMemoryControlService _service;
  final _supabase = SupabaseService();
  List<FfmPersonalMemoryControlItem> _items = const [];
  List<FfmPendingMemoryItem> _pendingItems = const [];
  List<Map<String, dynamic>> _cloudItems = const [];
  FfmPersonalMemoryControlScope? _filter;
  String? _error;
  var _loading = true;
  var _loadingCloud = false;
  var _supabaseConnected = false;

  @override
  void initState() {
    super.initState();
    _service = FfmPersonalMemoryControlService(
      getIt<FfmAssistantMemoryRepository>(),
    );
    _load();
    _loadCloud();
  }

  Future<void> _loadCloud() async {
    setState(() => _loadingCloud = true);
    try {
      final client = await SupabaseClientProvider.getInstance();
      if (client == null) {
        if (mounted) {
          setState(() {
            _supabaseConnected = false;
            _cloudItems = const [];
          });
        }
        return;
      }
      final cloud = await _supabase.fetchAll();
      if (mounted) {
        setState(() {
          _supabaseConnected = true;
          _cloudItems = cloud;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _supabaseConnected = false);
    } finally {
      if (mounted) setState(() => _loadingCloud = false);
    }
  }

  Future<void> _deleteCloudItem(String id) async {
    try {
      await _supabase.deleteMemory(id);
      await _loadCloud();
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _service.readVisible(),
        _service.readPendingLearning(),
      ]);
      if (!mounted) return;
      setState(() {
        _items = results[0] as List<FfmPersonalMemoryControlItem>;
        _pendingItems = results[1] as List<FfmPendingMemoryItem>;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Memori belum dapat dimuat. Coba muat ulang.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _approvePending(FfmPendingMemoryItem item) async {
    final ok = await _service.approvePending(item.id);
    if (!mounted) return;
    if (ok) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('“${item.kindLabel}” disetujui dan mulai dipakai Asisten.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Memori belum dapat disetujui. Coba lagi.')),
      );
    }
  }

  Future<void> _rejectPending(FfmPendingMemoryItem item) async {
    try {
      await _service.rejectPending(item.id);
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Usulan memori dibuang tanpa dipakai.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Memori belum dapat dibuang. Coba lagi.')),
      );
    }
  }

  Future<void> _forget(FfmPersonalMemoryControlItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Lupakan memori ini?'),
        content: Text(
          'Asisten tidak akan memakai “${item.label}” pada percakapan berikutnya. Tindakan ini tidak menghapus riwayat chat dan tidak mengubah data keuangan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Lupakan'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.forget(item.id);
      if (!mounted) return;
      setState(
        () => _items = _items.where((entry) => entry.id != item.id).toList(),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Memori dilupakan secara lokal.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Memori belum dapat dilupakan. Coba lagi.'),
        ),
      );
    }
  }

  List<FfmPersonalMemoryControlItem> get _visibleItems => _filter == null
      ? _items
      : _items.where((item) => item.scope == _filter).toList();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Pusat Kontrol Memori'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Lokal'),
              Tab(text: 'Cloud'),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Muat ulang',
              onPressed: _loading ? null : () {
                _load();
                _loadCloud();
              },
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showAddMemoryDialog(context),
          icon: const Icon(Icons.add),
          label: const Text('Tambah Memori'),
        ),
        body: TabBarView(
          children: [
            _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _ErrorState(message: _error!, onRetry: _load)
                    : _buildContent(theme),
            _buildCloudContent(theme),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddMemoryDialog(BuildContext context) async {
    var selectedScope = FfmPersonalMemoryControlScope.userModel;
    var targetStorage = 'local';
    final labelController = TextEditingController();
    final valueController = TextEditingController();
    String? formError;
    var saving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: !saving,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final theme = Theme.of(context);
          final colorScheme = theme.colorScheme;
          final isCloudTarget = targetStorage == 'cloud';
          final canSave = !saving &&
              labelController.text.trim().isNotEmpty &&
              valueController.text.trim().isNotEmpty &&
              (!isCloudTarget || _supabaseConnected);

          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.add_circle_outline),
                SizedBox(width: 8),
                Text('Tambah Memori Manual'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Simpan fakta, preferensi, atau koreksi agar Asisten AI mengingatnya saat berinteraksi.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: targetStorage,
                    decoration: const InputDecoration(
                      labelText: 'Target Penyimpanan',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'local',
                        child: Text('Memori Lokal (HP Saya)'),
                      ),
                      DropdownMenuItem(
                        value: 'cloud',
                        child: Text('Memori Cloud (Supabase)'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() {
                          targetStorage = val;
                          formError = null;
                        });
                      }
                    },
                  ),
                  if (isCloudTarget && !_supabaseConnected) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colorScheme.errorContainer.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colorScheme.error),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.warning_amber_rounded, size: 16, color: colorScheme.error),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Supabase belum terhubung di FFM.',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                    color: colorScheme.onErrorContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Silakan hubungkan Supabase terlebih dahulu atau pilih penyimpanan Memori Lokal.',
                            style: TextStyle(fontSize: 11, color: colorScheme.onErrorContainer),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () {
                                  Navigator.of(dialogContext).pop();
                                  Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => const SupabaseSetupPage()),
                                  ).then((_) {
                                    _load();
                                    _loadCloud();
                                  });
                                },
                                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                                child: const Text('Buka Setup Supabase'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  DropdownButtonFormField<FfmPersonalMemoryControlScope>(
                    initialValue: selectedScope,
                    decoration: const InputDecoration(
                      labelText: 'Kategori Memori',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: FfmPersonalMemoryControlScope.userModel,
                        child: Text('Profil Pengguna (Nama/Domisili)'),
                      ),
                      DropdownMenuItem(
                        value: FfmPersonalMemoryControlScope.personalMemory,
                        child: Text('Preferensi & Kebiasaan Keuangan'),
                      ),
                      DropdownMenuItem(
                        value: FfmPersonalMemoryControlScope.aliasCorrection,
                        child: Text('Koreksi / Catatan Asisten'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => selectedScope = val);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: labelController,
                    decoration: InputDecoration(
                      labelText: 'Topik / Label',
                      hintText: selectedScope == FfmPersonalMemoryControlScope.userModel
                          ? 'Contoh: Nama Panggilan, Domisili, Pekerjaan'
                          : selectedScope == FfmPersonalMemoryControlScope.personalMemory
                              ? 'Contoh: Tanggal Gajian, Batas Makan Siang'
                              : 'Contoh: Koreksi Nama Toko',
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onChanged: (_) => setDialogState(() => formError = null),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: valueController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Isi Fakta Memori',
                      hintText: selectedScope == FfmPersonalMemoryControlScope.userModel
                          ? 'Contoh: Panggil saya Mas Budi'
                          : selectedScope == FfmPersonalMemoryControlScope.personalMemory
                              ? 'Contoh: Gajian setiap tanggal 25'
                              : 'Contoh: Warung Berkah maksudnya Toko Berkah',
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onChanged: (_) => setDialogState(() => formError = null),
                  ),
                  if (formError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      formError!,
                      style: TextStyle(color: colorScheme.error, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.of(dialogContext).pop(),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: !canSave
                    ? null
                    : () async {
                        final label = labelController.text.trim();
                        final value = valueController.text.trim();
                        if (label.isEmpty || value.isEmpty) {
                          setDialogState(() => formError = 'Semua field wajib diisi.');
                          return;
                        }
                        if (!FfmPersonalMemorySafetyPolicy.isSafeForPersonalContext(
                          key: label,
                          value: value,
                        )) {
                          setDialogState(
                            () => formError =
                                'Memori tidak boleh memuat kata sensitif (PIN/password) atau nominal uang di atas 4 digit.',
                          );
                          return;
                        }

                        setDialogState(() => saving = true);
                        try {
                          if (targetStorage == 'local') {
                            await _service.saveManualMemory(
                              label: label,
                              value: value,
                              scope: selectedScope,
                            );
                            await _load();
                          } else {
                            await _supabase.saveMemory(
                              content: '$label: $value',
                              category: selectedScope.name,
                            );
                            await _loadCloud();
                          }
                          if (!context.mounted) return;
                          Navigator.of(dialogContext).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                targetStorage == 'local'
                                    ? 'Memori lokal “$label” berhasil disimpan.'
                                    : 'Memori cloud “$label” berhasil disimpan.',
                              ),
                            ),
                          );
                        } catch (e) {
                          setDialogState(() {
                            saving = false;
                            formError = 'Gagal menyimpan: $e';
                          });
                        }
                      },
                child: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Simpan'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCloudContent(ThemeData theme) {
    if (_loadingCloud) return const Center(child: CircularProgressIndicator());
    if (!_supabaseConnected) return _buildCloudNotConnected(theme);
    if (_cloudItems.isEmpty) return const _EmptyState(hasItems: false);

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _cloudItems.length,
      itemBuilder: (context, index) {
        final item = _cloudItems[index];
        return Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.cloud_outlined)),
            title: Text(item['content'] ?? ''),
            subtitle: Text('Category: ${item['category']} • ${_formatCloudDate(item['created_at'])}'),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _deleteCloudItem(item['id']),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCloudNotConnected(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.cloud_off_outlined,
                size: 48,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Memori Cloud Belum Terhubung',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Hubungkan project Supabase Anda untuk menyinkronkan dan mencadangkan memori jangka panjang Asisten ke Cloud secara aman.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => Navigator.of(context)
                  .push(
                    MaterialPageRoute(builder: (_) => const SupabaseSetupPage()),
                  )
                  .then((_) {
                    _load();
                    _loadCloud();
                  }),
              icon: const Icon(Icons.settings),
              label: const Text('Atur Supabase di FFM'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => launchUrl(
                Uri.parse('https://supabase.com/'),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Buka supabase.com'),
            ),
            const SizedBox(height: 16),
            Text(
              'Gratis di supabase.com. Buat project baru, lalu salin URL dan Anon Key ke pengaturan FFM.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  String _formatCloudDate(dynamic raw) {
    if (raw == null) return '-';
    try {
      final date = DateTime.parse(raw.toString());
      return DateFormat('d MMM yyyy, HH:mm', 'id_ID').format(date);
    } catch (_) {
      return raw.toString();
    }
  }

  Widget _buildContent(ThemeData theme) {
    final items = _visibleItems;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        Card(
          color: theme.colorScheme.secondaryContainer,
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.privacy_tip_outlined),
                    SizedBox(width: 8),
                    Text(
                      'Memori yang dapat dipakai Asisten',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  'Hanya item lokal yang telah disetujui dan lolos filter privasi tampil di sini. Riwayat chat, draft, PIN, data finansial mentah, dan metadata teknis tidak disimpan sebagai daftar memori.',
                ),
                SizedBox(height: 8),
                Text(
                  'Reset chat hanya menghapus konteks sementara. Gunakan “Lupakan” untuk menghentikan pemakaian item ini pada percakapan berikutnya.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_pendingItems.isNotEmpty) ...[
          _PendingSection(
            items: _pendingItems,
            onApprove: _approvePending,
            onReject: _rejectPending,
          ),
          const SizedBox(height: 16),
        ],
        _buildFilters(),
        const SizedBox(height: 12),
        if (items.isEmpty)
          _EmptyState(hasItems: _items.isNotEmpty)
        else
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _MemoryItemCard(item: item, onForget: () => _forget(item)),
            ),
          ),
      ],
    );
  }

  Widget _buildFilters() {
    final entries = <(FfmPersonalMemoryControlScope?, String, IconData)>[
      (null, 'Semua', Icons.apps_outlined),
      (FfmPersonalMemoryControlScope.userModel, 'Profil', Icons.person_outline),
      (
        FfmPersonalMemoryControlScope.personalMemory,
        'Memori',
        Icons.psychology_outlined,
      ),
      (
        FfmPersonalMemoryControlScope.aliasCorrection,
        'Koreksi',
        Icons.spellcheck_outlined,
      ),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: entries.map((entry) {
        final (scope, label, icon) = entry;
        final count = scope == null
            ? _items.length
            : _items.where((item) => item.scope == scope).length;
        return FilterChip(
          selected: _filter == scope,
          avatar: Icon(icon, size: 16),
          label: Text('$label ($count)'),
          onSelected: (_) => setState(() => _filter = scope),
        );
      }).toList(),
    );
  }
}

class _PendingSection extends StatelessWidget {
  const _PendingSection({
    required this.items,
    required this.onApprove,
    required this.onReject,
  });

  final List<FfmPendingMemoryItem> items;
  final Future<void> Function(FfmPendingMemoryItem) onApprove;
  final Future<void> Function(FfmPendingMemoryItem) onReject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.pending_actions_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Menunggu Persetujuan (${items.length})',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Tersimpulan otomatis dari percakapanmu. Setujui agar Asisten boleh memakainya, atau buang bila kurang tepat.',
            ),
            const SizedBox(height: 10),
            ...items.map(
              (item) => _PendingItemCard(
                item: item,
                onApprove: () => onApprove(item),
                onReject: () => onReject(item),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingItemCard extends StatelessWidget {
  const _PendingItemCard({
    required this.item,
    required this.onApprove,
    required this.onReject,
  });

  final FfmPendingMemoryItem item;
  final Future<void> Function() onApprove;
  final Future<void> Function() onReject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.kindLabel.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: .3,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(item.value, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: onReject,
                child: const Text('Buang'),
              ),
              const SizedBox(width: 4),
              FilledButton.tonalIcon(
                onPressed: onApprove,
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Setujui'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MemoryItemCard extends StatelessWidget {  const _MemoryItemCard({required this.item, required this.onForget});

  final FfmPersonalMemoryControlItem item;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (item.scope) {
      FfmPersonalMemoryControlScope.userModel => theme.colorScheme.primary,
      FfmPersonalMemoryControlScope.personalMemory =>
        theme.colorScheme.tertiary,
      FfmPersonalMemoryControlScope.aliasCorrection =>
        theme.colorScheme.secondary,
    };
    final icon = switch (item.scope) {
      FfmPersonalMemoryControlScope.userModel => Icons.person_outline,
      FfmPersonalMemoryControlScope.personalMemory => Icons.psychology_outlined,
      FfmPersonalMemoryControlScope.aliasCorrection =>
        Icons.spellcheck_outlined,
    };
    final date = DateFormat('d MMM yyyy, HH:mm', 'id_ID').format(item.savedAt);
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: .12),
          foregroundColor: color,
          child: Icon(icon),
        ),
        title: Text(
          item.label,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 3),
            Text(item.value),
            const SizedBox(height: 6),
            Text('${item.sourceLabel} • $date'),
          ],
        ),
        isThreeLine: true,
        trailing: IconButton(
          tooltip: 'Lupakan memori',
          onPressed: onForget,
          icon: const Icon(Icons.delete_outline),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasItems});

  final bool hasItems;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
    child: Column(
      children: [
        const Icon(Icons.visibility_off_outlined, size: 42),
        const SizedBox(height: 12),
        Text(
          hasItems
              ? 'Tidak ada memori pada kategori ini'
              : 'Belum ada memori tersimpan',
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        const Text(
          'Memori hanya muncul setelah persetujuan eksplisit. Asisten tetap dapat membantu tanpa menyimpan fakta baru secara otomatis.',
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 42),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Muat ulang'),
          ),
        ],
      ),
    ),
  );
}
