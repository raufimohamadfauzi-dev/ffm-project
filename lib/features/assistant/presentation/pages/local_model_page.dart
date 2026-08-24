import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/diagnostics/app_diagnostics_service.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/utils/safe_date_format.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../domain/ffm_assistant_models.dart';
import '../widgets/ffm_assistant_page_context.dart';
import '../../data/ffm_background_download_service.dart';
import '../../data/ffm_local_model_assembly_status.dart';
import '../../data/ffm_local_model_service.dart';
import '../../data/ffm_local_model_readiness.dart';
import '../../data/ffm_local_model_status_load_gate.dart';
import '../../data/ffm_staging_status.dart';

class LocalModelPage extends StatefulWidget {
  const LocalModelPage({
    super.key,
    this.modelService,
    this.backgroundService,
    this.statusLoadTimeout = const Duration(seconds: 10),
  });

  final FfmLocalModelService? modelService;
  final FfmBackgroundDownloadService? backgroundService;
  final Duration statusLoadTimeout;

  @override
  State<LocalModelPage> createState() => _LocalModelPageState();
}

class _LocalModelPageState extends State<LocalModelPage>
    with WidgetsBindingObserver {
  late final FfmLocalModelService _service;
  late final FfmBackgroundDownloadService _backgroundService;
  late final FfmLocalModelStatusLoadGate _loadGate;
  FfmLocalModelInfo? _model;
  FfmStagingStatus? _stagingStatus;
  FfmLocalModelAssemblyStatus? _assemblyStatus;
  FfmModelProgress? _progress;
  FfmModelProgress? _importProgress;
  String? _importStageDescription;
  List<FfmBackgroundDownloadStatus> _backgroundStatuses =
      const <FfmBackgroundDownloadStatus>[];
  String? _error;
  var _loading = true;
  var _working = false;
  var _loadingMessage = 'Sedang memeriksa status model lokal...';
  var _workingMessage = 'Sedang menyiapkan proses...';
  var _loadEpoch = 0;
  Timer? _loadWatchdog;

  @override
  void initState() {
    super.initState();
    _service = widget.modelService ?? FfmLocalModelService();
    _backgroundService =
        widget.backgroundService ?? const FfmBackgroundDownloadService();
    _loadGate = FfmLocalModelStatusLoadGate(timeout: widget.statusLoadTimeout);
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    _loadWatchdog?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  String _messageForLoadStage(String stage) {
    if (stage.contains('getAssemblyStatus mulai')) {
      return 'Sedang memeriksa apakah ada proses perakitan model yang perlu dilanjutkan...';
    }
    if (stage.contains('getInstalled mulai')) {
      return 'Sedang mencari model yang sudah terpasang di perangkat...';
    }
    if (stage.contains('background.status')) {
      return 'Sedang memeriksa download yang berjalan di background...';
    }
    if (stage.contains('adoptCompletedBackground mulai')) {
      return 'Sedang memindahkan hasil download yang selesai ke staging...';
    }
    if (stage.contains('getStagingStatus')) {
      return 'Sedang membaca file model yang siap dipasang...';
    }
    if (stage.contains('setState selesai')) {
      return 'Sedang menyiapkan ringkasan status terbaru...';
    }
    if (stage.contains('gagal')) {
      return 'Sedang menyiapkan detail pemulihan...';
    }
    return 'Sedang memuat status model lokal...';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_working) {
      _load(showLoading: false);
    }
  }

  Future<void> _load({bool showLoading = true}) async {
    if (_loadGate.isRunning) return;
    final loadEpoch = ++_loadEpoch;
    final trace = <String>[];
    void mark(String stage) {
      final entry = '${DateTime.now().toIso8601String()} $stage';
      trace.add(entry);
      debugPrint('[SLM_STATUS_LOAD] $entry');
      if (mounted && showLoading) {
        setState(() => _loadingMessage = _messageForLoadStage(stage));
      }
    }

    if (mounted && showLoading) {
      setState(() {
        _loading = true;
        _loadingMessage = 'Sedang memeriksa status model lokal...';
        _error = null;
      });
    }
    final watchdog = _armLoadWatchdog(loadEpoch: loadEpoch, trace: trace);

    try {
      mark('mulai');
      final snapshot = await _loadGate.run(() async {
        mark('getAssemblyStatus mulai');
        final assembly = await _service.getAssemblyStatus();
        mark('getAssemblyStatus selesai');
        if (loadEpoch != _loadEpoch) return null;
        mark('getInstalled mulai');
        final model = await _service.getInstalled();
        mark('getInstalled selesai');
        if (loadEpoch != _loadEpoch) return null;
        final background = await _backgroundService.status();
        mark('background.status selesai (${background.length} item)');
        if (loadEpoch != _loadEpoch) return null;
        if (model == null) {
          mark('adoptCompletedBackground mulai');
          await _adoptCompletedBackground(background);
          mark('adoptCompletedBackground selesai');
          if (loadEpoch != _loadEpoch) return null;
        }
        final staging = await _service.getStagingStatus();
        mark('getStagingStatus selesai');
        if (loadEpoch != _loadEpoch) return null;
        return _LocalModelStatusSnapshot(
          model: model,
          background: background,
          staging: staging,
          assembly: assembly,
        );
      });
      if (snapshot == null || loadEpoch != _loadEpoch) return;
      if (!mounted) return;
      setState(() {
        _model = snapshot.model;
        _stagingStatus = snapshot.staging;
        _assemblyStatus = snapshot.assembly;
        _backgroundStatuses = snapshot.background;
        _error = null;
        _loading = false;
      });
      mark('setState selesai');
    } catch (error, stackTrace) {
      if (loadEpoch != _loadEpoch) return;
      // Future.timeout tidak membatalkan platform/IO yang lama. Menambah epoch
      // mencegah kelanjutan Future lama melakukan tahap impor berikutnya.
      _loadEpoch++;
      mark('gagal: $error');
      await _recordLoadFailure(
        error: error,
        stackTrace: stackTrace,
        trace: trace,
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error is TimeoutException
            ? 'Gagal memuat status dalam 10 detik. Tekan tombol Perbarui status download.'
            : 'Status model lokal belum dapat dibaca. Tekan tombol Perbarui status download.';
      });
    } finally {
      watchdog.cancel();
      if (identical(_loadWatchdog, watchdog)) {
        _loadWatchdog = null;
      }
    }
  }

  Timer _armLoadWatchdog({
    required int loadEpoch,
    required List<String> trace,
  }) {
    _loadWatchdog?.cancel();
    final watchdog = Timer(widget.statusLoadTimeout, () {
      if (!mounted || loadEpoch != _loadEpoch) return;
      _loadEpoch++;
      final timeout = TimeoutException('Status model tidak selesai dimuat');
      trace.add('${DateTime.now().toIso8601String()} watchdog timeout');
      debugPrint('[SLM_STATUS_LOAD] watchdog timeout');
      setState(() {
        _loading = false;
        _error = 'Gagal memuat status dalam 10 detik. Tekan tombol Perbarui status download.';
      });
      unawaited(
        _recordLoadFailure(
          error: timeout,
          stackTrace: StackTrace.current,
          trace: trace,
        ),
      );
    });
    _loadWatchdog = watchdog;
    return watchdog;
  }

  Future<void> _recordLoadFailure({
    required Object error,
    required StackTrace stackTrace,
    required List<String> trace,
  }) async {
    try {
      await getIt<AppDiagnosticsService>().recordException(
        code: error is TimeoutException
            ? 'SLM_STATUS_LOAD_TIMEOUT'
            : 'SLM_STATUS_LOAD_FAILED',
        feature: 'Status Model Asisten Lokal',
        error: '$error\nTahap pemuatan:\n${trace.join('\n')}',
        stackTrace: stackTrace,
        impact: 'Halaman model menampilkan tindakan pemulihan; model dan data keuangan tidak diubah.',
      );
    } catch (diagnosticError) {
      debugPrint(
        '[SLM_STATUS_LOAD] gagal mencatat diagnostik: $diagnosticError',
      );
    }
  }

  Future<void> _adoptCompletedBackground(
    List<FfmBackgroundDownloadStatus> statuses,
  ) async {
    var staging = await _service.getStagingStatus();
    for (final status in statuses) {
      final localPath = status.localPath;
      if (localPath == null) continue;
      if (status.isAlreadyInStaging(staging)) {
        if (status.isComplete) {
          await _service.deleteAdoptedBackgroundDuplicate(localPath);
        }
        continue;
      }
      if (!status.needsStagingImport(staging)) continue;
      try {
        await _service.importGgufFromPath(
          localPath,
          expectedBytes: status.totalBytes > 0 ? status.totalBytes : null,
          onProgress: (progress, stage) {
            if (mounted) {
              setState(() {
                _importProgress = progress;
                _importStageDescription = stage;
                _loadingMessage = stage;
                _workingMessage = stage;
              });
            }
          },
        );
        staging = await _service.getStagingStatus();
      } on Object catch (error, stackTrace) {
        final inspection = await _service.inspectBackgroundFile(
          localPath,
          expectedBytes: status.totalBytes > 0 ? status.totalBytes : null,
        );
        await getIt<AppDiagnosticsService>().recordException(
          code: 'SLM_BACKGROUND_IMPORT_RETRY',
          feature: 'Unduhan SLM latar belakang',
          error: '$error\n$inspection',
          stackTrace: stackTrace,
          impact: 'Model belum dipasang. Perbarui status download atau gunakan impor bundle offline.',
        );
        _error =
            'Download ${status.fileName} belum dapat diverifikasi. FFM akan mencoba lagi saat Perbarui status; detail teknis tersimpan di Bantuan perbaikan.';
      } finally {
        if (mounted) {
          setState(() {
            _importProgress = null;
            _importStageDescription = null;
          });
        }
      }
    }
  }

  Future<void> _startBackgroundDownload() async {
    final staging = _stagingStatus;
    final roles = <String>{
      if (staging == null || !staging.hasModel) 'language_model',
      if (staging == null || !staging.hasProjector) 'multimodal_projector',
    };
    if (roles.isEmpty) {
      await _load(showLoading: false);
      return;
    }
    setState(() {
      _working = true;
      _workingMessage = 'Sedang menyiapkan download model di background...';
      _error = null;
    });
    try {
      final statuses = await _backgroundService.start(roles: roles);
      if (!mounted) return;
      setState(() => _backgroundStatuses = statuses);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            roles.length == 1
                ? 'Hanya komponen yang belum ada sedang diunduh di background.'
                : 'Dua komponen yang belum ada sedang diunduh di background.',
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
    setState(() {
      _working = true;
      _workingMessage = 'Sedang membatalkan download background...';
    });
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
      _workingMessage = 'Sedang mengunduh paket model dan memeriksa integritasnya...';
      _error = null;
      _progress = null;
    });
    try {
      final model = await _service.downloadBundle(
        restartPartial: restart,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _progress = progress;
              _workingMessage =
                  'Sedang mengunduh ${progress.fileName} dan menyiapkan pemeriksaan integritas...';
            });
          }
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
      _workingMessage = 'Menunggu Anda memilih file GGUF dari perangkat...';
      _error = null;
      _importProgress = null;
      _importStageDescription = null;
    });
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['gguf'],
        // ignore: deprecated_member_use
        allowMultiple: true,
      );
      final selectedFiles = picked;
      if (selectedFiles.isEmpty) return;
      setState(() {
        _workingMessage = 'Sedang membaca file GGUF dan memeriksa isinya...';
        _importStageDescription =
            'Sedang membaca dan memverifikasi file GGUF berukuran besar. Ini bisa memerlukan beberapa saat.';
      });
      for (final selected in selectedFiles) {
        await _service.importSingleGguf(
          selected,
          onProgress: (progress, stage) {
            if (mounted) {
              setState(() {
                _importProgress = progress;
                _importStageDescription = stage;
                _loadingMessage = stage;
                _workingMessage = stage;
              });
            }
          },
        );
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
      if (mounted) {
        setState(() {
          _working = false;
          _importProgress = null;
          _importStageDescription = null;
        });
      }
    }
  }

  Future<void> _commitStaging() async {
    setState(() {
      _working = true;
      _workingMessage = 'Sedang menyiapkan pemasangan bundle yang sudah diverifikasi...';
      _error = null;
    });
    try {
      final model = await _service.commitStaging(
        onStatus: (status) {
          if (mounted) {
            setState(() {
              _assemblyStatus = status;
              _workingMessage = switch (status.stage) {
                FfmLocalModelAssemblyStage.verifyingModel =>
                  'Sedang memeriksa isi file model GGUF...',
                FfmLocalModelAssemblyStage.verifyingProjector =>
                  'Sedang memeriksa isi file projector GGUF...',
                FfmLocalModelAssemblyStage.committing =>
                  'Sedang memasang bundle dan menyimpan manifest...',
                FfmLocalModelAssemblyStage.ready =>
                  'Model selesai dirakit. Sedang menyiapkan hasil...',
                FfmLocalModelAssemblyStage.failed =>
                  'Sedang menyiapkan detail kesalahan perakitan...',
                FfmLocalModelAssemblyStage.idle =>
                  'Sedang menyiapkan proses perakitan...',
              };
            });
          }
        },
      );
      if (!mounted) return;
      setState(() {
        _model = model;
        _stagingStatus = null;
      });
    } on FfmLocalModelManifestException catch (error) {
      final status = await _service.getAssemblyStatus();
      if (mounted) {
        setState(() {
          _error = error.message;
          _assemblyStatus = status;
        });
      }
    } catch (_) {
      final status = await _service.getAssemblyStatus();
      if (mounted) {
        setState(() {
          _error = 'Gagal merakit SLM. Pastikan file GGUF tidak rusak.';
          _assemblyStatus = status;
        });
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _clearStaging() async {
    setState(() {
      _working = true;
      _workingMessage = 'Sedang membersihkan file staging yang tersimpan...';
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
      _workingMessage = 'Menunggu Anda memilih bundle offline dari perangkat...';
      _error = null;
      _importProgress = null;
      _importStageDescription = null;
    });
    try {
      final model = await _service.pickAndInstallBundle(
        onProgress: (progress, stage) {
          if (mounted) {
            setState(() {
              _importProgress = progress;
              _importStageDescription = stage;
              _workingMessage = stage;
            });
          }
        },
      );
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
      if (mounted) {
        setState(() {
          _working = false;
          _importProgress = null;
          _importStageDescription = null;
        });
      }
    }
  }

  Future<void> _exportBundle() async {
    setState(() {
      _working = true;
      _workingMessage = 'Sedang menyiapkan bundle terverifikasi untuk dibagikan...';
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
    setState(() {
      _working = true;
      _workingMessage = 'Sedang menghapus model lokal dan metadata verifikasi...';
    });
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

  void _returnToFfm() => Navigator.of(context).pop();

  String _size(int bytes) {
    final mb = bytes / (1024 * 1024);
    if (mb >= 1024) {
      return '${(mb / 1024).toStringAsFixed(2)} GB';
    }
    return '${mb.toStringAsFixed(1)} MB';
  }

  String? _remainingEstimate(FfmLocalModelAssemblyStatus status) {
    final startedAt = status.startedAt;
    if (startedAt == null ||
        status.processedBytes <= 0 ||
        status.totalBytes <= 0) {
      return null;
    }
    final elapsed = DateTime.now().difference(startedAt);
    if (elapsed.inSeconds < 1) return null;
    final remainingSeconds =
        elapsed.inSeconds *
        (status.totalBytes - status.processedBytes) ~/
        status.processedBytes;
    if (remainingSeconds <= 0) return null;
    return remainingSeconds >= 60
        ? '~${(remainingSeconds / 60).ceil()} menit'
        : '~$remainingSeconds detik';
  }

  Widget _buildAssemblyStatusCard(BuildContext context) {
    final status = _assemblyStatus!;
    final colorScheme = Theme.of(context).colorScheme;
    final isModel = status.stage == FfmLocalModelAssemblyStage.verifyingModel;
    final isProjector =
        status.stage == FfmLocalModelAssemblyStage.verifyingProjector;
    final isFailed = status.stage == FfmLocalModelAssemblyStage.failed;
    final isReady = status.stage == FfmLocalModelAssemblyStage.ready;
    final title = switch (status.stage) {
      FfmLocalModelAssemblyStage.verifyingModel =>
        'Memverifikasi Model GGUF...',
      FfmLocalModelAssemblyStage.verifyingProjector =>
        'Memverifikasi Projector GGUF...',
      FfmLocalModelAssemblyStage.committing =>
        'Memasang bundle terverifikasi...',
      FfmLocalModelAssemblyStage.ready =>
        'SLM berhasil dirakit dan siap dipakai!',
      FfmLocalModelAssemblyStage.failed => 'Gagal merakit SLM',
      FfmLocalModelAssemblyStage.idle => 'Status rakit SLM',
    };
    final detail = isModel
        ? '${_size(FfmQwen2VlBundle.modelBytes)} — Tahap 1 dari 2'
        : isProjector
        ? '${_size(FfmQwen2VlBundle.projectorBytes)} — Tahap 2 dari 2'
        : status.stage == FfmLocalModelAssemblyStage.committing
        ? 'Menyimpan manifest dan memindahkan bundle secara atomik.'
        : null;
    final estimate = status.isWorking ? _remainingEstimate(status) : null;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isReady
                    ? Icons.verified_outlined
                    : isFailed
                    ? Icons.error_outline
                    : Icons.build_circle_outlined,
                color: isReady
                    ? Colors.green.shade700
                    : isFailed
                    ? colorScheme.error
                    : colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          if (status.isWorking) ...[
            const SizedBox(height: 14),
            LinearProgressIndicator(value: status.fraction),
            const SizedBox(height: 8),
            if (detail != null) Text(detail),
            if (status.totalBytes > 0) ...[
              const SizedBox(height: 4),
              Text(
                '${_size(status.processedBytes)} / ${_size(status.totalBytes)} diverifikasi',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (estimate != null) ...[
              const SizedBox(height: 4),
              Text(
                'Perkiraan sisa waktu: $estimate',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 10),
            Text(
              'Jangan tutup atau tinggalkan halaman ini sampai proses selesai.',
              style: TextStyle(
                color: colorScheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (isReady) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _returnToFfm,
              icon: const Icon(Icons.smart_toy_outlined),
              label: const Text('Buka Asisten'),
            ),
          ],
          if (isFailed) ...[
            const SizedBox(height: 10),
            Text(
              status.errorDetail ?? 'Status kegagalan tidak tersedia.',
              style: TextStyle(color: colorScheme.error),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _working
                      ? null
                      : _stagingStatus?.isReadyToCommit == true
                      ? _commitStaging
                      : _load,
                  icon: const Icon(Icons.refresh_outlined),
                  label: const Text('Coba Lagi'),
                ),
                OutlinedButton.icon(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Detail teknis rakit SLM'),
                      content: SelectableText(
                        status.errorDetail ?? 'Tidak ada detail tersimpan.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Tutup'),
                        ),
                      ],
                    ),
                  ),
                  icon: const Icon(Icons.bug_report_outlined),
                  label: const Text('Lihat Detail Teknis'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _formatInstalledDate(DateTime date) {
    return SafeDateFormat.format(
      date.toLocal(),
      pattern: 'd MMM y, HH:mm',
      locale: 'id_ID',
      fallbackText: '-',
    );
  }

  Widget _buildSpecItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.teal.shade200),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: Colors.teal.shade200,
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCapabilityRow({
    required IconData icon,
    required Color color,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInstalledModelDashboard(
    BuildContext context,
    FfmLocalModelInfo model,
  ) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.teal.shade800,
                Colors.teal.shade900,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.teal.withValues(alpha: 0.25),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.auto_awesome,
                      color: Colors.amberAccent,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Model AI Qwen2-VL 2B Aktif',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Vision & Bahasa Alami • 100% Offline',
                          style: TextStyle(
                            color: Colors.teal.shade100,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.greenAccent.shade700.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.greenAccent.shade400),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle,
                          color: Colors.greenAccent,
                          size: 13,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'SIAP',
                          style: TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Divider(color: Colors.white.withValues(alpha: 0.15)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildSpecItem(
                      icon: Icons.layers_outlined,
                      label: 'Model GGUF',
                      value: _size(model.bytes),
                    ),
                  ),
                  Expanded(
                    child: _buildSpecItem(
                      icon: Icons.remove_red_eye_outlined,
                      label: 'Projector',
                      value: _size(model.projectorBytes ?? 0),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildSpecItem(
                      icon: Icons.fingerprint_outlined,
                      label: 'SHA-256 Hash',
                      value: '${model.sha256.substring(0, 10)}…',
                    ),
                  ),
                  Expanded(
                    child: _buildSpecItem(
                      icon: Icons.calendar_today_outlined,
                      label: 'Terpasang',
                      value: _formatInstalledDate(model.installedAt),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Kemampuan AI yang Aktif:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 12),
              _buildCapabilityRow(
                icon: Icons.receipt_long_outlined,
                color: Colors.blueAccent,
                title: 'Vision OCR (Baca Foto Struk)',
                description:
                    'Membaca foto struk, invoice, dan nota belanja langsung dari kamera/galeri tanpa internet.',
              ),
              const SizedBox(height: 12),
              _buildCapabilityRow(
                icon: Icons.chat_bubble_outline,
                color: Colors.purpleAccent,
                title: 'Pemahaman Bahasa Alami',
                description:
                    'Memahami instruksi teks bebas dan menyusun proposal draf transaksi otomatis.',
              ),
              const SizedBox(height: 12),
              _buildCapabilityRow(
                icon: Icons.security_outlined,
                color: Colors.green.shade700,
                title: 'Privasi & Keamanan Penuh',
                description:
                    'Semua pemrosesan AI berjalan lokal di RAM HP Anda. Tidak ada data yang dikirim ke cloud.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: _working ? null : _returnToFfm,
              icon: const Icon(Icons.chat_outlined),
              label: const Text('Buka Chat & Coba Asisten'),
            ),
            OutlinedButton.icon(
              onPressed: _working ? null : _exportBundle,
              icon: const Icon(Icons.share_outlined),
              label: const Text('Bagikan Bundle (.ffmbundle)'),
            ),
            OutlinedButton.icon(
              onPressed: _working ? null : _remove,
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              label: Text(
                'Hapus Model',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOperationStatus(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Aktivitas saat ini',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(_workingMessage),
                const SizedBox(height: 4),
                Text(
                  'Jangan tutup halaman ini sampai proses selesai.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInitialLoading(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 18),
            Text(
              _loadingMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Sedang membaca status file model dan download. Data keuangan tidak diubah.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final readiness = FfmLocalModelReadiness.resolve(
      model: _model,
      staging: _stagingStatus,
      backgroundStatuses: _backgroundStatuses,
    );
    return FfmAssistantPageContext(
      destination: FfmAssistantDestination.localModel,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Model Asisten Lokal'),
          actions: [
            IconButton(
              onPressed: _working || _loadGate.isRunning ? null : _load,
              tooltip: 'Perbarui status',
              icon: const Icon(Icons.refresh_outlined),
            ),
          ],
        ),
        body: _loading
            ? _buildInitialLoading(context)
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
                children: [
                  const AppHelpBanner(
                    title: 'AI lokal bersifat opsional, draft tetap aman',
                    message:
                        'Model berjalan di perangkat setelah dipasang. Model hanya membuat proposal; model tidak membaca database, menyimpan transaksi, mengubah saldo, atau melewati konfirmasi.',
                    icon: Icons.memory_outlined,
                  ),
                  const SizedBox(height: 16),
                  if (_working) ...[
                    _buildOperationStatus(context),
                    const SizedBox(height: 12),
                  ],
                  if (_model != null)
                    _buildInstalledModelDashboard(context, _model!)
                  else ...[
                    AppCard(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          readiness.canUseAssistant
                              ? Icons.verified_outlined
                              : readiness.state ==
                                    FfmLocalModelReadinessState.downloadFailed
                              ? Icons.error_outline
                              : readiness.state ==
                                    FfmLocalModelReadinessState
                                        .downloadingBackground
                              ? Icons.downloading_outlined
                              : Icons.smart_toy_outlined,
                          color: readiness.canUseAssistant
                              ? Colors.green.shade700
                              : readiness.state ==
                                    FfmLocalModelReadinessState.downloadFailed
                              ? Theme.of(context).colorScheme.error
                              : null,
                        ),
                        title: Text(readiness.title),
                        subtitle: Text(
                          '${readiness.message}\n\nLangkah berikutnya: ${readiness.nextStep}',
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
                            Builder(
                              builder: (context) {
                                final isAlreadyInStaging =
                                    _stagingStatus != null &&
                                    status.isAlreadyInStaging(_stagingStatus!);
                                return ListTile(
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
                                    isAlreadyInStaging
                                        ? 'Sudah diverifikasi dan masuk staging.'
                                        : status.isComplete
                                        ? 'Selesai. Tekan Perbarui status agar file diverifikasi dan masuk staging.'
                                        : status.isFailed
                                        ? (status.reason ?? 'Download gagal.')
                                        : 'Sedang berjalan. Progres lengkap terlihat di notifikasi HP.',
                                  ),
                                  trailing:
                                      status.fraction == null ||
                                          status.isComplete
                                      ? null
                                      : SizedBox(
                                          width: 56,
                                          child: Text(
                                            '${(status.fraction! * 100).toStringAsFixed(0)}%',
                                            textAlign: TextAlign.end,
                                          ),
                                        ),
                                );
                              },
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
                          OutlinedButton.icon(
                            onPressed: _working || _loadGate.isRunning
                                ? null
                                : _load,
                            icon: const Icon(Icons.refresh_outlined),
                            label: const Text('Perbarui status download'),
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
                        if (_importProgress case final importProgress?) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest
                                  .withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.3),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _importStageDescription ??
                                            'Sedang memproses file GGUF...',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    if (importProgress.fraction != null)
                                      Text(
                                        '${((importProgress.fraction!) * 100).toStringAsFixed(1)}%',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                LinearProgressIndicator(
                                  value: importProgress.fraction,
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        importProgress.fileName,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      '${_size(importProgress.receivedBytes)} / ${_size(importProgress.totalBytes)}',
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Proses menyalin & memverifikasi file GGUF (~1-2 GB). Mohon jangan menutup halaman ini.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color:
                                        Theme.of(context).colorScheme.outline,
                                  ),
                                ),
                              ],
                            ),
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
                        if (_assemblyStatus != null &&
                            (_assemblyStatus!.isWorking ||
                                _assemblyStatus!.stage ==
                                    FfmLocalModelAssemblyStage.ready ||
                                _assemblyStatus!.stage ==
                                    FfmLocalModelAssemblyStage.failed)) ...[
                          const SizedBox(height: 16),
                          _buildAssemblyStatusCard(context),
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
                                onPressed: _working ? null : _download,
                                icon: const Icon(Icons.download_outlined),
                                label: const Text('Unduh komponen yang kurang'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _working
                                    ? null
                                    : _startBackgroundDownload,
                                icon: const Icon(
                                  Icons.notifications_active_outlined,
                                ),
                                label: const Text('Unduh kurang di background'),
                              ),
                              OutlinedButton.icon(
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
                              FilledButton.icon(
                                onPressed: _working ? null : _returnToFfm,
                                icon: const Icon(Icons.auto_awesome_outlined),
                                label: const Text('Kembali & coba Asisten'),
                              ),
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
                    'Unduh di background tetap berjalan saat aplikasi diminimalkan dan menampilkan progres di notifikasi HP. Setelah notifikasi selesai, buka halaman ini atau tekan Perbarui status. Jika dua file sudah masuk staging, tekan Rakit dan Pasang SLM. Setelah status AI lokal siap dipakai muncul, kembali lalu buka ✨ Asisten. Mode teks tetap kembali ke aturan lokal bila model belum siap atau inference gagal.',
                    style: TextStyle(fontSize: 13),
                  ),
                ],
                ],
              ),
      ),
    );
  }
}

class _LocalModelStatusSnapshot {
  const _LocalModelStatusSnapshot({
    required this.model,
    required this.background,
    required this.staging,
    required this.assembly,
  });

  final FfmLocalModelInfo? model;
  final List<FfmBackgroundDownloadStatus> background;
  final FfmStagingStatus staging;
  final FfmLocalModelAssemblyStatus? assembly;
}
