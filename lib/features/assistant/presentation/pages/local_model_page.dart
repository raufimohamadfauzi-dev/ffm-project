import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../shared/widgets/app_components.dart';
import '../../domain/ffm_assistant_models.dart';
import '../widgets/ffm_assistant_page_context.dart';
import '../../data/ffm_background_download_service.dart';
import '../../data/ffm_local_model_service.dart';
import '../../data/ffm_staging_status.dart';

class LocalModelPage extends StatefulWidget {
  const LocalModelPage({super.key});

  @override
  State<LocalModelPage> createState() => _LocalModelPageState();
}

class _LocalModelPageState extends State<LocalModelPage> {
  final _service = FfmLocalModelService();
  final _backgroundService = const FfmBackgroundDownloadService();
  FfmLocalModelInfo? _model;
  FfmStagingStatus? _stagingStatus;
  FfmModelProgress? _progress;
  List<FfmBackgroundDownloadStatus> _backgroundStatuses =
      const <FfmBackgroundDownloadStatus>[];
  String? _error;
  var _loading = true;
  var _working = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final model = await _service.getInstalled();
      final background = await _backgroundService.status();
      if (model == null) await _adoptCompletedBackground(background);
      final staging = await _service.getStagingStatus();
      if (!mounted) return;
      setState(() {
        _model = model;
        _stagingStatus = staging;
        _backgroundStatuses = background;
        _loading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _model = null;
        _loading = false;
        _error = 'Status model lokal belum dapat dibaca. Coba buka ulang halaman ini.';
      });
    }
  }

  Future<void> _adoptCompletedBackground(
    List<FfmBackgroundDownloadStatus> statuses,
  ) async {
    for (final status in statuses) {
      final localPath = status.localPath;
      if (!status.isComplete || localPath == null || localPath.isEmpty) {
        continue;
      }
      try {
        await _service.importGgufFromPath(localPath);
      } on Object catch (error) {
        _error =
            'Download ${status.fileName} selesai, tetapi belum dapat diverifikasi: $error';
      }
    }
  }

  Future<void> _startBackgroundDownload() async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final statuses = await _backgroundService.start();
      if (!mounted) return;
      setState(() => _backgroundStatuses = statuses);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Download berjalan di latar belakang. Progres tersedia di notifikasi HP.',
          ),
        ),
      );
    } on PlatformException catch (error) {
      if (mounted)
        setState(() => _error = error.message ?? 'Download background gagal.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _cancelBackgroundDownload() async {
    setState(() => _working = true);
    try {
      await _backgroundService.cancel();
      if (mounted) setState(() => _backgroundStatuses = const []);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _download({bool restart = false}) async {
    setState(() {
      _working = true;
      _error = null;
      _progress = null;
    });
    try {
      final model = await _service.downloadBundle(
        restartPartial: restart,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      if (!mounted) return;
      setState(() {
        _model = model;
        _progress = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Model Qwen2-VL terverifikasi dan siap.')),
      );
    } on FfmLocalModelDownloadException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
      if (error.canRetry || error.canRestart) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message),
            action: SnackBarAction(
              label: error.canRetry ? 'Coba lagi' : 'Mulai ulang',
              onPressed: () => _download(restart: !error.canRetry),
            ),
          ),
        );
      }
    } on FfmLocalModelManifestException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          if (e is FileSystemException && e.message.contains('No space left')) {
            _error = 'Ruang penyimpanan tidak cukup. Siapkan minimal 5 GB kosong untuk instalasi bundle.';
          } else {
            _error = 'Download model gagal. Periksa koneksi internet dan ruang penyimpanan, lalu coba lagi.';
          }
        });
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _importGguf() async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['gguf'],
      );
      final selectedFiles = picked;
      if (selectedFiles.isEmpty) return;
      for (final selected in selectedFiles) {
        await _service.importSingleGguf(selected);
      }
      final staging = await _service.getStagingStatus();
      if (!mounted) return;
      setState(() {
        _stagingStatus = staging;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${selectedFiles.length} file GGUF cocok dan berhasil masuk staging.',
          ),
        ),
      );
    } on FfmLocalModelManifestException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error = 'Gagal mengimpor file GGUF. Pastikan file tidak rusak.',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _commitStaging() async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final model = await _service.commitStaging();
      if (!mounted) return;
      setState(() {
        _model = model;
        _stagingStatus = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('SLM berhasil dirakit dan siap dipakai.')),
      );
    } on FfmLocalModelManifestException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Gagal merakit SLM. Pastikan file GGUF tidak rusak.',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _clearStaging() async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await _service.clearStaging();
      final staging = await _service.getStagingStatus();
      if (!mounted) return;
      setState(() {
        _stagingStatus = staging;
      });
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _importBundle() async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final model = await _service.pickAndInstallBundle();
      if (!mounted) return;
      if (model != null) {
        setState(() => _model = model);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bundle offline terverifikasi dan siap dipakai.'),
          ),
        );
      }
    } on FfmLocalModelManifestException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Impor bundle gagal. Pastikan file .ffmbundle berasal dari FFM dan tidak rusak.',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _exportBundle() async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final bundle = await _service.exportVerifiedBundle();
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(bundle.path)],
          text: 'Bundle SLM lokal FFM terverifikasi. Impor file ini di halaman Model Asisten Lokal.',
        ),
      );
    } on FfmLocalModelManifestException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Ekspor bundle gagal. Coba lagi setelah model terverifikasi.',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _remove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus model lokal?'),
        content: const Text(
          'Yang dihapus hanya file model dan metadata verifikasinya. '
          'Database transaksi dan lampiran FFM tetap aman.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _working = true);
    await _service.clear();
    await _service.clearStaging();
    if (!mounted) return;
    setState(() {
      _model = null;
      _stagingStatus = null;
      _working = false;
      _error = null;
    });
  }

  String _size(int bytes) =>
      '${NumberFormat.decimalPattern('id_ID').format(bytes / (1024 * 1024))} MB';

  @override
  Widget build(BuildContext context) {
    return FfmAssistantPageContext(
      destination: FfmAssistantDestination.localModel,
      child: Scaffold(
        appBar: AppBar(title: const Text('Model Asisten Lokal')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
                children: [
                  const AppHelpBanner(
                    title: 'AI lokal bersifat opsional, draft tetap aman',
                    message: 'Model berjalan di perangkat setelah dipasang. Model hanya membuat proposal; model tidak membaca database, menyimpan transaksi, mengubah saldo, atau melewati konfirmasi.',
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
                              'Asisten tetap berjalan dengan aturan lokal bawaan. Download model hanya dilakukan setelah kamu memilihnya.',
                            ),
                          )
                        : ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.verified_outlined),
                            title: const Text('Qwen2-VL terverifikasi'),
                            subtitle: Text(
                              '${_size(_model!.bytes)} + ${_size(_model!.projectorBytes ?? 0)} projector\nSHA-256 model ${_model!.sha256.substring(0, 12)}…\nTersimpan privat sejak ${DateFormat('d MMM y, HH:mm', 'id_ID').format(_model!.installedAt)}',
                            ),
                          ),
                  ),
                  const SizedBox(height: 12),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Paket Qwen2-VL 2B',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Ukuran unduhan sekitar ${_size(FfmQwen2VlBundle.modelBytes + FfmQwen2VlBundle.projectorBytes)}. File disimpan di storage privat aplikasi, diverifikasi dengan SHA-256 streaming, lalu dipindah secara atomik.',
                        ),
                        if (_backgroundStatuses.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          const Text(
                            'Download latar belakang',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          for (final status in _backgroundStatuses)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              leading: Icon(
                                status.isComplete
                                    ? Icons.check_circle_outline
                                    : status.isFailed
                                    ? Icons.error_outline
                                    : Icons.downloading_outlined,
                              ),
                              title: Text(status.fileName),
                              subtitle: Text(
                                status.isComplete
                                    ? 'Selesai. Buka halaman ini untuk memasukkan file ke staging.'
                                    : status.isFailed
                                    ? (status.reason ?? 'Download gagal.')
                                    : 'Sedang berjalan. Progres lengkap terlihat di notifikasi HP.',
                              ),
                              trailing:
                                  status.fraction == null || status.isComplete
                                  ? null
                                  : SizedBox(
                                      width: 56,
                                      child: Text(
                                        '${(status.fraction! * 100).toStringAsFixed(0)}%',
                                        textAlign: TextAlign.end,
                                      ),
                                    ),
                            ),
                          if (_backgroundStatuses.any(
                            (status) => !status.isComplete && !status.isFailed,
                          ))
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: _working
                                    ? null
                                    : _cancelBackgroundDownload,
                                icon: const Icon(Icons.cancel_outlined),
                                label: const Text(
                                  'Batalkan download background',
                                ),
                              ),
                            ),
                        ],
                        if (_progress case final progress?) ...[
                          const SizedBox(height: 16),
                          LinearProgressIndicator(value: progress.fraction),
                          const SizedBox(height: 6),
                          Text(
                            '${progress.fileName}: ${_size(progress.receivedBytes)} / ${_size(progress.totalBytes)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        if (_stagingStatus != null &&
                            !_stagingStatus!.isEmpty &&
                            _model == null) ...[
                          const SizedBox(height: 16),
                          const Text(
                            'Status Impor GGUF Sementara:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                _stagingStatus!.hasModel
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                color: _stagingStatus!.hasModel
                                    ? Colors.green
                                    : Colors.grey,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              const Text('Model GGUF (936 MB)'),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                _stagingStatus!.hasProjector
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                color: _stagingStatus!.hasProjector
                                    ? Colors.green
                                    : Colors.grey,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              const Text('Projector GGUF (1.33 GB)'),
                            ],
                          ),
                        ],
                        if (_error case final error?) ...[
                          const SizedBox(height: 12),
                          Text(
                            error,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (_model == null &&
                                (_stagingStatus == null ||
                                    _stagingStatus!.isEmpty)) ...[
                              FilledButton.icon(
                                onPressed: _working ? null : () => _download(),
                                icon: const Icon(Icons.download_outlined),
                                label: const Text('Unduh di halaman ini'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _working
                                    ? null
                                    : _startBackgroundDownload,
                                icon: const Icon(
                                  Icons.notifications_active_outlined,
                                ),
                                label: const Text('Unduh di background'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _working ? null : _importGguf,
                                icon: const Icon(Icons.file_open_outlined),
                                label: const Text('Pilih GGUF dari Download'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _working ? null : _importBundle,
                                icon: const Icon(Icons.archive_outlined),
                                label: const Text('Impor .ffmbundle'),
                              ),
                            ] else if (_model == null &&
                                _stagingStatus != null &&
                                !_stagingStatus!.isReadyToCommit) ...[
                              FilledButton.icon(
                                onPressed: _working ? null : _importGguf,
                                icon: const Icon(Icons.file_open_outlined),
                                label: const Text('Pilih GGUF Berikutnya'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _working ? null : _clearStaging,
                                icon: const Icon(Icons.cancel_outlined),
                                label: const Text('Batal & Hapus Staging'),
                              ),
                            ] else if (_model == null &&
                                _stagingStatus != null &&
                                _stagingStatus!.isReadyToCommit) ...[
                              FilledButton.icon(
                                onPressed: _working ? null : _commitStaging,
                                icon: const Icon(Icons.build_circle_outlined),
                                label: const Text('Rakit dan Pasang SLM'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _working ? null : _clearStaging,
                                icon: const Icon(Icons.cancel_outlined),
                                label: const Text('Batal & Hapus Staging'),
                              ),
                            ] else ...[
                              OutlinedButton.icon(
                                onPressed: _working ? null : _remove,
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('Hapus model'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _working ? null : _exportBundle,
                                icon: const Icon(Icons.share_outlined),
                                label: const Text('Bagikan bundle'),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Unduh di background tetap berjalan saat aplikasi diminimalkan dan menampilkan progres di notifikasi HP. Setelah selesai, buka halaman ini untuk memasukkan dua file ke staging lalu tekan Rakit dan Pasang SLM. Mode teks akan kembali ke aturan lokal bila model belum siap atau inference gagal.',
                    style: TextStyle(fontSize: 13),
                  ),
                ],
              ),
      ),
    );
  }
}
