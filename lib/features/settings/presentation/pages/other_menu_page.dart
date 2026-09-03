import 'package:flutter/material.dart';

import '../../../../shared/widgets/app_components.dart';
import '../../../audit/presentation/pages/activity_log_page.dart';
import '../../../assistant/domain/ffm_assistant_models.dart';
import '../../../assistant/presentation/pages/assistant_profile_page.dart';
import '../../../assistant/presentation/pages/agent_inbox_page.dart';
import '../../../assistant/presentation/pages/ffm_assistant_autonomy_monitor_page.dart';

import '../../../assistant/presentation/widgets/ffm_assistant_page_context.dart';
import '../../../asset/presentation/pages/asset_pages.dart';
import '../../../backup/presentation/pages/backup_page.dart';
import '../../../backup/presentation/pages/monthly_report_page.dart';
import '../../../goal/presentation/pages/goal_pages.dart';
import '../../../hijri/presentation/pages/hijri_settings_page.dart';
import '../../../liability/presentation/pages/liability_pages.dart';
import '../../../reminder/presentation/pages/reminder_page.dart';
import 'app_diagnostics_page.dart';
import 'database_structure_page.dart';
import '../../../advisor/presentation/pages/analysis_page.dart';
import 'master_data_page.dart';

import '../../../recurring_transaction/presentation/pages/recurring_transaction_page.dart';

import 'pin_security_page.dart';
import 'privacy_center_page.dart';
import 'supabase_setup_page.dart';

class OtherMenuPage extends StatefulWidget {
  const OtherMenuPage({super.key});

  @override
  State<OtherMenuPage> createState() => _OtherMenuPageState();
}

