import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/database/app_context.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../transaction/domain/usecases/transaction_crud_usecases.dart';
import '../../data/notification_listener_bridge.dart';
import '../../data/payment_draft_repository.dart';
import '../../data/payment_notification_parser.dart';
import '../../data/payment_analytics_service.dart';
import '../../domain/ffm_assistant_models.dart';
import '../widgets/ffm_assistant_page_context.dart';

/// Jenis error yang bisa terjadi saat mengkonfirmasi draft pembayaran.
enum PaymentDraftError {
  accountNotFound,
  categoryNotFound,
  databaseError,
  unknownError;

  String get userMessage {
    switch (this) {
      case PaymentDraftError.accountNotFound:
        return 'Akun tidak ditemukan. Silakan tambahkan akun terlebih dahulu.';
      case PaymentDraftError.categoryNotFound:
        return 'Kategori tidak ditemukan. Silakan tambahkan kategori terlebih dahulu.';
      case PaymentDraftError.databaseError:
        return 'Gagal menyimpan transaksi. Silakan coba lagi.';
      case PaymentDraftError.unknownError:
        return 'Terjadi kesalahan. Silakan coba lagi.';
    }
  }
}

/// Halaman pengaturan Pendeteksi Bayar Otomatis (QRIS & Bank).
///
/// Fitur ini membaca notifikasi dari aplikasi bank/e-wallet secara lokal
/// (100% on-device, tidak ada data dikirim ke cloud) dan membuat draft
/// transaksi yang memerlukan konfirmasi 1-ketukan dari pengguna.
class PaymentDetectorSettingsPage extends StatefulWidget {
  const PaymentDetectorSettingsPage({super.key});

  @override
  State<PaymentDetectorSettingsPage> createState() =>
      _PaymentDetectorSettingsPageState();
}

