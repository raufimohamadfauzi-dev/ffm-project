import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../shared/widgets/app_components.dart';
import '../../data/ffm_local_model_service.dart';

class LocalModelPage extends StatefulWidget {
  const LocalModelPage({super.key});

  @override
  State<LocalModelPage> createState() => _LocalModelPageState();
}

class _LocalModelPageState extends State<LocalModelPage> {
  final _service = FfmLocalModelService();
  FfmLocalModelInfo? _model;
  var _loading = true;
  var _working = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final model = await _service.getInstalled();
    if (mounted)
      setState(() {
        _model = model;
        _loading = false;
      });
  }

  Future<void> _install() async {
    setState(() => _working = true);
    try {
      final model = await _service.pickAndInstall();
      if (!mounted || model == null) return;
      setState(() => _model = model);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Paket model tersimpan privat di FFM.')),
      );
    } on FormatException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _remove() async {
    setState(() => _working = true);
    await _service.clear();
    if (mounted)
      setState(() {
        _model = null;
        _working = false;
      });
  }

  String _size(int bytes) =>
      NumberFormat.decimalPattern('id_ID').format(bytes / (1024 * 1024));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Model Asisten Lokal')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
              children: [
                const AppHelpBanner(
                  title: 'Model itu opsional, draft tetap aman',
                  message: 'Paket model hanya membantu memahami perintah Bahasa Indonesia. Model tidak dapat menyimpan transaksi, mengubah saldo, atau melewati layar konfirmasi.',
                  icon: Icons.memory_outlined,
                ),
                const SizedBox(height: 20),
                AppCard(
                  child: _model == null
                      ? const ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.smart_toy_outlined),
                          title: Text('Belum ada model terpasang'),
                          subtitle: Text(
                            'Kolom Perintah FFM tetap berjalan dengan aturan lokal bawaan.',
                          ),
                        )
                      : ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.verified_outlined),
                          title: Text(_model!.fileName),
                          subtitle: Text(
                            '${_size(_model!.bytes)} MB • SHA-256 ${_model!.sha256.substring(0, 12)}…\nTersimpan privat sejak ${DateFormat('d MMM y, HH:mm', 'id_ID').format(_model!.installedAt)}',
                          ),
                        ),
                ),
                const SizedBox(height: 12),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Tahap uji tanpa server',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Pilih paket .litertlm, .task, atau .bin yang sudah kamu dapat dari sumber tepercaya. FFM menyalin file ke ruang privat aplikasi dan menghitung SHA-256. File asli di folder Download boleh kamu hapus setelah pemasangan.',
                      ),
                      const SizedBox(height: 14),
                      if (_model == null)
                        FilledButton.icon(
                          onPressed: _working ? null : _install,
                          icon: const Icon(Icons.file_open_outlined),
                          label: const Text('Pilih file model'),
                        )
                      else
                        OutlinedButton.icon(
                          onPressed: _working ? null : _remove,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Hapus model dari FFM'),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Catatan: v47 menyiapkan pemasangan, pemeriksaan format, penyimpanan privat, dan fallback. Runtime SLM belum diaktifkan; model tidak akan dipanggil untuk membuat keputusan keuangan sampai benchmark dan integrasi LiteRT selesai.',
                  style: TextStyle(fontSize: 13),
                ),
              ],
            ),
    );
  }
}
