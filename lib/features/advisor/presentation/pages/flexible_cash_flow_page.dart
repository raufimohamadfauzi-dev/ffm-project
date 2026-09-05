import 'package:flutter/material.dart';

import '../../../../core/database/app_context.dart';
import '../../../../core/di/injection.dart';
import '../../data/cash_flow_profile_repository.dart';
import '../../domain/entities/cash_flow_profile_models.dart';
import '../../domain/usecases/flexible_cash_flow_calculator.dart';

/// Halaman manajemen profil arus kas adaptif & siklus musiman / bisnis (AgroTrack).
class FlexibleCashFlowPage extends StatefulWidget {
  const FlexibleCashFlowPage({super.key});

  @override
  State<FlexibleCashFlowPage> createState() => _FlexibleCashFlowPageState();
}

class _FlexibleCashFlowPageState extends State<FlexibleCashFlowPage> {
  late final CashFlowProfileRepository _repo;
  late final FlexibleCashFlowCalculator _calculator;

  List<CashFlowProfile> _profiles = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _repo = getIt<CashFlowProfileRepository>();
    _calculator = getIt<FlexibleCashFlowCalculator>();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    final list = await _repo.getAllProfiles(AppContext.householdId);
    if (mounted) {
      setState(() {
        _profiles = list;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleActive(CashFlowProfile profile) async {
    await _repo.setActiveProfile(AppContext.householdId, profile.id);
    await _loadProfiles();
  }

  Future<void> _deleteProfile(CashFlowProfile profile) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Siklus?'),
        content: Text(
          'Apakah Anda yakin ingin menghapus "${profile.name}"? Data ini tidak dapat dikembalikan.',
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

    if (confirm == true) {
      await _repo.deleteProfile(AppContext.householdId, profile.id);
      await _loadProfiles();
    }
  }

  Future<void> _showCreateOrEditDialog([CashFlowProfile? existing]) async {
    final isEditing = existing != null;
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final commodityCtrl = TextEditingController(
      text: existing?.commodityOrBusinessType ?? 'Padi',
    );
    final capitalCtrl = TextEditingController(
      text: existing != null ? _formatNumber(existing.initialCapital) : '15.000.000',
    );
    final inflowCtrl = TextEditingController(
      text: existing != null ? _formatNumber(existing.estimatedInflow) : '45.000.000',
    );
    final livingCtrl = TextEditingController(
      text: existing != null ? _formatNumber(existing.dailyLivingBudget) : '85.000',
    );
    final operationalCtrl = TextEditingController(
      text: existing != null ? _formatNumber(existing.dailyOperationalBudget) : '50.000',
    );

    var selectedType = existing?.profileType ?? CashFlowProfileType.agriculture;
    var startDate = existing?.startDate ?? DateTime.now();
    var harvestDate = existing?.targetHarvestDate ??
        DateTime.now().add(const Duration(days: 105));
    if (harvestDate.isBefore(startDate)) {
      harvestDate = startDate.add(const Duration(days: 105));
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                16,
                20,
                MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade400,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      isEditing ? 'Ubah Siklus Arus Kas' : 'Buat Siklus Baru (AgroTrack / Bisnis)',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 16),

                    // Pilih tipe profil
                    DropdownButtonFormField<CashFlowProfileType>(
                      initialValue: selectedType,
                      decoration: const InputDecoration(
                        labelText: 'Tipe Siklus Finansial',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.category_outlined),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: CashFlowProfileType.agriculture,
                          child: Text('Pertanian / Musiman (AgroTrack)'),
                        ),
                        DropdownMenuItem(
                          value: CashFlowProfileType.business,
                          child: Text('Bisnis / Toko / Dagang'),
                        ),
                        DropdownMenuItem(
                          value: CashFlowProfileType.freelance,
                          child: Text('Freelance / Proyek / Termin'),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setSheetState(() => selectedType = val);
                        }
                      },
                    ),
                    const SizedBox(height: 12),

                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nama Siklus (misal: Sawah Blok Barat MT-1)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.label_outline),
                      ),
                    ),
                    const SizedBox(height: 12),

                    TextField(
                      controller: commodityCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Komoditas / Bidang Usaha (misal: Padi / Kelontong)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.eco_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Pemilihan Tanggal
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: startDate,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2035),
                              );
                              if (picked != null) {
                                setSheetState(() {
                                  startDate = picked;
                                  if (harvestDate.isBefore(startDate)) {
                                    harvestDate = startDate.add(const Duration(days: 90));
                                  }
                                });
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Tanggal Mulai',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(Icons.calendar_today_outlined, size: 16),
                                      const SizedBox(width: 6),
                                      Text(
                                        '${startDate.day}/${startDate.month}/${startDate.year}',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: harvestDate.isBefore(startDate) ? startDate : harvestDate,
                                firstDate: startDate,
                                lastDate: DateTime(2035),
                              );
                              if (picked != null) {
                                setSheetState(() => harvestDate = picked);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Estimasi Panen',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(Icons.event_available_outlined, size: 16),
                                      const SizedBox(width: 6),
                                      Text(
                                        '${harvestDate.day}/${harvestDate.month}/${harvestDate.year}',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    TextField(
                      controller: capitalCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Modal Awal yang Dialokasikan (Rp)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),

                    TextField(
                      controller: inflowCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Estimasi Hasil Panen / Kas Masuk (Rp)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.savings_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: livingCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Belanja Dapur / Hari (Rp)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: operationalCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Biaya Rawat / Hari (Rp)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton(
                        onPressed: () async {
                          if (nameCtrl.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Nama siklus wajib diisi'),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }

                          final newProfile = CashFlowProfile(
                            id: existing?.id ?? 'cycle_${DateTime.now().millisecondsSinceEpoch}',
                            householdId: AppContext.householdId,
                            profileType: selectedType,
                            name: nameCtrl.text.trim(),
                            commodityOrBusinessType: commodityCtrl.text.trim(),
                            startDate: startDate,
                            targetHarvestDate: harvestDate,
                            initialCapital: _parseCurrency(capitalCtrl.text),
                            estimatedInflow: _parseCurrency(inflowCtrl.text),
                            dailyLivingBudget: _parseCurrency(livingCtrl.text),
                            dailyOperationalBudget: _parseCurrency(operationalCtrl.text),
                            isActive: existing?.isActive ?? true,
                          );

                          await _repo.saveProfile(newProfile);
                          if (ctx.mounted) Navigator.pop(ctx);
                          _loadProfiles();
                        },
                        child: Text(isEditing ? 'Simpan Perubahan' : 'Mulai Siklus Ini'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showHarvestSimulatorDialog() {
    final revenueCtrl = TextEditingController(text: '50.000.000');
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final revenue = _parseCurrency(revenueCtrl.text);
            final alloc = _calculator.simulateHarvestAllocation(actualHarvestRevenue: revenue);

            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.calculate_outlined, color: Colors.green),
                  SizedBox(width: 8),
                  Text('Kalkulator Bagi Hasil Panen'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Simulasi pembagian hasil panen otomatis agar modal tanam berikutnya tidak terpakai habis:',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: revenueCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Total Uang Hasil Panen (Rp)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 16),
                  _buildAllocRow('Modal Siklus Berikutnya (45%)', alloc['nextCycleCapital'] ?? 0, Colors.blue),
                  const SizedBox(height: 6),
                  _buildAllocRow('Cadangan Dana Darurat (15%)', alloc['emergencyFund'] ?? 0, Colors.orange),
                  const SizedBox(height: 6),
                  _buildAllocRow('Laba Bersih Keluarga (40%)', alloc['familyProfit'] ?? 0, Colors.green),
                ],
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Tutup'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildAllocRow(String label, int amount, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
          Text('Rp ${_formatNumber(amount)}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Siklus Kas & Profil Finansial'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calculate_outlined),
            tooltip: 'Kalkulator Bagi Panen',
            onPressed: _showHarvestSimulatorDialog,
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Tambah Siklus',
            onPressed: () => _showCreateOrEditDialog(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _profiles.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.eco_outlined,
                          size: 64,
                          color: colorScheme.primary.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Belum Ada Siklus Aktif',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Cocok untuk Petani (AgroTrack), Pemilik Usaha, dan Freelancer agar perhitungan ketahanan kas (Runway) akurat.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: () => _showCreateOrEditDialog(),
                          icon: const Icon(Icons.add),
                          label: const Text('Buat Siklus Pertama'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _profiles.length,
                  itemBuilder: (context, index) {
                    final p = _profiles[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                          color: p.isActive ? colorScheme.primary : Colors.transparent,
                          width: p.isActive ? 1.5 : 0,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        p.name,
                                        style: theme.textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        '${p.commodityOrBusinessType} • ${p.phaseLabel}',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch(
                                  value: p.isActive,
                                  onChanged: (_) => _toggleActive(p),
                                ),
                              ],
                            ),
                            const Divider(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Modal Awal:', style: theme.textTheme.bodySmall),
                                Text('Rp ${_formatNumber(p.initialCapital)}',
                                    style: const TextStyle(fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Estimasi Inflow / Hasil:', style: theme.textTheme.bodySmall),
                                Text('Rp ${_formatNumber(p.estimatedInflow)}',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold, color: Colors.green.shade700)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Durasi Siklus:', style: theme.textTheme.bodySmall),
                                Text('${p.daysElapsed} dari ${p.totalDays} hari (Sisa ${p.daysRemaining} hari)',
                                    style: const TextStyle(fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton.icon(
                                  onPressed: () => _deleteProfile(p),
                                  icon: const Icon(Icons.delete_outline, size: 16),
                                  label: const Text('Hapus'),
                                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  onPressed: () => _showCreateOrEditDialog(p),
                                  icon: const Icon(Icons.edit_outlined, size: 16),
                                  label: const Text('Ubah'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  static String _formatNumber(int val) {
    return val.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]}.',
        );
  }

  static int _parseCurrency(String text) {
    final clean = text.replaceAll(RegExp(r'[^\d]'), '');
    return int.tryParse(clean) ?? 0;
  }
}
