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
    if (!mounted) return;
    setState(() {
      _meters = list;
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
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
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
    final tariffCtrl = TextEditingController(text: meter?.tariffPower ?? 'R1/900VA');
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
                final number = numberCtrl.text.trim().replaceAll(RegExp(r'\D'), '');
                if (name.isEmpty || number.length < 9) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Nama dan Nomor Meter (min 9 digit) wajib diisi!'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                final householdId = AppContext.householdId;
                final cleanToken = tokenCtrl.text.trim().replaceAll(RegExp(r'\D'), '');

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
                  lastTokenNumber: cleanToken.isNotEmpty ? cleanToken : meter?.lastTokenNumber,
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
    final amountCtrl = TextEditingController();

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
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Nominal Pembelian (Rp, Opsional)',
                  hintText: 'Contoh: 50000 atau 100000',
                  prefixIcon: Icon(Icons.monetization_on_outlined),
                ),
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
                final cleanToken = tokenCtrl.text.trim().replaceAll(RegExp(r'\D'), '');
                if (cleanToken.length != 20) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Kode token harus persis 20 digit angka!'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                final amount = double.tryParse(amountCtrl.text.trim().replaceAll(RegExp(r'\D'), ''));

                await _repository.updateLastToken(
                  householdId: meter.householdId,
                  meterNumber: meter.meterNumber,
                  tokenCode: cleanToken,
                  amount: amount,
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
              child: const Text('Simpan & Salin'),
            ),
          ],
        );
      },
    );
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
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFEFF6FF),
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
                                    color: isDark ? const Color(0xFF93C5FD) : const Color(0xFF1D4ED8),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Simpan nomor IDPEL/meteran PLN rumah, sawah ladang, ruko, atau kontrakan. Salin nomor meter atau 20-digit token dengan 1-ketukan saat beli pulsa listrik!',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
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
                      ..._meters.map((meter) => _buildMeterCard(context, meter, isDark)),
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
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
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

  Widget _buildMeterCard(BuildContext context, UtilityMeter meter, bool isDark) {
    final theme = Theme.of(context);

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
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
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
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
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
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
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
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          meter.customerName,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
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
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          meter.location,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],

            // Strum / Token 20 Digit Box (jika ada)
            if (meter.lastTokenNumber != null && meter.lastTokenNumber!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF261D0C) : const Color(0xFFFFFBEB),
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
                            color: isDark ? const Color(0xFFFDE68A) : const Color(0xFFB45309),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            meter.formattedTokenNumber ?? meter.lastTokenNumber!,
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
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],

            // Row Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
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
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
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
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
    ];
    return '${dt.day} ${months[dt.month]} ${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
