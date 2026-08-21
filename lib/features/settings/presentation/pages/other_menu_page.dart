import 'package:flutter/material.dart';

import '../../../../shared/widgets/app_components.dart';
import '../../../activity/presentation/pages/activity_page.dart';
import '../../../asset/presentation/pages/asset_pages.dart';
import '../../../backup/presentation/pages/backup_page.dart';
import '../../../backup/presentation/pages/monthly_report_page.dart';
import '../../../goal/presentation/pages/goal_pages.dart';
import '../../../liability/presentation/pages/liability_pages.dart';
import '../../../reminder/presentation/pages/reminder_page.dart';
import 'database_structure_page.dart';
import '../../../audit/presentation/pages/activity_log_page.dart';
import 'master_data_page.dart';
import 'offline_advanced_page.dart';
import '../../../recurring_transaction/presentation/pages/recurring_transaction_page.dart';
import 'offline_features_page.dart';
import 'pin_security_page.dart';
import 'privacy_center_page.dart';

class OtherMenuPage extends StatelessWidget {
  const OtherMenuPage({super.key});

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
          const AppSectionHeader(title: 'Mulai dari sini'),
          const SizedBox(height: 8),
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
          const AppSectionHeader(title: 'Data keluarga'),
          const SizedBox(height: 8),
          _MenuCard(
            icon: Icons.inventory_2_outlined,
            title: 'Aset keluarga',
            subtitle:
                'Catat barang atau kekayaan keluarga yang ingin dipantau.',
            onTap: () => _open(context, const AssetListPage()),
          ),
          _MenuCard(
            icon: Icons.flag_outlined,
            title: 'Target keuangan',
            subtitle: 'Pantau uang yang ingin dikumpulkan sampai batas waktu tertentu.',
            onTap: () => _open(context, const GoalListPage()),
          ),
          _MenuCard(
            icon: Icons.account_balance_outlined,
            title: 'Hutang & piutang',
            subtitle:
                'Kelola kewajiban dan uang yang masih perlu diterima keluarga.',
            onTap: () => _open(context, const LiabilityReceivablePage()),
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
          ),
          _MenuCard(
            icon: Icons.summarize_outlined,
            title: 'Ringkasan bulanan',
            subtitle: 'Bandingkan arus kas, kesehatan keuangan, dan laporan per bulan.',
            onTap: () => _open(context, const MonthlyReportPage()),
          ),
          _MenuCard(
            icon: Icons.history,
            title: 'Log aktivitas',
            subtitle: 'Lihat jejak perubahan transaksi, transfer, impor, dan rekonsiliasi.',
            onTap: () => _open(context, const ActivityLogPage()),
          ),
          const SizedBox(height: 20),
          const AppSectionHeader(title: 'Pengingat dan alat'),
          const SizedBox(height: 8),
          _MenuCard(
            icon: Icons.timeline_outlined,
            title: 'Aktivitas & jurnal',
            subtitle: 'Lacak perjalanan, pekerjaan, pertemuan, obrolan, dan catatan harian keluarga.',
            onTap: () => _open(context, const ActivityPage()),
          ),
          _MenuCard(
            icon: Icons.notifications_none_outlined,
            title: 'Pengingat',
            subtitle:
                'Buat pengingat lokal untuk hal yang tidak boleh kelupaan.',
            onTap: () => _open(context, const ReminderPage()),
          ),
          _MenuCard(
            icon: Icons.event_repeat_outlined,
            title: 'Pemasukan berkala',
            subtitle: 'Atur bunga atau pemasukan rutin harian, mingguan, dan bulanan.',
            onTap: () => _open(context, const RecurringTransactionPage()),
          ),
          _MenuCard(
            icon: Icons.offline_bolt_outlined,
            title: 'Alat offline lanjutan',
            subtitle: 'Cek saldo, rekonsiliasi saldo, impor data, dan pemeriksaan lokal di perangkat.',
            onTap: () => _open(context, const OfflineAdvancedPage()),
          ),
          const SizedBox(height: 20),
          const AppSectionHeader(title: 'Keamanan dan informasi'),
          const SizedBox(height: 8),
          _MenuCard(
            icon: Icons.lock_outline,
            title: 'Kunci aplikasi',
            subtitle: 'Atur PIN untuk membantu menjaga akses ke data keluarga.',
            onTap: () => _open(context, const PinSecurityPage()),
          ),
          _MenuCard(
            icon: Icons.privacy_tip_outlined,
            title: 'Pusat privasi',
            subtitle: 'Lihat lokasi data, enkripsi, izin perangkat, dan kendali ekspor.',
            onTap: () => _open(context, const PrivacyCenterPage()),
          ),
          _MenuCard(
            icon: Icons.storage_outlined,
            title: 'Struktur database',
            subtitle: 'Lihat tabel dan gambaran isi database lokal FFM.',
            onTap: () => _open(context, const DatabaseStructurePage()),
          ),
          _MenuCard(
            icon: Icons.wifi_off_outlined,
            title: 'Fitur tanpa internet',
            subtitle:
                'Baca panduan lengkap tentang teknologi offline yang tersedia.',
            onTap: () => _open(context, const OfflineFeaturesPage()),
          ),
        ],
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
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
