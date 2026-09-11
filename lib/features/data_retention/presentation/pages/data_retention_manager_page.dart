import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../backup/data/json_backup_service.dart';
import '../../domain/bulk_retention_service.dart';

/// Pengelolaan retensi data lintas entity: arsip massal sebelum tanggal
/// (reversible) dan hapus permanen massal (wajib backup gate + konfirmasi
/// ketik "HAPUS PERMANEN"). Akses via "Retensi & Arsip" di menu Lainnya
/// dan dari Arsip Transaksi.
class DataRetentionManagerPage extends StatefulWidget {
  const DataRetentionManagerPage({super.key});

  @override
  State<DataRetentionManagerPage> createState() =>
      _DataRetentionManagerPageState();
}

class _DataRetentionManagerPageState extends State<DataRetentionManagerPage> {
  late DateTime _beforeDate;
  BulkRetentionPreview? _archivePreview;
  BulkRetentionPreview? _deletePreview;
  var _working = false;
  var _backupVerified = false;
  String? _backupPath;

  BulkRetentionService get _service =>
      BulkRetentionService(getIt<AppDatabase>());

  @override
  void initState() {
    super.initState();
    _beforeDate = DateTime(DateTime.now().year, DateTime.now().month);
    _refreshPreviews();
  }

  Future<void> _refreshPreviews() async {
    setState(() => _working = true);
    try {
      final archive = await _service.previewArchive(_beforeDate);
      final del = await _service.previewDelete(_beforeDate);
      if (!mounted) return;
      setState(() {
        _archivePreview = archive;
        _deletePreview = del;
        _working = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _working = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _beforeDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() => _beforeDate = DateTime(picked.year, picked.month, picked.day));
    await _refreshPreviews();
  }

  Future<void> _archiveBefore() async {
    final preview = _archivePreview;
    if (preview == null || preview.isEmpty || _working) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.archive, color: AppColors.primary),
        title: const Text('Arsipkan sebelum tanggal?'),
        content: Text(
          'Arsipkan semua data sebelum '
          '${preview.beforeDate.day}/${preview.beforeDate.month}/${preview.beforeDate.year}:\n\n'
          '- ${preview.transactions} transaksi\n'
          '- ${preview.activitySessions} aktivitas\n'
          '- ${preview.dailyNotes} catatan harian\n\n'
          'Data tidak dihapus dan dapat dipulihkan dari halaman arsip.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Arsipkan'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _working = true);
    try {
      final result = await _service.archiveBefore(preview.beforeDate);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${result.total} data diarsipkan.')),
      );
      await _refreshPreviews();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: AppColors.negative),
      );
      setState(() => _working = false);
    }
  }

  Future<void> _createBackup() async {
    if (_working) return;
    setState(() => _working = true);
    try {
      final service = getIt<JsonBackupService>();
      final content = await service.exportJson();
      final bytes = Uint8List.fromList(utf8.encode(content));
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(RegExp(r'[:.]'), '-');
      final path = await FilePicker.saveFile(
        dialogTitle: 'Simpan Cadangan Sebelum Penghapusan',
        fileName: 'ffm-cadangan-sebelum-hapus-$stamp.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: bytes,
      );
      if (path == null) {
        if (mounted) setState(() => _working = false);
        return;
      }
      final filePath = path.toString();
      final uri = Uri.tryParse(filePath);
      final isFileUri = uri?.scheme == 'file';
      final file = isFileUri ? File.fromUri(uri!) : File(filePath);
      if (isFileUri || file.isAbsolute) {
        if (await file.exists()) return;
        await file.writeAsString(content);
      }
      if (!mounted) return;
      setState(() {
        _backupVerified = true;
        _backupPath = filePath;
        _working = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cadangan JSON berhasil disimpan.')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _working = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cadangan belum berhasil dibuat. Coba lagi.'),
          backgroundColor: AppColors.negative,
        ),
      );
    }
  }

  Future<bool> _typedConfirmationDialog(int count) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_forever, color: AppColors.negative),
        title: const Text('Konfirmasi Hapus Permanen'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Anda akan menghapus permanen $count data yang sudah terarsip. '
              'Ketik HAPUS PERMANEN untuk melanjutkan.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autocorrect: false,
              decoration: const InputDecoration(
                hintText: 'HAPUS PERMANEN',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              final ok = controller.text.trim().toUpperCase() ==
                  'HAPUS PERMANEN';
              Navigator.pop(context, ok);
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.negative,
            ),
            child: const Text('Hapus Sekarang'),
          ),
        ],
      ),
    );
    controller.dispose();
    return confirmed == true;
  }

  Future<void> _deleteBefore() async {
    final preview = _deletePreview;
    if (preview == null || preview.isEmpty || _working) return;
    if (!_backupVerified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Buat cadangan JSON dulu sebelum penghapusan massal.'),
          backgroundColor: AppColors.negative,
        ),
      );
      return;
    }
    final ok = await _typedConfirmationDialog(preview.total);
    if (!ok || !mounted) return;
    setState(() => _working = true);
    try {
      final result = await _service.deleteBefore(
        preview.beforeDate,
        backupVerified: _backupVerified,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${result.total} data dihapus permanen.')),
      );
      await _refreshPreviews();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: AppColors.negative),
      );
      setState(() => _working = false);
    }
  }

  Widget _countRow(IconData icon, Color color, String label, int count) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: .14),
        foregroundColor: color,
        child: Icon(icon, size: 18),
      ),
      title: Text(label),
      trailing: Text(
        count.toString(),
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final archive = _archivePreview;
    final del = _deletePreview;
    return Scaffold(
      appBar: AppBar(title: const Text('Retensi & Arsip')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Kelola data lama lintas jenis. Arsip bersifat reversible; '
            'hapus permanen hanya untuk data terarsip dan wajib cadangan dahulu.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.event, color: AppColors.primary),
              title: const Text('Batas tanggal'),
              subtitle: Text(
                'Data sebelum '
                '${_beforeDate.day}/${_beforeDate.month}/${_beforeDate.year}',
              ),
              trailing: const Icon(Icons.edit_calendar),
              onTap: _working ? null : _pickDate,
            ),
          ),
          const SizedBox(height: 16),
          if (_working && (archive == null || del == null))
            const Center(child: CircularProgressIndicator())
          else ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.archive, color: AppColors.primary, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Preview Arsip',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _countRow(
                      Icons.receipt_long,
                      AppColors.negative,
                      'Transaksi',
                      archive?.transactions ?? 0,
                    ),
                    _countRow(
                      Icons.timer_outlined,
                      AppColors.primary,
                      'Aktivitas',
                      archive?.activitySessions ?? 0,
                    ),
                    _countRow(
                      Icons.notes,
                      AppColors.positive,
                      'Catatan harian',
                      archive?.dailyNotes ?? 0,
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed:
                            (archive == null || archive.isEmpty || _working)
                            ? null
                            : _archiveBefore,
                        icon: const Icon(Icons.archive),
                        label: const Text('Arsipkan sebelum tanggal'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              color: AppColors.negative.withValues(alpha: .05),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(
                          Icons.delete_forever,
                          color: AppColors.negative,
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Hapus Permanen (data terarsip)',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _countRow(
                      Icons.receipt_long,
                      AppColors.negative,
                      'Transaksi',
                      del?.transactions ?? 0,
                    ),
                    _countRow(
                      Icons.timer_outlined,
                      AppColors.primary,
                      'Aktivitas',
                      del?.activitySessions ?? 0,
                    ),
                    _countRow(
                      Icons.notes,
                      AppColors.positive,
                      'Catatan harian',
                      del?.dailyNotes ?? 0,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _working ? null : _createBackup,
                        icon: Icon(
                          _backupVerified
                              ? Icons.verified
                              : Icons.save_alt,
                          color: _backupVerified
                              ? AppColors.positive
                              : null,
                        ),
                        label: Text(
                          _backupVerified
                              ? 'Cadangan dibuat ✓'
                              : '1. Buat cadangan JSON dulu',
                        ),
                      ),
                    ),
                    if (_backupPath != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          _backupPath!,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.inkMuted,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed:
                            (del == null || del.isEmpty || _working)
                            ? null
                            : _deleteBefore,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.negative,
                        ),
                        icon: const Icon(Icons.delete_forever),
                        label: Text(
                          _backupVerified
                              ? '2. Hapus permanen sebelum tanggal'
                              : '2. Hapus permanen (isikan cadangan dulu)',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}