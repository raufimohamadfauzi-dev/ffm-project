import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/app_context.dart';
import '../../../../core/di/injection.dart';
import '../../data/telegram_bot_service.dart';
import '../../data/telegram_config_repository.dart';
import '../../domain/autonomous_evaluation_coordinator.dart';
import '../../domain/ffm_assistant_models.dart';
import '../widgets/ffm_assistant_page_context.dart';

/// Halaman pengaturan integrasi Telegram Bot untuk asisten keuangan keluarga.
class TelegramSetupPage extends StatefulWidget {
  const TelegramSetupPage({super.key, this.repository, this.botService});

  final TelegramConfigRepository? repository;
  final TelegramBotService? botService;

  @override
  State<TelegramSetupPage> createState() => _TelegramSetupPageState();
}

class _TelegramSetupPageState extends State<TelegramSetupPage> {
  final _formKey = GlobalKey<FormState>();
  final _tokenController = TextEditingController();
  final _chatIdController = TextEditingController();

  late final TelegramConfigRepository _repository;
  late final TelegramBotService _botService;

  bool _obscureToken = true;
  bool _isLoading = true;
  bool _isTesting = false;
  bool _isSaving = false;
  bool _isSendingReportNow = false;

  bool _isEnabled = false;
  bool _weeklyReportEnabled = true;
  bool _alertsEnabled = true;
  bool _notifyOnNewTransaction = false;
  int _notifyMinAmount = 50000;

  String? _familyName;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? getIt<TelegramConfigRepository>();
    _botService = widget.botService ?? getIt<TelegramBotService>();
    _loadData();
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _chatIdController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final config = await _repository.loadConfig();
      _tokenController.text = config.botToken;
      _chatIdController.text = config.chatId;
      _isEnabled = config.isEnabled;
      _weeklyReportEnabled = config.weeklyReportEnabled;
      _alertsEnabled = config.alertsEnabled;
      _notifyOnNewTransaction = config.notifyOnNewTransaction;
      _notifyMinAmount = config.notifyMinAmount;

