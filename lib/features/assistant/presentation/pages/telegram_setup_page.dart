import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/app_context.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/utils/string_sanitizer.dart';
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
  bool _loadFailed = false;

  bool _isEnabled = false;
  bool _weeklyReportEnabled = true;
  bool _alertsEnabled = true;
  bool _notifyOnNewTransaction = false;
  int _notifyMinAmount = 50000;

  TelegramOperationalStatus _operational = const TelegramOperationalStatus();
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
          final household =
              await (db.select(db.households)
                    ..where((tbl) => tbl.id.equals(AppContext.householdId)))
                  .getSingleOrNull();
          _familyName = household?.name;
        }
      } catch (_) {}

      // Muat status operasional terakhir (verifikasi & pengiriman)
      try {
        _operational = await _repository.loadOperationalStatus();
      } catch (_) {}

      _loadFailed = false;
    } catch (e) {
      _loadFailed = true;
      if (mounted) {
        _showErrorDialog(
          'Gagal Memuat Pengaturan',
          'Gagal membaca penyimpanan aman Telegram: $e',
        );
      }
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
          content: Text(
            'Isi Bot Token dan Chat ID terlebih dahulu untuk uji koneksi.',
          ),
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

      // Catat hasil verifikasi untuk ditampilkan sebagai status operasional.
      // Gagal mencatat tidak menghentikan alur utama.
      try {
        await _repository.recordVerificationResult(
          ok: result.success,
          at: DateTime.now(),
          botToken: token,
          chatId: chatId,
          message: result.message,
        );
      } catch (_) {}

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
      // Pastikan konfigurasi tersimpan terlebih dahulu; jika gagal simpan,
      // laporan tidak boleh dikirim dengan kredensial yang tidak tersimpan
      // sehingga status pengiriman palsu dapat tercipta.
      final saved = await _saveSettings(silent: true);
      if (!saved) {
        if (mounted) {
          _showErrorDialog(
            'Gagal Menyimpan',
            'Pengaturan harus tersimpan sebelum laporan dikirim. Simpan pengaturan secara manual lalu coba kembali.',
          );
        }
        return;
      }

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
      } else if (mounted) {
        _showErrorDialog(
          'Layanan Belum Tersedia',
          'Layanan pengiriman asisten belum aktif. Nyalakan ulang aplikasi lalu coba kembali.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSendingReportNow = false);
    }
  }

  Future<bool> _saveSettings({bool silent = false}) async {
    if (!_formKey.currentState!.validate()) return false;

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

      if (mounted && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pengaturan Telegram Bot berhasil disimpan.'),
            backgroundColor: Colors.teal,
          ),
        );
      }
      return true;
    } catch (e) {
      if (mounted && !silent) {
        _showErrorDialog(
          'Gagal Menyimpan',
          'Terjadi kesalahan saat menyimpan pengaturan Telegram: $e',
        );
      }
      return false;
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
            if (_loadFailed && !_isLoading)
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Muat Ulang Pengaturan',
                onPressed: _loadData,
              ),
            if (!_isLoading && !_loadFailed)
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
                    if (_loadFailed) ...[
                      _buildLoadFailureBanner(theme),
                      const SizedBox(height: 16),
                    ],
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

  Widget _buildLoadFailureBanner(ThemeData theme) {
    return Material(
      color: Colors.red.shade50,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade700, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Pengaturan Telegram gagal dimuat, sehingga penyimpanan dinonaktifkan agar kredensial yang ada tidak tertimpa. Sambungan penyimpanan aman belum pulih.',
                style: TextStyle(fontSize: 12, color: Colors.red.shade900),
              ),
            ),
            const SizedBox(width: 6),
            TextButton(onPressed: _loadData, child: const Text('Coba Lagi')),
          ],
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
              child: const Icon(
                Icons.send_rounded,
                color: Colors.white,
                size: 24,
              ),
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
    final hasToken = _tokenController.text.trim().isNotEmpty;
    final hasChatId = _chatIdController.text.trim().isNotEmpty;
    final isFullyConfigured = hasToken && hasChatId;

    String statusText;
    Color statusColor;
    IconData statusIcon;

    if (!_isEnabled) {
      statusText = 'Integrasi dinonaktifkan sementara.';
      statusColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
      statusIcon = Icons.power_settings_new_rounded;
    } else if (!isFullyConfigured) {
      final missingMsg = !hasToken && !hasChatId
          ? 'Bot Token & Chat ID belum diisi'
          : !hasToken
          ? 'Bot Token belum diisi'
          : 'Chat ID belum diisi';
      statusText = 'Belum siap: $missingMsg';
      statusColor = Colors.orange.shade700;
      statusIcon = Icons.warning_amber_rounded;
    } else {
      // Koneksi hanya dianggap "Terhubung" bila kredensial yang terverifikasi
      // sama dengan kredensial yang sedang diketik. Bila berubah sejak
      // verifikasi terakhir, status diturunkan hingga uji koneksi ulang.
      final currentFingerprint =
          TelegramConfigRepository.credentialFingerprintFor(
            _tokenController.text.trim(),
            _chatIdController.text.trim(),
          );
      final verifiedWithCurrent =
          _operational.lastVerifiedOk &&
          _operational.verificationFingerprint != null &&
          _operational.verificationFingerprint == currentFingerprint;
      if (verifiedWithCurrent) {
        statusText = 'Status: Terhubung & Siap Mengirim Laporan/Alarm.';
        statusColor = Colors.green.shade700;
        statusIcon = Icons.check_circle_rounded;
      } else if (_operational.lastVerifiedAt != null) {
        statusText = 'Status: Kredensial berubah sejak verifikasi terakhir. Lakukan Uji Koneksi kembali.';
        statusColor = Colors.orange.shade700;
        statusIcon = Icons.warning_amber_rounded;
      } else {
        statusText = 'Status: Belum Terverifikasi. Lakukan Uji Koneksi.';
        statusColor = Colors.orange.shade700;
        statusIcon = Icons.help_rounded;
      }
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? const Color(0xFF333333) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            SwitchListTile.adaptive(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              title: const Text(
                'Aktifkan Integrasi Telegram',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                _isEnabled
                    ? 'Asisten akan mengirim laporan & alarm ke Telegram.'
                    : 'Integrasi dinonaktifkan sementara.',
                style: const TextStyle(fontSize: 12),
              ),
              value: _isEnabled,
              onChanged: (val) => setState(() => _isEnabled = val),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Icon(statusIcon, size: 16, color: statusColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_buildOperationalStatusLines().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1F2937)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _buildOperationalStatusLines(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildOperationalStatusLines() {
    final lines = <Widget>[];

    if (_operational.lastVerifiedAt != null) {
      final label = _operational.lastVerifiedOk
          ? 'Koneksi terverifikasi: '
          : 'Verifikasi terakhir gagal: ';
      final color = _operational.lastVerifiedOk
          ? Colors.green.shade700
          : Colors.red.shade700;
      lines.add(
        _statusLine(
          label,
          _formatTimestamp(_operational.lastVerifiedAt!) +
              (_operational.lastVerifiedOk
                  ? ''
                  : ' — kredensial mungkin tidak valid.'),
          color,
        ),
      );
    }

    switch (_operational.lastDeliveryStatus) {
      case TelegramDeliveryStatus.sent:
        lines.add(
          _statusLine(
            'Pengiriman terakhir:',
            'berhasil. ${_operational.lastDeliveryMessage ?? ''}',
            Colors.green.shade700,
          ),
        );
        break;
      case TelegramDeliveryStatus.failed:
        lines.add(
          _statusLine(
            'Pengiriman terakhir gagal:',
            _operational.lastDeliveryMessage ??
                'periksa kembali kredensial dan koneksi internet.',
            Colors.red.shade700,
          ),
        );
        break;
      case TelegramDeliveryStatus.pending:
        lines.add(
          _statusLine(
            'Pengiriman',
            'sedang berlangsung...',
            Colors.orange.shade700,
          ),
        );
        break;
      case TelegramDeliveryStatus.none:
        break;
    }

    return lines;
  }

  Widget _statusLine(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: const TextStyle(fontSize: 12),
                children: [
                  TextSpan(
                    text: '${StringSanitizer.sanitizeForTextWidget(label)} ',
                    style: TextStyle(color: color, fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: StringSanitizer.sanitizeForTextWidget(value)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime at) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Agu',
      'Sep',
      'Okt',
      'Nov',
      'Des',
    ];
    final local = at.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '${local.day} ${months[local.month - 1]} ${local.year} $hh:$mm';
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
                const Icon(
                  Icons.vpn_key_outlined,
                  size: 20,
                  color: Color(0xFF0284C7),
                ),
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
                helperText: 'ID chat pribadi atau grup keluarga di Telegram',
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
                      _isTesting
                          ? 'Menguji...'
                          : 'Uji Koneksi (Kirim Pesan Tes)',
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
                const Icon(
                  Icons.tune_rounded,
                  size: 20,
                  color: Color(0xFF0284C7),
                ),
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
              subtitle: Text(
                'Kirim ringkasan otomatis ke Telegram setiap kali ada transaksi baru dicatat (min. Rp $_notifyMinAmount).',
                style: const TextStyle(fontSize: 12),
              ),
              value: _notifyOnNewTransaction,
              onChanged: _isEnabled
                  ? (val) => setState(() => _notifyOnNewTransaction = val)
                  : null,
            ),
            if (_isEnabled && _notifyOnNewTransaction) ...[
              const SizedBox(height: 4),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Batas nominal transaksi: Rp $_notifyMinAmount',
                  style: const TextStyle(fontSize: 13),
                ),
                subtitle: const Text(
                  'Transaksi di bawah batas ini tidak dikirim ke Telegram.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              Slider(
                value: _notifyMinAmount.toDouble().clamp(0, 500000),
                min: 0,
                max: 500000,
                divisions: 50,
                label: 'Rp $_notifyMinAmount',
                onChanged: (value) =>
                    setState(() => _notifyMinAmount = value.round()),
              ),
            ],
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
          leading: const Icon(
            Icons.help_outline_rounded,
            color: Color(0xFF0284C7),
          ),
          title: const Text(
            'Panduan: dari Telegram sampai pesan pertama',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            const Divider(height: 1),
            const SizedBox(height: 12),
            _guideStep(
              '1',
              'Di Telegram — buat bot sendiri\n'
                  'Buka @BotFather melalui tombol di bawah, kirim /newbot, lalu ikuti petunjuk nama dan username bot. Simpan username bot Anda.',
            ),
            _guideStep(
              '2',
              'Di FFM — isi Bot Token\n'
                  'Salin token dari BotFather ke kolom Bot Token. Token adalah kunci bot, bukan Chat ID. Jangan kirim token ke grup atau bot lain.',
            ),
            _guideStep(
              '3',
              'Di Telegram — pilih penerima\n'
                  'Pribadi: buka bot Anda dan tekan Start.\n'
                  'Grup keluarga: tambahkan bot Anda ke grup dan izinkan mengirim pesan; kirim /start@username_bot_Anda di grup. Penerima laporan adalah semua anggota grup tersebut.',
            ),
            _guideStep(
              '4',
              'Ambil Chat ID dari bot Anda sendiri\n'
                  'Setelah langkah 3, buka alamat berikut di browser pribadi:\n'
                  'https://api.telegram.org/bot<TOKEN_ANDA>/getUpdates\n'
                  'Ganti <TOKEN_ANDA> dengan token tanpa tanda < >. Pada hasilnya, cari message → chat → id sesuai nama chat/grup tujuan. Salin seluruh angka, termasuk tanda minus untuk grup. Jangan salin from.id bila tujuan Anda grup. Alamat berisi token: jangan bagikan alamat atau tangkapan layarnya.',
            ),
            _guideStep(
              '5',
              'Di FFM — uji tujuan sebelum mengaktifkan\n'
                  'Tempel Chat ID lalu tekan Uji Koneksi (Kirim Pesan Tes). Periksa bahwa pesan benar-benar muncul pada chat/grup yang dipilih. Bot ini dipakai FFM untuk mengirim laporan; percakapan dengan bot di Telegram belum menjadi perintah ke asisten FFM.',
            ),
            _guideStep(
              '6',
              'Aktifkan dan simpan\n'
                  'Nyalakan integrasi Telegram dan pilih laporan mingguan, peringatan radar, atau notifikasi transaksi baru. Untuk transaksi, atur batas nominal. Tekan ikon centang Simpan Pengaturan. Menekan Uji Koneksi saja belum menyimpan atau mengaktifkan pengiriman otomatis.',
            ),
            _guideStep(
              '7',
              'Periksa dengan penggunaan nyata\n'
                  'Saat mencatat transaksi manual berikutnya yang mencapai batas nominal, periksa pesan Telegram. Pengiriman memerlukan internet. Integrasi saat ini belum mencakup semua jalur asisten, impor batch, transfer, hapus, atau perubahan Data Utama. Edit transaksi manual juga dapat dikirim sebagai pesan transaksi baru. Laporan otomatis mengikuti evaluasi aplikasi, bukan jam kirim tetap.',
            ),
            _guideStep(
              '8',
              'Jika belum berhasil\n'
                  'Hasil getUpdates kosong: kirim /start lagi ke bot/di grup lalu muat ulang. Jika bot dipakai layanan lain dengan webhook, gunakan bot khusus FFM. Token tidak valid: periksa token di BotFather. Chat tidak ditemukan: cek Chat ID dan Start. Bot diblokir: buka blokir atau periksa izin grup. Pesan gagal karena jaringan belum mempunyai antrean kirim ulang otomatis.',
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.shield_outlined,
                    size: 18,
                    color: Color(0xFF0284C7),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Token dan Chat ID disimpan melalui penyimpanan aman perangkat. Laporan dikirim melalui Telegram ke tujuan yang Anda pilih; anggota grup penerima dapat membacanya. Periksa tujuan melalui pesan tes sebelum mengaktifkan laporan.',
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
              style: const TextStyle(
                fontSize: 11,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
