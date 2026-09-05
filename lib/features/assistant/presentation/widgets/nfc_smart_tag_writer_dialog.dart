import 'package:flutter/material.dart';

import '../../data/nfc_bridge.dart';

enum NfcSmartTagPreset {
  fuel,
  groceries,
  voiceAssistant,
  timerActivity,
  custom,
}

/// Dialog untuk menulis payload NDEF aksi cepat ke stiker koin NFC fisik.
class NfcSmartTagWriterDialog extends StatefulWidget {
  const NfcSmartTagWriterDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const NfcSmartTagWriterDialog(),
    );
  }

  @override
  State<NfcSmartTagWriterDialog> createState() => _NfcSmartTagWriterDialogState();
}

class _NfcSmartTagWriterDialogState extends State<NfcSmartTagWriterDialog>
    with SingleTickerProviderStateMixin {
  final _nfcBridge = NfcBridge();
  NfcSmartTagPreset _selectedPreset = NfcSmartTagPreset.fuel;
  final _customTitleController = TextEditingController(text: 'Uang Jajan Anak');
  final _customCategoryController = TextEditingController(text: 'Pendidikan & Anak');

  bool _isWriting = false;
  bool _writeSuccess = false;
  String? _errorMessage;

  late AnimationController _animController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.9, end: 1.15).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    _customTitleController.dispose();
    _customCategoryController.dispose();
    if (_isWriting) {
      _nfcBridge.cancelWrite();
    }
    super.dispose();
  }

  String _generateUri() {
    switch (_selectedPreset) {
      case NfcSmartTagPreset.fuel:
        return 'ffm://action?type=fuel&title=Bensin&category=Transportasi';
      case NfcSmartTagPreset.groceries:
        return 'ffm://action?type=groceries&title=Belanja+Dapur&category=Kebutuhan+Rumah+Tangga';
      case NfcSmartTagPreset.voiceAssistant:
        return 'ffm://action?type=voice_assistant';
      case NfcSmartTagPreset.timerActivity:
        return 'ffm://action?type=timer_activity&title=Sesi+Kerja+Tani';
      case NfcSmartTagPreset.custom:
        final title = Uri.encodeComponent(_customTitleController.text.trim());
        final category = Uri.encodeComponent(_customCategoryController.text.trim());
        return 'ffm://action?type=custom&title=$title&category=$category';
    }
  }

  Future<void> _startWriting() async {
    final isAvail = await _nfcBridge.isNfcAvailable();
    final isEnabled = await _nfcBridge.isNfcEnabled();

    if (!isAvail || !isEnabled) {
      setState(() {
        _errorMessage = !isAvail
            ? 'HP ini tidak memiliki sensor NFC.'
            : 'Sensor NFC sedang nonaktif. Nyalakan NFC di pengaturan HP Anda.';
      });
      return;
    }

    setState(() {
      _isWriting = true;
      _writeSuccess = false;
      _errorMessage = null;
    });

    final uri = _generateUri();
    final result = await _nfcBridge.writeTag(uri);

    if (!mounted) return;

    if (result['success'] == true) {
      setState(() {
        _isWriting = false;
        _writeSuccess = true;
      });
    } else {
      setState(() {
        _isWriting = false;
        _errorMessage = result['error']?.toString() ?? 'Gagal memprogram stiker NFC.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.nfc_rounded, color: colors.primary, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Program Stiker Pintar NFC',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Jadikan koin/stiker NFC tombol aksi instan di dunia nyata',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (_isWriting)
              _buildWritingState(theme, colors)
            else if (_writeSuccess)
              _buildSuccessState(theme, colors)
            else
              _buildConfigForm(theme, colors),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigForm(ThemeData theme, ColorScheme colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_errorMessage != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: colors.error),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: colors.onErrorContainer),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        Text(
          'Pilih Aksi Cepat yang Didaftarkan:',
          style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),

        _PresetCard(
          icon: Icons.local_gas_station_rounded,
          title: 'Tombol Bensin di Mobil / Motor',
          subtitle: 'Kategori otomatis Transportasi / Bensin',
          isSelected: _selectedPreset == NfcSmartTagPreset.fuel,
          color: Colors.amber.shade800,
          onTap: () => setState(() => _selectedPreset = NfcSmartTagPreset.fuel),
        ),
        _PresetCard(
          icon: Icons.kitchen_rounded,
          title: 'Tombol Belanja di Kulkas / Dapur',
          subtitle: 'Kategori otomatis Kebutuhan Rumah Tangga',
          isSelected: _selectedPreset == NfcSmartTagPreset.groceries,
          color: Colors.green.shade700,
          onTap: () => setState(() => _selectedPreset = NfcSmartTagPreset.groceries),
        ),
        _PresetCard(
          icon: Icons.mic_rounded,
          title: 'Tombol Asisten AI (Mode Suara)',
          subtitle: 'Langsung mengaktifkan mikrofon Asisten AI FFM',
          isSelected: _selectedPreset == NfcSmartTagPreset.voiceAssistant,
          color: Colors.purple.shade700,
          onTap: () => setState(() => _selectedPreset = NfcSmartTagPreset.voiceAssistant),
        ),
        _PresetCard(
          icon: Icons.timer_rounded,
          title: 'Tombol Timer Sesi Kerja / Tani',
          subtitle: 'Mulai stopwatch sesi aktivitas kebun/proyek',
          isSelected: _selectedPreset == NfcSmartTagPreset.timerActivity,
          color: Colors.teal.shade700,
          onTap: () => setState(() => _selectedPreset = NfcSmartTagPreset.timerActivity),
        ),
        _PresetCard(
          icon: Icons.tune_rounded,
          title: 'Kustom Aksi Sendiri',
          subtitle: 'Tentukan judul dan pos pengeluaran keluarga',
          isSelected: _selectedPreset == NfcSmartTagPreset.custom,
          color: Colors.blue.shade700,
          onTap: () => setState(() => _selectedPreset = NfcSmartTagPreset.custom),
        ),

        if (_selectedPreset == NfcSmartTagPreset.custom) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _customTitleController,
            decoration: const InputDecoration(
              labelText: 'Label Pengeluaran',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _customCategoryController,
            decoration: const InputDecoration(
              labelText: 'Kategori',
              border: OutlineInputBorder(),
            ),
          ),
        ],

        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton.icon(
            icon: const Icon(Icons.nfc_rounded),
            label: const Text('Tulis ke Koin / Stiker NFC'),
            onPressed: _startWriting,
          ),
        ),
      ],
    );
  }

  Widget _buildWritingState(ThemeData theme, ColorScheme colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            ScaleTransition(
              scale: _pulseAnim,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.primary.withValues(alpha: 0.15),
                  border: Border.all(color: colors.primary, width: 2),
                ),
                child: Icon(Icons.nfc_rounded, color: colors.primary, size: 50),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Tempelkan Stiker / Koin ke Belakang HP',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tahan selama 1 detik sampai HP bergetar...',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () {
                _nfcBridge.cancelWrite();
                setState(() => _isWriting = false);
              },
              child: const Text('Batal'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessState(ThemeData theme, ColorScheme colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.green.shade100,
              ),
              child: Icon(Icons.check_circle, color: Colors.green.shade700, size: 56),
            ),
            const SizedBox(height: 16),
            Text(
              'Stiker NFC Berhasil Diprogram!',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.green.shade800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Sekarang Anda bisa menempelkan stiker ini di tempatnya (mobil, kulkas, atau meja kerja). Kapan pun disentuh HP, aksi ini langsung terbuka otomatis!',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Selesai'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected
            ? color.withValues(alpha: 0.12)
            : colors.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected ? color : colors.outlineVariant.withValues(alpha: 0.5),
          width: isSelected ? 1.8 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(Icons.check_circle, color: color, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
