import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
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

  Future<void> _pickImage() async {
    final result = await FilePicker.pickFiles(type: FileType.image);
    if (result.isEmpty || result.single.path == null) return;
    await _runTask(() async {
      final value = await ReceiptOcrService().recognize(result.single.path!);
      if (!mounted) return;
      setState(() => _result = value);
      _showOcrStatus(value);
    });
  }

  void _showOcrStatus(ReceiptOcrResult value) {
    if (value.rawText.trim().isEmpty) {
      _showMessage(
        'Foto berhasil dipilih, tapi tulisan belum terbaca. Coba foto lebih terang dan tidak miring.',
      );
    } else if (value.items.isEmpty) {
      _showMessage(
        'Teks nota terbaca, tetapi item belum dikenali. Buka teks mentah atau tambahkan item manual.',
      );
    } else {
      _showMessage(
        'OCR selesai: ${value.items.length} item terbaca. Cek draft sebelum dipakai.',
      );
    }
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
        title: 'Tempel JSON Gemini',
        hint: 'Tempel balasan JSON dari Gemini di sini.',
        actionLabel: 'Baca JSON',
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
    _showMessage('Draft nota berhasil dimuat. Cek dan edit sebelum dipakai.');
  }

  Future<void> _runTask(Future<void> Function() task) async {
    setState(() => _working = true);
    try {
      await task();
    } catch (_) {
      if (mounted) _showMessage('Nota belum berhasil diproses. Coba lagi.');
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
          ? 'Template prompt Gemini sudah disalin. Tambahkan teks atau foto nota di Gemini.'
          : 'Prompt Gemini sudah disalin. Tinggal tempel di Gemini.',
    );
  }

  Future<void> _copyTemplateJson() async {
    await Clipboard.setData(
      ClipboardData(text: ReceiptImportService.templateJson()),
    );
    _showMessage(
      'Template JSON kosong sudah disalin. Isi atau minta LLM mengisinya tanpa mengubah format.',
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
      appBar: AppBar(title: const Text('Scan dan baca nota')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          const AppHelpBanner(
            title: 'Baca nota, cek dulu, baru simpan',
            message: 'OCR berjalan di perangkat. Gemini tidak terhubung otomatis; kamu bisa membagikan foto atau menyalin prompt, lalu impor JSON-nya kembali setelah mengecek hasil.',
            icon: Icons.document_scanner_outlined,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _working ? null : _pickImage,
            icon: _working
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.photo_library_outlined),
            label: Text(
              _working ? 'Membaca nota...' : 'Pilih foto nota dari galeri',
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _importJson,
                  icon: const Icon(Icons.file_open_outlined),
                  label: const Text('Impor JSON'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _manualText,
                  icon: const Icon(Icons.text_fields),
                  label: const Text('Teks manual'),
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
                  'Pakai Gemini secara manual (opsional)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Bagikan foto atau salin prompt ke Gemini. Setelah mendapat JSON, impor kembali ke sini. Hasilnya tetap draft dan belum tersimpan sebelum kamu menekan tombol konfirmasi.',
                ),
                const SizedBox(height: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _copyPrompt,
                      icon: const Icon(Icons.copy_all_outlined),
                      label: const Text('1. Salin prompt Gemini/LLM'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _copyTemplateJson,
                      icon: const Icon(Icons.data_object_outlined),
                      label: const Text('2. Salin template JSON kosong'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _pasteJson,
                      icon: const Icon(Icons.content_paste_go_outlined),
                      label: const Text('3. Tempel JSON hasil LLM'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _importJson,
                      icon: const Icon(Icons.file_open_outlined),
                      label: const Text('4. Impor file JSON'),
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
              label: const Text('Pakai hasil ini di transaksi'),
            ),
          ],
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
