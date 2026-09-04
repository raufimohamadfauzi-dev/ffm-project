import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

import '../../../../core/database/app_context.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../../advisor/domain/usecases/financial_health_calculator.dart';
import '../../../asset/domain/usecases/asset_crud_usecases.dart';
import '../../../assistant/data/ffm_assistant_chat_history_repository.dart';
import '../../../assistant/domain/ffm_assistant_models.dart';
import '../../../assistant/presentation/widgets/ffm_assistant_page_context.dart';
import '../../../goal/domain/usecases/goal_crud_usecases.dart';
import '../../../liability/domain/usecases/liability_crud_usecases.dart';
import '../../../receivable/domain/usecases/receivable_crud_usecases.dart';
import '../../../transaction/domain/usecases/transaction_crud_usecases.dart';
import '../../data/json_backup_service.dart';
import '../../data/pdf_report_service.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  var _working = false;
  String? _lastMessage;
  var _lastMessageIsError = false;
  var _exportIncludeChatHistory = false;

  JsonBackupService get _service => getIt<JsonBackupService>();

  void _showNotice(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).colorScheme.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _exportFullBackup() async {
    if (_working) return; // Anti-spam
    setState(() {
      _working = true;
      _lastMessage = null;
      _lastMessageIsError = false;
    });
    try {
      final historyRepo = FfmAssistantChatHistoryRepository();
      final historyRows = await historyRepo.readRaw();
      final conversationRows = await historyRepo.readConversationsRaw();
      final filteredHistory = historyRows
          .map((row) {
            final mutable = Map<String, Object?>.of(row);
            mutable.remove('imagePath');
            return mutable;
          })
          .toList(growable: false);

      final content = await _service.exportJson(
        assistantChatHistory:
            _exportIncludeChatHistory && filteredHistory.isNotEmpty
            ? filteredHistory
            : null,
        assistantChatConversations:
            _exportIncludeChatHistory && conversationRows.isNotEmpty
            ? conversationRows
            : null,
      );

      final bytes = Uint8List.fromList(utf8.encode(content));
      final stamp = _fileStamp(DateTime.now());
      final path = await FilePicker.saveFile(
        dialogTitle: 'Simpan Berkas Cadangan FFM',
        fileName: 'ffm-cadangan-penuh-$stamp.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: bytes,
      );

      if (path != null) {
        final filePath = path.toString();
        final uri = Uri.tryParse(filePath);
        final isFileUri = uri?.scheme == 'file';
        final file = isFileUri ? File.fromUri(uri!) : File(filePath);
        if (isFileUri || file.isAbsolute) {
          if (!await file.exists()) {
            await file.writeAsString(content);
          }
        }
        if (!mounted) return;
        final msg = 'Cadangan penuh berhasil dibuat & disimpan.';
        setState(() {
          _lastMessage = msg;
          _lastMessageIsError = false;
        });
        _showNotice(msg);
      }
    } catch (e) {
      if (!mounted) return;
      const msg = 'Cadangan belum berhasil dibuat. Silakan coba lagi.';
      setState(() {
        _lastMessage = msg;
        _lastMessageIsError = true;
      });
      _showNotice(msg, isError: true);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _checkBackup() async {
    if (_working) return; // Anti-spam
    final path = await _pickJsonPath();
    if (path == null || !mounted) return;
    setState(() {
      _working = true;
      _lastMessage = null;
      _lastMessageIsError = false;
    });
    try {
      final preview = _service.previewJson(await File(path).readAsString());
      if (!mounted) return;
      final msg = _previewMessage(preview);
      setState(() {
        _lastMessage = msg;
        _lastMessageIsError = false;
      });
      _showRestorePreview(preview, isCheckOnly: true);
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() {
        _lastMessage = error.message;
        _lastMessageIsError = true;
      });
      _showNotice(error.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      const msg = 'Berkas cadangan tidak bisa dibaca atau format salah.';
      setState(() {
        _lastMessage = msg;
        _lastMessageIsError = true;
      });
      _showNotice(msg, isError: true);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _restoreBackup() async {
    if (_working) return; // Anti-spam
    final path = await _pickJsonPath();
    if (path == null || !mounted) return;
    try {
      final content = await File(path).readAsString();
      final preview = _service.previewJson(content);
      if (!mounted) return;
      final confirmed = await _showRestorePreview(preview, isCheckOnly: false);
      if (!confirmed || !mounted) return;
      setState(() {
        _working = true;
        _lastMessage = null;
        _lastMessageIsError = false;
      });
      await _service.importAndRestore(
        path,
        onRestoreChatHistory: (rows) async {
          await FfmAssistantChatHistoryRepository().importRaw(rows);
        },
        onRestoreChatConversations: (rows) async {
          await FfmAssistantChatHistoryRepository().importConversationsRaw(
            rows,
          );
        },
      );
      if (!mounted) return;
      const msg =
          'Data berhasil dipulihkan! Seluruh data lokal diselaraskan secara aman.';
      setState(() {
        _lastMessage = msg;
        _lastMessageIsError = false;
      });
      _showNotice(msg);
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() {
        _lastMessage = error.message;
        _lastMessageIsError = true;
      });
      _showNotice(error.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      const msg = 'Pemulihan dibatalkan karena berkas tidak cocok.';
      setState(() {
        _lastMessage = msg;
        _lastMessageIsError = true;
      });
      _showNotice(msg, isError: true);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _exportPdfReport() async {
    if (_working) return; // Anti-spam
    setState(() {
      _working = true;
      _lastMessage = null;
      _lastMessageIsError = false;
    });
    try {
      final now = DateTime.now();
      final transactions = await getIt<GetTransactions>()(
        AppContext.householdId,
      );

      // Pengecekan data kosong untuk mengedukasi pengguna
      if (transactions.isEmpty) {
        _showNotice(
          'Belum ada data transaksi yang tercatat untuk dibuatkan laporan PDF.',
          isError: true,
        );
        setState(() {
          _lastMessage = 'Laporan PDF dibatalkan: Belum ada transaksi.';
          _lastMessageIsError = true;
        });
        return;
      }

      final assets = await getIt<GetAssets>()(AppContext.householdId);
      final liabilities = await getIt<GetLiabilities>()(AppContext.householdId);
      final receivables = await getIt<GetReceivables>()(AppContext.householdId);
      final goals = await getIt<GetGoals>()(AppContext.householdId);
      final categories = await (getIt<AppDatabase>().select(
        getIt<AppDatabase>().categories,
      )..where((row) => row.householdId.equals(AppContext.householdId))).get();
      final labels = {
        for (final category in categories) category.id: category.name,
      };
      final monthTransactions = transactions.where((item) {
        final date = item.transaction.date;
        return date.year == now.year && date.month == now.month;
      });

      final income = monthTransactions
          .where((item) => item.transaction.amount > 0)
          .fold<int>(0, (sum, item) => sum + item.transaction.amount);
      final expenses = monthTransactions
          .where((item) => item.transaction.amount < 0)
          .fold<int>(0, (sum, item) => sum + item.transaction.amount.abs());
      final installments = liabilities.fold<int>(
        0,
        (sum, item) => sum + item.monthlyInstallment,
      );
      final emergencyFund = assets
          .where((item) => item.assetType == 'cash')
          .fold<int>(0, (sum, item) => sum + item.value);
      final score = const FinancialHealthCalculator().calculate(
        FinancialHealthInput(
          totalIncome: income,
          totalExpenses: expenses,
          totalMonthlyInstallments: installments,
          emergencyFundAmount: emergencyFund,
          averageMonthlyExpenses: expenses,
        ),
      );
      final bytes = await const PdfReportService().buildMonthlyReport(
        month: now,
        transactions: transactions,
        assets: assets,
        liabilities: liabilities,
        receivables: receivables,
        goals: goals,
        categoryLabels: labels,
        score: score,
      );
      await Printing.sharePdf(
        bytes: Uint8List.fromList(bytes),
        filename: 'ffm-laporan-${_fileStamp(now)}.pdf',
      );
      if (!mounted) return;
      const msg = 'Laporan PDF bulanan siap dibagikan/dicetak.';
      setState(() {
        _lastMessage = msg;
        _lastMessageIsError = false;
      });
      _showNotice(msg);
    } catch (_) {
      if (!mounted) return;
      const msg = 'Laporan PDF belum berhasil dibuat. Coba lagi.';
      setState(() {
        _lastMessage = msg;
        _lastMessageIsError = true;
      });
      _showNotice(msg, isError: true);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _exportWeeklyPdfReport() async {
    if (_working) return; // Anti-spam
    setState(() {
      _working = true;
      _lastMessage = null;
      _lastMessageIsError = false;
    });
    try {
      final now = DateTime.now();
      final transactions = await getIt<GetTransactions>()(
        AppContext.householdId,
      );

      if (transactions.isEmpty) {
        _showNotice(
          'Belum ada data transaksi untuk laporan mingguan PDF.',
          isError: true,
        );
        setState(() {
          _lastMessage = 'Laporan mingguan dibatalkan: Belum ada transaksi.';
          _lastMessageIsError = true;
        });
        return;
      }

      final categories = await (getIt<AppDatabase>().select(
        getIt<AppDatabase>().categories,
      )..where((row) => row.householdId.equals(AppContext.householdId))).get();
      final labels = {
        for (final category in categories) category.id: category.name,
      };
      final bytes = await const PdfReportService().buildWeeklyReport(
        weekContaining: now,
        transactions: transactions,
        categoryLabels: labels,
      );
      await Printing.sharePdf(
        bytes: Uint8List.fromList(bytes),
        filename: 'ffm-laporan-mingguan-${_fileStamp(now)}.pdf',
      );
      if (!mounted) return;
      const msg = 'Laporan PDF mingguan siap dibagikan/dicetak.';
      setState(() {
        _lastMessage = msg;
        _lastMessageIsError = false;
      });
      _showNotice(msg);
    } catch (_) {
      if (!mounted) return;
      const msg = 'Laporan mingguan belum berhasil dibuat. Coba lagi.';
      setState(() {
        _lastMessage = msg;
        _lastMessageIsError = true;
      });
      _showNotice(msg, isError: true);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<String?> _pickJsonPath() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result.isEmpty) return null;
    return result.single.path;
  }

  Future<bool> _showRestorePreview(
    BackupPreview preview, {
    required bool isCheckOnly,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Row(
              children: [
                Icon(
                  isCheckOnly
                      ? Icons.info_outline
                      : Icons.warning_amber_rounded,
                  color: isCheckOnly
                      ? Theme.of(dialogContext).colorScheme.primary
                      : Theme.of(dialogContext).colorScheme.error,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isCheckOnly
                        ? 'Informasi Berkas Cadangan'
                        : (preview.isFull
                              ? 'Konfirmasi Pemulihan Data'
                              : 'Berkas Cadangan Tidak Lengkap'),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _previewMessage(preview),
                    style: const TextStyle(height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  if (!isCheckOnly)
                    Text(
                      preview.isFull
                          ? '⚠️ PERHATIAN: Pemulihan data akan menyelaraskan database lokal dengan isi cadangan ini secara atomik dan aman.'
                          : '❌ Berkas ini bukan cadangan penuh FFM yang valid untuk dipulihkan.',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: preview.isFull
                            ? Theme.of(dialogContext).colorScheme.error
                            : Theme.of(dialogContext).colorScheme.outline,
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(isCheckOnly ? 'Tutup' : 'Batal'),
              ),
              if (!isCheckOnly && preview.isFull)
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Ya, Pulihkan Sekarang'),
                ),
            ],
          ),
        ) ??
        false;
  }

  String _previewMessage(BackupPreview preview) {
    final transaksi = preview.counts['transactions'] ?? 0;
    final aset = preview.counts['assets'] ?? 0;
    final hutang = preview.counts['liabilities'] ?? 0;
    final target = preview.counts['goals'] ?? 0;
    final piutang = preview.counts['receivables'] ?? 0;
    final anggaran = preview.counts['budgets'] ?? 0;
    final rekonsiliasi = preview.counts['reconciliations'] ?? 0;
    final aktivitas = preview.counts['activity_logs'] ?? 0;
    final pengingat = preview.counts['reminders'] ?? 0;
    final rentang = preview.transactionFrom == null
        ? 'belum ada data transaksi'
        : '${_dateLabel(preview.transactionFrom!)} s/d ${_dateLabel(preview.transactionTo!)}';
    return 'Format Versi: ${preview.formatVersion}\n\n'
        'Rincian Modul Terdeteksi:\n'
        '• Transaksi: $transaksi ($rentang)\n'
        '• Aset Kelolaan: $aset\n'
        '• Kewajiban Hutang: $hutang\n'
        '• Hak Piutang: $piutang\n'
        '• Target Keuangan: $target\n'
        '• Batas Anggaran: $anggaran\n'
        '• Pengingat Lokal: $pengingat\n'
        '• Rekonsiliasi Saldo: $rekonsiliasi\n'
        '• Log Aktivitas: $aktivitas';
  }

  String _dateLabel(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _fileStamp(DateTime date) {
    return '${date.year}${date.month.toString().padLeft(2, '0')}'
        '${date.day.toString().padLeft(2, '0')}-'
        '${date.hour.toString().padLeft(2, '0')}'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return FfmAssistantPageContext(
      destination: FfmAssistantDestination.backup,
      child: Scaffold(
        appBar: AppBar(title: const Text('Ekspor & Cadangan')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const AppHelpBanner(
              title: 'Cadangan Aman & Adaptif',
              message: 'Cadangan penuh menyimpan transaksi, aset, hutang, target, dan data utama ke berkas JSON. Berkas bersifat adaptif untuk pemulihan di versi APK mendatang.',
              icon: Icons.shield_outlined,
            ),
            const SizedBox(height: 16),

            // SEKSI 1: CADANGAN & PEMULIHAN APLIKASI
            const AppSectionHeader(title: 'Cadangan & Pemulihan Data'),
            const SizedBox(height: 8),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _exportIncludeChatHistory,
                    onChanged: _working
                        ? null
                        : (value) => setState(
                            () => _exportIncludeChatHistory = value ?? false,
                          ),
                    title: const Text('Sertakan riwayat obrolan Asisten'),
                    subtitle: const Text(
                      'Teks riwayat percakapan akan ikut dicadangkan.',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _working ? null : _exportFullBackup,
                    icon: const Icon(Icons.backup_outlined),
                    label: const Text('Buat Cadangan Penuh (.json)'),
                  ),
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _working ? null : _restoreBackup,
                        icon: const Icon(Icons.restore),
                        label: const Text('Impor & Pulihkan Data'),
                      ),
                      TextButton.icon(
                        onPressed: _working ? null : _checkBackup,
                        icon: const Icon(Icons.fact_check_outlined),
                        label: const Text('Cek Berkas Cadangan'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // SEKSI 2: LAPORAN KEUANGAN PDF
            const AppSectionHeader(title: 'Cetak Laporan PDF'),
            const SizedBox(height: 8),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ekspor laporan keuangan berbentuk dokumen PDF siap cetak atau dibagikan.',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _working ? null : _exportPdfReport,
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('Laporan PDF Bulan Ini'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _working ? null : _exportWeeklyPdfReport,
                        icon: const Icon(Icons.date_range_outlined),
                        label: const Text('Laporan PDF Minggu Ini'),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            if (_working) ...[
              const SizedBox(height: 20),
              AppCard(
                color: scheme.surfaceContainer,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Sedang memproses & menyusun data…',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                  ],
                ),
              ),
            ],

            if (_lastMessage != null) ...[
              const SizedBox(height: 20),
              AppCard(
                color: _lastMessageIsError
                    ? scheme.errorContainer
                    : AppSemanticContainers.positiveContainer(context),
                child: Row(
                  children: [
                    Icon(
                      _lastMessageIsError
                          ? Icons.error_outline
                          : Icons.check_circle_outline,
                      color: _lastMessageIsError
                          ? scheme.onErrorContainer
                          : AppSemanticContainers.onPositiveContainer(context),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _lastMessage!,
                        style: TextStyle(
                          color: _lastMessageIsError
                              ? scheme.onErrorContainer
                              : AppSemanticContainers.onPositiveContainer(
                                  context,
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