class _PaymentDetectorSettingsPageState
    extends State<PaymentDetectorSettingsPage> with WidgetsBindingObserver {
  late final NotificationListenerBridge _bridge;
  late final PaymentDraftRepository _draftRepo;
  late final PaymentAnalyticsService _analytics;

  bool _isPermissionGranted = false;
  bool _isLoading = true;
  List<PaymentDraft> _allDrafts = [];
  final Set<String> _confirmingDrafts = {};


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bridge = getIt<NotificationListenerBridge>();
    _draftRepo = getIt<PaymentDraftRepository>();
    _analytics = PaymentAnalyticsService();
    _checkPermission();
    _loadDrafts();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Refresh status izin saat kembali dari layar pengaturan Android
    if (state == AppLifecycleState.resumed) {
      _checkPermission();
    }
  }

  Future<void> _checkPermission() async {
    final enabled = await _bridge.isNotificationListenerEnabled();
    if (mounted) {
      setState(() {
        _isPermissionGranted = enabled;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadDrafts() async {
    final drafts = await _draftRepo.getAllDrafts();
    if (mounted) setState(() => _allDrafts = drafts);
  }

  Future<void> _requestPermission() async {
    await _bridge.openNotificationListenerSettings();
  }

  Future<void> _confirmDraft(PaymentDraft draft) async {
    if (mounted) {
      setState(() {
        _confirmingDrafts.add(draft.id);
      });
    }

    try {
      final db = getIt<AppDatabase>();
      final isDebit = draft.mutationType == PaymentMutationType.debit;
      final signedAmount =
          isDebit ? -draft.amount.round() : draft.amount.round();
      final txId = 'tx_notif_${draft.id}';

      // 1. Cari akun yang cocok (SeaBank, GoPay, BCA, dll.)
      final accounts = await (db.select(db.accounts)
            ..where((a) => a.isArchived.equals(false)))
          .get();
      
      if (accounts.isEmpty) {
        throw PaymentDraftError.accountNotFound;
      }
      
      Account? matchedAccount;
      final lowerSource = draft.sourceApp.toLowerCase();
      final lowerLabel = draft.accountLabel.toLowerCase();
      for (final a in accounts) {
        final aName = a.name.toLowerCase();
        if (lowerLabel.contains('seabank') || lowerSource.contains('seabank')) {
          if (aName.contains('seabank')) {
            matchedAccount = a;
            break;
          }
        } else if (lowerLabel.contains('gopay') ||
            lowerSource.contains('gojek') ||
            lowerSource.contains('gopay')) {
          if (aName.contains('gopay') || aName.contains('gojek')) {
            matchedAccount = a;
            break;
          }
        } else if (lowerLabel.contains('neo') || lowerSource.contains('bnc')) {
          if (aName.contains('neo') || aName.contains('bnc')) {
            matchedAccount = a;
            break;
          }
        } else if (lowerLabel.contains('krom') || lowerSource.contains('krom')) {
          if (aName.contains('krom')) {
            matchedAccount = a;
            break;
          }
        } else if (lowerLabel.contains('jago') || lowerSource.contains('jago')) {
          if (aName.contains('jago')) {
            matchedAccount = a;
            break;
          }
        } else if (lowerLabel.contains('blu') || lowerSource.contains('bcadigital')) {
          if (aName.contains('blu')) {
            matchedAccount = a;
            break;
          }
        } else if (lowerLabel.contains('jenius') || lowerSource.contains('btpn')) {
          if (aName.contains('jenius')) {
            matchedAccount = a;
            break;
          }
        } else if (lowerLabel.contains('shopee') || lowerSource.contains('shopee')) {
          if (aName.contains('shopee')) {
            matchedAccount = a;
            break;
          }
        } else if (lowerLabel.contains('tokopedia') || lowerSource.contains('tokopedia')) {
          if (aName.contains('tokopedia') || aName.contains('gopay')) {
            matchedAccount = a;
            break;
          }
        } else if (lowerLabel.contains('lazada') || lowerSource.contains('lazada')) {
          if (aName.contains('lazada')) {
            matchedAccount = a;
            break;
          }
        } else if (lowerLabel.contains('tiktok') ||
            lowerSource.contains('musically') ||
            lowerSource.contains('trill')) {
          if (aName.contains('tiktok')) {
            matchedAccount = a;
            break;
          }
        } else if (lowerLabel.contains('paypal') || lowerSource.contains('paypal')) {
          if (aName.contains('paypal')) {
            matchedAccount = a;
            break;
          }
        } else if (lowerLabel.contains('wise') || lowerSource.contains('transferwise')) {
          if (aName.contains('wise')) {
            matchedAccount = a;
            break;
          }
        } else if (lowerLabel.contains('doku') || lowerSource.contains('doku')) {
          if (aName.contains('doku')) {
            matchedAccount = a;
            break;
          }
        } else if (lowerLabel.contains('google') || lowerSource.contains('walletnfcrel')) {
          if (aName.contains('google')) {
            matchedAccount = a;
            break;
          }
        } else if (lowerLabel.contains('bibit') || lowerSource.contains('bibit')) {
          if (aName.contains('bibit')) {
            matchedAccount = a;
            break;
          }
        } else if (lowerLabel.contains('ajaib') || lowerSource.contains('ajaib')) {
          if (aName.contains('ajaib')) {
            matchedAccount = a;
            break;
          }
        } else if (aName.contains(lowerLabel)) {
          matchedAccount = a;
          break;
        }
      }
      matchedAccount ??= accounts.first;

      // 2. Cari kategori yang cocok
      final categories = await (db.select(db.categories)
            ..where((c) => c.isActive.equals(true)))
          .get();
      
      if (categories.isEmpty) {
        throw PaymentDraftError.categoryNotFound;
      }
      
      Category? matchedCategory;
      if (draft.suggestedCategory != null) {
        final targetCat = draft.suggestedCategory!.toLowerCase();
        for (final c in categories) {
          if (c.name.toLowerCase().contains(targetCat) ||
              targetCat.contains(c.name.toLowerCase())) {
            matchedCategory = c;
            break;
          }
        }
      }
      if (matchedCategory == null) {
        final targetType = isDebit ? 'expense' : 'income';
        matchedCategory = categories.where((c) => c.type == targetType).firstOrNull ??
            categories.first;
      }

      // 3. Simpan transaksi secara nyata ke database
      final saveTx = getIt.isRegistered<SaveTransaction>()
          ? getIt<SaveTransaction>()
          : SaveTransaction(db);

      await saveTx(
        TransactionEntity(
          id: txId,
          householdId: AppContext.householdId,
          date: draft.createdAt,
          amount: signedAmount,
          owner: 'Asisten (Notifikasi)',
          categoryId: matchedCategory.id,
          accountId: matchedAccount.id,
          note:
              'Otomatis dari notifikasi ${draft.accountLabel}${draft.merchantName.isNotEmpty ? ' (${draft.merchantName})' : ''}',
          source: 'notification_detector',
          sourceId: draft.id,
          partyName: draft.merchantName.isNotEmpty ? draft.merchantName : null,
          recordedAt: DateTime.now(),
        ),
      );

      await _draftRepo.updateStatus(draft.id, PaymentDraftStatus.confirmed);
      await _analytics.recordUserConfirmation();
      _loadDrafts();
      if (mounted) {
        final targetName = 'ke ${matchedAccount.name}';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Transaksi ${draft.formattedAmount} berhasil dicatat $targetName.',
            ),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on PaymentDraftError catch (error) {
      // Handle specific payment draft errors
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.userMessage),
            backgroundColor: Colors.orange.shade700,
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Tutup',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    } catch (error) {
      // Handle general database errors
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menyimpan transaksi: ${error.toString()}'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Coba Lagi',
              textColor: Colors.white,
              onPressed: () => _confirmDraft(draft),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _confirmingDrafts.remove(draft.id);
        });
      }
    }
  }

  Future<void> _dismissDraft(PaymentDraft draft) async {
    await _draftRepo.updateStatus(draft.id, PaymentDraftStatus.dismissed);
    await _analytics.recordUserDismissal();
    _loadDrafts();
  }

  Future<void> _clearAll() async {
    await _draftRepo.clearAll();
    _loadDrafts();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Semua riwayat draft dihapus.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return FfmAssistantPageContext(
      destination: FfmAssistantDestination.paymentDetector,
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Pendeteksi Bayar Otomatis'),
        actions: [
          if (_allDrafts.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Hapus semua riwayat',
              onPressed: _clearAll,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      // --- Status izin ---
                      _PermissionStatusCard(
                        isGranted: _isPermissionGranted,
                        onRequest: _requestPermission,
                        onRefresh: _checkPermission,
                      ),
                      const SizedBox(height: 16),

                      // --- Penjelasan fitur ---
                      _FeatureInfoCard(),
                      const SizedBox(height: 16),

                      // --- Daftar bank yang dipantau ---
                      _MonitoredAppsCard(),
                      const SizedBox(height: 16),

                      // --- Pending drafts ---
                      if (_isPermissionGranted) ...[
                        _SectionHeader(
                          icon: Icons.pending_actions,
                          title: 'Menunggu Konfirmasi',
                          count: _allDrafts
                              .where((d) =>
                                  d.status == PaymentDraftStatus.pending)
                              .length,
                          color: colors.primary,
                        ),
                        ..._allDrafts
                            .where((d) => d.status == PaymentDraftStatus.pending)
                            .map((d) => _DraftCard(
                                  draft: d,
                                  isConfirming: _confirmingDrafts.contains(d.id),
                                  onConfirm: () => _confirmDraft(d),
                                  onDismiss: () => _dismissDraft(d),
                                )),
                        const SizedBox(height: 16),
                        _SectionHeader(
                          icon: Icons.history,
                          title: 'Riwayat',
                          count: _allDrafts
                              .where((d) =>
                                  d.status != PaymentDraftStatus.pending)
                              .length,
                          color: colors.secondary,
                        ),
                        ..._allDrafts
                            .where((d) => d.status != PaymentDraftStatus.pending)
                            .map((d) => _HistoryDraftTile(draft: d)),
                        if (_allDrafts.every(
                            (d) => d.status != PaymentDraftStatus.pending) &&
                            _allDrafts.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 32),
                            child: Center(
                              child: Column(
                                children: [
                                  Icon(Icons.inbox_outlined,
                                      size: 56,
                                      color: colors.onSurface.withValues(alpha: 0.3)),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Belum ada transaksi terdeteksi.',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: colors.onSurface.withValues(alpha: 0.5),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Lakukan pembayaran QRIS atau transfer\ndan notifikasi akan muncul di sini.',
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colors.onSurface.withValues(alpha: 0.4),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ]),
                  ),
                ),
              ],
            ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Widget: Status Izin
// ---------------------------------------------------------------------------

class _PermissionStatusCard extends StatelessWidget {
  const _PermissionStatusCard({
    required this.isGranted,
    required this.onRequest,
    required this.onRefresh,
  });

  final bool isGranted;
  final VoidCallback onRequest;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final color = isGranted ? Colors.green.shade600 : colors.error;
    final icon = isGranted ? Icons.check_circle : Icons.warning_rounded;
    final label = isGranted ? 'Izin Aktif' : 'Belum Diizinkan';
    final desc = isGranted
        ? 'FFM dapat membaca notifikasi bank & e-wallet Anda untuk membuat draft transaksi.'
        : 'FFM memerlukan izin "Akses Notifikasi" untuk mendeteksi transaksi otomatis. '
          'Tap tombol di bawah untuk mengaktifkan.';

    return Card(
      elevation: 0,
      color: color.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: color, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.refresh, size: 18, color: color),
                  tooltip: 'Perbarui status',
                  onPressed: onRefresh,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(desc, style: theme.textTheme.bodySmall),
            if (!isGranted) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                icon: const Icon(Icons.settings, size: 18),
                label: const Text('Buka Pengaturan Android'),
                onPressed: onRequest,
                style: FilledButton.styleFrom(backgroundColor: color),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Widget: Info Fitur
// ---------------------------------------------------------------------------

class _FeatureInfoCard extends StatelessWidget {
  const _FeatureInfoCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.privacy_tip_outlined, size: 18),
                const SizedBox(width: 8),
                Text('Cara Kerja & Keamanan',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 10),
            _InfoRow(
                icon: Icons.device_hub,
                text: '100% lokal di perangkat — tidak ada data dikirim ke cloud'),
            _InfoRow(
                icon: Icons.verified_user_outlined,
                text: 'Hanya membaca notifikasi bank & e-wallet resmi yang dipilih'),
            _InfoRow(
                icon: Icons.lock_outlined,
                text: 'Notifikasi OTP & keamanan selalu diabaikan otomatis'),
            _InfoRow(
                icon: Icons.touch_app_outlined,
                text: 'Draft transaksi memerlukan ketukan "Simpan" sebelum dicatat'),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Widget: Daftar App yang Dipantau
// ---------------------------------------------------------------------------

class _MonitoredAppsCard extends StatelessWidget {
  const _MonitoredAppsCard();

  static const _apps = [
    // Bank Konvensional
    ('BCA Mobile & myBCA', Icons.account_balance),
    ("Livin' by Mandiri", Icons.account_balance),
    ('BRImo', Icons.account_balance),
    ('BNI Mobile & Wondr', Icons.account_balance),
    // Bank Digital
    ('Neobank (BNC)', Icons.account_balance),
    ('Krom Bank', Icons.account_balance),
    ('Bank Jago', Icons.account_balance),
    ('SeaBank', Icons.account_balance),
    ('blu by BCA Digital', Icons.account_balance),
    ('Jenius', Icons.account_balance),
    ('Allo Bank', Icons.account_balance),
    ('Bank Saqu', Icons.account_balance),
    ('Superbank', Icons.account_balance),
    ('TMRW by UOB', Icons.account_balance),
    ('LINE Bank', Icons.account_balance),
    ('digibank DBS', Icons.account_balance),
    // E-Commerce / Marketplace
    ('Tokopedia', Icons.storefront),
    ('Shopee', Icons.shopping_bag_outlined),
    ('Lazada', Icons.shopping_bag_outlined),
    ('TikTok Shop', Icons.shopping_bag_outlined),
    ('Blibli', Icons.storefront),
    ('Bukalapak', Icons.storefront),
    // E-Wallet & Pembayaran Digital
    ('GoPay', Icons.wallet),
    ('OVO', Icons.wallet),
    ('DANA', Icons.wallet),
    ('ShopeePay', Icons.shopping_bag_outlined),
    ('LinkAja', Icons.wallet),
    ('AstraPay', Icons.wallet),
    ('Flip', Icons.currency_exchange),
    ('i.saku', Icons.account_balance_wallet),
    ('MotionPay', Icons.payment),
    ('PayPal', Icons.payment),
    ('DOKU', Icons.wallet),
    ('KasPro', Icons.wallet),
    ('Google Wallet', Icons.wallet),
    ('Wise', Icons.currency_exchange),
    ('Paytren', Icons.wallet),
    ('OY! Indonesia', Icons.currency_exchange),
    ('Pluang', Icons.trending_up),
    ('Bibit', Icons.trending_up),
    ('Ajaib', Icons.trending_up),
    // Bisnis & Pengiriman
    ('DANA Bisnis', Icons.store),
    ('Honest', Icons.credit_card),
    ('Lalamove', Icons.local_shipping),
    ('Qmove', Icons.local_shipping),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Aplikasi yang Dipantau',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: _apps
                  .map((app) => Chip(
                        avatar: Icon(app.$2, size: 14),
                        label: Text(app.$1,
                            style: theme.textTheme.labelSmall),
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Widget: Section Header
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.count,
    required this.color,
  });
  final IconData icon;
  final String title;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Text(
            '$title${count > 0 ? ' ($count)' : ''}',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Widget: Draft Menunggu Konfirmasi
// ---------------------------------------------------------------------------

class _DraftCard extends StatelessWidget {
  const _DraftCard({
    required this.draft,
    required this.isConfirming,
    required this.onConfirm,
    required this.onDismiss,
  });

  final PaymentDraft draft;
  final bool isConfirming;
  final VoidCallback onConfirm;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDebit = draft.mutationType == PaymentMutationType.debit;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.outline.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: isDebit
                        ? Colors.red.shade50
                        : Colors.green.shade50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isDebit ? '▼ Keluar' : '▲ Masuk',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isDebit ? Colors.red.shade700 : Colors.green.shade700,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    draft.accountLabel,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: colors.onSurface.withValues(alpha: 0.6)),
                  ),
                ),
                Text(
                  DateFormat('d MMM HH:mm', 'id_ID').format(draft.createdAt),
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: colors.onSurface.withValues(alpha: 0.5)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              draft.formattedAmount,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: isDebit ? Colors.red.shade700 : Colors.green.shade700,
              ),
            ),
            if (draft.merchantName.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                draft.merchantName,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
            if (draft.suggestedCategory != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.label_outline, size: 12,
                      color: colors.onSurface.withValues(alpha: 0.4)),
                  const SizedBox(width: 4),
                  Text(
                    draft.suggestedCategory!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Opacity(
                    opacity: isConfirming ? 0.7 : 1.0,
                    child: FilledButton.icon(
                      icon: isConfirming
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.check, size: 16),
                      label: Text(isConfirming ? 'Memproses...' : 'Simpan'),
                      onPressed: isConfirming ? null : onConfirm,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade600,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Opacity(
                    opacity: isConfirming ? 0.7 : 1.0,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Abaikan'),
                      onPressed: isConfirming ? null : onDismiss,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
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
}

// ---------------------------------------------------------------------------
// Widget: Tile Riwayat
// ---------------------------------------------------------------------------

class _HistoryDraftTile extends StatelessWidget {
  const _HistoryDraftTile({required this.draft});
  final PaymentDraft draft;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isConfirmed = draft.status == PaymentDraftStatus.confirmed;
    final statusIcon =
        isConfirmed ? Icons.check_circle_outline : Icons.cancel_outlined;
    final statusColor = isConfirmed ? Colors.green.shade600 : colors.outline;
    final statusLabel = isConfirmed ? 'Tersimpan' : 'Diabaikan';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      leading: Icon(statusIcon, color: statusColor),
      title: Text(
        draft.merchantName.isNotEmpty
            ? draft.merchantName
            : draft.accountLabel,
        style: theme.textTheme.bodyMedium,
      ),
      subtitle: Text(
        '${draft.formattedAmount} · ${draft.accountLabel}',
        style: theme.textTheme.bodySmall
            ?.copyWith(color: colors.onSurface.withValues(alpha: 0.6)),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            statusLabel,
            style: theme.textTheme.labelSmall?.copyWith(color: statusColor),
          ),
          Text(
            DateFormat('d MMM', 'id_ID').format(draft.createdAt),
            style: theme.textTheme.labelSmall
                ?.copyWith(color: colors.onSurface.withValues(alpha: 0.4)),
          ),
        ],
      ),
      dense: true,
    );
  }
}
