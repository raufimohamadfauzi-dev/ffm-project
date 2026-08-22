import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../shared/widgets/app_components.dart';
import '../../../assistant/domain/ffm_assistant_models.dart';
import '../../../assistant/presentation/widgets/ffm_assistant_page_context.dart';
import '../../data/services/receipt_import_models.dart';
import '../../data/services/receipt_import_service.dart';

/// Halaman khusus impor hasil JSON dari LLM. Tidak menyediakan OCR atau foto nota.
class ReceiptJsonImportPage extends StatefulWidget {
  const ReceiptJsonImportPage({super.key});

  @override
  State<ReceiptJsonImportPage> createState() => _ReceiptJsonImportPageState();
}

class _ReceiptJsonImportPageState extends State<ReceiptJsonImportPage> {
  ReceiptOcrResult? _result;

  Future<void> _pickJsonFile() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (files.isEmpty || files.single.path == null) return;
    try {
      final text = await File(files.single.path!).readAsString();
      _readJson(text);
    } on ReceiptImportException catch (error) {
      _showMessage(error.message);
    } catch (_) {
      _showMessage(
        'File JSON belum berhasil dibaca. Coba pilih file yang benar.',
      );
    }
  }

  Future<void> _pasteJson() async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => const _PasteReceiptJsonDialog(),
    );
    if (!mounted || text == null || text.trim().isEmpty) return;
    _readJson(text);
  }

  void _readJson(String text) {
    try {
      final result = ReceiptImportService.parseJson(text);
      setState(() => _result = result);
      _showMessage('JSON terbaca. Cek rangkumannya sebelum lanjut.');
    } on ReceiptImportException catch (error) {
      _showMessage(error.message);
    } catch (_) {
      _showMessage(
        'Format JSON belum sesuai. Salin ulang hasil LLM lalu coba lagi.',
      );
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return FfmAssistantPageContext(
      destination: FfmAssistantDestination.transactions,
      child: Scaffold(
        appBar: AppBar(title: const Text('Impor JSON transaksi')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            const AppHelpBanner(
              title: 'Masukkan hasil JSON dari LLM',
              message: 'Kirim foto nota atau teks mutasi ke LLM pilihanmu, lalu minta hasil JSON FFM. Di sini kamu hanya tempel atau pilih file JSON. FFM tidak membaca foto dan tidak menyimpan transaksi otomatis.',
              icon: Icons.data_object_rounded,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _pasteJson,
              icon: const Icon(Icons.content_paste_rounded),
              label: const Text('Tempel hasil JSON'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _pickJsonFile,
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('Pilih file JSON'),
            ),
            if (result != null) ...[
              const SizedBox(height: 16),
              _ImportPreview(result: result),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(result),
                icon: const Icon(Icons.edit_note_rounded),
                label: const Text('Lanjut cek dan edit transaksi'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ImportPreview extends StatelessWidget {
  const _ImportPreview({required this.result});

  final ReceiptOcrResult result;

  @override
  Widget build(BuildContext context) {
    final total = result.total ?? result.itemsTotal;
    final warnings = result.validationWarnings;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.fact_check_outlined),
              SizedBox(width: 8),
              Text(
                'Yang akan dicek di form transaksi',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _PreviewRow('Toko/catatan', result.merchant ?? 'Belum ada'),
          _PreviewRow('Total', total > 0 ? 'Rp$total' : 'Belum ada'),
          _PreviewRow('Jumlah item', '${result.items.length} item'),
          if (result.date != null)
            _PreviewRow(
              'Tanggal',
              '${result.date!.day.toString().padLeft(2, '0')}/${result.date!.month.toString().padLeft(2, '0')}/${result.date!.year}',
            ),
          if (result.items.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'Contoh item',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            ...result.items
                .take(4)
                .map(
                  (item) => Text('• ${item.name} — Rp${item.calculatedTotal}'),
                ),
            if (result.items.length > 4)
              Text('+ ${result.items.length - 4} item lain'),
          ],
          if (warnings.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...warnings.map(
              (warning) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('Perlu dicek: $warning'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 108, child: Text(label)),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _PasteReceiptJsonDialog extends StatefulWidget {
  const _PasteReceiptJsonDialog();

  @override
  State<_PasteReceiptJsonDialog> createState() =>
      _PasteReceiptJsonDialogState();
}

class _PasteReceiptJsonDialogState extends State<_PasteReceiptJsonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Tempel hasil JSON'),
      content: SizedBox(
        width: 520,
        child: TextField(
          controller: _controller,
          minLines: 8,
          maxLines: 14,
          decoration: const InputDecoration(
            hintText: 'Tempel JSON dari LLM di sini…',
            border: OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Baca JSON'),
        ),
      ],
    );
  }
}
