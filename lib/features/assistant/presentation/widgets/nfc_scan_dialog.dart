import 'package:flutter/material.dart';

import '../../../../core/di/injection.dart';
import '../../data/nfc_bridge.dart';
import '../../data/nfc_card_repository.dart';
import '../../data/payment_draft_repository.dart';
import '../../data/payment_notification_parser.dart';

/// Modal BottomSheet untuk memindai kartu e-Money via NFC
/// dan menampilkan hasil adaptasi saldo secara otomatis.
class NfcScanDialog extends StatefulWidget {
  const NfcScanDialog({super.key});

  /// Menampilkan modal dialog scan NFC dari mana saja di aplikasi.
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const NfcScanDialog(),
    );
  }

  @override
  State<NfcScanDialog> createState() => _NfcScanDialogState();
}

class _NfcScanDialogState extends State<NfcScanDialog>
    with SingleTickerProviderStateMixin {
  late final NfcBridge _nfcBridge;
  late final NfcCardRepository _nfcRepo;
  late final PaymentDraftRepository _draftRepo;

  late final AnimationController _animController;
  late final Animation<double> _pulseAnim;

  bool _isAvailable = false;
  bool _isEnabled = false;
  bool _isScanning = false;
  bool _isLoading = true;

  NfcAdaptationResult? _adaptationResult;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nfcBridge = getIt<NfcBridge>();
    _nfcRepo = getIt<NfcCardRepository>();
    _draftRepo = getIt<PaymentDraftRepository>();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.9, end: 1.15).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );

    _checkNfcAndStart();
  }

  @override
  void dispose() {
    _animController.dispose();
    _nfcBridge.stopScanning();
    super.dispose();
  }

  Future<void> _checkNfcAndStart() async {
    final avail = await _nfcBridge.isNfcAvailable();
    final enabled = await _nfcBridge.isNfcEnabled();

    if (!mounted) return;
    setState(() {
      _isAvailable = avail;
      _isEnabled = enabled;
      _isLoading = false;
    });

    if (avail && enabled) {
      _startSession();
    }
  }

  Future<void> _startSession() async {
    setState(() {
      _isScanning = true;
      _errorMessage = null;
      _adaptationResult = null;
    });

    final started = await _nfcBridge.startScanning((scanResult) async {
      if (!scanResult.success) {
        if (mounted) {
          setState(() {
            _errorMessage = scanResult.error ?? 'Gagal membaca kartu NFC';
          });
        }
        return;
      }

      // Hitung adaptasi selisih saldo via repository
      final result = await _nfcRepo.processCardScan(scanResult);

      if (mounted) {
        setState(() {
          _adaptationResult = result;
          _isScanning = false;
        });
      }
    });

    if (!started && mounted) {
      setState(() {
        _isScanning = false;
        _errorMessage = 'Gagal memulai sesi pemindaian NFC.';
      });
    }
  }

  Future<void> _confirmDraft(PaymentDraft draft) async {
    await _draftRepo.updateStatus(draft.id, PaymentDraftStatus.confirmed);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Transaksi ${draft.formattedAmount} berhasil disimpan.'),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
    Navigator.of(context).pop();
  }

  Future<void> _dismissDraft(PaymentDraft draft) async {
    await _draftRepo.updateStatus(draft.id, PaymentDraftStatus.dismissed);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colors.onSurface.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // Title Header
          Row(
            children: [
              Icon(Icons.nfc, color: colors.primary),
              const SizedBox(width: 10),
              Text(
                'Pembaca NFC e-Money',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            )
          else if (!_isAvailable)
            _buildUnavailableState(
              theme,
              colors,
              'Perangkat Tidak Mendukung NFC',
              'HP Anda tidak memiliki sensor fisik NFC untuk membaca kartu e-Money.',
            )
          else if (!_isEnabled)
            _buildUnavailableState(
              theme,
              colors,
              'NFC Belum Aktif',
              'Silakan aktifkan NFC di Pengaturan HP Anda untuk memindai kartu.',
            )
          else if (_adaptationResult != null)
            _buildScanResultView(theme, colors, _adaptationResult!)
          else
            _buildScanningView(theme, colors),
        ],
      ),
    );
  }

  Widget _buildUnavailableState(
    ThemeData theme,
    ColorScheme colors,
    String title,
    String message,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(Icons.nfc_outlined, size: 64, color: colors.error),
          const SizedBox(height: 12),
          Text(title,
              style: theme.textTheme.titleSmall?.copyWith(color: colors.error)),
          const SizedBox(height: 6),
          Text(message,
              textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _buildScanningView(ThemeData theme, ColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          ScaleTransition(
            scale: _pulseAnim,
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.primaryContainer.withValues(alpha: 0.4),
              ),
              child: Icon(
                Icons.contactless_rounded,
                size: 64,
                color: colors.primary,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            _isScanning ? 'Siap Memindai Kartu e-Money...' : 'Tempelkan Kartu e-Money',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tempelkan kartu Mandiri e-Money, BCA Flazz, BNI TapCash, atau BRI Brizzi di bagian belakang HP Anda.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurface.withValues(alpha: 0.7),
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              style: theme.textTheme.bodySmall?.copyWith(color: colors.error),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildScanResultView(
    ThemeData theme,
    ColorScheme colors,
    NfcAdaptationResult result,
  ) {
    final account = result.cardAccount;
    final draft = result.draft;
    final isDebit = draft?.mutationType == PaymentMutationType.debit;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Kartu Saldo Terkini
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [colors.primary, colors.primary.withValues(alpha: 0.8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.credit_card, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    account.cardType,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'ID: ${account.cardId}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Saldo Terkini',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 2),
              Text(
                'Rp ${_formatNumber(account.lastKnownBalance)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Hasil Adaptasi
        if (result.isBaseline)
          _buildInfoBanner(
            theme,
            colors,
            Icons.new_releases_outlined,
            Colors.blue,
            'Kartu Baru Terdeteksi',
            'Saldo awal sebesar Rp ${_formatNumber(result.newBalance)} berhasil dicatat sebagai titik acuan.',
          )
        else if (draft == null)
          _buildInfoBanner(
            theme,
            colors,
            Icons.check_circle_outline,
            Colors.grey,
            'Saldo Tidak Berubah',
            'Sisa saldo masih sama dengan pemindaian sebelumnya.',
          )
        else ...[
          // Ada Transaksi Terdeteksi!
          Text(
            'Transaksi Terdeteksi Otomatis',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: isDebit ? Colors.red.shade700 : Colors.green.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (isDebit ? Colors.red : Colors.green).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: (isDebit ? Colors.red : Colors.green).withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      isDebit ? '▼ Pengeluaran' : '▲ Top-Up / Isi Ulang',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: isDebit ? Colors.red.shade700 : Colors.green.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      draft.formattedAmount,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: isDebit ? Colors.red.shade700 : Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  draft.merchantName,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Tombol Konfirmasi 1-Ketukan
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Simpan Transaksi'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                  ),
                  onPressed: () => _confirmDraft(draft),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Abaikan'),
                  onPressed: () => _dismissDraft(draft),
                ),
              ),
            ],
          ),
        ],

        const SizedBox(height: 16),
        Center(
          child: TextButton.icon(
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Scan Kartu Lain'),
            onPressed: _startSession,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoBanner(
    ThemeData theme,
    ColorScheme colors,
    IconData icon,
    Color color,
    String title,
    String message,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: color, fontWeight: FontWeight.bold)),
                Text(message, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatNumber(double amount) {
    final n = amount.toStringAsFixed(0);
    final buf = StringBuffer();
    int count = 0;
    for (int i = n.length - 1; i >= 0; i--) {
      if (count > 0 && count % 3 == 0) buf.write('.');
      buf.write(n[i]);
      count++;
    }
    return buf.toString().split('').reversed.join();
  }
}
