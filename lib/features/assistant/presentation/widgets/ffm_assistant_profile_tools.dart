import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/database/app_context.dart';
import '../../../../core/di/injection.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../data/ffm_assistant_personalization_repository.dart';
import '../../data/ffm_assistant_profile_export_service.dart';

/// Kontrol cadangan dan pembelajaran di dalam halaman Profil Keluarga.
class FfmAssistantProfileTools extends StatefulWidget {
  const FfmAssistantProfileTools({
    super.key,
    this.enabled = true,
    this.onImported,
  });

  final bool enabled;
  final Future<void> Function()? onImported;

  @override
  State<FfmAssistantProfileTools> createState() => _FfmAssistantProfileToolsState();
}

class _FfmAssistantProfileToolsState extends State<FfmAssistantProfileTools> {
  final _passphraseController = TextEditingController();
  final _confirmPassphraseController = TextEditingController();
  late final FfmAssistantProfileExportService _profileService;
  late final FfmAssistantPersonalizationRepository _repository;

  int _preferenceCount = 0;
  int _patternCount = 0;
  bool _obscurePassphrase = true;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _repository = getIt<FfmAssistantPersonalizationRepository>();
    _profileService = FfmAssistantProfileExportService(_repository);
    _loadSummary();
  }

  @override
  void dispose() {
    _passphraseController.dispose();
    _confirmPassphraseController.dispose();
    super.dispose();
  }

  Future<void> _loadSummary() async {
    try {
      final preferences = await _repository.getPreferences(
        AppContext.householdId,
      );
      final patterns = await _repository.getAllPatterns(AppContext.householdId);
      if (!mounted) return;
      setState(() {
        _preferenceCount = preferences.length;
        _patternCount = patterns
            .where(
              (p) =>
                  p.sampleCount >= FfmPersonalizationPattern.minimumSampleCount &&
                  p.confidenceScore >=
                      FfmPersonalizationPattern.minimumConfidenceScore,
            )
            .length;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _preferenceCount = 0;
        _patternCount = 0;
      });
    }
  }

  Future<void> _resetLearning() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset pembelajaran asisten?'),
        content: const Text(
          'Koreksi transaksi dan pola merchant akan dihapus. Perkenalan diri, preferensi, dan transaksi tidak ikut dihapus.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Reset learning'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _working = true);
    try {
      await _repository.resetLearning(AppContext.householdId);
      await _loadSummary();
      _showMessage(
        'Pembelajaran direset. Perkenalan diri dan transaksi tetap ada.',
      );
    } catch (_) {
      _showMessage('Reset pembelajaran belum berhasil.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _exportProfile() async {
    final passphrase = _passphraseController.text;
    if (!_validatePassphrase(passphrase)) return;
    setState(() => _working = true);
    File? tempFile;
    try {
      final encrypted = await _profileService.exportProfile(
        householdId: AppContext.householdId,
        passphrase: passphrase,
      );
      final directory = await getApplicationDocumentsDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      tempFile = File('${directory.path}/ffm-profile-$stamp.ffmprofile');
      await tempFile.writeAsString(encrypted, flush: true);
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(tempFile.path)],
          text: 'Profil personalisasi FFM terenkripsi. Simpan file ini untuk dipindahkan ke perangkat lain.',
        ),
      );
      _showMessage('Profil berhasil dibuat dan siap dibagikan.');
    } catch (_) {
      _showMessage('Profil belum berhasil diekspor. Coba lagi.');
    } finally {
      if (tempFile != null && await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
      if (mounted) setState(() => _working = false);
    }
  }

  static const _maxFileSizeBytes = 2 * 1024 * 1024; // 2 MB

  Future<void> _importProfile() async {
    final passphrase = _passphraseController.text;
    if (passphrase.isEmpty) {
      _showMessage('Masukkan passphrase profil terlebih dahulu.');
      return;
    }

    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['ffmprofile'],
    );
    if (result.isEmpty || result.single.path == null) return;

    final file = File(result.single.path!);
    final fileSize = await file.length();
    if (fileSize > _maxFileSizeBytes) {
      _showMessage('Ukuran file terlalu besar. Maksimal 2 MB.');
      return;
    }

    setState(() => _working = true);
    try {
      final encrypted = await file.readAsString();
      await _profileService.importProfile(
        householdId: AppContext.householdId,
        encryptedPayload: encrypted,
        passphrase: passphrase,
      );
      await _loadSummary();
      await widget.onImported?.call();
      _showMessage(
        'Profil berhasil digabungkan. Data lama tetap dipertahankan; nilai yang sama diperbarui.',
      );
    } on Exception catch (error) {
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    } catch (_) {
      _showMessage('File profil belum berhasil dibaca.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  bool _validatePassphrase(String passphrase) {
    if (passphrase.length < 8) {
      _showMessage('Passphrase minimal 8 karakter.');
      return false;
    }
    if (passphrase != _confirmPassphraseController.text) {
      _showMessage('Konfirmasi passphrase belum sama.');
      return false;
    }
    return true;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: const Text('Cadangan & pembelajaran asisten'),
      subtitle: const Text('Ekspor, impor, dan reset pola belajar'),
      leading: const Icon(Icons.ios_share_outlined),
      childrenPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AppHelpBanner(
              title: 'Cadangan profil terenkripsi',
              message: 'Profil ini hanya berisi preferensi dan pola terstruktur. Transaksi mentah, catatan, dan riwayat chat tidak ikut diekspor.',
              icon: Icons.shield_outlined,
            ),
            const SizedBox(height: 16),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Isi profil saat ini',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),
                  Text('Preferensi: $_preferenceCount'),
                  Text('Pola kuat: $_patternCount'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (!widget.enabled)
              const Text('Simpan perubahan profil keluarga terlebih dahulu.'),
            const SizedBox(height: 22),
            const Text(
              'Kunci ekspor-impor profil',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _passphraseController,
              enabled: widget.enabled && !_working,
              obscureText: _obscurePassphrase,
              decoration: InputDecoration(
                labelText: 'Passphrase profil',
                helperText: 'Gunakan minimal 8 karakter dan simpan baik-baik.',
                prefixIcon: const Icon(Icons.key_outlined),
                suffixIcon: IconButton(
                  tooltip: _obscurePassphrase ? 'Tampilkan' : 'Sembunyikan',
                  onPressed: () =>
                      setState(() => _obscurePassphrase = !_obscurePassphrase),
                  icon: Icon(
                    _obscurePassphrase
                        ? Icons.visibility
                        : Icons.visibility_off,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmPassphraseController,
              enabled: widget.enabled && !_working,
              obscureText: _obscurePassphrase,
              decoration: const InputDecoration(
                labelText: 'Ulangi passphrase',
                prefixIcon: Icon(Icons.check_circle_outline),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _working || !widget.enabled ? null : _exportProfile,
              icon: const Icon(Icons.ios_share_outlined),
              label: const Text('Ekspor & bagikan profil'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _working || !widget.enabled ? null : _importProfile,
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('Impor dan gabungkan profil'),
            ),
            if (_working) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              const Center(child: Text('Memproses profil secara lokal...')),
            ],
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: _working || !widget.enabled ? null : _resetLearning,
              icon: const Icon(Icons.restart_alt_outlined),
              label: const Text('Reset learning'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Saat impor, preferensi dengan kunci sama diperbarui dan pola merchant-field yang sama ditimpa dengan data impor. Data transaksi tidak disentuh.',
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
      ],
    );
  }
}