      // Ambil nama keluarga untuk sambutan tes jika ada
      try {
        if (getIt.isRegistered<AppDatabase>()) {
          final db = getIt<AppDatabase>();
          final household = await (db.select(db.households)
                ..where((tbl) => tbl.id.equals(AppContext.householdId)))
              .getSingleOrNull();
          _familyName = household?.name;
        }
      } catch (_) {}
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _testConnection() async {
    final token = _tokenController.text.trim();
    final chatId = _chatIdController.text.trim();

    if (token.isEmpty || chatId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Isi Bot Token dan Chat ID terlebih dahulu untuk uji koneksi.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isTesting = true);
    try {
      final result = await _botService.testConnection(
        botToken: token,
        chatId: chatId,
        familyName: _familyName,
      );

      if (!mounted) return;

      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    result.message,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 4),
          ),
        );
      } else {
        _showErrorDialog('Uji Koneksi Gagal', result.message);
      }
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  Future<void> _sendWeeklyReportNow() async {
    final token = _tokenController.text.trim();
    final chatId = _chatIdController.text.trim();

    if (token.isEmpty || chatId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Simpan Bot Token dan Chat ID terlebih dahulu.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSendingReportNow = true);
    try {
      // Pastikan konfigurasi tersimpan terlebih dahulu
      await _saveSettings(silent: true);

      if (getIt.isRegistered<AutonomousEvaluationCoordinator>()) {
        final coordinator = getIt<AutonomousEvaluationCoordinator>();
        final success = await coordinator.checkAndSendWeeklyReport(
          householdId: AppContext.householdId,
          force: true,
        );

        if (!mounted) return;

        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Laporan keuangan pekan ini berhasil dikirim ke Telegram!',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.green.shade700,
              duration: const Duration(seconds: 4),
            ),
          );
        } else {
          _showErrorDialog(
            'Pengiriman Gagal',
            'Gagal mengirim laporan mingguan. Pastikan Bot Token dan Chat ID valid, bot sudah di-Start di Telegram, dan koneksi internet aktif.',
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isSendingReportNow = false);
    }
  }

  Future<void> _saveSettings({bool silent = false}) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final config = TelegramConfig(
        botToken: _tokenController.text.trim(),
        chatId: _chatIdController.text.trim(),
        isEnabled: _isEnabled,
        weeklyReportEnabled: _weeklyReportEnabled,
        alertsEnabled: _alertsEnabled,
        notifyOnNewTransaction: _notifyOnNewTransaction,
        notifyMinAmount: _notifyMinAmount,
      );

      await _repository.saveConfig(config);

      if (!mounted || silent) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pengaturan Telegram Bot berhasil disimpan.'),
          backgroundColor: Colors.teal,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showErrorDialog(String title, String message) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Mengerti'),
          ),
        ],
      ),
    );
  }

  Future<void> _openTelegramBotFather() async {
    final uri = Uri.parse('https://t.me/BotFather');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return FfmAssistantPageContext(
      destination: FfmAssistantDestination.telegramSetup,
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Telegram Bot Keluarga'),
        actions: [
          if (!_isLoading)
            IconButton(
              icon: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              tooltip: 'Simpan Pengaturan',
              onPressed: _isSaving ? null : _saveSettings,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  _buildHeaderCard(theme, isDark),
                  const SizedBox(height: 16),
                  _buildStatusSwitchCard(theme, isDark),
                  const SizedBox(height: 16),
                  _buildCredentialsCard(theme, isDark),
                  const SizedBox(height: 16),
                  _buildPreferencesCard(theme, isDark),
                  const SizedBox(height: 16),
                  _buildGuideCard(theme, isDark),
                ],
              ),
            ),
      ),
    );
  }

  Widget _buildHeaderCard(ThemeData theme, bool isDark) {
    return Card(
      elevation: 0,
      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE0F2FE),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFBAE6FD),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF0284C7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.send_rounded, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Asisten Keuangan di Telegram',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF0369A1),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Terima laporan mingguan otomatis dan alarm boncos langsung di chat pribadi atau grup Telegram keluarga (Suami & Istri).',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF075985),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusSwitchCard(ThemeData theme, bool isDark) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? const Color(0xFF333333) : const Color(0xFFE2E8F0),
        ),
      ),
      child: SwitchListTile.adaptive(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: const Text(
          'Aktifkan Integrasi Telegram',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          _isEnabled
              ? 'Asisten siap mengirimkan laporan dan alarm ke Telegram.'
              : 'Integrasi dinonaktifkan sementara.',
          style: const TextStyle(fontSize: 12),
        ),
        value: _isEnabled,
        onChanged: (val) => setState(() => _isEnabled = val),
      ),
    );
  }

  Widget _buildCredentialsCard(ThemeData theme, bool isDark) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? const Color(0xFF333333) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.vpn_key_outlined, size: 20, color: Color(0xFF0284C7)),
                const SizedBox(width: 8),
                Text(
                  'Kredensial Bot Telegram',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _tokenController,
              obscureText: _obscureToken,
              decoration: InputDecoration(
                labelText: 'Bot Token',
                hintText: '123456789:ABCdefGhIJKlmNoPQRstuVWXyz',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.token_outlined),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureToken
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () =>
                      setState(() => _obscureToken = !_obscureToken),
                ),
                helperText: 'Dapatkan token dari @BotFather di Telegram',
              ),
              validator: (val) {
                if (_isEnabled && (val == null || val.trim().isEmpty)) {
                  return 'Token bot wajib diisi jika integrasi aktif';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _chatIdController,
              decoration: const InputDecoration(
                labelText: 'Chat ID / ID Grup',
                hintText: '123456789 atau -100123456789',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.chat_bubble_outline),
                helperText:
                    'ID chat pribadi atau grup keluarga di Telegram',
              ),
              validator: (val) {
                if (_isEnabled && (val == null || val.trim().isEmpty)) {
                  return 'Chat ID wajib diisi jika integrasi aktif';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _isTesting ? null : _testConnection,
                    icon: _isTesting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_outlined, size: 18),
                    label: Text(
                      _isTesting ? 'Menguji...' : 'Uji Koneksi (Kirim Pesan Tes)',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreferencesCard(ThemeData theme, bool isDark) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? const Color(0xFF333333) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.tune_rounded, size: 20, color: Color(0xFF0284C7)),
                const SizedBox(width: 8),
                Text(
                  'Preferensi Pengiriman Pesan',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Laporan Mingguan Otomatis'),
              subtitle: const Text(
                'Kirim ringkasan pengeluaran dan kas keluarga setiap akhir pekan (otomatis susul kirim saat aplikasi dibuka).',
                style: TextStyle(fontSize: 12),
              ),
              value: _weeklyReportEnabled,
              onChanged: _isEnabled
                  ? (val) => setState(() => _weeklyReportEnabled = val)
                  : null,
            ),
            if (_isEnabled && _weeklyReportEnabled) ...[
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0284C7),
                    side: const BorderSide(color: Color(0xFF0284C7)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onPressed: _isSendingReportNow ? null : _sendWeeklyReportNow,
                  icon: _isSendingReportNow
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.assessment_outlined, size: 18),
                  label: Text(
                    _isSendingReportNow
                        ? 'Mengirim Laporan...'
                        : 'Kirim Ringkasan Pekan Ini Sekarang',
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            const Divider(height: 1),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Alarm Boncos & Peringatan Radar'),
              subtitle: const Text(
                'Kirim peringatan instan jika ada lonjakan pengeluaran atau anggaran amplop habis.',
                style: TextStyle(fontSize: 12),
              ),
              value: _alertsEnabled,
              onChanged: _isEnabled
                  ? (val) => setState(() => _alertsEnabled = val)
                  : null,
            ),
            const Divider(height: 1),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Notifikasi Transaksi Baru ke Grup'),
              subtitle: const Text(
                'Kirim ringkasan otomatis ke Telegram setiap kali ada transaksi baru dicatat (min. Rp 50.000).',
                style: TextStyle(fontSize: 12),
              ),
              value: _notifyOnNewTransaction,
              onChanged: _isEnabled
                  ? (val) => setState(() => _notifyOnNewTransaction = val)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGuideCard(ThemeData theme, bool isDark) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? const Color(0xFF333333) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          leading: const Icon(Icons.help_outline_rounded, color: Color(0xFF0284C7)),
          title: const Text(
            'Panduan Lengkap Membuat Bot & Grup Telegram',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            const Divider(height: 1),
            const SizedBox(height: 12),
            _guideStep(
              '1',
              'Buka Telegram dan cari akun resmi @BotFather (akun bertanda centang biru).',
            ),
            _guideStep(
              '2',
              'Ketik /newbot lalu ikuti petunjuk untuk memberi nama bot keluarga Anda (misal: KeuanganKeluargaKuBot).',
            ),
            _guideStep(
              '3',
              'BotFather akan memberikan HTTP API Token. Salin dan tempel ke kolom "Bot Token" di atas.',
            ),
            _guideStep(
              '4',
              'Buka bot yang baru Anda buat di Telegram, lalu tekan tombol "Start".',
            ),
            _guideStep(
              '5',
              'Menentukan Chat ID Penerima Pesan:\n'
              '• Chat Pribadi: Cari bot @userinfobot di Telegram, klik Start, lalu salin angka "Id" Anda (contoh: 123456789).\n'
              '• Grup Keluarga (Suami & Istri) [Disarankan]:\n'
              '   a. Buat grup di Telegram bersama pasangan Anda.\n'
              '   b. Masukkan bot Anda ke grup tersebut dan jadikan sebagai Admin.\n'
              '   c. Masukkan bot @userinfobot atau @RawDataBot ke grup. Bot akan menampilkan ID grup berawalan minus (contoh: -100192837465).\n'
              '   d. Salin angka minus tersebut ke kolom Chat ID di atas, lalu keluarkan @userinfobot dari grup.',
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.shield_outlined, size: 18, color: Color(0xFF0284C7)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Privasi Terjamin: Kredensial disimpan terenkripsi di HP Anda. Hanya chat ID yang Anda daftarkan yang berhak menerima laporan keuangan keluarga.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _openTelegramBotFather,
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Buka @BotFather di Telegram'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _guideStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 10,
            backgroundColor: const Color(0xFF0284C7),
            child: Text(
              number,
              style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, height: 1.35))),
        ],
      ),
    );
  }
}