class _OtherMenuPageState extends State<OtherMenuPage> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  bool _hasMatchingMenu() {
    const menuItems = <List<String>>[
      ['Data Utama', 'kategori toko tag rekening pemasukan'],
      ['Aset keluarga', 'barang kekayaan'],
      ['Target keuangan', 'uang dikumpulkan'],
      ['Hutang & piutang', 'kewajiban diterima'],
      ['Ekspor & cadangan', 'JSON CSV HTML PDF berkas'],
      ['Ringkasan bulanan', 'arus kas laporan'],
      ['Log aktivitas', 'transaksi transfer impor'],
      ['Profil Personalisasi Asisten', 'ekspor impor pola'],
      ['Analisa', 'pola keuangan'],
      ['Pengingat', 'lokal lupa'],
      ['Pemasukan berkala', 'rutin harian mingguan bulanan'],
      ['Kunci aplikasi', 'PIN keamanan'],
      ['Bantuan perbaikan', 'error laporan'],
      ['Monitoring Agent', 'riwayat run tool eksekusi autonomy'],
      ['Pusat privasi', 'data enkripsi izin'],
      ['Struktur database', 'tabel database'],
    ];
    final query = _searchQuery.trim().toLowerCase();
    return menuItems.any((item) => '${item[0]} ${item[1]}'.contains(query));
  }

  bool _matches(String title, String subtitle) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return true;
    return '$title $subtitle'.toLowerCase().contains(query);
  }

  @override
  Widget build(BuildContext context) {
    return FfmAssistantPageContext(
      destination: FfmAssistantDestination.otherMenu,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Lainnya'),
          actions: [
            IconButton(
              tooltip: 'Info Lainnya',
              onPressed: () => showAppInfoDialog(
                context,
                title: 'Tentang menu Lainnya',
                message: 'Data Utama membantu menyiapkan pilihan transaksi. Menu lain dipakai untuk mengelola aset, target, laporan, keamanan, dan alat offline.',
              ),
              icon: const Icon(Icons.info_outline),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
          children: [
            TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                labelText: 'Cari menu Lainnya',
                hintText: 'Contoh: laporan, pengingat, Gemini',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Hapus pencarian',
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                        icon: const Icon(Icons.clear),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            const AppSectionHeader(title: 'Mulai dari sini'),
            const SizedBox(height: 8),
            if (_matches(
              'Data Utama',
              'Isi kategori, toko, tag, rekening, dan sumber pemasukan untuk pilihan transaksi.',
            ))
              AppCard(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    child: const Icon(Icons.tune_outlined),
                  ),
                  title: const Text(
                    'Data Utama',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: const Text(
                    'Isi kategori, toko, tag, rekening, dan sumber pemasukan untuk pilihan transaksi.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(context, const MasterDataPage()),
                ),
              ),
            const SizedBox(height: 20),
            _MenuCard(
              icon: Icons.cloud_queue_outlined,
              title: 'Gemini Cloud & Memori',
              subtitle: 'Simpan dan uji model Gemini untuk chatbot, serta sambungkan memori Supabase.',
              onTap: () => _open(context, const SupabaseSetupPage()),
              visible: _matches(
                'Gemini Cloud Memori simpan uji model chatbot Supabase',
                'Simpan dan uji model Gemini untuk chatbot, serta sambungkan memori Supabase.',
              ),
            ),
            const AppSectionHeader(title: 'Data keluarga'),
            const SizedBox(height: 8),
            _MenuCard(
              icon: Icons.inventory_2_outlined,
              title: 'Aset keluarga',
              subtitle:
                  'Catat barang atau kekayaan keluarga yang ingin dipantau.',
              onTap: () => _open(context, const AssetListPage()),
              visible: _matches(
                'Aset keluarga',
                'Catat barang atau kekayaan keluarga yang ingin dipantau.',
              ),
            ),
            _MenuCard(
              icon: Icons.flag_outlined,
              title: 'Target keuangan',
              subtitle: 'Pantau uang yang ingin dikumpulkan sampai batas waktu tertentu.',
              onTap: () => _open(context, const GoalListPage()),
              visible: _matches(
                'Target keuangan',
                'Pantau uang yang ingin dikumpulkan sampai batas waktu tertentu.',
              ),
            ),
            _MenuCard(
              icon: Icons.account_balance_outlined,
              title: 'Hutang & piutang',
              subtitle: 'Kelola kewajiban dan uang yang masih perlu diterima keluarga.',
              onTap: () => _open(context, const LiabilityReceivablePage()),
              visible: _matches(
                'Hutang & piutang',
                'Kelola kewajiban dan uang yang masih perlu diterima keluarga.',
              ),
            ),
            const SizedBox(height: 20),
            const AppSectionHeader(title: 'Laporan dan cadangan'),
            const SizedBox(height: 8),
            _MenuCard(
              icon: Icons.ios_share_outlined,
              title: 'Ekspor & cadangan',
              subtitle:
                  'Buat JSON, CSV, HTML, PDF, atau pulihkan data dari berkas.',
              onTap: () => _open(context, const BackupPage()),
              visible: _matches(
                'Ekspor & cadangan',
                'Buat JSON, CSV, HTML, PDF, atau pulihkan data dari berkas.',
              ),
            ),
            _MenuCard(
              icon: Icons.summarize_outlined,
              title: 'Ringkasan bulanan',
              subtitle: 'Bandingkan arus kas, kesehatan keuangan, dan laporan per bulan.',
              onTap: () => _open(context, const MonthlyReportPage()),
              visible: _matches(
                'Ringkasan bulanan',
                'Bandingkan arus kas, kesehatan keuangan, dan laporan per bulan.',
              ),
            ),
            _MenuCard(
              icon: Icons.history,
              title: 'Log aktivitas',
              subtitle: 'Lihat jejak perubahan transaksi, transfer, impor, dan rekonsiliasi.',
              onTap: () => _open(context, const ActivityLogPage()),
              visible: _matches(
                'Log aktivitas',
                'Lihat jejak perubahan transaksi, transfer, impor, dan rekonsiliasi.',
              ),
            ),
            const SizedBox(height: 20),
            const AppSectionHeader(title: 'Pengingat dan alat'),
            const SizedBox(height: 8),
            _MenuCard(
              icon: Icons.badge_outlined,
              title: 'Profil Personalisasi Asisten',
              subtitle: 'Ekspor atau impor preferensi dan pola belajar terkontrol secara terenkripsi.',
              onTap: () => _open(context, const AssistantProfilePage()),
              visible: _matches(
                'Profil Personalisasi Asisten',
                'Ekspor atau impor preferensi dan pola belajar terkontrol secara terenkripsi.',
              ),
            ),

            _MenuCard(
              icon: Icons.mark_email_unread_outlined,
              title: 'Laporan & Kotak Masuk Asisten',
              subtitle: 'Tinjau rekomendasi proaktif, deteksi runway, rebalance anggaran, dan anomali belanja.',
              onTap: () => _open(context, const AgentInboxPage()),
              visible: _matches(
                'Laporan Kotak Masuk Asisten insight rekomendasi saran runway rebalance',
                'Tinjau rekomendasi proaktif, deteksi runway, rebalance anggaran, dan anomali belanja.',
              ),
            ),
            _MenuCard(
              icon: Icons.monitor_heart_outlined,
              title: 'Monitoring Agent',
              subtitle: 'Periksa riwayat run dan eksekusi tool Agent secara read-only.',
              onTap: () =>
                  _open(context, const FfmAssistantAutonomyMonitorPage()),
              visible: _matches(
                'Monitoring Agent riwayat run tool eksekusi autonomy',
                'Periksa riwayat run dan eksekusi tool Agent secara read-only.',
              ),
            ),
            _MenuCard(
              icon: Icons.insights_outlined,
              title: 'Analisa',
              subtitle:
                  'Baca pola keuangan dan saran dari data yang tersimpan.',
              onTap: () => _open(context, const AnalysisPage()),
              visible: _matches(
                'Analisa',
                'Baca pola keuangan dan saran dari data yang tersimpan.',
              ),
            ),
            _MenuCard(
              icon: Icons.notifications_none_outlined,
              title: 'Pengingat',
              subtitle:
                  'Buat pengingat lokal untuk hal yang tidak boleh kelupaan.',
              onTap: () => _open(context, const ReminderPage()),
              visible: _matches(
                'Pengingat',
                'Buat pengingat lokal untuk hal yang tidak boleh kelupaan.',
              ),
            ),
            _MenuCard(
              icon: Icons.nights_stay_outlined,
              title: 'Kalender Hijriah & Hilal',
              subtitle: 'Atur koreksi Hilal (-2/+2 hari) dan penetapan awal bulan Hijriah.',
              onTap: () => _open(context, const HijriSettingsPage()),
              visible: _matches(
                'Kalender Hijriah Hilal rukyat isbat puasa ramadan',
                'Atur koreksi Hilal (-2/+2 hari) dan penetapan awal bulan Hijriah.',
              ),
            ),
            _MenuCard(
              icon: Icons.event_repeat_outlined,
              title: 'Pemasukan berkala',
              subtitle: 'Atur bunga atau pemasukan rutin harian, mingguan, dan bulanan.',
              onTap: () => _open(context, const RecurringTransactionPage()),
              visible: _matches(
                'Pemasukan berkala',
                'Atur bunga atau pemasukan rutin harian, mingguan, dan bulanan.',
              ),
            ),

            if (_searchQuery.trim().isNotEmpty && !_hasMatchingMenu())
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Center(child: Text('Menu tidak ditemukan.')),
              ),
            const SizedBox(height: 20),
            const AppSectionHeader(title: 'Keamanan dan informasi'),
            const SizedBox(height: 8),
            _MenuCard(
              icon: Icons.lock_outline,
              title: 'Kunci aplikasi',
              subtitle:
                  'Atur PIN untuk membantu menjaga akses ke data keluarga.',
              onTap: () => _open(context, const PinSecurityPage()),
              visible: _matches(
                'Kunci aplikasi',
                'Atur PIN untuk membantu menjaga akses ke data keluarga.',
              ),
            ),
            _MenuCard(
              icon: Icons.bug_report_outlined,
              title: 'Bantuan perbaikan',
              subtitle: 'Lihat error yang benar-benar tercatat dan salin laporan aman untuk perbaikan APK.',
              onTap: () => _open(context, const AppDiagnosticsPage()),
              visible: _matches(
                'Bantuan perbaikan',
                'Lihat error yang benar-benar tercatat dan salin laporan aman untuk perbaikan APK.',
              ),
            ),
            _MenuCard(
              icon: Icons.privacy_tip_outlined,
              title: 'Pusat privasi',
              subtitle: 'Lihat lokasi data, enkripsi, izin perangkat, dan kendali ekspor.',
              onTap: () => _open(context, const PrivacyCenterPage()),
              visible: _matches(
                'Pusat privasi',
                'Lihat lokasi data, enkripsi, izin perangkat, dan kendali ekspor.',
              ),
            ),
            _MenuCard(
              icon: Icons.storage_outlined,
              title: 'Struktur database',
              subtitle: 'Lihat tabel dan gambaran isi database lokal FFM.',
              onTap: () => _open(context, const DatabaseStructurePage()),
              visible: _matches(
                'Struktur database',
                'Lihat tabel dan gambaran isi database lokal FFM.',
              ),
            ),

          ],
        ),
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.visible = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: ListTile(
          minVerticalPadding: 14,
          leading: CircleAvatar(
            backgroundColor: scheme.secondaryContainer,
            foregroundColor: scheme.onSecondaryContainer,
            child: Icon(icon),
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      ),
    );
  }
}
