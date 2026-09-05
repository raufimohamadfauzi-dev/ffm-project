import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_context.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/audit_logger.dart';
import '../../../../core/di/injection.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../../assistant/data/ffm_assistant_personalization_repository.dart';
import '../../../assistant/domain/ffm_assistant_models.dart';
import '../../../assistant/presentation/pages/assistant_profile_page.dart';
import '../../../assistant/presentation/widgets/ffm_assistant_page_context.dart';

/// Satu halaman untuk profil keluarga dan data pribadi yang membantu Asisten.
///
/// Memindahkan profil keluarga (nama rumah tangga, suami, istri) keluar dari
/// Data Utama dan menggabungkannya dengan "Kenalkan Diri" agar tidak ada dua
/// tempat menyimpan data pribadi yang sama.
class FamilyProfilePage extends StatefulWidget {
  const FamilyProfilePage({
    super.key,
    this.initialHouseholdName,
    this.initialIdentityName,
  });

  final String? initialHouseholdName;
  final String? initialIdentityName;

  @override
  State<FamilyProfilePage> createState() => _FamilyProfilePageState();
}

class _FamilyProfilePageState extends State<FamilyProfilePage> {
  final _database = getIt<AppDatabase>();
  late final _audit = AuditLogger(_database);
  late final FfmAssistantPersonalizationRepository _repository;
  final _householdController = TextEditingController();
  final _husbandController = TextEditingController();
  final _wifeController = TextEditingController();
  final _nameController = TextEditingController();
  final _occupationController = TextEditingController();
  final _routineController = TextEditingController();
  final _goalsController = TextEditingController();
  var _loading = true;
  var _working = false;
  var _dirty = false;

  @override
  void initState() {
    super.initState();
    _repository = getIt<FfmAssistantPersonalizationRepository>();
    _load();
  }

  @override
  void dispose() {
    _householdController.dispose();
    _husbandController.dispose();
    _wifeController.dispose();
    _nameController.dispose();
    _occupationController.dispose();
    _routineController.dispose();
    _goalsController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final row =
        await (_database.select(_database.households)
              ..where((item) => item.id.equals(AppContext.householdId)))
            .getSingleOrNull();
    final preferences = await _repository.getPreferences(
      AppContext.householdId,
    );
    final values = <String, String>{
      for (final preference in preferences)
        preference.preferenceKey: preference.preferenceValue,
    };
    if (!mounted) return;
    setState(() {
      _loading = false;
      _householdController.text =
          widget.initialHouseholdName?.trim().isNotEmpty == true
          ? widget.initialHouseholdName!.trim()
          : (row?.name ?? 'Keluarga');
      _husbandController.text = row?.husbandName ?? '';
      _wifeController.text = row?.wifeName ?? '';
      _nameController.text =
          widget.initialIdentityName?.trim().isNotEmpty == true
          ? widget.initialIdentityName!.trim()
          : (values['profile_name'] ?? '');
      _occupationController.text = values['profile_occupation'] ?? '';
      _routineController.text = values['profile_routine'] ?? '';
      _goalsController.text = values['profile_goals'] ?? '';
    });
  }

  Future<void> _saveFamilyProfile() async {
    final now = DateTime.now();
    await _database
        .into(_database.households)
        .insertOnConflictUpdate(
          HouseholdsCompanion.insert(
            id: AppContext.householdId,
            name: _householdController.text.trim().isEmpty
                ? 'Keluarga'
                : _householdController.text.trim(),
            husbandName: Value(
              _husbandController.text.trim().isEmpty
                  ? null
                  : _husbandController.text.trim(),
            ),
            wifeName: Value(
              _wifeController.text.trim().isEmpty
                  ? null
                  : _wifeController.text.trim(),
            ),
            createdAt: now,
            updatedAt: Value(now),
          ),
        );
    await _saveParty(_husbandController.text, 'husband');
    await _saveParty(_wifeController.text, 'wife');
    await _audit.record(
      action: 'Profil keluarga disimpan',
      entity: 'family_profile',
    );
  }

