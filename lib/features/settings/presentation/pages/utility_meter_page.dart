import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_context.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/gemini_service.dart';
import '../../../assistant/domain/ffm_assistant_models.dart';
import '../../../assistant/presentation/widgets/ffm_assistant_page_context.dart';
import '../../data/utility_meter_repository.dart';
import '../../domain/entities/utility_meter_models.dart';

/// Halaman Token Listrik PLN (Pillar 3).
///
/// Menyimpan daftar nomor meteran PLN untuk berbagai lokasi/keperluan
/// (Rumah, Sawah/Ladang Pompa Air, Ruko Usaha, Kontrakan),
/// serta menyediakan tombol 1-ketukan untuk menyalin nomor meteran dan token 20-digit.
class UtilityMeterPage extends StatefulWidget {
  const UtilityMeterPage({super.key});

  @override
  State<UtilityMeterPage> createState() => _UtilityMeterPageState();
}

class _UtilityMeterPageState extends State<UtilityMeterPage> {
  late final UtilityMeterRepository _repository;
  List<UtilityMeter> _meters = [];
  Map<String, List<UtilityPurchaseHistory>> _historyByMeter = const {};
  Map<String, ElectricityUsageSummary> _summaryByMeter = const {};
  Map<String, List<PeriodUsage>> _periodDataByMeter = const {};
  Map<String, MeterReading?> _latestReadingByMeter = const {};
  Map<String, ElectricityBurnRate?> _burnRateByMeter = const {};
  String _chartPeriod = 'monthly';
  bool _isLoading = true;
  String _filterType = 'all'; // all, rumah, sawah, ruko, kontrakan
  String _sortBy = 'cost'; // cost, consumption, name
  List<UtilityMeter> _filteredMeters = [];

  @override
  void initState() {
    super.initState();
    _repository = getIt<UtilityMeterRepository>();
    _loadMeters();
  }

  Future<void> _loadMeters() async {
    setState(() => _isLoading = true);
    final householdId = AppContext.householdId;
    final list = await _repository.getAllMeters(householdId);
    final history = <String, List<UtilityPurchaseHistory>>{};
    final summaries = <String, ElectricityUsageSummary>{};
    final periodData = <String, List<PeriodUsage>>{};
    final latestReadings = <String, MeterReading?>{};
    final burnRates = <String, ElectricityBurnRate?>{};
    for (final meter in list) {
      history[meter.id] = await _repository.getPurchaseHistory(
        householdId,
        meterId: meter.id,
        limit: 5,
      );
      summaries[meter.id] = await _repository.summarizeUsage(
        householdId,
        meterId: meter.id,
      );
      periodData[meter.id] = await _repository.summarizeUsageByPeriod(
        householdId,
        meterId: meter.id,
        period: _chartPeriod,
        limit: _chartPeriod == 'daily'
            ? 14
            : (_chartPeriod == 'weekly' ? 8 : 6),
        includeReadings: true,
      );
      latestReadings[meter.id] = await _repository.getLatestReading(
        householdId,
        meter.id,
      );
      burnRates[meter.id] = await _repository.calculateBurnRate(
        householdId,
        meter.id,
      );
    }
    if (!mounted) return;
    setState(() {
      _meters = list;
      _historyByMeter = history;
      _summaryByMeter = summaries;
      _periodDataByMeter = periodData;
      _latestReadingByMeter = latestReadings;
      _burnRateByMeter = burnRates;
      _isLoading = false;
      _applyFilterAndSort();
    });
  }

  void _applyFilterAndSort() {
    var filtered = List<UtilityMeter>.from(_meters);

    // Apply filter
    if (_filterType != 'all') {
      filtered = filtered.where((meter) {
        final name = meter.name.toLowerCase();
        switch (_filterType) {
          case 'rumah':
            return name.contains('rumah') ||
                name.contains('utama') ||
                name.contains('main');
          case 'sawah':
            return name.contains('sawah') ||
                name.contains('ladang') ||
                name.contains('pompa');
          case 'ruko':
            return name.contains('ruko') ||
                name.contains('toko') ||
                name.contains('usaha');
          case 'kontrakan':
            return name.contains('kontrakan') || name.contains('kos');
          default:
            return true;
        }
      }).toList();
    }

    // Apply sort
    switch (_sortBy) {
      case 'cost':
        filtered.sort((a, b) {
          final costA = _summaryByMeter[a.id]?.totalCost.round() ?? 0;
          final costB = _summaryByMeter[b.id]?.totalCost.round() ?? 0;
          return costB.compareTo(costA);
        });
        break;
      case 'consumption':
        filtered.sort((a, b) {
          final kwhA = _burnRateByMeter[a.id]?.dailyKwh ?? 0.0;
          final kwhB = _burnRateByMeter[b.id]?.dailyKwh ?? 0.0;
          return kwhB.compareTo(kwhA);
        });
        break;
      case 'name':
        filtered.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        break;
    }

    setState(() => _filteredMeters = filtered);
  }

  Future<void> _changeChartPeriod(String period) async {
    if (_chartPeriod == period) return;
    setState(() => _chartPeriod = period);
    final householdId = AppContext.householdId;
    final periodData = <String, List<PeriodUsage>>{};
    for (final meter in _meters) {
      periodData[meter.id] = await _repository.summarizeUsageByPeriod(
        householdId,
        meterId: meter.id,
        period: period,
        limit: period == 'daily' ? 14 : (period == 'weekly' ? 8 : 6),
        includeReadings: true,
      );
    }
    if (!mounted) return;
    setState(() => _periodDataByMeter = periodData);
  }

