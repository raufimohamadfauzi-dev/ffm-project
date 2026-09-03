import 'package:flutter/material.dart';
import '../../domain/ffm_assistant_insight.dart';
import '../../domain/ffm_proactive_delivery_policy.dart';

class ProactiveSettingsDialog extends StatefulWidget {
  const ProactiveSettingsDialog({
    super.key,
    required this.policy,
  });

  final FfmProactiveDeliveryPolicy policy;

  static Future<void> show(
    BuildContext context,
    FfmProactiveDeliveryPolicy policy,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ProactiveSettingsDialog(policy: policy),
    );
  }

  @override
  State<ProactiveSettingsDialog> createState() =>
      _ProactiveSettingsDialogState();
}

class _ProactiveSettingsDialogState extends State<ProactiveSettingsDialog> {
  bool _loading = true;
  bool _enabled = true;
  bool _quietHours = true;
  int _dailyLimit = 3;
  List<String> _disabledDetectors = const [];

  final List<(FfmAssistantInsightType, String, String)> _allDetectors = const [
    (
      FfmAssistantInsightType.runwayRisk,
      'Prediksi Runway Kas',
      'Peringatan dini ketahanan kas jika pengeluaran melampaui pemasukan',
    ),
    (
      FfmAssistantInsightType.envelopeRebalance,
      'Penyeimbangan Pos Anggaran',
      'Saran pengalihan saldo amplop surplus ke pos yang defisit',
    ),
    (
      FfmAssistantInsightType.anomalySpike,
      'Lonjakan Pengeluaran',
      'Deteksi pengeluaran di luar kebiasaan',
    ),
    (
      FfmAssistantInsightType.microExpenseLeak,
      'Kebocoran Pengeluaran Kecil',
      'Peringatan akumulasi transaksi kecil harian yang berulang',
    ),
    (
      FfmAssistantInsightType.debtServiceRatio,
      'Rasio Beban Utang (DSR)',
      'Pemantauan porsi cicilan terhadap pemasukan bulanan',
    ),
    (
      FfmAssistantInsightType.goalProgressRisk,
      'Risiko Target Finansial',
      'Evaluasi ketercapaian target tabungan keluarga',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final enabled = await widget.policy.isEnabled();
    final quiet = await widget.policy.isQuietHoursEnabled();
    final limit = await widget.policy.getDailyLimit();
    final disabled = await widget.policy.getDisabledDetectors();

    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _quietHours = quiet;
      _dailyLimit = limit;
      _disabledDetectors = disabled;
      _loading = false;
    });
  }

  Future<void> _toggleEnabled(bool value) async {
    setState(() => _enabled = value);
    await widget.policy.setEnabled(value);
  }

  Future<void> _toggleQuietHours(bool value) async {
    setState(() => _quietHours = value);
    await widget.policy.setQuietHoursEnabled(value);
  }

  Future<void> _setDailyLimit(int limit) async {
    setState(() => _dailyLimit = limit);
    await widget.policy.setDailyLimit(limit);
  }

  Future<void> _toggleDetector(String typeName, bool disabled) async {
    final updated = List<String>.from(_disabledDetectors);
    if (disabled && !updated.contains(typeName)) {
      updated.add(typeName);
    } else if (!disabled) {
      updated.remove(typeName);
    }
    setState(() => _disabledDetectors = updated);
    await widget.policy.setDetectorDisabled(typeName, disabled);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Preferensi Wawasan Asisten',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Atur batas notifikasi dan detektor proaktif',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Notifikasi Wawasan Otomatis'),
                    subtitle: const Text(
                      'Izinkan asisten memberikan sinyal penting saat ada kondisi finansial yang perlu perhatian.',
                    ),
                    value: _enabled,
                    onChanged: _toggleEnabled,
                  ),
                  const Divider(),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Jam Hening (Quiet Hours)'),
                    subtitle: const Text(
                      'Tahan notifikasi antara pukul 22:00 malam s.d. 06:00 pagi agar tidak mengganggu istirahat.',
                    ),
                    value: _quietHours,
                    onChanged: _enabled ? _toggleQuietHours : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Batas Maksimal per Hari',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Mencegah terlalu banyak pemberitahuan',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      DropdownButton<int>(
                        value: _dailyLimit,
                        items: const [
                          DropdownMenuItem(value: 1, child: Text('1x / hari')),
                          DropdownMenuItem(value: 2, child: Text('2x / hari')),
                          DropdownMenuItem(value: 3, child: Text('3x / hari')),
                          DropdownMenuItem(value: 5, child: Text('5x / hari')),
                        ],
                        onChanged: _enabled
                            ? (val) {
                                if (val != null) _setDailyLimit(val);
                              }
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Detektor Finansial Aktif',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? const Color(0xFFC49A6B)
                          : const Color(0xFFB07A4A),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._allDetectors.map((item) {
                    final type = item.$1;
                    final title = item.$2;
                    final desc = item.$3;
                    final isDetectorDisabled =
                        _disabledDetectors.contains(type.name);

                    return CheckboxListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(title),
                      subtitle: Text(desc, style: const TextStyle(fontSize: 12)),
                      value: !isDetectorDisabled,
                      onChanged: _enabled
                          ? (checked) {
                              if (checked != null) {
                                _toggleDetector(type.name, !checked);
                              }
                            }
                          : null,
                    );
                  }),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
