import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_context.dart';
import '../../../../core/di/injection.dart';
import '../../../assistant/domain/ffm_assistant_models.dart';
import '../../../assistant/presentation/widgets/ffm_assistant_page_context.dart';
import '../../data/vehicle_repository.dart';
import '../../domain/entities/vehicle_models.dart';

/// Halaman Buku Saku Kendaraan & Riwayat Log BBM (Pillar Kendaraan & Logistik).
///
/// Menyimpan data kendaraan (motor, mobil, truk, traktor sawah), nomor polisi,
/// merek/model, kapasitas tangki, serta riwayat konsumsi BBM dan efisiensi KM/L.
class VehiclePage extends StatefulWidget {
  const VehiclePage({super.key});

  @override
  State<VehiclePage> createState() => _VehiclePageState();
}

class _VehiclePageState extends State<VehiclePage> {
  late final VehicleRepository _repository;
  List<Vehicle> _vehicles = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _repository = getIt<VehicleRepository>();
    _loadVehicles();
  }

  Future<void> _loadVehicles() async {
    setState(() => _isLoading = true);
    final householdId = AppContext.householdId;
    final list = await _repository.getAllVehicles(householdId);
    if (!mounted) return;
    setState(() {
      _vehicles = list;
      _isLoading = false;
    });
  }

  void _showNotice(String message, {bool isError = false}) {
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline_rounded : Icons.check_circle_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? Colors.red.shade700 : const Color(0xFF059669),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  IconData _iconForType(String type) {
    switch (type.toLowerCase()) {
      case 'motor':
        return Icons.two_wheeler_rounded;
      case 'mobil':
        return Icons.directions_car_rounded;
      case 'truk':
        return Icons.local_shipping_rounded;
      case 'traktor':
        return Icons.agriculture_rounded;
      default:
        return Icons.commute_rounded;
    }
  }

  Color _colorForType(String type) {
    switch (type.toLowerCase()) {
      case 'motor':
        return const Color(0xFF0D9488); // Teal
      case 'mobil':
        return const Color(0xFF2563EB); // Blue
      case 'truk':
        return const Color(0xFFD97706); // Amber
      case 'traktor':
        return const Color(0xFF16A34A); // Green
      default:
        return const Color(0xFF64748B); // Slate
    }
  }

  String _formatRp(double amount) {
    final clean = amount.round().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < clean.length; i++) {
      if (i > 0 && (clean.length - i) % 3 == 0) buffer.write('.');
      buffer.write(clean[i]);
    }
    return 'Rp $buffer';
  }

  Future<void> _showAddEditVehicleDialog([Vehicle? vehicle]) async {
    final isEditing = vehicle != null;
    final nameCtrl = TextEditingController(text: vehicle?.name ?? '');
    final brandCtrl = TextEditingController(text: vehicle?.brandModel ?? '');
    final plateCtrl = TextEditingController(text: vehicle?.plateNumber ?? '');
    final tankCtrl = TextEditingController(
      text: vehicle != null && vehicle.tankCapacity > 0
          ? vehicle.tankCapacity.toString()
          : '',
    );
    final odoCtrl = TextEditingController(
      text: vehicle?.lastOdometer != null ? vehicle!.lastOdometer!.toStringAsFixed(0) : '',
    );
    final notesCtrl = TextEditingController(text: vehicle?.notes ?? '');

    String selectedType = vehicle?.vehicleType ?? 'motor';
    String selectedFuel = vehicle?.fuelType ?? 'Pertalite';

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                isEditing ? 'Ubah Data Kendaraan' : 'Tambah Kendaraan Baru',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nama / Panggilan Kendaraan *',
                        hintText: 'Misal: Vario Harian, Avanza Ayah, Traktor Sawah',
                        prefixIcon: Icon(Icons.label_outline_rounded),
                      ),
                      autofocus: !isEditing,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: brandCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Merek & Model Kendaraan',
                        hintText: 'Misal: Honda Vario 160, Toyota Avanza 1.3',
                        prefixIcon: Icon(Icons.commute_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: plateCtrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Nomor Polisi / Plat *',
                        hintText: 'Contoh: B 1234 ABC / D 5678 XY',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedType,
                      decoration: const InputDecoration(
                        labelText: 'Jenis Kendaraan',
                        prefixIcon: Icon(Icons.category_outlined),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'motor', child: Text('Sepeda Motor')),
                        DropdownMenuItem(value: 'mobil', child: Text('Mobil')),
                        DropdownMenuItem(value: 'truk', child: Text('Truk / Niaga')),
                        DropdownMenuItem(value: 'traktor', child: Text('Traktor / Mesin Tani')),
                        DropdownMenuItem(value: 'lainnya', child: Text('Lainnya')),
                      ],
                      onChanged: (val) {
                        if (val != null) setDialogState(() => selectedType = val);
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedFuel,
                      decoration: const InputDecoration(
                        labelText: 'Jenis Bahan Bakar (BBM)',
                        prefixIcon: Icon(Icons.local_gas_station_outlined),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Pertalite', child: Text('Pertalite (RON 90)')),
                        DropdownMenuItem(value: 'Pertamax', child: Text('Pertamax (RON 92)')),
                        DropdownMenuItem(value: 'Pertamax Turbo', child: Text('Pertamax Turbo (RON 98)')),
                        DropdownMenuItem(value: 'Solar', child: Text('Solar / Biosolar (CN 48)')),
                        DropdownMenuItem(value: 'Dexlite', child: Text('Dexlite (CN 51)')),
                        DropdownMenuItem(value: 'Listrik/EV', child: Text('Listrik / Kendaraan Listrik (EV)')),
                      ],
                      onChanged: (val) {
                        if (val != null) setDialogState(() => selectedFuel = val);
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: tankCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Kapasitas Tangki (L)',
                              hintText: 'Misal: 5.5',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: odoCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Odometer (KM)',
                              hintText: 'Misal: 14200',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Catatan (Opsional)',
                        hintText: 'Misal: Servis rutin per 2000 KM',
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
                    final plate = plateCtrl.text.trim().toUpperCase();
                    if (name.isEmpty || plate.isEmpty) {
                      _showNotice('Nama dan Nomor Polisi wajib diisi!', isError: true);
                      return;
                    }

                    final householdId = AppContext.householdId;
                    final tankCap = double.tryParse(tankCtrl.text.replaceAll(',', '.')) ?? 0.0;
                    final odo = double.tryParse(odoCtrl.text.replaceAll(',', '.'));

                    final newVehicle = Vehicle(
                      id: vehicle?.id ?? const Uuid().v4(),
                      householdId: householdId,
                      name: name,
                      plateNumber: plate,
                      brandModel: brandCtrl.text.trim(),
                      vehicleType: selectedType,
                      fuelType: selectedFuel,
                      tankCapacity: tankCap,
                      lastOdometer: odo ?? vehicle?.lastOdometer,
                      notes: notesCtrl.text.trim(),
                      createdAt: vehicle?.createdAt ?? DateTime.now(),
                      fuelLogs: vehicle?.fuelLogs ?? const [],
                    );

                    await _repository.saveVehicle(newVehicle);
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) {
                      _showNotice(
                        isEditing
                            ? 'Data kendaraan berhasil diperbarui!'
                            : 'Kendaraan "${newVehicle.name}" berhasil didaftarkan!',
                      );
                      _loadVehicles();
                    }
                  },
                  child: Text(isEditing ? 'Simpan' : 'Daftarkan'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showAddFuelLogDialog(Vehicle vehicle) async {
    final litersCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final odoCtrl = TextEditingController(
      text: vehicle.lastOdometer != null ? vehicle.lastOdometer!.toStringAsFixed(0) : '',
    );
    final spbuCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    String selectedFuel = vehicle.fuelType;
    DateTime fillDate = DateTime.now();

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.local_gas_station_rounded, color: Color(0xFFD97706)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Catat BBM - ${vehicle.name}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.calendar_today_rounded, size: 20),
                      title: Text(
                        '${fillDate.day}/${fillDate.month}/${fillDate.year} ${fillDate.hour.toString().padLeft(2, '0')}:${fillDate.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      trailing: TextButton(
                        onPressed: () async {
                          final pickedDate = await showDatePicker(
                            context: context,
                            initialDate: fillDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now().add(const Duration(days: 1)),
                          );
                          if (pickedDate != null) {
                            setDialogState(() {
                              fillDate = DateTime(
                                pickedDate.year,
                                pickedDate.month,
                                pickedDate.day,
                                fillDate.hour,
                                fillDate.minute,
                              );
                            });
                          }
                        },
                        child: const Text('Ubah'),
                      ),
                    ),
                    const Divider(),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: litersCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Jumlah Liter (L) *',
                              hintText: 'Misal: 4.2',
                              prefixIcon: Icon(Icons.opacity_rounded),
                            ),
                            autofocus: true,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: amountCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Total Biaya (Rp) *',
                              hintText: 'Misal: 42000',
                              prefixIcon: Icon(Icons.payments_outlined),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedFuel,
                      decoration: const InputDecoration(
                        labelText: 'Bahan Bakar',
                        prefixIcon: Icon(Icons.local_gas_station_outlined),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Pertalite', child: Text('Pertalite')),
                        DropdownMenuItem(value: 'Pertamax', child: Text('Pertamax')),
                        DropdownMenuItem(value: 'Pertamax Turbo', child: Text('Pertamax Turbo')),
                        DropdownMenuItem(value: 'Solar', child: Text('Solar / Biosolar')),
                        DropdownMenuItem(value: 'Dexlite', child: Text('Dexlite')),
                        DropdownMenuItem(value: 'Listrik/EV', child: Text('Listrik / Charging EV')),
                      ],
                      onChanged: (val) {
                        if (val != null) setDialogState(() => selectedFuel = val);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: odoCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Odometer Saat Isi (KM, opsional)',
                        hintText: 'Contoh: 14520',
                        prefixIcon: Icon(Icons.speed_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: spbuCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nama / Lokasi SPBU (Opsional)',
                        hintText: 'Misal: SPBU Pertamina Bypass',
                        prefixIcon: Icon(Icons.place_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Catatan Tambahan',
                        hintText: 'Misal: Tangki penuh (full tank)',
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
                FilledButton.icon(
                  onPressed: () async {
                    final liters = double.tryParse(litersCtrl.text.replaceAll(',', '.')) ?? 0.0;
                    final amount = double.tryParse(amountCtrl.text.replaceAll(RegExp(r'\D'), '')) ?? 0.0;

                    if (liters <= 0 || amount <= 0) {
                      _showNotice('Liter dan Total Biaya harus diisi dengan benar!', isError: true);
                      return;
                    }

                    final odo = double.tryParse(odoCtrl.text.replaceAll(',', '.'));
                    final newLog = FuelLogEntry(
                      id: const Uuid().v4(),
                      date: fillDate,
                      liters: liters,
                      totalAmount: amount,
                      odometerKm: odo,
                      fuelType: selectedFuel,
                      spbuLocation: spbuCtrl.text.trim(),
                      notes: notesCtrl.text.trim(),
                    );

                    await _repository.addFuelLog(
                      householdId: vehicle.householdId,
                      vehicleId: vehicle.id,
                      fuelLog: newLog,
                    );

                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) {
                      _showNotice('Log BBM ${liters}L (${_formatRp(amount)}) berhasil dicatat!');
                      _loadVehicles();
                    }
                  },
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('Simpan Log BBM'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showFuelHistorySheet(Vehicle vehicle) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleDynamicTopBorder(),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, scrollController) {
            final logs = List<FuelLogEntry>.from(vehicle.fuelLogs)
              ..sort((a, b) => b.date.compareTo(a.date));

            return Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.history_rounded, color: Color(0xFF2563EB)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Riwayat BBM - ${vehicle.name}',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              '${vehicle.formattedPlateNumber} • ${logs.length} pengisian tercatat',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Tutup',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                if (logs.isEmpty)
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.local_gas_station_outlined, size: 56, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          const Text('Belum ada riwayat pengisian BBM.'),
                          const SizedBox(height: 8),
                          FilledButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _showAddFuelLogDialog(vehicle);
                            },
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Catat BBM Sekarang'),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: logs.length,
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (context, idx) {
                        final item = logs[idx];
                        final dateStr =
                            '${item.date.day}/${item.date.month}/${item.date.year} ${item.date.hour.toString().padLeft(2, '0')}:${item.date.minute.toString().padLeft(2, '0')}';
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(vertical: 4),
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFFFEF3C7),
                            child: const Icon(Icons.local_gas_station_rounded, color: Color(0xFFD97706), size: 20),
                          ),
                          title: Row(
                            children: [
                              Text(
                                '${item.liters} L (${item.fuelType})',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              const Spacer(),
                              Text(
                                _formatRp(item.totalAmount),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF059669),
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$dateStr • @${_formatRp(item.effectivePricePerLiter)}/L'
                                '${item.odometerKm != null ? ' • Odo: ${item.odometerKm!.toStringAsFixed(0)} KM' : ''}',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              ),
                              if (item.spbuLocation.isNotEmpty || item.notes.isNotEmpty)
                                Text(
                                  [
                                    if (item.spbuLocation.isNotEmpty) item.spbuLocation,
                                    if (item.notes.isNotEmpty) item.notes,
                                  ].join(' - '),
                                  style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey.shade700),
                                ),
                            ],
                          ),
                          trailing: IconButton(
                            tooltip: 'Hapus Catatan',
                            icon: Icon(Icons.delete_outline_rounded, color: Colors.red.shade400, size: 20),
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (c) => AlertDialog(
                                  title: const Text('Hapus Catatan BBM?'),
                                  content: Text('Catatan pengisian ${item.liters}L (${_formatRp(item.totalAmount)}) akan dihapus.'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
                                    FilledButton(
                                      onPressed: () => Navigator.pop(c, true),
                                      style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                      child: const Text('Hapus'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                await _repository.deleteFuelLog(
                                  householdId: vehicle.householdId,
                                  vehicleId: vehicle.id,
                                  fuelLogId: item.id,
                                );
                                if (mounted) {
                                  _showNotice('Catatan BBM berhasil dihapus.');
                                  _loadVehicles();
                                }
                                if (ctx.mounted) Navigator.pop(ctx);
                              }
                            },
                          ),
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _confirmDeleteVehicle(Vehicle vehicle) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Kendaraan?'),
        content: Text(
          'Kendaraan "${vehicle.name}" (${vehicle.formattedPlateNumber}) '
          'beserta ${vehicle.fuelLogs.length} riwayat pengisian BBM akan dihapus.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _repository.deleteVehicle(vehicle.householdId, vehicle.id);
      if (mounted) {
        _showNotice('Kendaraan "${vehicle.name}" berhasil dihapus.');
        _loadVehicles();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    // Hitung total armada
    final totalVehicles = _vehicles.length;
    final totalLitersMonth = _vehicles.fold(
      0.0,
      (sum, v) => sum + v.totalLitersForMonth(now),
    );
    final totalExpenseMonth = _vehicles.fold(
      0.0,
      (sum, v) => sum + v.totalExpenseForMonth(now),
    );

    return FfmAssistantPageContext(
      destination: FfmAssistantDestination.otherMenu,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Kendaraan & Catatan BBM'),
          actions: [
            IconButton(
              tooltip: 'Petunjuk & Manfaat',
              icon: const Icon(Icons.info_outline_rounded),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Buku Saku Kendaraan & BBM'),
                  content: const Text(
                    '1. Daftarkan motor, mobil, truk, atau traktor sawah beserta nomor polisi dan mereknya.\n\n'
                    '2. Catat pengisian BBM dengan cepat atau cukup scan struk SPBU di Asisten — data liter dan plat nomor akan dicocokkan otomatis.\n\n'
                    '3. Pantau pengeluaran bulanan dan efisiensi konsumsi (KM per Liter) secara akurat dan mandiri.',
                  ),
                  actions: [
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Mengerti'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadVehicles,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                  children: [
                    // Header Ringkasan Armada
                    Card(
                      elevation: 0,
                      color: const Color(0xFF0F172A),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF059669).withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.speed_rounded, color: Color(0xFF34D399), size: 22),
                                ),
                                const SizedBox(width: 10),
                                const Text(
                                  'Ringkasan Konsumsi BBM',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Armada Aktif',
                                        style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '$totalVehicles Kendaraan',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(width: 1, height: 32, color: Colors.grey.shade800),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Liter Bulan Ini',
                                        style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${totalLitersMonth.toStringAsFixed(1)} L',
                                        style: const TextStyle(
                                          color: Color(0xFF38BDF8),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(width: 1, height: 32, color: Colors.grey.shade800),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Biaya BBM Bln Ini',
                                        style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _formatRp(totalExpenseMonth),
                                        style: const TextStyle(
                                          color: Color(0xFF4ADE80),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Empty State atau List Kendaraan
                    if (_vehicles.isEmpty) ...[
                      const SizedBox(height: 36),
                      Center(
                        child: Column(
                          children: [
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(40),
                              ),
                              child: const Icon(
                                Icons.directions_car_filled_rounded,
                                size: 40,
                                color: Color(0xFF64748B),
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Belum Ada Kendaraan Terdaftar',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                            ),
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 32),
                              child: Text(
                                'Daftarkan motor, mobil keluarga, atau kendaraan usaha/tani Anda untuk mencatat konsumsi BBM dan efisiensi harian.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                              ),
                            ),
                            const SizedBox(height: 20),
                            FilledButton.icon(
                              onPressed: () => _showAddEditVehicleDialog(),
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Daftarkan Kendaraan Pertama'),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Daftar Kendaraan',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          Text(
                            '${_vehicles.length} terdaftar',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      for (final vehicle in _vehicles) _buildVehicleCard(vehicle, now),
                    ],
                  ],
                ),
              ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showAddEditVehicleDialog(),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Tambah Kendaraan'),
        ),
      ),
    );
  }

  Widget _buildVehicleCard(Vehicle vehicle, DateTime now) {
    final typeIcon = _iconForType(vehicle.vehicleType);
    final typeColor = _colorForType(vehicle.vehicleType);
    final monthLiters = vehicle.totalLitersForMonth(now);
    final monthExpense = vehicle.totalExpenseForMonth(now);
    final kmPerL = vehicle.averageKmPerLiter;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200, width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon jenis kendaraan
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(typeIcon, color: typeColor, size: 24),
                ),
                const SizedBox(width: 12),
                // Nama, Merek, dan No Polisi
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              vehicle.name,
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                            ),
                          ),
                          // Plat nomor bergaya plat Indonesia
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.grey.shade400, width: 0.8),
                            ),
                            child: Text(
                              vehicle.formattedPlateNumber,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        vehicle.brandModel.isNotEmpty ? vehicle.brandModel : 'Merek belum diisi',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded, size: 20),
                  onSelected: (val) {
                    if (val == 'edit') {
                      _showAddEditVehicleDialog(vehicle);
                    } else if (val == 'history') {
                      _showFuelHistorySheet(vehicle);
                    } else if (val == 'delete') {
                      _confirmDeleteVehicle(vehicle);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'history', child: Text('Riwayat Pengisian BBM')),
                    PopupMenuItem(value: 'edit', child: Text('Ubah Data Kendaraan')),
                    PopupMenuItem(value: 'delete', child: Text('Hapus Kendaraan', style: TextStyle(color: Colors.red))),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Badges BBM, Kapasitas Tangki, dan Odometer
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _buildInfoChip(
                  icon: Icons.local_gas_station_rounded,
                  label: vehicle.fuelType,
                  color: const Color(0xFFD97706),
                ),
                if (vehicle.tankCapacity > 0)
                  _buildInfoChip(
                    icon: Icons.invert_colors_rounded,
                    label: '${vehicle.tankCapacity} L',
                    color: const Color(0xFF0284C7),
                  ),
                if (vehicle.lastOdometer != null)
                  _buildInfoChip(
                    icon: Icons.speed_rounded,
                    label: '${vehicle.lastOdometer!.toStringAsFixed(0)} KM',
                    color: const Color(0xFF475569),
                  ),
                if (kmPerL != null)
                  _buildInfoChip(
                    icon: Icons.eco_rounded,
                    label: '${kmPerL.toStringAsFixed(1)} KM/L',
                    color: const Color(0xFF16A34A),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),

            // Ringkasan Bulan Ini & Tombol Aksi
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bulan ini: ${monthLiters.toStringAsFixed(1)} L (${_formatRp(monthExpense)})',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
                      ),
                      Text(
                        '${vehicle.fuelLogs.length} pengisian tercatat',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _showFuelHistorySheet(vehicle),
                  icon: const Icon(Icons.history_rounded, size: 16),
                  label: const Text('Riwayat', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => _showAddFuelLogDialog(vehicle),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Catat BBM', style: TextStyle(fontSize: 12)),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                    backgroundColor: const Color(0xFFD97706),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class RoundedRectangleDynamicTopBorder extends ShapeBorder {
  const RoundedRectangleDynamicTopBorder();

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => getOuterPath(rect, textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    return Path()
      ..addRRect(
        RRect.fromRectAndCorners(
          rect,
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
        ),
      );
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  ShapeBorder scale(double t) => this;
}
