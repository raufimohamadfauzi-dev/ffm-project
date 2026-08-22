import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/diagnostics/app_diagnostics_service.dart';
import '../../../../core/di/injection.dart';
import '../../../../shared/widgets/app_components.dart';

/// Gaya halaman mengikuti FFM: status ringkas, teks santai, dan data sensitif
/// tidak pernah dirender karena layanan hanya menyediakan ringkasan tersaring.
class AppDiagnosticsPage extends StatefulWidget {
  const AppDiagnosticsPage({super.key, this.diagnostics});

  final AppDiagnosticsService? diagnostics;

  @override
  State<AppDiagnosticsPage> createState() => _AppDiagnosticsPageState();
}

class _AppDiagnosticsPageState extends State<AppDiagnosticsPage> {
  late final AppDiagnosticsService _diagnostics =
      widget.diagnostics ?? getIt<AppDiagnosticsService>();
  var _loading = true;
  List<FfmDiagnosticEntry> _entries = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final entries = await _diagnostics.latest();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _entries = entries;
    });
  }

  Future<void> _copyReport() async {
    final content = await _diagnostics.buildSafeReport();
    await Clipboard.setData(ClipboardData(text: content));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Laporan error aman sudah disalin.')),
    );
  }

  Future<void> _clear() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus riwayat error?'),
        content: const Text(
          'Hanya ringkasan diagnostik yang dihapus. Transaksi, data keluarga, PIN, dan memori Asisten tetap aman.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Hapus riwayat'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    await _diagnostics.clear();
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Riwayat error sudah dihapus.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bantuan perbaikan'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: [
                AppHelpBanner(
                  title: _entries.isEmpty
                      ? 'Belum ada error teknis'
                      : '${_entries.length} error teknis tercatat',
                  message: _entries.isEmpty
                      ? 'Kalau masalah muncul lagi, coba ulangi lalu buka halaman ini. FFM hanya menampilkan error yang benar-benar tertangkap.'
                      : 'Ringkasan ini aman untuk disalin saat melaporkan masalah. PIN, data keuangan, rekening, dan isi chat tidak dimasukkan.',
                  icon: _entries.isEmpty
                      ? Icons.check_circle_outline
                      : Icons.bug_report_outlined,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _copyReport,
                  icon: const Icon(Icons.copy_all_outlined),
                  label: const Text('Salin laporan error'),
                ),
                if (_entries.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _clear,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Hapus riwayat error'),
                  ),
                  const SizedBox(height: 20),
                  const AppSectionHeader(title: 'Error terbaru'),
                  const SizedBox(height: 8),
                  ..._entries.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.error_outline, color: scheme.error),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    entry.feature,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text('Kode: ${entry.code}'),
                            const SizedBox(height: 4),
                            Text('Waktu: ${_formatDate(entry.occurredAt)}'),
                            const SizedBox(height: 8),
                            Text(entry.summary),
                            const SizedBox(height: 8),
                            Text(
                              'Dampak: ${entry.impact}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${twoDigits(local.day)}/${twoDigits(local.month)}/${local.year} ${twoDigits(local.hour)}:${twoDigits(local.minute)}';
  }
}