  Future<void> _saveParty(String rawName, String kind) async {
    final name = rawName.trim();
    final existing =
        await (_database.select(_database.transactionParties)..where(
              (row) =>
                  row.householdId.equals(AppContext.householdId) &
                  row.kind.equals(kind),
            ))
            .getSingleOrNull();
    if (name.isEmpty) {
      if (existing != null) {
        await (_database.update(_database.transactionParties)
              ..where((row) => row.id.equals(existing.id)))
            .write(const TransactionPartiesCompanion(isArchived: Value(true)));
      }
      return;
    }
    await _database
        .into(_database.transactionParties)
        .insertOnConflictUpdate(
          TransactionPartiesCompanion.insert(
            id: existing?.id ?? const Uuid().v4(),
            householdId: AppContext.householdId,
            name: name,
            role: Value(kind == 'husband' ? 'Suami' : 'Istri'),
            kind: Value(kind),
            details: const Value(null),
            isArchived: const Value(false),
            createdAt: existing?.createdAt ?? DateTime.now(),
          ),
        );
  }

  Future<void> _saveIdentity() async {
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
  }

  Future<void> _saveAll() async {
    setState(() => _working = true);
    try {
      await _saveFamilyProfile();
      await _saveIdentity();
      if (!mounted) return;
      setState(() => _dirty = false);
      _showMessage('Profil keluarga dan data pribadi tersimpan.');
    } catch (_) {
      _showMessage('Profil belum berhasil disimpan. Coba lagi.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _openAssistantProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AssistantProfilePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FfmAssistantPageContext(
      destination: FfmAssistantDestination.familyProfile,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Profil Keluarga'),
          actions: [
            IconButton(
              tooltip: 'Ekspor & impor profil asisten',
              onPressed: _openAssistantProfile,
              icon: const Icon(Icons.ios_share_outlined),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 36),
                children: [
                  const AppHelpBanner(
                    title: 'Satu tempat untuk data keluarga',
                    message: 'Nama rumah tangga, pasangan, dan data pribadi yang membantu Asisten memahami keluargamu kini digabung di satu halaman. Data Utama difokuskan untuk pilihan transaksi.',
                    icon: Icons.family_restroom_outlined,
                  ),
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: 'Profil keluarga',
                    subtitle:
                        'Nama rumah tangga dan pasangan dipakai di ringkasan dan transaksi.',
                    icon: Icons.family_restroom_outlined,
                    color: theme.colorScheme.primary,
                    children: [
                      TextField(
                        controller: _householdController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Nama rumah tangga',
                          prefixIcon: Icon(Icons.home_outlined),
                        ),
                        onChanged: (_) => _markDirty(),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _husbandController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Nama Suami (opsional)',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        onChanged: (_) => _markDirty(),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _wifeController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Nama Istri (opsional)',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        onChanged: (_) => _markDirty(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: 'Data pribadi untuk Asisten',
                    subtitle:
                        'Kenalkan diri agar jawaban Asisten lebih sesuai konteks keluargamu.',
                    icon: Icons.psychology_outlined,
                    color: theme.colorScheme.tertiary,
                    children: [
                      TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Nama atau panggilan',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        onChanged: (_) => _markDirty(),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _occupationController,
                        decoration: const InputDecoration(
                          labelText: 'Pekerjaan atau peran utama',
                          prefixIcon: Icon(Icons.work_outline),
                        ),
                        onChanged: (_) => _markDirty(),
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
                        onChanged: (_) => _markDirty(),
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
                        onChanged: (_) => _markDirty(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _working ? null : _saveAll,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Simpan profil keluarga'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _openAssistantProfile,
                    icon: const Icon(Icons.ios_share_outlined),
                    label: const Text(
                      'Ekspor/impor & reset belajar asisten',
                    ),
                  ),
                  if (_working) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                    const Center(
                      child: Text('Menyimpan profil secara lokal...'),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  void _markDirty() {
    if (!_dirty) {
      setState(() => _dirty = true);
    }
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.children,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}