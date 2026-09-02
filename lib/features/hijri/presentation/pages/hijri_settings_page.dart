import 'package:flutter/material.dart';

import '../../../../core/database/app_context.dart';
import '../../../../core/di/injection.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../../../shared/widgets/date_time_components.dart';
import '../../../../shared/widgets/hijri_date_components.dart';
import '../../domain/hijri_calendar_service.dart';

class HijriSettingsPage extends StatefulWidget {
  const HijriSettingsPage({super.key});

  @override
  State<HijriSettingsPage> createState() => _HijriSettingsPageState();
}

class _HijriSettingsPageState extends State<HijriSettingsPage> {
  final _calendarService = getIt<HijriCalendarService>();
  HijriSettingsEntity? _settings;
  HijriDisplayDate? _todayDisplay;
  List<HijriMonthOverrideEntity> _overrides = [];
  List<HijriCorrectionLogEntity> _logs = [];
  bool _loading = true;
  int _selectedAdjustment = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final householdId = AppContext.householdId;
    final settings = await _calendarService.getSettings(householdId);
    final todayDisplay = await _calendarService.convert(
      householdId,
      DateTime.now(),
    );
    final overrides = await _calendarService.listOverrides(householdId);
    final logs = await _calendarService.listLogs(householdId);

    if (!mounted) return;
    setState(() {
      _settings = settings;
      _todayDisplay = todayDisplay;
      _overrides = overrides;
      _logs = logs;
      _selectedAdjustment = settings.dayAdjustment;
      _loading = false;
    });
  }

  Future<void> _saveAdjustment(int newAdjustment) async {
    final settings = _settings;
    if (settings == null) return;
    try {
      await _calendarService.saveSettings(
        householdId: AppContext.householdId,
        method: settings.method,
        region: settings.region,
        dayAdjustment: newAdjustment,
        timezone: settings.timezone,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Koreksi Hilal berhasil disimpan.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _loadData();
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menyimpan koreksi: $error')),
      );
    }
  }

  Future<void> _openAddOverrideDialog() async {
    final now = DateTime.now();
    int hijriYear = _todayDisplay?.hijri.year ?? 1448;
    int hijriMonth = _todayDisplay?.hijri.month ?? 9;
    DateTime startDate = DateTime(now.year, now.month, now.day);
    final noteController = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Koreksi Awal Bulan Hilal'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Tetapkan tanggal 1 Masehi untuk bulan Hijriah tertentu sesuai Sidang Isbat / Rukyatul Hilal lokal.',
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: hijriMonth,
                          decoration: const InputDecoration(
                            labelText: 'Bulan Hijriah',
                          ),
                          items: const [
                            DropdownMenuItem(value: 1, child: Text('1. Muharram')),
                            DropdownMenuItem(value: 2, child: Text('2. Safar')),
                            DropdownMenuItem(value: 3, child: Text('3. Rabiul Awal')),
                            DropdownMenuItem(value: 4, child: Text('4. Rabiul Akhir')),
                            DropdownMenuItem(value: 5, child: Text('5. Jumadil Awal')),
                            DropdownMenuItem(value: 6, child: Text('6. Jumadil Akhir')),
                            DropdownMenuItem(value: 7, child: Text('7. Rajab')),
                            DropdownMenuItem(value: 8, child: Text('8. Sya\'ban')),
                            DropdownMenuItem(value: 9, child: Text('9. Ramadan')),
                            DropdownMenuItem(value: 10, child: Text('10. Syawal')),
                            DropdownMenuItem(value: 11, child: Text('11. Zulkaidah')),
                            DropdownMenuItem(value: 12, child: Text('12. Zulhijah')),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() => hijriMonth = val);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          initialValue: hijriYear.toString(),
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Tahun H',
                          ),
                          onChanged: (val) {
                            final parsed = int.tryParse(val);
                            if (parsed != null && parsed > 1400) {
                              hijriYear = parsed;
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Tanggal 1 Bulan Ini'),
                    subtitle: Text(formatTanggalLengkap(startDate)),
                    trailing: IconButton(
                      icon: const Icon(Icons.calendar_today_outlined),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: startDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setDialogState(() => startDate = picked);
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: noteController,
                    decoration: const InputDecoration(
                      labelText: 'Catatan penetapan (opsional)',
                      hintText: 'Misal: Sidang Isbat Kemenag',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Simpan'),
              ),
            ],
          );
        },
      ),
    );

    if (saved == true && mounted) {
      try {
        await _calendarService.saveOverride(
          householdId: AppContext.householdId,
          hijriYear: hijriYear,
          hijriMonth: hijriMonth,
          gregorianStartDate: startDate,
          note: noteController.text.trim().isEmpty
              ? null
              : noteController.text.trim(),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Penetapan awal bulan Hijriah berhasil disimpan.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        await _loadData();
      } on Object catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan penetapan: $error')),
        );
      }
    }
  }

  Future<void> _deleteOverride(String id) async {
    try {
      await _calendarService.deleteOverride(AppContext.householdId, id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Koreksi bulan dihapus.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _loadData();
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menghapus koreksi: $error')),
      );
    }
  }

  String _monthName(int month) {
    const names = [
      '',
      'Muharram',
      'Safar',
      'Rabiul Awal',
      'Rabiul Akhir',
      'Jumadil Awal',
      'Jumadil Akhir',
      'Rajab',
      'Sya\'ban',
      'Ramadan',
      'Syawal',
      'Zulkaidah',
      'Zulhijah',
    ];
    if (month >= 1 && month <= 12) return names[month];
    return 'Bulan $month';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final todayDisplay = _todayDisplay;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kalender Hijriah & Hilal'),
        actions: [
          IconButton(
            tooltip: 'Info Pengaturan Hilal',
            onPressed: () => showAppInfoDialog(
              context,
              title: 'Tentang Kalender Hijriah & Hilal',
              message:
                  'Gunakan pengaturan ini untuk menyesuaikan tanggal Hijriah dengan penetapan Hilal / Rukyatul Hilal lokal (misal Sidang Isbat Kemenag).\n\nSetiap perubahan koreksi di sini akan otomatis memperbarui tanggal Hijriah di seluruh aplikasi FFM (Pengingat, Transaksi, Target, dll).',
            ),
            icon: const Icon(Icons.info_outline),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
              children: [
                // 1. Preview Tanggal Hari Ini
                if (todayDisplay != null) ...[
                  AppCard(
                    color: theme.colorScheme.primaryContainer.withValues(alpha: .45),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.nights_stay_outlined,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Tanggal Hari Ini',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Masehi: ${formatTanggalLengkap(todayDisplay.gregorian)}',
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Hijriah: ${formatHijriDate(todayDisplay)}',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        if (todayDisplay.manualOffsetDays != 0) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Status: Menggunakan koreksi offset (${todayDisplay.manualOffsetDays > 0 ? '+' : ''}${todayDisplay.manualOffsetDays} hari)',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // 2. Koreksi Hilal Global (Day Adjustment)
                AppSectionHeader(
                  title: 'Koreksi Hilal Global (Offset Harian)',
                  helpText:
                      'Geser penanggalan Hijriah umum (-2 s/d +2 hari) jika Hilal lokal masuk lebih cepat atau lebih lambat dari kalender standar.',
                ),
                const SizedBox(height: 8),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [-2, -1, 0, 1, 2].map((days) {
                          final isSelected = _selectedAdjustment == days;
                          final label = days == 0
                              ? '0 (Standar)'
                              : days > 0
                                  ? '+$days Hari'
                                  : '$days Hari';
                          return ChoiceChip(
                            label: Text(label),
                            selected: isSelected,
                            onSelected: (selected) {
                              if (selected) {
                                setState(() => _selectedAdjustment = days);
                                _saveAdjustment(days);
                              }
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // 3. Koreksi Spesifik Bulan (Hilal Override)
                Row(
                  children: [
                    Expanded(
                      child: AppSectionHeader(
                        title: 'Koreksi Awal Bulan (Hilal Override)',
                        helpText:
                            'Penetapan khusus tanggal 1 untuk bulan Hijriah tertentu (misal 1 Ramadan / 1 Syawal sesuai Sidang Isbat).',
                      ),
                    ),
                    IconButton(
                      tooltip: 'Tambah penetapan awal bulan',
                      onPressed: _openAddOverrideDialog,
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_overrides.isEmpty)
                  AppCard(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_month_outlined,
                            color: theme.colorScheme.outline,
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Belum ada penetapan khusus awal bulan. Klik + di kanan untuk menambah.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ..._overrides.map(
                    (item) => AppCard(
                      child: ListTile(
                        dense: true,
                        leading: const Icon(Icons.event_available_outlined),
                        title: Text(
                          '1 ${_monthName(item.hijriMonth)} ${item.hijriYear} H',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          'Tgl Masehi: ${formatTanggalLengkap(item.gregorianStartDate)}${item.note != null ? ' · ${item.note}' : ''}',
                        ),
                        trailing: IconButton(
                          tooltip: 'Hapus koreksi',
                          onPressed: () => _deleteOverride(item.id),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 20),

                // 4. Log Riwayat Koreksi Hilal
                if (_logs.isNotEmpty) ...[
                  AppSectionHeader(
                    title: 'Riwayat Koreksi Hilal',
                    helpText: 'Catatan log historis penyesuaian yang pernah disimpan.',
                  ),
                  const SizedBox(height: 8),
                  ..._logs.map(
                    (log) => AppCard(
                      child: ListTile(
                        dense: true,
                        leading: const Icon(Icons.history_outlined),
                        title: Text(
                          'Koreksi ${log.action.replaceAll('_', ' ')}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          '${formatTanggalLengkap(log.timestamp)} · ${log.oldValue ?? '-'} ➔ ${log.newValue ?? '-'}',
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
