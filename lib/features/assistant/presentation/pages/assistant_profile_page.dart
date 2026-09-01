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
import '../../domain/ffm_assistant_models.dart';
import '../widgets/ffm_assistant_page_context.dart';

class AssistantProfilePage extends StatefulWidget {
  const AssistantProfilePage({super.key});

  @override
  State<AssistantProfilePage> createState() => _AssistantProfilePageState();
}

class _AssistantProfilePageState extends State<AssistantProfilePage> {
  final _nameController = TextEditingController();
  final _occupationController = TextEditingController();
  final _routineController = TextEditingController();
  final _goalsController = TextEditingController();
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
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _occupationController.dispose();
    _routineController.dispose();
    _goalsController.dispose();
    _passphraseController.dispose();
    _confirmPassphraseController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final preferences = await _repository.getPreferences(
      AppContext.householdId,
    );
    final values = <String, String>{
      for (final preference in preferences)
        preference.preferenceKey: preference.preferenceValue,
    };
    _nameController.text = values['profile_name'] ?? '';
    _occupationController.text = values['profile_occupation'] ?? '';
    _routineController.text = values['profile_routine'] ?? '';
    _goalsController.text = values['profile_goals'] ?? '';
    await _loadSummary();
  }

  Future<void> _loadSummary() async {
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
  }

  Future<void> _saveIdentity() async {
    setState(() => _working = true);
    try {
      final values = <String, String>{
        'profile_name': _nameController.text,
        'profile_occupation': _occupationController.text,
        'profile_routine': _routineController.text,
        'profile_goals': _goalsController.text,
      };
      for (final entry in values.entries) {
        if (entry.value.trim().isEmpty) {
          await _repository.deletePreference(
            householdId: AppContext.householdId,
            preferenceKey: entry.key,
          );
        } else {
          await _repository.setPreference(
            householdId: AppContext.householdId,
            preferenceKey: entry.key,
            preferenceValue: entry.value,
          );
        }
      }
      await _loadSummary();
      _showMessage('Perkenalan diri tersimpan secara lokal.');
    } catch (_) {
      _showMessage('Perkenalan diri belum berhasil disimpan.');
    } finally {
      if (mounted) setState(() => _working = false);
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
    try {
      final encrypted = await _profileService.exportProfile(
        householdId: AppContext.householdId,
        passphrase: passphrase,
      );
      final directory = await getApplicationDocumentsDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${directory.path}/ffm-profile-$stamp.ffmprofile');
      await file.writeAsString(encrypted, flush: true);
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'Profil personalisasi FFM terenkripsi. Simpan file ini untuk dipindahkan ke perangkat lain.',
        ),
      );
      _showMessage('Profil berhasil dibuat dan siap dibagikan.');
    } catch (_) {
      _showMessage('Profil belum berhasil diekspor. Coba lagi.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

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

    setState(() => _working = true);
    try {
      final encrypted = await File(result.single.path!).readAsString();
      await _profileService.importProfile(
        householdId: AppContext.householdId,
        encryptedPayload: encrypted,
        passphrase: passphrase,
      );
      await _loadSummary();
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
    return FfmAssistantPageContext(
      destination: FfmAssistantDestination.assistantProfile,
      child: Scaffold(
        appBar: AppBar(title: const Text('Profil Personalisasi Asisten')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 36),
          children: [
            const AppHelpBanner(
              title: 'Belajar terkontrol dan tetap offline',
              message: 'Profil ini hanya berisi preferensi dan pola terstruktur. Transaksi mentah, catatan, dan riwayat chat tidak ikut diekspor.',
              icon: Icons.shield_outlined,
            ),
            const SizedBox(height: 16),
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset(
                  'assets/branding/Logo_FFM.png',
                  width: 72,
                  height: 72,
                ),
              ),
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
            const Text(
              'Kenalkan Diri',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              'Isi yang ingin dibantu asisten. Semua tersimpan lokal dan dapat diedit kapan saja.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Nama atau panggilan',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _occupationController,
              decoration: const InputDecoration(
                labelText: 'Pekerjaan atau peran utama',
                prefixIcon: Icon(Icons.work_outline),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _routineController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Rutinitas penting',
                hintText: 'Contoh: panen setiap Jumat pagi',
                prefixIcon: Icon(Icons.repeat_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _goalsController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Tujuan atau prioritas',
                hintText: 'Contoh: menabung untuk modal usaha',
                prefixIcon: Icon(Icons.flag_outlined),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _working ? null : _saveIdentity,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Simpan perkenalan diri'),
            ),
            const SizedBox(height: 22),
            const Text(
              'Kunci ekspor-impor profil',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _passphraseController,
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
              obscureText: _obscurePassphrase,
              decoration: const InputDecoration(
                labelText: 'Ulangi passphrase',
                prefixIcon: Icon(Icons.check_circle_outline),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _working ? null : _exportProfile,
              icon: const Icon(Icons.ios_share_outlined),
              label: const Text('Ekspor & bagikan profil'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _working ? null : _importProfile,
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
              onPressed: _working ? null : _resetLearning,
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
      ),
    );
  }
}
