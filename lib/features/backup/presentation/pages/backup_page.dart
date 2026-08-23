import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide Column;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../../core/database/app_context.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../../advisor/domain/usecases/financial_health_calculator.dart';
import '../../../assistant/domain/ffm_assistant_models.dart';
import '../../../assistant/presentation/widgets/ffm_assistant_page_context.dart';
import '../../../assistant/data/ffm_assistant_chat_history_repository.dart';
import '../../../asset/domain/usecases/asset_crud_usecases.dart';
import '../../../goal/domain/usecases/goal_crud_usecases.dart';
import '../../../liability/domain/usecases/liability_crud_usecases.dart';
import '../../../receivable/domain/usecases/receivable_crud_usecases.dart';
import '../../../transaction/domain/usecases/transaction_crud_usecases.dart';
import '../../data/analysis_export_service.dart';
import '../../data/json_backup_service.dart';
import '../../data/json_export_studio_service.dart';
import '../../data/pdf_report_service.dart';
import '../../../settings/data/export_service.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  var _working = false;
  String? _lastMessage;
  DateTimeRange? _dateRange;
  var _typeFilter = 'all';
  var _categoryFilter = 'all';
  Map<String, String> _categoryLabels = const {};
  var _analysisIncludeNotes = false;
  var _analysisIncludeItems = true;
  final _analysisIncludeMerchantDetails = false;
  var _exportIncludeFinance = true;
  var _exportIncludeMetadata = true;
  var _studioIncludeActivities = true;
  var _studioIncludeFamilyProfile = true;
  var _studioAnonymizeIdentity = false;
  var _studioAnonymizeAmounts = false;
  var _studioReportStyle = 'pembelajaran keluarga';
  var _studioAiOutput = '';
  var _exportIncludeChatHistory = false;

  JsonBackupService get _service => getIt<JsonBackupService>();
  DataExportService get _smartExport => getIt<DataExportService>();
  JsonExportStudioService get _studio => getIt<JsonExportStudioService>();

  @override
  void initState() {
    super.initState();
    _loadCategoryLabels();
  }

  Future<void> _loadCategoryLabels() async {
    final rows =
        await (getIt<AppDatabase>().select(getIt<AppDatabase>().categories)
              ..where(
                (row) =>
                    row.householdId.equals(AppContext.householdId) &
                    row.isActive.equals(true),
              ))
            .get();
    if (!mounted) return;
    setState(() {
      _categoryLabels = {for (final row in rows) row.id: row.name};
    });
  }

  Future<void> _exportPdfReport() async {
    setState(() => _working = true);
    try {
      final now = DateTime.now();
      final transactions = await getIt<GetTransactions>()(
        AppContext.householdId,
      );
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
      setState(() => _lastMessage = 'Laporan PDF siap dibagikan.');
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _lastMessage = 'Laporan PDF belum berhasil dibuat. Coba lagi.',
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _exportWeeklyPdfReport() async {
    setState(() => _working = true);
    try {
      final now = DateTime.now();
      final transactions = await getIt<GetTransactions>()(
        AppContext.householdId,
      );
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
      setState(() => _lastMessage = 'Laporan mingguan PDF siap dibagikan.');
    } catch (_) {
      if (!mounted) return;
      setState(
        () =>
            _lastMessage = 'Laporan mingguan belum berhasil dibuat. Coba lagi.',
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<AnalysisExportBundle> _makeAnalysisBundle() async {
    final db = getIt<AppDatabase>();
    final transactions = await getIt<GetTransactions>()(AppContext.householdId);
    final categories = await (db.select(
      db.categories,
    )..where((row) => row.householdId.equals(AppContext.householdId))).get();
    final merchants = await (db.select(
      db.merchants,
    )..where((row) => row.householdId.equals(AppContext.householdId))).get();
    final tags = await (db.select(
      db.tags,
    )..where((row) => row.householdId.equals(AppContext.householdId))).get();
    final links = await db.select(db.transactionTags).get();
    final tagsByTransaction = <String, List<String>>{};
    for (final link in links) {
      tagsByTransaction
          .putIfAbsent(link.transactionId, () => <String>[])
          .add(link.tagId);
    }
    return const AnalysisExportService().build(
      records: transactions,
      from: _dateRange?.start,
      to: _dateRange?.end,
      typeFilter: _typeFilter,
      categoryFilter: _categoryFilter,
      categoryLabels: {
        for (final category in categories) category.id: category.name,
      },
      merchantLabels: {
        for (final merchant in merchants) merchant.id: merchant.name,
      },
      merchantDetails: {
        for (final merchant in merchants)
          if (merchant.details?.trim().isNotEmpty == true)
            merchant.id: merchant.details!,
      },
      tagLabels: {for (final tag in tags) tag.id: tag.name},
      tagsByTransaction: tagsByTransaction,
      includeNotes: _analysisIncludeNotes,
      includeItems: _analysisIncludeItems,
      includeMerchantDetails: _analysisIncludeMerchantDetails,
    );
  }

  Future<void> _copyAnalysisPrompt() async {
    setState(() => _working = true);
    try {
      final bundle = await _makeAnalysisBundle();
      await Clipboard.setData(ClipboardData(text: bundle.prompt));
      if (!mounted) return;
      setState(
        () => _lastMessage =
            'Prompt siap ditempel ke AI. Jangan lupa salin JSON analisa juga.',
      );
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _lastMessage = 'Prompt belum berhasil disiapkan. Coba lagi.',
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _copyAnalysisJson() async {
    setState(() => _working = true);
    try {
      final bundle = await _makeAnalysisBundle();
      await Clipboard.setData(ClipboardData(text: bundle.json));
      if (!mounted) return;
      setState(
        () => _lastMessage = 'JSON analisa sudah disalin. Tempel setelah prompt di layanan AI pilihanmu.',
      );
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _lastMessage = 'JSON analisa belum berhasil dibuat. Coba lagi.',
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _exportAnalysisFile(String extension) async {
    setState(() => _working = true);
    try {
      final bundle = await _makeAnalysisBundle();
      final directory = await getApplicationDocumentsDirectory();
      final stamp = _fileStamp(DateTime.now());
      final content = switch (extension) {
        'json' => bundle.json,
        'csv' => bundle.csv,
        _ => bundle.html,
      };
      final file = File('${directory.path}/ffm-analisa-$stamp.$extension');
      await file.writeAsString(content);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'Berkas analisa FFM periode ${bundle.periodLabel}.',
        ),
      );
      if (!mounted) return;
      setState(
        () => _lastMessage =
            'Berkas ${extension.toUpperCase()} analisa berhasil dibuat dan siap dibagikan.',
      );
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _lastMessage = 'Berkas analisa belum berhasil dibuat. Coba lagi.',
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<JsonStudioBundle> _makeStudioBundle() {
    return _studio.build(
      JsonStudioOptions(
        includeFinance: _exportIncludeFinance,
        includeActivities: _studioIncludeActivities,
        includeMetadata: _exportIncludeMetadata,
        includeFamilyProfile: _studioIncludeFamilyProfile,
        includeNotes: _analysisIncludeNotes,
        anonymizeIdentity: _studioAnonymizeIdentity,
        anonymizeAmounts: _studioAnonymizeAmounts,
        from: _dateRange?.start,
        to: _dateRange?.end,
        reportStyle: _studioReportStyle,
      ),
    );
  }

  Future<void> _copyStudioJson() async {
    setState(() => _working = true);
    try {
      final bundle = await _makeStudioBundle();
      await Clipboard.setData(ClipboardData(text: bundle.json));
      if (!mounted) return;
      setState(
        () => _lastMessage = 'JSON Studio sudah disalin. Tempel ke Gemini atau Claude sesuai prompt.',
      );
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _lastMessage = 'JSON Studio belum berhasil dibuat. Coba lagi.',
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _copyStudioPrompt() async {
    setState(() => _working = true);
    try {
      final bundle = await _makeStudioBundle();
      await Clipboard.setData(ClipboardData(text: bundle.prompt));
      if (!mounted) return;
      setState(
        () => _lastMessage =
            'Prompt Studio sudah disalin. Tempel prompt dulu, lalu JSON-nya.',
      );
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _lastMessage = 'Prompt Studio belum berhasil dibuat. Coba lagi.',
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _shareStudioJson() async {
    setState(() => _working = true);
    try {
      final bundle = await _makeStudioBundle();
      final directory = await getApplicationDocumentsDirectory();
      final file = File(
        '${directory.path}/ffm-studio-${_fileStamp(DateTime.now())}.json',
      );
      await file.writeAsString(bundle.json);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'JSON Export Studio FFM untuk laporan ${bundle.periodLabel}.',
        ),
      );
      if (!mounted) return;
      setState(() => _lastMessage = 'JSON Studio siap dibagikan.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _lastMessage = 'JSON Studio belum berhasil dibagikan.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  String _plainTextFromAiOutput(String value) {
    final withoutScripts = value.replaceAll(
      RegExp(r'<(script|style)[^>]*>[\s\S]*?</\1>', caseSensitive: false),
      '',
    );
    return withoutScripts
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(
          RegExp(r'</(p|div|h[1-6]|li|tr)>', caseSensitive: false),
          '\n',
        )
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  Future<void> _shareAiHtml() async {
    final content = _studioAiOutput.trim();
    if (content.isEmpty) {
      setState(
        () => _lastMessage = 'Tempel dulu hasil HTML atau Markdown dari AI.',
      );
      return;
    }
    setState(() => _working = true);
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File(
        '${directory.path}/ffm-laporan-ai-${_fileStamp(DateTime.now())}.html',
      );
      final html = content.toLowerCase().contains('<html')
          ? content
          : '<!doctype html><html lang="id"><meta charset="utf-8"><title>Laporan FFM</title><body><pre style="white-space:pre-wrap;font-family:sans-serif">${const HtmlEscape().convert(content)}</pre></body></html>';
      await file.writeAsString(html);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'Laporan HTML hasil AI eksternal dari FFM.',
        ),
      );
      if (!mounted) return;
      setState(() => _lastMessage = 'Laporan HTML siap dibagikan.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _lastMessage = 'Laporan HTML belum berhasil dibuat.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _shareAiPdf() async {
    final content = _studioAiOutput.trim();
    if (content.isEmpty) {
      setState(
        () => _lastMessage = 'Tempel dulu hasil HTML atau Markdown dari AI.',
      );
      return;
    }
    setState(() => _working = true);
    try {
      final document = pw.Document();
      final plainText = _plainTextFromAiOutput(content);
      document.addPage(
        pw.MultiPage(
          build: (context) => [
            pw.Text('Laporan FFM dari AI eksternal'),
            pw.SizedBox(height: 12),
            pw.Text(plainText),
          ],
        ),
      );
      await Printing.sharePdf(
        bytes: Uint8List.fromList(await document.save()),
        filename: 'ffm-laporan-ai-${_fileStamp(DateTime.now())}.pdf',
      );
      if (!mounted) return;
      setState(() => _lastMessage = 'Laporan PDF hasil AI siap dibagikan.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _lastMessage = 'Laporan PDF belum berhasil dibuat.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _previewStudio() async {
    setState(() => _working = true);
    try {
      final bundle = await _makeStudioBundle();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Preview JSON Studio'),
          content: SizedBox(
            width: 720,
            child: SingleChildScrollView(child: SelectableText(bundle.json)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tutup'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _lastMessage = 'Preview JSON belum berhasil dibuat.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _exportBackup() async {
    setState(() => _working = true);
    try {
      final householdId = AppContext.householdId;
      final options = ExportFilterOptions(
        includeFinance: _exportIncludeFinance,
        includeMetadata: _exportIncludeMetadata,
        startDate: _dateRange?.start,
        endDate: _dateRange?.end,
      );
      final content = await _smartExport.exportFilteredJson(
        householdId,
        options,
      );
      final directory = await getApplicationDocumentsDirectory();
      final stamp = _fileStamp(DateTime.now());
      final file = File('${directory.path}/ffm-ekspor-llm-$stamp.json');
      await file.writeAsString(content);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'Ekspor data FFM terfilter untuk analisis AI.',
        ),
      );
      if (!mounted) return;
      setState(
        () => _lastMessage =
            'Ekspor terfilter berhasil dibuat dan siap dibagikan.',
      );
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _lastMessage = 'Berkas ekspor belum berhasil dibuat. Coba lagi.',
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _exportFullBackup() async {
    setState(() => _working = true);
    try {
      final historyRepo = FfmAssistantChatHistoryRepository();
      final historyRows = await historyRepo.readRaw();
      // Filter path gambar jika ada, karena file tidak disalin
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
      );
      final directory = await getApplicationDocumentsDirectory();
      final stamp = _fileStamp(DateTime.now());
      final file = File('${directory.path}/ffm-cadangan-penuh-$stamp.json');
      await file.writeAsString(content);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'Cadangan penuh data FFM.',
        ),
      );
      if (!mounted) return;
      setState(
        () => _lastMessage = 'Cadangan penuh berhasil dibuat di perangkat.',
      );
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _lastMessage = 'Cadangan belum berhasil dibuat. Coba lagi.',
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _chooseDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: _dateRange,
      helpText: 'Pilih rentang transaksi',
      cancelText: 'Batal',
      confirmText: 'Pakai tanggal',
      saveText: 'Simpan',
    );
    if (!mounted || range == null) return;
    setState(() => _dateRange = range);
  }

  Future<void> _checkBackup() async {
    final path = await _pickJsonPath();
    if (path == null || !mounted) return;
    setState(() => _working = true);
    try {
      final preview = _service.previewJson(await File(path).readAsString());
      if (!mounted) return;
      setState(() => _lastMessage = _previewMessage(preview));
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() => _lastMessage = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _lastMessage = 'Berkas cadangan tidak bisa dibaca.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _restoreBackup() async {
    final path = await _pickJsonPath();
    if (path == null || !mounted) return;
    try {
      final content = await File(path).readAsString();
      final preview = _service.previewJson(content);
      if (!mounted) return;
      final confirmed = await _showRestorePreview(preview);
      if (!confirmed || !mounted) return;
      setState(() => _working = true);
      await _service.importAndRestore(
        path,
        onRestoreChatHistory: (rows) async {
          await FfmAssistantChatHistoryRepository().importRaw(rows);
        },
      );
      if (!mounted) return;
      setState(
        () => _lastMessage = 'Data berhasil dipulihkan. Semua data lokal sudah diganti sesuai cadangan.',
      );
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() => _lastMessage = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _lastMessage =
            'Pemulihan dibatalkan karena berkas tidak aman atau tidak cocok.',
      );
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

  Future<bool> _showRestorePreview(BackupPreview preview) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(
              preview.isFull
                  ? 'Cadangan siap dipulihkan'
                  : 'Ekspor transaksi terbatas',
            ),
            content: SingleChildScrollView(
              child: Text(
                preview.isFull
                    ? '${_previewMessage(preview)}\n\nPemulihan akan mengganti semua data lokal. Data lama tetap aman bila proses gagal karena pemulihan berjalan atomik.'
                    : '${_previewMessage(preview)}\n\nBerkas ini hanya untuk dibaca atau dibagikan. Ekspor terbatas tidak boleh dipakai untuk mengganti seluruh data lokal.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Tutup'),
              ),
              if (preview.isFull)
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Pulihkan dan ganti data'),
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
    final dana = preview.counts['sinking_funds'] ?? 0;
    final rentang = preview.transactionFrom == null
        ? 'belum ada transaksi'
        : '${_dateLabel(preview.transactionFrom!)} sampai ${_dateLabel(preview.transactionTo!)}';
    return 'Versi cadangan: ${preview.formatVersion}\n'
        'Transaksi: $transaksi ($rentang)\n'
        'Aset: $aset · Hutang: $hutang · Piutang: $piutang · Target: $target\n'
        'Anggaran: $anggaran · Pengingat: $pengingat · Dana Berkala: $dana\n'
        'Rekonsiliasi: $rekonsiliasi · Aktivitas: $aktivitas';
  }

  String _dateLabel(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _fileStamp(DateTime date) {
    return '${date.year}${date.month.toString().padLeft(2, '0')}'
        '${date.day.toString().padLeft(2, '0')}-'
        '${date.hour.toString().padLeft(2, '0')}'
        '${date.minute.toString().padLeft(2, '0')}'
        '${date.second.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final filtered =
        _dateRange != null || _typeFilter != 'all' || _categoryFilter != 'all';
    return FfmAssistantPageContext(
      destination: FfmAssistantDestination.backup,
      child: Scaffold(
        appBar: AppBar(title: const Text('Ekspor & Cadangan')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const AppHelpBanner(
              title: 'Cara pakainya',
              message: 'Cadangan penuh dipakai untuk pindah perangkat dan membawa data utama, transaksi, aset, hutang, piutang, target, anggaran, transfer, serta riwayat rekonsiliasi dan aktivitas. Ekspor analisa AI hanya membawa data sesuai filter.',
              icon: Icons.shield_outlined,
            ),
            const SizedBox(height: 12),
            AppCard(
              color: scheme.primaryContainer,

              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lock_outline, size: 32, color: scheme.primary),
                  const SizedBox(height: 14),
                  Text(
                    'Data tetap di perangkatmu.',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(color: scheme.onPrimaryContainer),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Cadangan disimpan sebagai JSON dan bisa dicek dulu sebelum dipulihkan. Tidak ada data yang dikirim ke internet oleh aplikasi.',
                    style: TextStyle(color: scheme.onPrimaryContainer),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const AppSectionHeader(title: 'Pilihan ekspor'),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _working ? null : _exportPdfReport,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Buat laporan PDF bulan ini'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _working ? null : _exportWeeklyPdfReport,
              icon: const Icon(Icons.date_range_outlined),
              label: const Text('Buat laporan PDF minggu ini'),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _working ? null : _exportBackup,
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text('Ekspor JSON analisa AI (bukan backup)'),
            ),
            const SizedBox(height: 10),
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
                'Opsional. Gambar yang dikirim tidak akan ikut dicadangkan.',
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            OutlinedButton.icon(
              onPressed: _working ? null : _exportFullBackup,
              icon: const Icon(Icons.backup_outlined),
              label: const Text('Buat cadangan penuh semua data (.json)'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _working ? null : _chooseDateRange,
              icon: const Icon(Icons.date_range_outlined),
              label: const Text('Pilih filter tanggal'),
            ),
            const SizedBox(height: 8),
            SearchableDropdown<String>(
              items: const ['all', 'income', 'expense'],
              selectedItem: _typeFilter,
              itemLabel: (value) => switch (value) {
                'income' => 'Pemasukan saja',
                'expense' => 'Pengeluaran saja',
                _ => 'Semua jenis',
              },
              labelText: 'Jenis transaksi',
              searchHintText: 'Cari jenis transaksi',
              cacheKey: 'backup.jenis_transaksi',
              enabled: !_working,
              onChanged: (value) {
                if (value != null) setState(() => _typeFilter = value);
              },
            ),
            const SizedBox(height: 8),
            SearchableDropdown<String>(
              items: ['all', ..._categoryLabels.keys],
              selectedItem: _categoryLabels.containsKey(_categoryFilter)
                  ? _categoryFilter
                  : 'all',
              itemLabel: (value) => value == 'all'
                  ? 'Semua kategori'
                  : _categoryLabels[value] ?? value,
              labelText: 'Kategori transaksi',
              searchHintText: 'Cari kategori transaksi',
              cacheKey: 'backup.kategori_transaksi',
              enabled: !_working,
              onChanged: (value) {
                if (value != null) setState(() => _categoryFilter = value);
              },
            ),
            const SizedBox(height: 18),
            AppCard(
              color: filtered
                  ? AppSemanticContainers.warningContainer(context)
                  : scheme.surfaceContainer,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    filtered ? Icons.filter_alt : Icons.filter_alt_off,
                    color: filtered
                        ? AppSemanticColors.warning(context)
                        : scheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      filtered
                          ? 'Filter aktif: hanya data yang kamu pilih yang ikut diekspor.'
                          : 'Belum ada filter: ekspor analisa akan memakai seluruh periode.',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: filtered
                            ? AppSemanticContainers.onWarningContainer(context)
                            : scheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const AppSectionHeader(
              title: 'JSON analisa untuk LLM (bukan cadangan)',
            ),
            const SizedBox(height: 8),
            AppCard(
              color: scheme.primaryContainer,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pilih modul dan periode di atas, lalu salin atau ekspor data analisa ke AI (Claude/ChatGPT). Berkas ini bukan backup dan tidak bisa dipakai untuk memulihkan seluruh aplikasi.',
                    style: TextStyle(color: scheme.onPrimaryContainer),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Pilih modul data yang ingin disertakan:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _exportIncludeFinance,
                    onChanged: _working
                        ? null
                        : (value) => setState(
                            () => _exportIncludeFinance = value ?? true,
                          ),
                    title: const Text('Keuangan Keluarga'),
                    subtitle: const Text(
                      'Transaksi, Aset, Hutang, Goal, Budget.',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _exportIncludeMetadata,
                    onChanged: _working
                        ? null
                        : (value) => setState(
                            () => _exportIncludeMetadata = value ?? true,
                          ),
                    title: const Text('Metadata & Master Data'),
                    subtitle: const Text('Kategori, Toko, Tag, Rekening.'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  const Divider(),
                  const Text(
                    'Opsi Rincian:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _analysisIncludeItems,
                    onChanged: _working
                        ? null
                        : (value) => setState(
                            () => _analysisIncludeItems = value ?? true,
                          ),
                    title: const Text('Sertakan rincian item belanja'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _analysisIncludeNotes,
                    onChanged: _working
                        ? null
                        : (value) => setState(
                            () => _analysisIncludeNotes = value ?? false,
                          ),
                    title: const Text('Sertakan catatan transaksi'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _working ? null : _copyAnalysisPrompt,
                        icon: const Icon(Icons.content_copy_outlined),
                        label: const Text('Salin prompt'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _working ? null : _copyAnalysisJson,
                        icon: const Icon(Icons.data_object_outlined),
                        label: const Text('Salin JSON'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _working
                            ? null
                            : () => _exportAnalysisFile('json'),
                        icon: const Icon(Icons.file_download_outlined),
                        label: const Text('Ekspor JSON'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _working
                            ? null
                            : () => _exportAnalysisFile('csv'),
                        icon: const Icon(Icons.table_chart_outlined),
                        label: const Text('Ekspor CSV'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _working
                            ? null
                            : () => _exportAnalysisFile('html'),
                        icon: const Icon(Icons.language_outlined),
                        label: const Text('Ekspor HTML'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const AppSectionHeader(
              title: 'JSON Export Studio untuk AI eksternal',
            ),
            const SizedBox(height: 8),
            AppCard(
              color: scheme.secondaryContainer,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Data tetap sama, tampilan laporan bisa berbeda. Salin prompt dan JSON ini ke Gemini atau Claude untuk membuat HTML, Markdown, atau bahan PDF.',
                    style: TextStyle(color: scheme.onSecondaryContainer),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _studioReportStyle,
                    decoration: const InputDecoration(
                      labelText: 'Gaya laporan AI',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'pembelajaran keluarga',
                        child: Text('Pembelajaran keluarga'),
                      ),
                      DropdownMenuItem(
                        value: 'manajemen keuangan formal',
                        child: Text('Manajemen keuangan formal'),
                      ),
                      DropdownMenuItem(
                        value: 'ringkasan visual santai',
                        child: Text('Ringkasan visual santai'),
                      ),
                    ],
                    onChanged: _working
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => _studioReportStyle = value);
                            }
                          },
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _studioIncludeFamilyProfile,
                    onChanged: _working
                        ? null
                        : (value) => setState(
                            () => _studioIncludeFamilyProfile = value ?? true,
                          ),
                    title: const Text('Sertakan nama rumah tangga dan anggota'),
                    subtitle: const Text(
                      'Bisa dimatikan jika laporan akan dibagikan umum.',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _studioIncludeActivities,
                    onChanged: _working
                        ? null
                        : (value) => setState(
                            () => _studioIncludeActivities = value ?? true,
                          ),
                    title: const Text('Sertakan aktivitas dan jurnal keluarga'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _studioAnonymizeIdentity,
                    onChanged: _working
                        ? null
                        : (value) => setState(
                            () => _studioAnonymizeIdentity = value ?? false,
                          ),
                    title: const Text('Samarkan nama, peserta, dan lokasi'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _studioAnonymizeAmounts,
                    onChanged: _working
                        ? null
                        : (value) => setState(
                            () => _studioAnonymizeAmounts = value ?? false,
                          ),
                    title: const Text('Samarkan nominal'),
                    subtitle: const Text(
                      'Persentase nominal tidak akan dihitung jika nominal disamarkan.',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _working ? null : _previewStudio,
                        icon: const Icon(Icons.visibility_outlined),
                        label: const Text('Preview JSON'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _working ? null : _copyStudioPrompt,
                        icon: const Icon(Icons.content_copy_outlined),
                        label: const Text('Salin prompt AI'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _working ? null : _copyStudioJson,
                        icon: const Icon(Icons.data_object_outlined),
                        label: const Text('Salin JSON Studio'),
                      ),
                      FilledButton.icon(
                        onPressed: _working ? null : _shareStudioJson,
                        icon: const Icon(Icons.share_outlined),
                        label: const Text('Bagikan JSON'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const AppSectionHeader(
              title: 'Masukkan hasil dari AI eksternal (opsional)',
            ),
            const SizedBox(height: 8),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tempel HTML atau Markdown hasil AI di bawah. FFM tidak mengubah angka; aplikasi hanya membantu preview dan membuat berkas HTML/PDF.',
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    minLines: 7,
                    maxLines: 14,
                    onChanged: (value) => _studioAiOutput = value,
                    decoration: const InputDecoration(
                      labelText: 'Hasil laporan AI',
                      hintText: 'Tempel hasil HTML atau Markdown di sini…',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _working || _studioAiOutput.trim().isEmpty
                            ? null
                            : () => showDialog<void>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Preview hasil AI'),
                                  content: SingleChildScrollView(
                                    child: SelectableText(
                                      _plainTextFromAiOutput(_studioAiOutput),
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('Tutup'),
                                    ),
                                  ],
                                ),
                              ),
                        icon: const Icon(Icons.visibility_outlined),
                        label: const Text('Preview hasil'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _working || _studioAiOutput.trim().isEmpty
                            ? null
                            : _shareAiHtml,
                        icon: const Icon(Icons.language_outlined),
                        label: const Text('Bagikan HTML'),
                      ),
                      FilledButton.icon(
                        onPressed: _working || _studioAiOutput.trim().isEmpty
                            ? null
                            : _shareAiPdf,
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('Buat PDF'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (filtered) ...[
              const SizedBox(height: 8),
              AppCard(
                color: AppSemanticContainers.warningContainer(context),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Mode ekspor terbatas aktif. Berkas ini bukan cadangan pemulihan penuh.',
                        style: TextStyle(
                          color: AppSemanticContainers.onWarningContainer(
                            context,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Hapus filter',
                      onPressed: _working
                          ? null
                          : () => setState(() {
                              _dateRange = null;
                              _typeFilter = 'all';
                              _categoryFilter = 'all';
                            }),
                      icon: Icon(
                        Icons.clear,
                        color: AppSemanticContainers.onWarningContainer(
                          context,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            const AppSectionHeader(title: 'Pilihan pemulihan'),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _working ? null : _restoreBackup,
              icon: const Icon(Icons.restore),
              label: const Text('Impor dan pulihkan dari file'),
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: _working ? null : _checkBackup,
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Cek berkas tanpa mengubah data'),
            ),
            if (_working) ...[
              const SizedBox(height: 20),
              AppCard(
                color: scheme.surfaceContainer,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sedang menyiapkan berkas…',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const LinearProgressIndicator(),
                  ],
                ),
              ),
            ],
            if (_lastMessage != null) ...[
              const SizedBox(height: 20),
              AppCard(
                color: AppSemanticContainers.positiveContainer(context),
                child: Text(
                  _lastMessage!,
                  style: TextStyle(
                    color: AppSemanticContainers.onPositiveContainer(context),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            const AppSectionHeader(title: 'Yang ikut dicadangkan'),
            const SizedBox(height: 8),
            const AppCard(
              child: Text(
                'Transaksi, aset, hutang, target, anggaran, pengingat, Dana Berkala, kategori, dan data pendukung lainnya. Berkas juga dilindungi checksum agar perubahan atau kerusakan bisa terdeteksi.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
