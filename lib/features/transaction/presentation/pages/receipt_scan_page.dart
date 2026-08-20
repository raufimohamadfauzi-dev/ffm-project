import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../shared/widgets/app_components.dart';
import '../../../../shared/widgets/hijri_date_components.dart';
import '../../data/services/receipt_import_service.dart';
import '../../data/services/receipt_ocr_service.dart';

class ReceiptScanPage extends StatefulWidget {
  const ReceiptScanPage({super.key});

  @override
  State<ReceiptScanPage> createState() => _ReceiptScanPageState();
}

class _ReceiptScanPageState extends State<ReceiptScanPage> {
  var _working = false;
  ReceiptOcrResult? _result;
  ReceiptOcrDiagnostic? _diagnostic;
  String? _selectedImagePath;
  final _imagePicker = ImagePicker();

  Future<void> _pickImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                'Masukkan foto nota',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text('Pilih dari galeri atau ambil foto baru.'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Pilih dari galeri'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Ambil foto dengan kamera'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 95,
        maxWidth: 2400,
        maxHeight: 3200,
      );
      if (picked == null || !mounted) return;
      setState(() {
        _selectedImagePath = picked.path;
        _result = null;
        _diagnostic = null;
      });
      _showMessage('Foto sudah masuk. FFM sedang membaca tulisannya...');
      await _analyzeSelectedImage();
    } catch (error) {
      final diagnostic = ReceiptOcrDiagnostic.fromFailure(error);
      if (mounted) {
        setState(() => _diagnostic = diagnostic);
        _showMessage('${diagnostic.title}: ${diagnostic.message}');
      }
    }
  }

  Future<void> _analyzeSelectedImage() async {
    final path = _selectedImagePath;
    if (path == null || path.isEmpty) {
      const diagnostic = ReceiptOcrDiagnostic.imageNotSelected;
      setState(() => _diagnostic = diagnostic);
      _showMessage('${diagnostic.title}: ${diagnostic.message}');
      return;
    }

    try {
      final file = File(path);
      if (!await file.exists() || await file.length() == 0) {
        const diagnostic = ReceiptOcrDiagnostic.imageUnreadable;
        if (mounted) {
          setState(() => _diagnostic = diagnostic);
          _showMessage('${diagnostic.title}: ${diagnostic.message}');
        }
        return;
      }
    } catch (error) {
      final diagnostic = ReceiptOcrDiagnostic.fromFailure(error);
      if (mounted) {
        setState(() => _diagnostic = diagnostic);
        _showMessage('${diagnostic.title}: ${diagnostic.message}');
      }
      return;
    }

    await _runTask(() async {
      final value = await ReceiptOcrService().recognize(path);
      if (!mounted) return;
      final diagnostic = ReceiptOcrDiagnostic.fromResult(value);
      setState(() {
        _result = value;
        _diagnostic = diagnostic;
      });
      _showOcrStatus(diagnostic);
    });
  }

  void _showOcrStatus(ReceiptOcrDiagnostic diagnostic) {
    _showMessage('${diagnostic.title}: ${diagnostic.message}');
  }

  Future<void> _importJson() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result.isEmpty || result.single.path == null) return;
    final picked = result.single;
    try {
      final text = await File(picked.path!).readAsString();
      _setImportedResult(ReceiptImportService.parseJson(text));
    } on ReceiptImportException catch (error) {
      _showMessage(error.message);
    } catch (_) {
      _showMessage('File JSON belum berhasil dibaca.');
    }
  }

  Future<void> _pasteJson() async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => const _LargeTextDialog(
        title: 'Tempel hasil Gemini',
        hint: 'Tempel hasil yang diberikan Gemini di sini. FFM akan membacanya sebagai draft nota.',
        actionLabel: 'Baca hasil',
      ),
    );
    if (!mounted || text == null || text.trim().isEmpty) return;
    try {
      _setImportedResult(ReceiptImportService.parseJson(text));
    } on ReceiptImportException catch (error) {
      _showMessage(error.message);
    }
  }

  Future<void> _manualText() async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => const _LargeTextDialog(
        title: 'Tulis atau tempel teks nota',
        hint: 'Contoh: Mie Sakura 3 PCS 2.000 6.000',
        actionLabel: 'Deteksi teks',
      ),
    );
    if (!mounted || text == null || text.trim().isEmpty) return;
    setState(() {
      _result = ReceiptOcrService().parseText(text);
    });
  }

  void _setImportedResult(ReceiptOcrResult value) {
    setState(() {
      _result = value;
    });
    _showMessage(
      'Hasil berhasil dibaca sebagai draft. Cek dan edit dulu sebelum dipakai.',
    );
  }

  Future<void> _runTask(Future<void> Function() task) async {
    setState(() => _working = true);
    try {
      await task();
    } catch (error) {
      if (mounted) {
        final diagnostic = ReceiptOcrDiagnostic.fromFailure(error);
        setState(() => _diagnostic = diagnostic);
        _showMessage('${diagnostic.title}: ${diagnostic.message}');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _editItem(int index) async {
    final result = _result;
    if (result == null) return;
    final updated = await showDialog<ReceiptOcrItem>(
      context: context,
      builder: (_) => _ReceiptItemDialog(item: result.items[index]),
    );
    if (!mounted || updated == null) return;
    final items = [...result.items]..[index] = updated;
    setState(() => _result = result.copyWith(items: items));
  }

  Future<void> _addItem() async {
    final result = _result;
    if (result == null) return;
    final item = await showDialog<ReceiptOcrItem>(
      context: context,
      builder: (_) => const _ReceiptItemDialog(),
    );
    if (!mounted || item == null) return;
    setState(() => _result = result.copyWith(items: [...result.items, item]));
  }

  void _removeItem(int index) {
    final result = _result;
    if (result == null) return;
    final items = [...result.items]..removeAt(index);
    setState(() => _result = result.copyWith(items: items));
  }

  void _useItemsTotal() {
    final result = _result;
    if (result == null || result.items.isEmpty) return;
    setState(() => _result = result.copyWith(total: result.itemsTotal));
  }

  Future<void> _sharePhoto() async {
    final path = _result?.imagePath;
    if (path == null || path.isEmpty) {
      _showMessage('Pilih foto nota dulu supaya bisa dibagikan.');
      return;
    }
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path)],
        text: 'Tolong baca nota ini dan balas memakai format JSON ffm-receipt-draft-v1.',
      ),
    );
  }

  Future<void> _copyPrompt() async {
    final rawText = _result?.rawText ?? '';
    await Clipboard.setData(
      ClipboardData(
        text: ReceiptImportService.buildGeminiPrompt(rawText: rawText),
      ),
    );
    _showMessage(
      rawText.isEmpty
          ? 'Instruksi Gemini sudah disalin. Kirim bersama foto atau teks nota ke Gemini.'
          : 'Instruksi sudah disalin. Tempel di Gemini bersama foto atau teks nota.',
    );
  }

  Future<void> _copyTemplateJson() async {
    await Clipboard.setData(
      ClipboardData(text: ReceiptImportService.templateJson()),
    );
    _showMessage(
      'Contoh format JSON sudah disalin. Ini opsi teknis; kamu tidak wajib mengeditnya sendiri.',
    );
  }

  Future<void> _shareJson() async {
    final result = _result;
    if (result == null) return;
    final directory = await getApplicationDocumentsDirectory();
    final file = File(
      '${directory.path}/ffm-nota-${DateTime.now().millisecondsSinceEpoch}.json',
    );
    await file.writeAsString(ReceiptImportService.toJson(result));
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: 'Draft nota FFM. Periksa JSON sebelum diimpor.',
      ),
    );
  }

  Future<void> _shareTemplateJson() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/ffm-receipt-template-v1.json');
    await file.writeAsString(ReceiptImportService.templateJson());
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: 'Template JSON nota FFM untuk diisi oleh Gemini atau LLM.',
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('Nota: foto atau Gemini')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          const AppHelpBanner(
            title: 'Pilih cara yang paling gampang',
            message: 'Kamu tidak perlu paham JSON. Pilih foto untuk dibaca langsung di HP, atau pakai bantuan Gemini kalau tulisan nota sulit terbaca. Untuk uji OCR offline, foto harus terang, nota rata dan tidak miring, kamera dekat tetapi seluruh nota tetap masuk. Hasilnya tetap draft dan wajib dicek sebelum disimpan.',
            icon: Icons.document_scanner_outlined,
          ),
          if (_diagnostic != null) ...[
            const SizedBox(height: 12),
            _buildDiagnosticCard(_diagnostic!),
          ],
          const SizedBox(height: 16),
          if (_selectedImagePath != null) ...[
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Foto nota sudah masuk',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      File(_selectedImagePath!),
                      width: double.infinity,
                      height: 220,
                      fit: BoxFit.contain,
                      errorBuilder: (_, error, __) => const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'Preview foto belum bisa ditampilkan, tetapi FFM tetap bisa mencoba membacanya.',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _working ? null : _analyzeSelectedImage,
                      icon: const Icon(Icons.document_scanner_outlined),
                      label: Text(
                        _working
                            ? 'Sedang menganalisis foto...'
                            : 'Analisis lagi dengan OCR offline',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          FilledButton.icon(
            onPressed: _working ? null : _pickImage,
            icon: _working
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_photo_alternate_outlined),
            label: Text(
              _working ? 'Sedang membaca foto...' : '1. Masukkan foto nota',
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _importJson,
                  icon: const Icon(Icons.file_open_outlined),
                  label: const Text('Pilih hasil Gemini'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _manualText,
                  icon: const Icon(Icons.text_fields),
                  label: const Text('Tulis teks nota'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AppCard(
            color: Theme.of(context).colorScheme.secondaryContainer
                .withValues(alpha: .45),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '2. Minta bantuan Gemini (opsional)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Pakai ini kalau foto atau tulisan nota sulit dibaca. Gemini membantu menuliskan isi nota. FFM tidak terhubung otomatis ke Gemini dan tidak langsung menyimpan hasilnya.',
                ),
                const SizedBox(height: 10),
                const Text(
                  'Cara pakai: salin instruksi → kirim ke Gemini bersama foto/teks nota → salin hasilnya → tempel di sini.',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _copyPrompt,
                      icon: const Icon(Icons.copy_all_outlined),
                      label: const Text('Salin instruksi ke Gemini'),
                    ),
                    FilledButton.icon(
                      onPressed: _pasteJson,
                      icon: const Icon(Icons.content_paste_go_outlined),
                      label: const Text('Tempel hasil Gemini di sini'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _importJson,
                      icon: const Icon(Icons.file_open_outlined),
                      label: const Text('Pilih file hasil Gemini'),
                    ),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.help_outline),
                      title: const Text('Opsi teknis JSON (boleh dilewati)'),
                      subtitle: const Text(
                        'Dipakai kalau kamu ingin melihat atau mengirim format JSON.',
                      ),
                      children: [
                        OutlinedButton.icon(
                          onPressed: _copyTemplateJson,
                          icon: const Icon(Icons.data_object_outlined),
                          label: const Text('Salin contoh format JSON'),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (result != null) ...[
            const SizedBox(height: 16),
            _buildResultCard(result),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, result),
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Cek selesai, pakai hasil ini di transaksi'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDiagnosticCard(ReceiptOcrDiagnostic diagnostic) {
    final success = diagnostic.isSuccess;
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      color: success ? scheme.secondaryContainer : scheme.errorContainer,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            success ? Icons.check_circle_outline : Icons.info_outline,
            color: success
                ? scheme.onSecondaryContainer
                : scheme.onErrorContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  diagnostic.title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(diagnostic.message),
                if (success)
                  Text(
                    'Jumlah item: ${diagnostic.itemCount}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard(ReceiptOcrResult result) {
    final warnings = result.validationWarnings;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Text(
                  'Draft nota',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'photo':
                      _sharePhoto();
                    case 'prompt':
                      _copyPrompt();
                    case 'json':
                      _shareJson();
                    case 'template':
                      _shareTemplateJson();
                    case 'paste':
                      _pasteJson();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'photo',
                    child: Text('Bagikan foto ke Gemini'),
                  ),
                  PopupMenuItem(
                    value: 'prompt',
                    child: Text('Salin prompt Gemini'),
                  ),
                  PopupMenuItem(
                    value: 'json',
                    child: Text('Bagikan JSON draft'),
                  ),
                  PopupMenuItem(
                    value: 'template',
                    child: Text('Bagikan template JSON kosong'),
                  ),
                  PopupMenuItem(
                    value: 'paste',
                    child: Text('Impor JSON Gemini'),
                  ),
                ],
              ),
            ],
          ),
          Text(
            result.merchant ?? 'Nama toko belum terbaca',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (result.date != null)
            HijriDateText(
              date: result.date!,
              includeSeconds: true,
              compact: true,
            ),
          if (result.receiptNumber != null)
            Text('Nomor nota: ${result.receiptNumber}'),
          const Divider(height: 24),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Lihat teks mentah hasil OCR'),
            subtitle: Text(
              result.rawText.trim().isEmpty
                  ? 'Belum ada teks yang terbaca'
                  : '${result.rawText.split(RegExp(r'\\r?\\n')).length} baris teks terbaca',
            ),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SelectableText(
                  result.rawText.trim().isEmpty
                      ? 'Teks OCR kosong. Coba foto lebih terang atau gunakan teks manual.'
                      : result.rawText,
                ),
              ),
            ],
          ),
          if (result.items.isEmpty)
            const Text(
              'Belum ada item. Tambahkan manual dari tombol di bawah.',
            ),
          ...result.items.asMap().entries.map(
            (entry) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(entry.value.name),
              subtitle: Text(
                '${_quantityLabel(entry.value)} × ${formatRupiahInput(entry.value.price.toString())}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    formatRupiahInput(entry.value.calculatedTotal.toString()),
                  ),
                  IconButton(
                    tooltip: 'Edit item',
                    onPressed: () => _editItem(entry.key),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: 'Hapus item dari draft',
                    onPressed: () => _removeItem(entry.key),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _addItem,
              icon: const Icon(Icons.add),
              label: const Text('Tambah item'),
            ),
          ),
          const Divider(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Total nota'),
            trailing: Text(
              result.total == null
                  ? 'Belum terbaca'
                  : 'Rp${formatRupiahInput(result.total.toString())}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          if (result.items.isNotEmpty)
            TextButton.icon(
              onPressed: _useItemsTotal,
              icon: const Icon(Icons.calculate_outlined),
              label: Text(
                'Pakai total item Rp${formatRupiahInput(result.itemsTotal.toString())}',
              ),
            ),
          if (result.paidAmount != null)
            Text('Bayar: Rp${formatRupiahInput(result.paidAmount.toString())}'),
          if (result.changeAmount != null)
            Text(
              'Kembali: Rp${formatRupiahInput(result.changeAmount.toString())}',
            ),
          if (warnings.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Perlu dicek:',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  ...warnings.map((warning) => Text('• $warning')),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _quantityLabel(ReceiptOcrItem item) {
    final quantity = item.quantity == item.quantity.roundToDouble()
        ? item.quantity.toStringAsFixed(0)
        : item.quantity.toString();
    return '$quantity ${item.unit ?? 'pcs'}';
  }
}

class _ReceiptItemDialog extends StatefulWidget {
  const _ReceiptItemDialog({this.item});

  final ReceiptOcrItem? item;

  @override
  State<_ReceiptItemDialog> createState() => _ReceiptItemDialogState();
}

class _ReceiptItemDialogState extends State<_ReceiptItemDialog> {
  late final TextEditingController _name;
  late final TextEditingController _quantity;
  late final TextEditingController _price;
  late final TextEditingController _unit;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _name = TextEditingController(text: item?.name ?? '');
    _quantity = TextEditingController(text: item?.quantity.toString() ?? '1');
    _price = TextEditingController(
      text: item == null ? '' : formatRupiahInput(item.price.toString()),
    );
    _unit = TextEditingController(text: item?.unit ?? 'pcs');
  }

  @override
  void dispose() {
    _name.dispose();
    _quantity.dispose();
    _price.dispose();
    _unit.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    final quantity = double.tryParse(_quantity.text.replaceAll(',', '.')) ?? 0;
    final price = parseRupiah(_price.text);
    if (name.isEmpty || quantity <= 0 || price <= 0) return;
    Navigator.pop(
      context,
      ReceiptOcrItem(
        name: name,
        quantity: quantity,
        price: price,
        unit: _unit.text.trim().isEmpty ? null : _unit.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.item == null ? 'Tambah item nota' : 'Edit item nota'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Nama barang'),
          ),
          TextField(
            controller: _quantity,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Jumlah'),
          ),
          TextField(
            controller: _unit,
            decoration: const InputDecoration(labelText: 'Satuan'),
          ),
          TextField(
            controller: _price,
            keyboardType: TextInputType.number,
            inputFormatters: [RupiahInputFormatter()],
            decoration: const InputDecoration(labelText: 'Harga satuan'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Batal'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Simpan item')),
    ],
  );
}

class _LargeTextDialog extends StatefulWidget {
  const _LargeTextDialog({
    required this.title,
    required this.hint,
    required this.actionLabel,
  });

  final String title;
  final String hint;
  final String actionLabel;

  @override
  State<_LargeTextDialog> createState() => _LargeTextDialogState();
}

class _LargeTextDialogState extends State<_LargeTextDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _controller,
      minLines: 8,
      maxLines: 16,
      autofocus: true,
      decoration: InputDecoration(
        hintText: widget.hint,
        alignLabelWithHint: true,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Batal'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text),
        child: Text(widget.actionLabel),
      ),
    ],
  );
}
