import 'package:flutter/material.dart';
import '../../domain/entities/autonomous_activity_models.dart';

/// Menampilkan dialog konfirmasi pembatalan (revert) aksi otonom.
Future<bool> showRevertActivityDialog({
  required BuildContext context,
  required AutonomousActivityRecord activity,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.undo_rounded,
                color: Colors.redAccent,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Batalkan Aksi Otonom?',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tindakan yang dijalankan oleh Asisten berikut akan dibatalkan dan statusnya dikembalikan:',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    activity.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    activity.description,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: isDark ? Colors.grey[300] : Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.amber.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.amber, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Data terkait (mutasi transfer/log BBM/token) akan dicabut secara aman.',
                      style: TextStyle(fontSize: 11.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Batalkan Aksi'),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

/// Menampilkan dialog koreksi untuk mengedit tindakan otonom sesuai jenis draft/aksinya.
Future<Map<String, dynamic>?> showEditActivityDialog({
  required BuildContext context,
  required AutonomousActivityRecord activity,
}) async {
  final payload = activity.payload;
  final titleController = TextEditingController(text: activity.title);
  final descController = TextEditingController(text: activity.description);

  // Field spesifik per jenis aksi otonom
  final amountController = TextEditingController(
    text: payload['amount']?.toString() ?? '',
  );
  final litersController = TextEditingController(
    text: payload['liters']?.toString() ?? '',
  );
  final costController = TextEditingController(
    text: payload['cost']?.toString() ?? '',
  );
  final odoController = TextEditingController(
    text: payload['odometer']?.toString() ?? '',
  );
  final meterNumberController = TextEditingController(
    text: payload['meterNumber']?.toString() ?? '',
  );
  final aliasController = TextEditingController(
    text: payload['alias']?.toString() ?? '',
  );
  final tariffPowerController = TextEditingController(
    text: payload['tariffPower']?.toString() ?? '',
  );
  final habitTextController = TextEditingController(
    text: payload['habitText']?.toString() ?? activity.title,
  );
  final categoryController = TextEditingController(
    text: payload['category']?.toString() ?? '',
  );

  DateTime? selectedHarvestDate;
  if (activity.activityType == AutonomousActivityType.harvestShift) {
    if (payload['newHarvestDate'] != null) {
      selectedHarvestDate = DateTime.tryParse(payload['newHarvestDate'].toString());
    }
    selectedHarvestDate ??= DateTime.now().add(const Duration(days: 30));
  }

  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (ctx) {
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      return StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          final typeBadge = switch (activity.activityType) {
            AutonomousActivityType.fuelLog => 'Catatan BBM Kendaraan',
            AutonomousActivityType.envelopeRebalance => 'Pergeseran Anggaran',
            AutonomousActivityType.utilityMeter => 'Meteran Listrik PLN',
            AutonomousActivityType.harvestShift => 'Pergeseran Panen Tani',
            AutonomousActivityType.habitDeclaration => 'Deklarasi Kebiasaan',
          };

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: Row(
              children: [
                const Icon(Icons.edit_note_rounded, color: Colors.blueAccent, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Koreksi $typeBadge',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sesuaikan rincian draft tindakan yang telah dicatat:',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Bidang Spesifik: Fuel Log (BBM)
                  if (activity.activityType == AutonomousActivityType.fuelLog) ...[
                    TextField(
                      controller: litersController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Volume Bahan Bakar (Liter)',
                        hintText: 'Contoh: 3.5',
                        border: OutlineInputBorder(),
                        isDense: true,
                        prefixIcon: Icon(Icons.local_gas_station_rounded, size: 20),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: costController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Total Biaya BBM (Rp)',
                        hintText: 'Contoh: 35000',
                        border: OutlineInputBorder(),
                        isDense: true,
                        prefixIcon: Icon(Icons.payments_outlined, size: 20),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: odoController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Angka Odometer (KM)',
                        hintText: 'Contoh: 12450',
                        border: OutlineInputBorder(),
                        isDense: true,
                        prefixIcon: Icon(Icons.speed_rounded, size: 20),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Bidang Spesifik: Envelope Rebalance (Pergeseran Anggaran)
                  if (activity.activityType == AutonomousActivityType.envelopeRebalance) ...[
                    TextField(
                      controller: amountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Nominal Pergeseran (Rp)',
                        hintText: 'Contoh: 50000',
                        border: OutlineInputBorder(),
                        isDense: true,
                        prefixIcon: Icon(Icons.swap_horiz_rounded, size: 20),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Bidang Spesifik: Utility Meter (Meteran Listrik)
                  if (activity.activityType == AutonomousActivityType.utilityMeter) ...[
                    TextField(
                      controller: meterNumberController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Nomor Meteran (11-12 digit)',
                        hintText: 'Contoh: 14234567890',
                        border: OutlineInputBorder(),
                        isDense: true,
                        prefixIcon: Icon(Icons.electric_meter_rounded, size: 20),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: aliasController,
                      decoration: const InputDecoration(
                        labelText: 'Nama / Lokasi Meteran',
                        hintText: 'Contoh: Rumah Induk / Pompa Sawah',
                        border: OutlineInputBorder(),
                        isDense: true,
                        prefixIcon: Icon(Icons.label_outline_rounded, size: 20),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: tariffPowerController,
                      decoration: const InputDecoration(
                        labelText: 'Daya / Tarif',
                        hintText: 'Contoh: R1M/900VA',
                        border: OutlineInputBorder(),
                        isDense: true,
                        prefixIcon: Icon(Icons.bolt_rounded, size: 20),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Bidang Spesifik: Harvest Shift (Siklus Tani)
                  if (activity.activityType == AutonomousActivityType.harvestShift) ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.calendar_month_rounded, color: Colors.green),
                      title: const Text('Target Tanggal Panen'),
                      subtitle: Text(
                        selectedHarvestDate != null
                            ? '${selectedHarvestDate!.day.toString().padLeft(2, '0')}/${selectedHarvestDate!.month.toString().padLeft(2, '0')}/${selectedHarvestDate!.year}'
                            : 'Belum dipilih',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      trailing: TextButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: dialogCtx,
                            initialDate: selectedHarvestDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2035),
                            helpText: 'Pilih Tanggal Panen Baru',
                          );
                          if (picked != null) {
                            setDialogState(() {
                              selectedHarvestDate = picked;
                            });
                          }
                        },
                        child: const Text('Ganti'),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Bidang Spesifik: Habit Declaration
                  if (activity.activityType == AutonomousActivityType.habitDeclaration) ...[
                    TextField(
                      controller: habitTextController,
                      decoration: const InputDecoration(
                        labelText: 'Pernyataan Kebiasaan',
                        hintText: 'Contoh: Selalu sarapan jam 07:00',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: categoryController,
                      decoration: const InputDecoration(
                        labelText: 'Kategori',
                        hintText: 'Contoh: Makanan / Rutinitas',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Judul dan Catatan Umum
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'Judul Catatan',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Keterangan Tambahan',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(null),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () {
                  final newTitle = titleController.text.trim();
                  var newDesc = descController.text.trim();
                  if (newTitle.isEmpty) return;

                  final updatedPayload = Map<String, dynamic>.of(activity.payload);

                  // Update payload & deskripsi otomatis sesuai nilai baru
                  if (activity.activityType == AutonomousActivityType.fuelLog) {
                    final liters = double.tryParse(litersController.text.trim());
                    final cost = int.tryParse(costController.text.replaceAll(RegExp(r'[^0-9]'), ''));
                    final odo = double.tryParse(odoController.text.trim());
                    if (liters != null) updatedPayload['liters'] = liters;
                    if (cost != null) updatedPayload['cost'] = cost;
                    if (odo != null) updatedPayload['odometer'] = odo;
                    if (liters != null && cost != null) {
                      newDesc = '$liters L BBM Rp $cost'
                          '${odo != null ? ' (Odo: ${odo.toInt()} km)' : ''}';
                    }
                  } else if (activity.activityType == AutonomousActivityType.envelopeRebalance) {
                    final amount = int.tryParse(amountController.text.replaceAll(RegExp(r'[^0-9]'), ''));
                    if (amount != null) {
                      updatedPayload['amount'] = amount;
                      final from = payload['fromBudgetName'] ?? 'Pos Sumber';
                      final to = payload['toBudgetName'] ?? 'Pos Target';
                      newDesc = 'Menggeser Rp $amount dari $from ke $to.';
                    }
                  } else if (activity.activityType == AutonomousActivityType.utilityMeter) {
                    final meterNum = meterNumberController.text.trim();
                    final alias = aliasController.text.trim();
                    final tariff = tariffPowerController.text.trim();
                    if (meterNum.isNotEmpty) updatedPayload['meterNumber'] = meterNum;
                    if (alias.isNotEmpty) updatedPayload['alias'] = alias;
                    if (tariff.isNotEmpty) updatedPayload['tariffPower'] = tariff;
                    newDesc = 'Meteran PLN: $alias ($meterNum - $tariff)';
                  } else if (activity.activityType == AutonomousActivityType.harvestShift) {
                    if (selectedHarvestDate != null) {
                      updatedPayload['newHarvestDate'] = selectedHarvestDate!.toIso8601String();
                      final dateStr =
                          '${selectedHarvestDate!.day.toString().padLeft(2, '0')}/${selectedHarvestDate!.month.toString().padLeft(2, '0')}/${selectedHarvestDate!.year}';
                      newDesc = 'Target panen diperbarui ke $dateStr.';
                    }
                  } else if (activity.activityType == AutonomousActivityType.habitDeclaration) {
                    final hText = habitTextController.text.trim();
                    final cat = categoryController.text.trim();
                    if (hText.isNotEmpty) updatedPayload['habitText'] = hText;
                    if (cat.isNotEmpty) updatedPayload['category'] = cat;
                  }

                  Navigator.of(ctx).pop({
                    'title': newTitle,
                    'description': newDesc.isNotEmpty ? newDesc : activity.description,
                    'payload': updatedPayload,
                  });
                },
                child: const Text('Simpan Koreksi'),
              ),
            ],
          );
        },
      );
    },
  );
}
