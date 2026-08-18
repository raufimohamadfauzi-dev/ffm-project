import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../shared/widgets/app_components.dart';
import '../../data/services/receipt_ocr_service.dart';

class ReceiptScanPage extends StatefulWidget {
  const ReceiptScanPage({super.key});

  @override
  State<ReceiptScanPage> createState() => _ReceiptScanPageState();
}

class _ReceiptScanPageState extends State<ReceiptScanPage> {
  var _working = false;
  ReceiptOcrResult? _result;

  Future<void> _pickImage() async {
    final result = await FilePicker.pickFiles(type: FileType.image);
    if (result.isEmpty || result.single.path == null) return;
    setState(() => _working = true);
    try {
      final value = await ReceiptOcrService().recognize(result.single.path!);
      if (mounted) setState(() => _result = value);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Scan struk')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            const AppHelpBanner(
              title: 'Scan lalu cek ulang',
              message: 'Pilih foto struk. Hasil bacaan hanya draf dan wajib dicek atau diedit sebelum disimpan sebagai transaksi.',
              icon: Icons.document_scanner_outlined,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _working ? null : _pickImage,
              icon: _working ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.photo_library_outlined),
              label: Text(_working ? 'Membaca struk...' : 'Pilih foto struk'),
            ),
            if (_result != null) ...[
              const SizedBox(height: 16),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const ListTile(leading: Icon(Icons.fact_check_outlined), title: Text('Hasil sementara'), subtitle: Text('Belum ada mesin OCR otomatis aktif di V1. Silakan isi transaksi secara manual setelah meninjau foto.')),
                    if (_result!.imagePath != null) ListTile(leading: const Icon(Icons.image_outlined), title: Text(_result!.imagePath!.split('/').last)),
                    FilledButton.tonal(onPressed: () => Navigator.pop(context, _result), child: const Text('Pakai hasil ini')),
                  ],
                ),
              ),
            ],
          ],
        ),
      );
}