  Future<void> _exportReport(UtilityMeter meter) async {
    final report = await _repository.exportMeterReport(
      meter.householdId,
      meterId: meter.id,
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.receipt_long_rounded),
            const SizedBox(width: 8),
            Expanded(child: Text('Laporan ${meter.name}')),
          ],
        ),
        content: SingleChildScrollView(
          child: SelectableText(
            report,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tutup'),
          ),
          FilledButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: report));
              Navigator.pop(ctx);
              _copyToClipboard(
                report,
                'Laporan ${meter.name} berhasil disalin ke clipboard!',
              );
            },
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Salin Semua'),
          ),
        ],
      ),
    );
  }

  void _copyToClipboard(String text, String successMessage) {
    Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(successMessage)),
          ],
        ),
        backgroundColor: const Color(0xFF059669),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _showAddEditDialog([UtilityMeter? meter]) async {
    final isEditing = meter != null;
    final nameCtrl = TextEditingController(text: meter?.name ?? '');
    final numberCtrl = TextEditingController(text: meter?.meterNumber ?? '');
    final customerCtrl = TextEditingController(text: meter?.customerName ?? '');
    final tariffCtrl = TextEditingController(
      text: meter?.tariffPower ?? 'R1/900VA',
    );
    final locationCtrl = TextEditingController(text: meter?.location ?? '');
    final notesCtrl = TextEditingController(text: meter?.notes ?? '');
    final tokenCtrl = TextEditingController(text: meter?.lastTokenNumber ?? '');

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(
            isEditing ? 'Ubah Data Meteran' : 'Tambah Meteran Listrik',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nama Properti / Meteran *',
                    hintText: 'Misal: Rumah Utama, Pompa Sawah, Ruko',
                    prefixIcon: Icon(Icons.label_outline_rounded),
                  ),
                  autofocus: !isEditing,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: numberCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Nomor Meter / IDPEL (11-12 Digit) *',
                    hintText: 'Contoh: 14238765432',
                    prefixIcon: Icon(Icons.pin_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: customerCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nama Pelanggan Terdaftar (PLN)',
                    hintText: 'Contoh: a.n. Raufi Fauzi / H. Ahmad',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tariffCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Golongan Daya / Tarif',
                    hintText: 'Misal: R1/900VA, R1/1300VA, B1/2200VA',
                    prefixIcon: Icon(Icons.bolt_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: locationCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Lokasi / Alamat Fisik',
                    hintText: 'Misal: Blok Karanganyar RT 03 / Sawah Blok C',
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tokenCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Kode Token 20 Digit Terakhir (Opsional)',
                    hintText: '20 digit angka tanpa spasi/strip',
                    prefixIcon: Icon(Icons.key_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Catatan Khusus (Opsional)',
                    hintText: 'Misal: Pompa sibel air sawah musim rendeng',
                    prefixIcon: Icon(Icons.notes_rounded),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final number = numberCtrl.text.trim().replaceAll(
                  RegExp(r'\D'),
                  '',
                );
                if (name.isEmpty || number.length < 9) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Nama dan Nomor Meter (min 9 digit) wajib diisi!',
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                final duplicate = await _repository.findMeterByNumber(
                  AppContext.householdId,
                  number,
                );
                if (duplicate != null && duplicate.id != meter?.id) {
                  if (!ctx.mounted) return;
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text('Nomor meter/IDPEL ini sudah terdaftar.'),
                    ),
                  );
                  return;
                }

                final householdId = AppContext.householdId;
                final cleanToken = tokenCtrl.text.trim().replaceAll(
                  RegExp(r'\D'),
                  '',
                );
                if (cleanToken.isNotEmpty && cleanToken.length != 20) {
                  if (!ctx.mounted) return;
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text('Kode token harus persis 20 digit angka.'),
                    ),
                  );
                  return;
                }

                final newMeter = UtilityMeter(
                  id: meter?.id ?? const Uuid().v4(),
                  householdId: householdId,
                  name: name,
                  meterNumber: number,
                  customerName: customerCtrl.text.trim(),
                  tariffPower: tariffCtrl.text.trim(),
                  location: locationCtrl.text.trim(),
                  notes: notesCtrl.text.trim(),
                  createdAt: meter?.createdAt ?? DateTime.now(),
                  lastTokenNumber: cleanToken.isNotEmpty
                      ? cleanToken
                      : meter?.lastTokenNumber,
                  lastPurchasedAt: cleanToken.isNotEmpty
                      ? (meter?.lastPurchasedAt ?? DateTime.now())
                      : meter?.lastPurchasedAt,
                  lastAmount: meter?.lastAmount,
                );

                await _repository.saveMeter(newMeter);
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                }
                if (mounted) {
                  _loadMeters();
                }
              },
              child: Text(isEditing ? 'Simpan Perubahan' : 'Tambahkan'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmDelete(UtilityMeter meter) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Meteran?'),
        content: Text(
          'Apakah kamu yakin ingin menghapus data meteran "${meter.name}" (${meter.meterNumber})?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await _repository.deleteMeter(meter.householdId, meter.id);
      _loadMeters();
    }
  }

  Future<void> _quickUpdateToken(UtilityMeter meter) async {
    final tokenCtrl = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Perbarui Token: ${meter.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: tokenCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Kode Token 20 Digit Baru *',
                  hintText: 'Contoh: 12345678901234567890',
                  prefixIcon: Icon(Icons.key_rounded),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              const Text(
                'Ini hanya menyimpan kode token. Untuk mencatat pembelian dan pengeluaran sekaligus, pindai struk lewat Asisten FFM.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () async {
                final cleanToken = tokenCtrl.text.trim().replaceAll(
                  RegExp(r'\D'),
                  '',
                );
                if (cleanToken.length != 20) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Kode token harus persis 20 digit angka!'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                await _repository.updateLastToken(
                  householdId: meter.householdId,
                  meterNumber: meter.meterNumber,
                  tokenCode: cleanToken,
                  timestamp: DateTime.now(),
                );

                if (ctx.mounted) {
                  Navigator.pop(ctx);
                }
                if (mounted) {
                  _loadMeters();
                  _copyToClipboard(
                    cleanToken,
                    'Token 20-digit disimpan dan disalin ke clipboard!',
                  );
                }
              },
              child: const Text('Simpan Token & Salin'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showMeterReadingDialog(UtilityMeter meter) async {
    final readingCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final latest = _latestReadingByMeter[meter.id];
    var recordedAt = DateTime.now();
    var isSaving = false;
    String? validationMessage;

    var isScanningLcd = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final parsedReading = double.tryParse(
            readingCtrl.text.trim().replaceAll(',', '.'),
          );
          final isLower =
              latest != null &&
              parsedReading != null &&
              parsedReading < latest.readingKwh;
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.speed_rounded),
                SizedBox(width: 8),
                Expanded(child: Text('Catat Pembacaan Meter')),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.lightbulb_outline_rounded, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Lihat angka kWh pada layar digital meter PLN. '
                            'Catat angka yang terlihat, biasanya 5-6 digit sebelum titik desimal.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: readingCtrl,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => setDialogState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Angka kWh *',
                      hintText: 'Contoh: 10112 atau 10112.3',
                      prefixIcon: const Icon(Icons.electric_bolt_rounded),
                      suffixIcon: isScanningLcd
                          ? const Padding(
                              padding: EdgeInsets.all(12.0),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : IconButton(
                              tooltip: 'Foto Layar Meteran PLN',
                              icon: const Icon(Icons.camera_alt_outlined),
                              onPressed: () async {
                                final picker = ImagePicker();
                                final file = await picker.pickImage(
                                  source: ImageSource.camera,
                                  maxWidth: 1600,
                                  maxHeight: 1600,
                                  imageQuality: 85,
                                );
                                if (file == null) return;
                                setDialogState(() => isScanningLcd = true);
                                try {
                                  final gemini = GeminiService();
                                  final bytes = await file.readAsBytes();
                                  final mimeType =
                                      file.path.toLowerCase().endsWith('.png')
                                      ? 'image/png'
                                      : 'image/jpeg';
                                  final result = await gemini.chat(
                                    prompt:
                                        'Lihat gambar layar LCD meteran listrik PLN ini. '
                                        'Tolong baca angka pembacaan kWh yang tertera pada layar. '
                                        'Balas HANYA angka numerik saja (contoh: 12345.6 atau 9821), '
                                        'tanpa tulisan kWh atau kata lain.',
                                    image: GeminiImageInput(
                                      base64Data: base64Encode(bytes),
                                      mimeType: mimeType,
                                    ),
                                    maxOutputTokens: 30,
                                  );
                                  if (!ctx.mounted) return;
                                  if (result.ok && result.text != null) {
                                    final match = RegExp(r'\d+(?:[.,]\d+)*')
                                        .firstMatch(result.text!);
                                    if (match != null) {
                                      var raw = match.group(0)!;
                                      if (raw.contains('.') &&
                                          raw.contains(',')) {
                                        raw = raw
                                            .replaceAll('.', '')
                                            .replaceAll(',', '.');
                                      } else if (raw.contains(',')) {
                                        raw = raw.replaceAll(',', '.');
                                      }
                                      final val = double.tryParse(raw);
                                      if (val != null) {
                                        setDialogState(() {
                                          readingCtrl.text = raw;
                                        });
                                        ScaffoldMessenger.of(ctx).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Angka kWh ($raw) berhasil dibaca dari foto!',
                                            ),
                                            duration: const Duration(
                                              seconds: 2,
                                            ),
                                          ),
                                        );
                                      }
                                    } else {
                                      ScaffoldMessenger.of(ctx).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Angka pada LCD tidak terbaca jelas. Pastikan foto terang dan tidak silau.',
                                          ),
                                          backgroundColor: Colors.orange,
                                        ),
                                      );
                                    }
                                  }
                                } catch (e) {
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Gagal memproses foto: $e',
                                        ),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                } finally {
                                  setDialogState(() => isScanningLcd = false);
                                }
                              },
                            ),
                    ),
                  ),

                  if (isLower) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Pembacaan lebih rendah dari sebelumnya '
                      '(${latest.readingKwh.toStringAsFixed(2)} kWh). Pastikan angka sudah benar.',
                      style: TextStyle(
                        color: Theme.of(ctx).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_today_outlined),
                    title: const Text('Tanggal pembacaan'),
                    subtitle: Text(_formatDate(recordedAt)),
                    onTap: () async {
                      final selected = await showDatePicker(
                        context: ctx,
                        initialDate: recordedAt,
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now().add(const Duration(days: 1)),
                      );
                      if (selected != null) {
                        setDialogState(() {
                          recordedAt = DateTime(
                            selected.year,
                            selected.month,
                            selected.day,
                            recordedAt.hour,
                            recordedAt.minute,
                          );
                        });
                      }
                    },
                  ),
                  TextField(
                    controller: noteCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Catatan (opsional)',
                      hintText: 'Contoh: setelah perbaikan listrik',
                      prefixIcon: Icon(Icons.notes_outlined),
                    ),
                  ),
                  if (validationMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      validationMessage!,
                      style: TextStyle(
                        color: Theme.of(ctx).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(ctx),
                child: const Text('Batal'),
              ),
              FilledButton.icon(
                onPressed: isSaving || isLower
                    ? null
                    : () async {
                        final value = double.tryParse(
                          readingCtrl.text.trim().replaceAll(',', '.'),
                        );
                        if (value == null || value < 0) {
                          setDialogState(
                            () => validationMessage =
                                'Masukkan angka kWh yang valid.',
                          );
                          return;
                        }
                        setDialogState(() => isSaving = true);
                        try {
                          await _repository.recordMeterReading(
                            householdId: meter.householdId,
                            meterId: meter.id,
                            readingKwh: value,
                            recordedAt: recordedAt,
                            note: noteCtrl.text.trim().isEmpty
                                ? null
                                : noteCtrl.text.trim(),
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) await _loadMeters();
                        } catch (error) {
                          setDialogState(() {
                            isSaving = false;
                            validationMessage = error.toString().replaceFirst(
                              'Bad state: ',
                              '',
                            );
                          });
                        }
                      },
                icon: const Icon(Icons.save_outlined),
                label: const Text('Simpan'),
              ),
            ],
          );
        },
      ),
    );
    readingCtrl.dispose();
    noteCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return FfmAssistantPageContext(
      destination: FfmAssistantDestination.utilityMeter,
      dataSummary: _meters.isEmpty
          ? 'Belum ada nomor meteran listrik PLN yang tersimpan.'
          : '${_meters.length} meteran PLN tersimpan: ${_meters.map((m) => "${m.name} (${m.meterNumber})").join(", ")}.',
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Token Listrik',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          actions: [
            IconButton(
              tooltip: 'Tambah Meteran',
              icon: const Icon(Icons.add_rounded),
              onPressed: () => _showAddEditDialog(),
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadMeters,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                  children: [
                    // Info banner
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1E293B)
                            : const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFF3B82F6).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.electric_bolt_rounded,
                            color: Color(0xFF2563EB),
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Kelola Token & Meteran Listrik',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5,
                                    color: isDark
                                        ? const Color(0xFF93C5FD)
                                        : const Color(0xFF1D4ED8),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Simpan nomor IDPEL/meteran PLN rumah, sawah ladang, ruko, atau kontrakan. Salin nomor meter atau 20-digit token dengan 1-ketukan saat beli pulsa listrik!',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Summary Section: Total Semua Meteran
                    if (_meters.isNotEmpty)
                      _buildSummarySection(context, isDark),
                    const SizedBox(height: 20),

                    // Alert Banner: Token Hampir Habis
                    _buildAlertBanner(context, isDark),
                    const SizedBox(height: 12),

                    // Quick Actions
                    _buildQuickActions(context, isDark),
                    const SizedBox(height: 12),

                    // Grafik Komparatif Antar Rumah
                    if (_meters.isNotEmpty)
                      _buildComparisonChart(context, isDark),
                    const SizedBox(height: 20),

                    // Section Header: Daftar Rumah Terdaftar
                    Row(
                      children: [
                        const Icon(
                          Icons.home_work_rounded,
                          size: 20,
                          color: Color(0xFF2563EB),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Daftar Rumah Terdaftar (${_filteredMeters.length})',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1D4ED8),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Filter & Sort Chips
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        // Filter Chips
                        _buildFilterChip('Semua', 'all', isDark),
                        _buildFilterChip('Rumah', 'rumah', isDark),
                        _buildFilterChip('Sawah', 'sawah', isDark),
                        _buildFilterChip('Ruko', 'ruko', isDark),
                        _buildFilterChip('Kontrakan', 'kontrakan', isDark),
                        const SizedBox(width: 8),
                        // Sort Button
                        DropdownButton<String>(
                          value: _sortBy,
                          icon: const Icon(Icons.sort_rounded, size: 18),
                          style: TextStyle(
                            fontSize: 12,
                            color: const Color(0xFF1D4ED8),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'cost',
                              child: Text('Biaya Tertinggi'),
                            ),
                            DropdownMenuItem(
                              value: 'consumption',
                              child: Text('Konsumsi Tertinggi'),
                            ),
                            DropdownMenuItem(
                              value: 'name',
                              child: Text('Nama A-Z'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _sortBy = value);
                              _applyFilterAndSort();
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (_filteredMeters.isEmpty)
                      _buildEmptyState(context, isDark)
                    else
                      ..._filteredMeters.map(
                        (meter) => _buildMeterCard(context, meter, isDark),
                      ),
                  ],
                ),
              ),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'add_utility_meter_fab',
          onPressed: () => _showAddEditDialog(),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Tambah Meteran'),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
            ),
            child: Icon(
              Icons.bolt_rounded,
              size: 56,
              color: isDark ? Colors.amber[400] : Colors.amber[700],
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Belum Ada Meteran Terdaftar',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Tambahkan nomor meteran PLN rumah, pompa sawah ladang, atau tokomu agar tidak perlu bolak-balik cari meteran fisik atau struk lama!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurface
                  .withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 24),

          // Tutorial Steps
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      size: 18,
                      color: Color(0xFF6366F1),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Cara Menggunakan',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF6366F1),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildTutorialStep(
                  '1',
                  'Daftarkan meteran listrik Anda',
                  'Tekan tombol + di bawah untuk menambahkan IDPEL/ID meteran.',
                  isDark,
                ),
                const SizedBox(height: 8),
                _buildTutorialStep(
                  '2',
                  'Catat pembelian token di assistant',
                  'Upload struk pembelian token ke assistant, otomatis tersimpan di riwayat.',
                  isDark,
                ),
                const SizedBox(height: 8),
                _buildTutorialStep(
                  '3',
                  'Catat pembacaan meter secara rutin',
                  'Gunakan tombol "Catat Pembacaan" agar estimasi konsumsi lebih akurat.',
                  isDark,
                ),
                const SizedBox(height: 8),
                _buildTutorialStep(
                  '4',
                  'Lihat grafik konsumsi di sini',
                  'Analisis tren dan perbandingan konsumsi antar rumah.',
                  isDark,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _showAddEditDialog(),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Mulai Mendaftarkan'),
          ),
        ],
      ),
    );
  }

  Widget _buildTutorialStep(
    String number,
    String title,
    String description,
    bool isDark,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: const Color(0xFF6366F1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF1D4ED8),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark
                      ? Colors.white70
                      : const Color(0xFF1D4ED8).withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummarySection(BuildContext context, bool isDark) {
    // Calculate total across all meters
    int totalPurchases = 0;
    int totalCost = 0;
    double totalKwh = 0;
    UtilityMeter? mostExpensiveMeter;
    int maxCost = 0;

    for (final meter in _meters) {
      final summary = _summaryByMeter[meter.id];
      if (summary != null) {
        totalPurchases += summary.purchaseCount;
        totalCost += summary.totalCost.round();
        totalKwh += summary.totalCreditedKwh;
        if (summary.totalCost.round() > maxCost) {
          maxCost = summary.totalCost.round();
          mostExpensiveMeter = meter;
        }
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1E3A8A), const Color(0xFF172554)]
              : [const Color(0xFFDBEAFE), const Color(0xFFBFDBFE)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF3B82F6).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.analytics_rounded,
                color: Color(0xFF2563EB),
                size: 22,
              ),
              const SizedBox(width: 8),
              const Text(
                'Ringkasan Semua Meteran',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1D4ED8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildSummaryMetric(
                  'Total Pembelian',
                  totalPurchases.toString(),
                  'kali',
                  isDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSummaryMetric(
                  'Total Biaya',
                  'Rp ${_formatNumber(totalCost.round())}',
                  '',
                  isDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildSummaryMetric(
                  'Total kWh',
                  totalKwh > 0 ? '${totalKwh.toStringAsFixed(1)} kWh' : '0 kWh',
                  '',
                  isDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSummaryMetric(
                  'Rata-rata',
                  totalKwh > 0 && totalCost > 0
                      ? 'Rp ${(totalCost / totalKwh).round()}/kWh'
                      : '-',
                  '',
                  isDark,
                ),
              ),
            ],
          ),
          if (mostExpensiveMeter != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF0F172A).withValues(alpha: 0.5)
                    : Colors.white.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: Color(0xFF2563EB),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Rumah paling banyak biaya: ${mostExpensiveMeter.name}',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? Colors.white70
                            : const Color(0xFF1D4ED8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryMetric(
    String label,
    String value,
    String unit,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF0F172A).withValues(alpha: 0.5)
            : Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: isDark ? Colors.white60 : const Color(0xFF1D4ED8),
            ),
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF1D4ED8),
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 2),
                Text(
                  unit,
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark ? Colors.white60 : const Color(0xFF1D4ED8),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context, bool isDark) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ActionChip(
          avatar: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Tambah Meteran'),
          onPressed: () => _showAddEditDialog(),
          backgroundColor: isDark
              ? const Color(0xFF1E293B)
              : const Color(0xFFF1F5F9),
        ),
        ActionChip(
          avatar: const Icon(Icons.speed_rounded, size: 18),
          label: const Text('Catat Pembacaan'),
          onPressed: () {
            if (_meters.isNotEmpty) {
              _showMeterReadingDialog(_meters.first);
            }
          },
          backgroundColor: isDark
              ? const Color(0xFF1E293B)
              : const Color(0xFFF1F5F9),
        ),
        ActionChip(
          avatar: const Icon(Icons.analytics_rounded, size: 18),
          label: const Text('Analisis Konsumsi'),
          onPressed: () {
            // Navigate to assistant with query
            Navigator.of(context).pushNamed('/assistant');
          },
          backgroundColor: isDark
              ? const Color(0xFF1E293B)
              : const Color(0xFFF1F5F9),
        ),
      ],
    );
  }

  Widget _buildAlertBanner(BuildContext context, bool isDark) {
    // Find meters with remaining days < 5
    final criticalMeters = _meters.where((meter) {
      final burnRate = _burnRateByMeter[meter.id];
      return burnRate != null &&
          burnRate.daysRemaining != null &&
          burnRate.daysRemaining! < 5;
    }).toList();

    if (criticalMeters.isEmpty) {
      // Show info banner if no burn rate data available
      final noDataMeters = _meters.where((meter) {
        final burnRate = _burnRateByMeter[meter.id];
        return burnRate == null || burnRate.daysRemaining == null;
      }).toList();

      if (noDataMeters.isNotEmpty) {
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.info_outline_rounded,
                size: 16,
                color: Colors.amber,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ℹ️ Estimasi habis tidak tersedia. Catat pembacaan meter secara rutin agar estimasi lebih akurat.',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white70 : const Color(0xFF594A00),
                  ),
                ),
              ),
            ],
          ),
        );
      }

      return const SizedBox.shrink();
    }

    // Show warning banner for critical meters
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF7C2D12) : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.warning_rounded,
                size: 16,
                color: Color(0xFFD97706),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '⚠️ Token listrik hampir habis!',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isDark
                        ? const Color(0xFFFDE68A)
                        : const Color(0xFFB45309),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...criticalMeters.take(2).map((meter) {
            final burnRate = _burnRateByMeter[meter.id]!;
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '• ${meter.name}: Estimasi habis dalam ~${burnRate.daysRemaining} hari (${_formatShortDate(burnRate.estimatedDepletedAt)})',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white70 : const Color(0xFF92400E),
                ),
              ),
            );
          }),
          if (criticalMeters.length > 2)
            Text(
              '• Dan ${criticalMeters.length - 2} meteran lainnya...',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white70 : const Color(0xFF92400E),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildComparisonChart(BuildContext context, bool isDark) {
    final theme = Theme.of(context);

    // Prepare data for comparison chart
    final chartData = _meters.map((meter) {
      final summary = _summaryByMeter[meter.id];
      final burnRate = _burnRateByMeter[meter.id];
      return {
        'meter': meter,
        'totalCost': summary?.totalCost.round() ?? 0,
        'dailyKwh': burnRate?.dailyKwh ?? 0.0,
      };
    }).toList();

    // Sort by total cost descending
    chartData.sort(
      (a, b) => (b['totalCost'] as int).compareTo(a['totalCost'] as int),
    );

    final maxCost = chartData.fold<int>(
      0,
      (max, item) =>
          max > (item['totalCost'] as int) ? max : (item['totalCost'] as int),
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.bar_chart_rounded,
                size: 20,
                color: Color(0xFF6366F1),
              ),
              const SizedBox(width: 8),
              const Text(
                'Perbandingan Konsumsi Antar Rumah',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF6366F1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (chartData.isEmpty)
            const Text(
              'Belum ada data untuk ditampilkan.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            )
          else
            ...chartData.map((item) {
              final meter = item['meter'] as UtilityMeter;
              final totalCost = item['totalCost'] as int;
              final dailyKwh = item['dailyKwh'] as double;
              final ratio = maxCost > 0 ? totalCost / maxCost : 0.0;

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 100,
                          child: Text(
                            meter.name,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: LinearProgressIndicator(
                                      value: ratio,
                                      backgroundColor: isDark
                                          ? const Color(0xFF334155)
                                          : const Color(0xFFE2E8F0),
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        const Color(0xFF6366F1),
                                      ),
                                      minHeight: 8,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Rp ${_formatNumber(totalCost)}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                              if (dailyKwh > 0)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    '~${dailyKwh.toStringAsFixed(2)} kWh/hari',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.6),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildTrendIndicator(UtilityMeter meter, bool isDark) {
    final periodData = _periodDataByMeter[meter.id] ?? [];
    if (periodData.length < 2) {
      return const SizedBox.shrink();
    }

    // Calculate trend from period data
    final sortedData = periodData.toList()
      ..sort((a, b) => a.dateFrom.compareTo(b.dateFrom));
    final oldest = sortedData.first;
    final newest = sortedData.last;

    if (oldest.totalCost == 0 || newest.totalCost == 0) {
      return const SizedBox.shrink();
    }

    final change = newest.totalCost - oldest.totalCost;
    final percentage = (change / oldest.totalCost * 100).round();
    final isUp = change > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isUp
            ? (isDark
                  ? const Color(0xFF14532D).withValues(alpha: 0.3)
                  : const Color(0xFFDCFCE7).withValues(alpha: 0.5))
            : (isDark
                  ? const Color(0xFF7F1D1D).withValues(alpha: 0.3)
                  : const Color(0xFFFEE2E2).withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isUp ? Icons.trending_up_rounded : Icons.trending_down_rounded,
            size: 14,
            color: isUp ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
          ),
          const SizedBox(width: 4),
          Text(
            '${isUp ? '+' : ''}$percentage%',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isUp ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, bool isDark) {
    final theme = Theme.of(context);
    final isSelected = _filterType == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() => _filterType = value);
          _applyFilterAndSort();
        }
      },
      selectedColor: isDark ? const Color(0xFF2563EB) : const Color(0xFFBFDBFE),
      checkmarkColor: isDark ? Colors.white : const Color(0xFF1D4ED8),
      labelStyle: TextStyle(
        fontSize: 11,
        color: isSelected
            ? (isDark ? Colors.white : const Color(0xFF1D4ED8))
            : theme.colorScheme.onSurface.withValues(alpha: 0.7),
      ),
    );
  }

  Widget _buildMeterCard(
    BuildContext context,
    UtilityMeter meter,
    bool isDark,
  ) {
    final theme = Theme.of(context);
    final history = _historyByMeter[meter.id] ?? const [];
    final summary = _summaryByMeter[meter.id];
    final periodData = _periodDataByMeter[meter.id] ?? const [];
    final latestReading = _latestReadingByMeter[meter.id];
    final burnRate = _burnRateByMeter[meter.id];

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row Header: Nama + Badge Daya
            Row(
              children: [
                Expanded(
                  child: Text(
                    meter.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (meter.tariffPower.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF334155)
                          : const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      meter.tariffPower,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // Nomor Meter & 1-Tap Copy Box
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF0F172A)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.4,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'NOMOR METER / ID PELANGGAN',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        SelectableText(
                          meter.formattedMeterNumber,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Salin Nomor Meter',
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    onPressed: () => _copyToClipboard(
                      meter.meterNumber,
                      'Nomor meter ${meter.meterNumber} berhasil disalin!',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Trend Indicators
            _buildTrendIndicator(meter, isDark),

            const SizedBox(height: 8),

            // Detail pelanggan & lokasi
            if (meter.customerName.isNotEmpty || meter.location.isNotEmpty) ...[
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  if (meter.customerName.isNotEmpty)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.person_outline_rounded,
                          size: 14,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          meter.customerName,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.75,
                            ),
                          ),
                        ),
                      ],
                    ),
                  if (meter.location.isNotEmpty)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 14,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          meter.location,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.75,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],

            // Strum / Token 20 Digit Box (jika ada)
            if (meter.lastTokenNumber != null &&
                meter.lastTokenNumber!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF261D0C)
                      : const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.key_rounded,
                          size: 15,
                          color: Color(0xFFD97706),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'KODE TOKEN TERAKHIR (SIAP INPUT)',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                            color: isDark
                                ? const Color(0xFFFDE68A)
                                : const Color(0xFFB45309),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            meter.formattedTokenNumber ??
                                meter.lastTokenNumber!,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                              color: Color(0xFFD97706),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Salin 20 Digit Token',
                          icon: const Icon(
                            Icons.copy_all_rounded,
                            color: Color(0xFFD97706),
                            size: 20,
                          ),
                          onPressed: () => _copyToClipboard(
                            meter.lastTokenNumber!,
                            'Kode token 20-digit disalin! Siap dimasukkan ke meteran.',
                          ),
                        ),
                      ],
                    ),
                    if (meter.lastPurchasedAt != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Dibeli pada: ${_formatDate(meter.lastPurchasedAt!)}${meter.lastAmount != null ? " • Rp ${meter.lastAmount!.toStringAsFixed(0)}" : ""}',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.65,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],

            if (summary != null && summary.purchaseCount > 0) ...[
              const Divider(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _buildMetric(
                      'TOTAL PEMBELIAN',
                      'Rp ${_formatNumber(summary.totalCost)}',
                    ),
                  ),
                  Expanded(
                    child: _buildMetric(
                      'KWH TERCATAT',
                      summary.totalCreditedKwh > 0
                          ? '${summary.totalCreditedKwh.toStringAsFixed(2)} kWh'
                          : 'Belum tersedia',
                    ),
                  ),
                ],
              ),
              if (summary.averageCostPerKwh != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Rata-rata Rp ${_formatNumber(summary.averageCostPerKwh!.round())}/kWh. '
                    'Ini biaya per kWh token, bukan pembacaan pemakaian aktual.',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.65,
                      ),
                    ),
                  ),
                ),
            ],
            if (burnRate != null) ...[
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 4),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF132A1C)
                      : const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFF22C55E).withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.bolt_rounded,
                      size: 20,
                      color: Color(0xFF16A34A),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'LAJU KONSUMSI: ~${burnRate.dailyKwh.toStringAsFixed(2)} kWh/hari',
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                              color: Color(0xFF15803D),
                            ),
                          ),
                          if (burnRate.daysRemaining != null)
                            Text(
                              burnRate.daysRemaining! > 0
                                  ? 'Estimasi sisa pulsa: ~${burnRate.daysRemaining} hari (${_formatShortDate(burnRate.estimatedDepletedAt)})'
                                  : 'Estimasi pulsa token listrik sudah menipis!',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: burnRate.daysRemaining! > 2
                                    ? (isDark
                                          ? Colors.white70
                                          : const Color(0xFF166534))
                                    : Colors.red[700],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            MiniMonthlyBarChart(
              data: periodData,
              period: _chartPeriod,
              onPeriodChanged: _changeChartPeriod,
            ),
            const SizedBox(height: 12),

            // Insight Section yang Lebih Jelas
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1E293B)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.4,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.lightbulb_rounded,
                        size: 16,
                        color: Color(0xFF6366F1),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Analisis Singkat',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF6366F1),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (burnRate != null) ...[
                    Text(
                      '• Konsumsi rata-rata: ~${burnRate.dailyKwh.toStringAsFixed(2)} kWh/hari',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.8,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (burnRate.daysRemaining != null)
                      Text(
                        burnRate.daysRemaining! > 0
                            ? '• Estimasi habis: ~${burnRate.daysRemaining} hari lagi (${_formatShortDate(burnRate.estimatedDepletedAt)})'
                            : '• ⚠️ Token hampir habis! Segera beli token baru.',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: burnRate.daysRemaining! > 2
                              ? FontWeight.normal
                              : FontWeight.bold,
                          color: burnRate.daysRemaining! > 2
                              ? theme.colorScheme.onSurface.withValues(
                                  alpha: 0.8,
                                )
                              : Colors.red[700],
                        ),
                      ),
                  ] else ...[
                    Text(
                      '• Belum cukup data untuk analisis konsumsi.',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (latestReading != null) ...[
              const SizedBox(height: 10),
              Text(
                'Pembacaan terakhir: ${latestReading.readingKwh.toStringAsFixed(2)} kWh (${_formatDate(latestReading.recordedAt)})',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
            const SizedBox(height: 4),
            Theme(
              data: Theme.of(context)
                  .copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 4),
                leading: Icon(
                  Icons.lightbulb_outline_rounded,
                  size: 18,
                  color: theme.colorScheme.tertiary,
                ),
                title: const Text(
                  'Cara membaca meter',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '• Lihat angka kWh pada layar digital meter.\n'
                      '• Biasanya 5-6 digit, contohnya 10.112 kWh.\n'
                      '• Catat angka yang terlihat tanpa menekan tombol meter.\n'
                      '• Catat setiap bulan agar grafik pemakaian makin akurat.',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.5,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.72,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (history.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text(
                'Riwayat token terbaru',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              ...history
                  .take(3)
                  .map(
                    (purchase) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.receipt_long_outlined,
                        size: 19,
                      ),
                      title: Text(
                        purchase.tokenCode == null
                            ? 'Token belum terbaca'
                            : 'Token ${_formatToken(purchase.tokenCode!)}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        'Nominal token: Rp ${_formatNumber(purchase.amount)}'
                        '${purchase.adminFee > 0 ? ' • Admin: Rp ${_formatNumber(purchase.adminFee)}' : ''}\n'
                        '${_formatDate(purchase.purchasedAt)}'
                        '${purchase.creditedKwh == null ? '' : ' • ${purchase.creditedKwh!.toStringAsFixed(2)} kWh'}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (purchase.tokenCode != null)
                            IconButton(
                              tooltip: 'Salin token',
                              icon: const Icon(Icons.copy_outlined, size: 18),
                              onPressed: () async {
                                await Clipboard.setData(
                                  ClipboardData(text: purchase.tokenCode!),
                                );
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Token berhasil disalin.'),
                                  ),
                                );
                              },
                            ),
                          const Tooltip(
                            message: 'Tertaut 1:1 dengan transaksi',
                            child: Icon(Icons.link_rounded, size: 18),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],

            // Row Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _showMeterReadingDialog(meter),
                  icon: const Icon(Icons.speed_outlined, size: 16),
                  label: const Text('Catat Pembacaan'),
                ),
                TextButton.icon(
                  onPressed: () => _quickUpdateToken(meter),
                  icon: const Icon(Icons.add_box_outlined, size: 16),
                  label: const Text('Input Token Baru'),
                ),
                IconButton(
                  tooltip: 'Ekspor & Bagikan Laporan',
                  icon: const Icon(Icons.share_outlined, size: 18),
                  onPressed: () => _exportReport(meter),
                ),
                IconButton(
                  tooltip: 'Ubah',
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: () => _showAddEditDialog(meter),
                ),
                IconButton(
                  tooltip: 'Hapus',
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: Colors.red,
                  ),
                  onPressed: () => _confirmDelete(meter),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatShortDate(DateTime? dt) {
    if (dt == null) return '';
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Agu',
      'Sep',
      'Okt',
      'Nov',
      'Des',
    ];
    return '${dt.day} ${months[dt.month]}';
  }

  String _formatDate(DateTime dt) {
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Agu',
      'Sep',
      'Okt',
      'Nov',
      'Des',
    ];
    return '${dt.day} ${months[dt.month]} ${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildMetric(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 3),
      Text(
        value,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
    ],
  );

  String _formatNumber(num value) => value.round().toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => '.',
  );

  String _formatToken(String token) {
    final clean = token.replaceAll(RegExp(r'\D'), '');
    if (clean.length != 20) return token;
    return '${clean.substring(0, 4)}-${clean.substring(4, 8)}-${clean.substring(8, 12)}-${clean.substring(12, 16)}-${clean.substring(16, 20)}';
  }
}

class MiniMonthlyBarChart extends StatelessWidget {
  const MiniMonthlyBarChart({
    super.key,
    required this.data,
    this.period = 'monthly',
    this.onPeriodChanged,
  });

  final List<PeriodUsage> data;
  final String period;
  final ValueChanged<String>? onPeriodChanged;

  @override
  Widget build(BuildContext context) {
    if (data.length < 2) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final points = data.toList()
      ..sort((a, b) => a.dateFrom.compareTo(b.dateFrom));
    final maxCost = points.fold<int>(
      0,
      (max, point) => point.totalCost > max ? point.totalCost : max,
    );
    final maxActual = points.fold<double>(
      0,
      (max, point) => (point.actualKwh ?? 0) > max ? point.actualKwh! : max,
    );
    if (maxCost <= 0 && maxActual <= 0) return const SizedBox.shrink();

    final now = DateTime.now();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bar_chart_rounded, size: 17, color: scheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  period == 'daily'
                      ? 'Tren listrik harian'
                      : period == 'weekly'
                      ? 'Tren listrik mingguan'
                      : 'Tren listrik bulanan',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (onPeriodChanged != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _PeriodChoiceChip(
                      label: 'Bln',
                      selected: period == 'monthly',
                      onSelected: () => onPeriodChanged!('monthly'),
                    ),
                    const SizedBox(width: 4),
                    _PeriodChoiceChip(
                      label: 'Mgg',
                      selected: period == 'weekly',
                      onSelected: () => onPeriodChanged!('weekly'),
                    ),
                    const SizedBox(width: 4),
                    _PeriodChoiceChip(
                      label: 'Hr',
                      selected: period == 'daily',
                      onSelected: () => onPeriodChanged!('daily'),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            children: [
              _LegendItem(color: scheme.primary, label: 'Estimasi beli'),
              if (maxActual > 0)
                _LegendItem(color: scheme.tertiary, label: 'Aktual kWh'),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 116,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: points
                  .map((point) {
                    final ratio = point.totalCost / maxCost;
                    final actualRatio = maxActual <= 0
                        ? 0.0
                        : (point.actualKwh ?? 0) / maxActual;
                    final isCurrentMonth = period == 'monthly'
                        ? (point.dateFrom.year == now.year &&
                              point.dateFrom.month == now.month)
                        : period == 'weekly'
                        ? (now.difference(point.dateFrom).inDays >= 0 &&
                              now.difference(point.dateFrom).inDays < 7)
                        : (point.dateFrom.year == now.year &&
                              point.dateFrom.month == now.month &&
                              point.dateFrom.day == now.day);
                    final monthLabel = point.label.split(' ').first;
                    return Expanded(
                      child: Semantics(
                        label:
                            '$monthLabel, Rp ${_formatCompact(point.totalCost)}, ${point.purchaseCount} pembelian',
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              SizedBox(
                                height: 20,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    _formatCompact(point.totalCost),
                                    maxLines: 1,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: scheme.onSurface,
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (maxCost > 0)
                                      AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 220,
                                        ),
                                        width: 8,
                                        height: 8 + (54 * ratio),
                                        decoration: BoxDecoration(
                                          color: isCurrentMonth
                                              ? scheme.primary
                                              : scheme.primaryContainer,
                                          borderRadius:
                                              const BorderRadius.vertical(
                                                top: Radius.circular(7),
                                              ),
                                        ),
                                      ),
                                    if (maxActual > 0) ...[
                                      const SizedBox(width: 3),
                                      AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 220,
                                        ),
                                        width: 8,
                                        height: (point.actualKwh ?? 0) <= 0
                                            ? 2
                                            : 8 + (54 * actualRatio),
                                        decoration: BoxDecoration(
                                          color: scheme.tertiary,
                                          borderRadius:
                                              const BorderRadius.vertical(
                                                top: Radius.circular(7),
                                              ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                monthLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  })
                  .toList(growable: false),
            ),
          ),
        ],
      ),
    );
  }

  String _formatCompact(int amount) {
    if (amount >= 1000000) {
      return 'Rp${(amount / 1000000).toStringAsFixed(1)}jt';
    }
    if (amount >= 1000) return 'Rp${(amount / 1000).toStringAsFixed(0)}rb';
    return 'Rp$amount';
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 4),
      Text(label, style: Theme.of(context).textTheme.labelSmall),
    ],
  );
}

class _PeriodChoiceChip extends StatelessWidget {
  const _PeriodChoiceChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onSelected,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.6,
                ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: selected
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
