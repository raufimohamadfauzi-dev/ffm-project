import 'package:flutter/material.dart';

import '../../../../shared/widgets/app_components.dart';
import '../../../audit/presentation/pages/activity_log_page.dart';
import '../../../assistant/domain/ffm_assistant_models.dart';
import '../../../assistant/presentation/pages/assistant_profile_page.dart';
import '../../../assistant/presentation/pages/agent_inbox_page.dart';
import '../../../assistant/presentation/pages/ffm_assistant_autonomy_monitor_page.dart';
import '../../../assistant/presentation/pages/telegram_setup_page.dart';
import '../../../assistant/presentation/pages/payment_detector_settings_page.dart';

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
import 'family_profile_page.dart';
import '../../../advisor/presentation/pages/analysis_page.dart';
import 'master_data_page.dart';
import 'utility_meter_page.dart';

import '../../../recurring_transaction/presentation/pages/recurring_transaction_page.dart';

import 'pin_security_page.dart';
import 'privacy_center_page.dart';
import 'supabase_setup_page.dart';
import 'calendar_settings_page.dart';
import '../../../assistant/presentation/widgets/nfc_scan_dialog.dart';
import '../../../assistant/presentation/widgets/nfc_smart_tag_writer_dialog.dart';

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
      ['Profil Keluarga', 'nama rumah tangga suami istri pribadi keluarga'],
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
      ['Kalender & Smartwatch', 'Google Calendar jam tangan pintar sinkronisasi tagihan'],
      ['Pemindai NFC e-Money', 'kartu tol flazz brizzi tap saldo selisih'],
      ['Program Tag Pintar NFC', 'stiker koin tombol bensin mobil dapur shortcut nfc ntag'],
      ['Kunci aplikasi', 'PIN keamanan'],
      ['Bantuan perbaikan', 'error laporan'],
      ['Monitoring Agent', 'riwayat run tool eksekusi autonomy'],
      ['Pusat privasi', 'data enkripsi izin'],
      ['Struktur database', 'tabel database'],
      ['Buku Saku Meteran & Token', 'meteran listrik pln idpel token sawah ladang pompa rumah'],
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
                color: const Color(0xFFD1FAE5).withValues(alpha: .5),
                border: BorderSide(color: const Color(0xFF059669).withValues(alpha: .4), width: 1.5),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: const Color(0xFF059669),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.tune_rounded, color: Colors.white, size: 24),
                  ),
                  title: Row(
                    children: const [
                      Expanded(
                        child: Text(
                          'Data Utama',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                      ),
                      AppStatusChip(
                        label: 'WAJIB AWAL',
                        color: Color(0xFF059669),
                        backgroundColor: Color(0xFFD1FAE5),
                      ),
                    ],
                  ),
                  subtitle: const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'Isi kategori, toko, tag, rekening, dan sumber pemasukan untuk pilihan transaksi.',
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(context, const MasterDataPage()),
                ),
              ),
            const SizedBox(height: 12),
            _MenuCard(
              icon: Icons.cloud_queue_rounded,
              title: 'Gemini Cloud & Memori',
              subtitle: 'Simpan dan uji model Gemini untuk chatbot, serta sambungkan memori Supabase.',
              iconColor: const Color(0xFF0284C7),
              iconBackgroundColor: const Color(0xFFE0F2FE),
              badgeText: 'AI CLOUD',
              onTap: () => _open(context, const SupabaseSetupPage()),
              visible: _matches(
                'Gemini Cloud Memori simpan uji model chatbot Supabase',
                'Simpan dan uji model Gemini untuk chatbot, serta sambungkan memori Supabase.',
              ),
            ),
            const SizedBox(height: 16),
            const AppSectionHeader(title: 'Data keluarga'),
            const SizedBox(height: 8),
            _MenuCard(
              icon: Icons.family_restroom_rounded,
              title: 'Profil Keluarga',
              subtitle:
                  'Isi nama rumah tangga, pasangan, dan data pribadi untuk Asisten.',
              iconColor: const Color(0xFFDB2777),
              iconBackgroundColor: const Color(0xFFFCE7F3),
              badgeText: 'PROFIL',
              onTap: () => _open(context, const FamilyProfilePage()),
              visible: _matches(
                'Profil Keluarga',
                'Isi nama rumah tangga, pasangan, dan data pribadi untuk Asisten.',
              ),
            ),
            _MenuCard(
              icon: Icons.inventory_2_rounded,
              title: 'Aset keluarga',
              subtitle:
                  'Catat barang atau kekayaan keluarga yang ingin dipantau.',
              iconColor: const Color(0xFF4F46E5),
              iconBackgroundColor: const Color(0xFFEEF2FF),
              badgeText: 'HARTA',
              onTap: () => _open(context, const AssetListPage()),
              visible: _matches(
                'Aset keluarga',
                'Catat barang atau kekayaan keluarga yang ingin dipantau.',
              ),
            ),
            _MenuCard(
              icon: Icons.flag_rounded,
              title: 'Target keuangan',
              subtitle: 'Pantau uang yang ingin dikumpulkan sampai batas waktu tertentu.',
              iconColor: const Color(0xFF0D9488),
              iconBackgroundColor: const Color(0xFFCCFBF1),
              badgeText: 'GOALS',
              onTap: () => _open(context, const GoalListPage()),
              visible: _matches(
                'Target keuangan',
                'Pantau uang yang ingin dikumpulkan sampai batas waktu tertentu.',
              ),
            ),
            _MenuCard(
              icon: Icons.account_balance_rounded,
              title: 'Hutang & piutang',
              subtitle: 'Kelola kewajiban dan uang yang masih perlu diterima keluarga.',
              iconColor: const Color(0xFFEA580C),
              iconBackgroundColor: const Color(0xFFFFEDD5),
              badgeText: 'KEWAJIBAN',
              onTap: () => _open(context, const LiabilityReceivablePage()),
              visible: _matches(
                'Hutang & piutang',
                'Kelola kewajiban dan uang yang masih perlu diterima keluarga.',
              ),
            ),
            const SizedBox(height: 16),
            const AppSectionHeader(title: 'Laporan dan cadangan'),
            const SizedBox(height: 8),
            _MenuCard(
              icon: Icons.ios_share_rounded,
              title: 'Ekspor & cadangan',
              subtitle:
                  'Buat JSON, CSV, HTML, PDF, atau pulihkan data dari berkas.',
              iconColor: const Color(0xFF7C3AED),
              iconBackgroundColor: const Color(0xFFF3E8FF),
              badgeText: 'BACKUP',
              onTap: () => _open(context, const BackupPage()),
              visible: _matches(
                'Ekspor & cadangan',
                'Buat JSON, CSV, HTML, PDF, atau pulihkan data dari berkas.',
              ),
            ),
            _MenuCard(
              icon: Icons.summarize_rounded,
              title: 'Ringkasan bulanan',
              subtitle: 'Bandingkan arus kas, kesehatan keuangan, dan laporan per bulan.',
              iconColor: const Color(0xFF2563EB),
              iconBackgroundColor: const Color(0xFFDBEAFE),
              badgeText: 'LAPORAN',
              onTap: () => _open(context, const MonthlyReportPage()),
              visible: _matches(
                'Ringkasan bulanan',
                'Bandingkan arus kas, kesehatan keuangan, dan laporan per bulan.',
              ),
            ),
            _MenuCard(
              icon: Icons.history_rounded,
              title: 'Log aktivitas',
              subtitle: 'Lihat jejak perubahan transaksi, transfer, impor, dan rekonsiliasi.',
              iconColor: const Color(0xFF475569),
              iconBackgroundColor: const Color(0xFFF1F5F9),
              badgeText: 'AUDIT',
              onTap: () => _open(context, const ActivityLogPage()),
              visible: _matches(
                'Log aktivitas',
                'Lihat jejak perubahan transaksi, transfer, impor, dan rekonsiliasi.',
              ),
            ),
            const SizedBox(height: 16),
            const AppSectionHeader(title: 'Pengingat dan alat'),
            const SizedBox(height: 8),
            _MenuCard(
              icon: Icons.badge_rounded,
              title: 'Profil Personalisasi Asisten',
              subtitle: 'Ekspor atau impor preferensi dan pola belajar terkontrol secara terenkripsi.',
              iconColor: const Color(0xFFC026D3),
              iconBackgroundColor: const Color(0xFFFAE8FF),
              badgeText: 'MEMORI AI',
              onTap: () => _open(context, const AssistantProfilePage()),
              visible: _matches(
                'Profil Personalisasi Asisten',
                'Ekspor atau impor preferensi dan pola belajar terkontrol secara terenkripsi.',
              ),
            ),
            _MenuCard(
              icon: Icons.mark_email_unread_rounded,
              title: 'Laporan & Kotak Masuk Asisten',
              subtitle: 'Tinjau rekomendasi proaktif, deteksi runway, rebalance anggaran, dan anomali belanja.',
              iconColor: const Color(0xFFD97706),
              iconBackgroundColor: const Color(0xFFFEF3C7),
              badgeText: 'PROAKTIF',
              onTap: () => _open(context, const AgentInboxPage()),
              visible: _matches(
                'Laporan Kotak Masuk Asisten insight rekomendasi saran runway rebalance',
                'Tinjau rekomendasi proaktif, deteksi runway, rebalance anggaran, dan anomali belanja.',
              ),
            ),
            _MenuCard(
              icon: Icons.monitor_heart_rounded,
              title: 'Monitoring Agent',
              subtitle: 'Periksa riwayat run dan eksekusi tool Agent secara read-only.',
              iconColor: const Color(0xFFE11D48),
              iconBackgroundColor: const Color(0xFFFFE4E6),
              badgeText: 'AUTONOMY',
              onTap: () =>
                  _open(context, const FfmAssistantAutonomyMonitorPage()),
              visible: _matches(
                'Monitoring Agent riwayat run tool eksekusi autonomy',
                'Periksa riwayat run dan eksekusi tool Agent secara read-only.',
              ),
            ),
            _MenuCard(
              icon: Icons.send_rounded,
              title: 'Telegram Bot Keluarga',
              subtitle: 'Kirim laporan mingguan otomatis & alarm radar boncos ke chat/grup keluarga.',
              iconColor: const Color(0xFF0284C7),
              iconBackgroundColor: const Color(0xFFE0F2FE),
              badgeText: 'BOT KELUARGA',
              onTap: () => _open(context, const TelegramSetupPage()),
              visible: _matches(
                'Telegram Bot Keluarga notifikasi laporan alarm boncos grup suami istri',
                'Kirim laporan mingguan otomatis & alarm radar boncos ke chat/grup keluarga.',
              ),
            ),
            _MenuCard(
              icon: Icons.qr_code_scanner,
              title: 'Pendeteksi Bayar Otomatis',
              subtitle: 'Tangkap otomatis transaksi QRIS & bank dari notifikasi HP. 100% lokal, tanpa cloud.',
              iconColor: const Color(0xFF7C3AED),
              iconBackgroundColor: const Color(0xFFEDE9FE),
              badgeText: 'QRIS & BANK',
              onTap: () => _open(context, const PaymentDetectorSettingsPage()),
              visible: _matches(
                'Pendeteksi Bayar Otomatis QRIS bank notifikasi transaksi auto detect',
                'Tangkap otomatis transaksi QRIS & bank dari notifikasi HP. 100% lokal, tanpa cloud.',
              ),
            ),
            _MenuCard(
              icon: Icons.electric_bolt_rounded,
              title: 'Buku Saku Meteran & Token',
              subtitle: 'Simpan nomor IDPEL/meteran PLN, salin nomor meter dan 20-digit token dengan 1-ketukan.',
              iconColor: const Color(0xFFD97706),
              iconBackgroundColor: const Color(0xFFFEF3C7),
              badgeText: 'UTILITAS',
              onTap: () => _open(context, const UtilityMeterPage()),
              visible: _matches(
                'Buku Saku Meteran Token listrik pln idpel pulsa rumah ladang sawah ruko',
                'Simpan nomor IDPEL/meteran PLN, salin nomor meter dan 20-digit token dengan 1-ketukan.',
              ),
            ),
            _MenuCard(
              icon: Icons.auto_graph_rounded,
              title: 'Analisa',
              subtitle:
                  'Baca pola keuangan dan saran dari data yang tersimpan.',
              iconColor: const Color(0xFF059669),
              iconBackgroundColor: const Color(0xFFD1FAE5),
              badgeText: 'INSIGHT',
              onTap: () => _open(context, const AnalysisPage()),
              visible: _matches(
                'Analisa',
                'Baca pola keuangan dan saran dari data yang tersimpan.',
              ),
            ),
            _MenuCard(
              icon: Icons.notifications_active_rounded,
              title: 'Pengingat',
              subtitle:
                  'Buat pengingat lokal untuk hal yang tidak boleh kelupaan.',
              iconColor: const Color(0xFFCA8A04),
              iconBackgroundColor: const Color(0xFFFEF9C3),
              badgeText: 'ALARM',
              onTap: () => _open(context, const ReminderPage()),
              visible: _matches(
                'Pengingat',
                'Buat pengingat lokal untuk hal yang tidak boleh kelupaan.',
              ),
            ),
            _MenuCard(
              icon: Icons.nights_stay_rounded,
              title: 'Kalender Hijriah & Hilal',
              subtitle: 'Atur koreksi Hilal (-2/+2 hari) dan penetapan awal bulan Hijriah.',
              iconColor: const Color(0xFF16A34A),
              iconBackgroundColor: const Color(0xFFDCFCE7),
              badgeText: 'HIJRIAH',
              onTap: () => _open(context, const HijriSettingsPage()),
              visible: _matches(
                'Kalender Hijriah Hilal rukyat isbat puasa ramadan',
                'Atur koreksi Hilal (-2/+2 hari) dan penetapan awal bulan Hijriah.',
              ),
            ),
            _MenuCard(
              icon: Icons.event_repeat_rounded,
              title: 'Pemasukan berkala',
              subtitle: 'Atur bunga atau pemasukan rutin harian, mingguan, dan bulanan.',
              iconColor: const Color(0xFF0891B2),
              iconBackgroundColor: const Color(0xFFCFFAFE),
              badgeText: 'RUTIN',
              onTap: () => _open(context, const RecurringTransactionPage()),
              visible: _matches(
                'Pemasukan berkala',
                'Atur bunga atau pemasukan rutin harian, mingguan, dan bulanan.',
              ),
            ),
            _MenuCard(
              icon: Icons.calendar_month_rounded,
              title: 'Kalender & Smartwatch',
              subtitle: 'Sinkronisasi tagihan & jatuh tempo ke Google Calendar dan jam tangan pintar.',
              iconColor: const Color(0xFF0284C7),
              iconBackgroundColor: const Color(0xFFE0F2FE),
              badgeText: 'SINKRON',
              onTap: () => _open(context, const CalendarSettingsPage()),
              visible: _matches(
                'Kalender Smartwatch Google Calendar sinkronisasi jadwal tagihan jatuh tempo',
                'Sinkronisasi tagihan & jatuh tempo ke Google Calendar dan jam tangan pintar.',
              ),
            ),
            _MenuCard(
              icon: Icons.nfc_rounded,
              title: 'Pemindai Kartu NFC e-Money',
              subtitle: 'Pindai kartu tol/e-Money langsung untuk cek saldo dan hitung selisih mutasi otomatis.',
              iconColor: const Color(0xFF059669),
              iconBackgroundColor: const Color(0xFFD1FAE5),
              badgeText: 'NFC',
              onTap: () => NfcScanDialog.show(context),
              visible: _matches(
                'Pemindai Kartu NFC e-Money cek saldo kartu tol mutasi otomatis tap flazz brizzi',
                'Pindai kartu tol/e-Money langsung untuk cek saldo dan hitung selisih mutasi otomatis.',
              ),
            ),
            _MenuCard(
              icon: Icons.tag_rounded,
              title: 'Program Tag Pintar NFC',
              subtitle: 'Program stiker koin NFC untuk tombol instan bensin, dapur, atau asisten suara.',
              iconColor: const Color(0xFF0284C7),
              iconBackgroundColor: const Color(0xFFE0F2FE),
              badgeText: 'SMART TAG',
              onTap: () => NfcSmartTagWriterDialog.show(context),
              visible: _matches(
                'Program Tag Pintar NFC stiker koin tombol bensin mobil dapur shortcut ntag',
                'Program stiker koin NFC untuk tombol instan bensin, dapur, atau asisten suara.',
              ),
            ),

            if (_searchQuery.trim().isNotEmpty && !_hasMatchingMenu())
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Center(child: Text('Menu tidak ditemukan.')),
              ),
            const SizedBox(height: 16),
            const AppSectionHeader(title: 'Keamanan dan informasi'),
            const SizedBox(height: 8),
            _MenuCard(
              icon: Icons.lock_rounded,
              title: 'Kunci aplikasi',
              subtitle:
                  'Atur PIN untuk membantu menjaga akses ke data keluarga.',
              iconColor: const Color(0xFFDC2626),
              iconBackgroundColor: const Color(0xFFFEE2E2),
              badgeText: 'PIN',
              onTap: () => _open(context, const PinSecurityPage()),
              visible: _matches(
                'Kunci aplikasi',
                'Atur PIN untuk membantu menjaga akses ke data keluarga.',
              ),
            ),
            _MenuCard(
              icon: Icons.bug_report_rounded,
              title: 'Bantuan perbaikan',
              subtitle: 'Lihat error yang benar-benar tercatat dan salin laporan aman untuk perbaikan APK.',
              iconColor: const Color(0xFFC2410C),
              iconBackgroundColor: const Color(0xFFFFEDD5),
              badgeText: 'DIAGNOSTIK',
              onTap: () => _open(context, const AppDiagnosticsPage()),
              visible: _matches(
                'Bantuan perbaikan',
                'Lihat error yang benar-benar tercatat dan salin laporan aman untuk perbaikan APK.',
              ),
            ),
            _MenuCard(
              icon: Icons.privacy_tip_rounded,
              title: 'Pusat privasi',
              subtitle: 'Lihat lokasi data, enkripsi, izin perangkat, dan kendali ekspor.',
              iconColor: const Color(0xFF4338CA),
              iconBackgroundColor: const Color(0xFFE0E7FF),
              badgeText: 'PRIVASI',
              onTap: () => _open(context, const PrivacyCenterPage()),
              visible: _matches(
                'Pusat privasi',
                'Lihat lokasi data, enkripsi, izin perangkat, dan kendali ekspor.',
              ),
            ),
            _MenuCard(
              icon: Icons.storage_rounded,
              title: 'Struktur database',
              subtitle: 'Lihat tabel dan gambaran isi database lokal FFM.',
              iconColor: const Color(0xFF334155),
              iconBackgroundColor: const Color(0xFFE2E8F0),
              badgeText: 'SQL LOKAL',
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
    this.iconColor,
    this.iconBackgroundColor,
    this.badgeText,
    this.visible = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? iconColor;
  final Color? iconBackgroundColor;
  final String? badgeText;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final fgColor = iconColor ?? scheme.primary;
    final bgColor = iconBackgroundColor ?? fgColor.withValues(alpha: .14);
    final badgeColor = scheme.primary;
    final badgeBackgroundColor = scheme.primaryContainer;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: ListTile(
          minVerticalPadding: 14,
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: fgColor, size: 22),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (badgeText != null) ...[
                const SizedBox(width: 8),
                AppStatusChip(
                  label: badgeText!,
                  color: badgeColor,
                  backgroundColor: badgeBackgroundColor,
                ),
              ],
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              subtitle,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 13,
                height: 1.3,
              ),
            ),
          ),
          trailing: const Icon(Icons.chevron_right, size: 20),
          onTap: onTap,
        ),
      ),
    );
  }
}
