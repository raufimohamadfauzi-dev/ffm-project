import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/diagnostics/app_diagnostics_service.dart';
import '../../../../core/di/injection.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../../assistant/domain/ffm_assistant_models.dart';
import '../../../assistant/presentation/widgets/ffm_assistant_page_context.dart';

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
  FfmDiagnosticBuild _build = const FfmDiagnosticBuild();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final entries = await _diagnostics.latest();
    final build = await _diagnostics.currentBuild();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _entries = entries;
      _build = build;
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
    final current = _entries.where((e) => e.build.matches(_build)).toList();
    final history = _entries.where((e) => !e.build.matches(_build)).toList();
    return FfmAssistantPageContext(
      destination: FfmAssistantDestination.diagnostics,
      child: Scaffold(
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
                    title: !_build.isKnown
                        ? 'Identitas build belum tersedia'
                        : current.isEmpty
                        ? 'Belum ada error pada build saat ini'
                        : '${current.length} error pada build saat ini',
                    message:
                        'Build: ${_build.label}\n'
                        'Riwayat build lain / tidak diketahui: ${history.length}. '
                        'Belum ada error baru bukan bukti perbaikan sudah terverifikasi. '
                        'Log disimpan 30 hari, maksimal 100 catatan.',
                    icon: current.isEmpty
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
                    const AppSectionHeader(title: 'Error build saat ini'),
                    const SizedBox(height: 8),
                    if (current.isEmpty)
                      const Text(
                        'Belum ada error tercatat yang cocok dengan build saat ini.',
                      ),
                    for (final group in [current, history])
                      if (group.isNotEmpty)
                        ExpansionTile(
                          title: Text(
                            identical(group, current)
                                ? 'Build saat ini (${group.length})'
                                : 'Riwayat build lain / tidak diketahui (${group.length})',
                          ),
                          initiallyExpanded: identical(group, current),
                          children: group
                              .map(
                                (entry) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: AppCard(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.error_outline,
                                              color: scheme.error,
                                            ),
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
                                        Text(
                                          'Build saat kejadian: ${entry.build.label}',
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Waktu: ${_formatDate(entry.occurredAt)}',
                                        ),
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
                              )
                              .toList(),
                        ),
                  ],
                ],
              ),
      ),
    );
  }

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${twoDigits(local.day)}/${twoDigits(local.month)}/${local.year} ${twoDigits(local.hour)}:${twoDigits(local.minute)}';
  }
}
