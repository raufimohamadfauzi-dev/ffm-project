import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_context.dart';
import '../../../../core/di/injection.dart';
import '../../../assistant/domain/ffm_assistant_models.dart';
import '../../../assistant/presentation/widgets/ffm_assistant_page_context.dart';
import '../../data/utility_meter_repository.dart';
import '../../domain/entities/utility_meter_models.dart';

/// Halaman Buku Saku Meteran & Token Listrik PLN (Pillar 3).
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
  bool _isLoading = true;

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
        period: 'monthly',
        limit: 6,
        includeReadings: true,
      );
      latestReadings[meter.id] = await _repository.getLatestReading(
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
      _isLoading = false;
    });
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

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final parsedReading = double.tryParse(
            readingCtrl.text.trim().replaceAll(',', '.'),
          );
          final isLower = latest != null &&
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
                    decoration: const InputDecoration(
                      labelText: 'Angka kWh *',
                      hintText: 'Contoh: 10112 atau 10112.3',
                      prefixIcon: Icon(Icons.electric_bolt_rounded),
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
            'Buku Saku Meteran & Token',
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
                                  'Buku Saku Meteran Listrik Mandiri',
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

                    if (_meters.isEmpty)
                      _buildEmptyState(context, isDark)
                    else
                      ..._meters.map(
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
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => _showAddEditDialog(),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Daftarkan Meteran Pertama'),
          ),
        ],
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
              MiniMonthlyBarChart(data: periodData),
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
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
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
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
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
                      title: Text('Rp ${_formatNumber(purchase.amount)}'),
                      subtitle: Text(
                        '${_formatDate(purchase.purchasedAt)}'
                        '${purchase.creditedKwh == null ? '' : ' • ${purchase.creditedKwh!.toStringAsFixed(2)} kWh'}',
                      ),
                      trailing: const Tooltip(
                        message: 'Tertaut 1:1 dengan transaksi',
                        child: Icon(Icons.link_rounded, size: 18),
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
}

class MiniMonthlyBarChart extends StatelessWidget {
  const MiniMonthlyBarChart({super.key, required this.data});

  final List<PeriodUsage> data;

  @override
  Widget build(BuildContext context) {
    if (data.length < 2) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final points = data.toList()..sort((a, b) => a.dateFrom.compareTo(b.dateFrom));
    final maxCost = points.fold<int>(
      0,
      (max, point) => point.totalCost > max ? point.totalCost : max,
    );
    final maxActual = points.fold<double>(
      0,
      (max, point) => (point.actualKwh ?? 0) > max
          ? point.actualKwh!
          : max,
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
              Text(
                'Tren listrik 6 bulan',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            children: [
              _LegendItem(color: scheme.primary, label: 'Estimasi beli'),
              if (maxActual > 0)
                _LegendItem(
                  color: scheme.tertiary,
                  label: 'Aktual kWh',
                ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 116,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: points.map((point) {
                final ratio = point.totalCost / maxCost;
                final actualRatio = maxActual <= 0
                    ? 0.0
                    : (point.actualKwh ?? 0) / maxActual;
                final isCurrentMonth =
                    point.dateFrom.year == now.year &&
                    point.dateFrom.month == now.month;
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
                                    duration: const Duration(milliseconds: 220),
                                    width: 8,
                                    height: 8 + (54 * ratio),
                                    decoration: BoxDecoration(
                                      color: isCurrentMonth
                                          ? scheme.primary
                                          : scheme.primaryContainer,
                                      borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(7),
                                      ),
                                    ),
                                  ),
                                if (maxActual > 0) ...[
                                  const SizedBox(width: 3),
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 220),
                                    width: 8,
                                    height: (point.actualKwh ?? 0) <= 0
                                        ? 2
                                        : 8 + (54 * actualRatio),
                                    decoration: BoxDecoration(
                                      color: scheme.tertiary,
                                      borderRadius: const BorderRadius.vertical(
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
              }).toList(growable: false),
            ),
          ),
        ],
      ),
    );
  }

  String _formatCompact(int amount) {
    if (amount >= 1000000) return 'Rp${(amount / 1000000).toStringAsFixed(1)}jt';
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
