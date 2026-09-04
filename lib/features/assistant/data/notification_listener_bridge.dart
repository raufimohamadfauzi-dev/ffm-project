import 'package:flutter/services.dart';

import '../data/payment_draft_repository.dart';
import '../data/payment_notification_parser.dart';

/// Jembatan antara Flutter dan FfmNotificationListenerService di Android.
///
/// Bertanggung jawab untuk:
/// 1. Memeriksa apakah izin Notification Access sudah diberikan.
/// 2. Membuka halaman pengaturan Android untuk meminta izin.
/// 3. Menerima notifikasi mentah dari Android dan memprosesnya via parser lokal.
/// 4. Menyimpan hasil parsing sebagai PaymentDraft (tanpa mutasi langsung).
class NotificationListenerBridge {
  NotificationListenerBridge(this._draftRepository);

  final PaymentDraftRepository _draftRepository;

  static const _accessChannel = MethodChannel('ffm/notification_access');
  static const _notifChannel = MethodChannel('ffm/notification_listener');

  /// Callback saat draft baru berhasil ditambahkan.
  void Function(PaymentDraft draft)? onNewDraft;

  /// Mulai mendengarkan notifikasi dari Android.
  void startListening() {
    _notifChannel.setMethodCallHandler(_handleIncomingNotification);
  }

  /// Hentikan listener.
  void stopListening() {
    _notifChannel.setMethodCallHandler(null);
  }

  /// Periksa apakah izin Notification Access sudah aktif di Android.
  Future<bool> isNotificationListenerEnabled() async {
    try {
      final result = await _accessChannel.invokeMethod<bool>('isEnabled');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Buka layar pengaturan Android "Notification Access".
  Future<void> openNotificationListenerSettings() async {
    try {
      await _accessChannel.invokeMethod('openSettings');
    } on PlatformException {
      // Abaikan jika tidak didukung platform
    }
  }

  // ---------------------------------------------------------------------------
  // Handler internal
  // ---------------------------------------------------------------------------

  Future<void> _handleIncomingNotification(MethodCall call) async {
    if (call.method != 'onNotification') return;

    final args = call.arguments as Map<dynamic, dynamic>?;
    if (args == null) return;

    final packageName = args['packageName'] as String? ?? '';
    final title = args['title'] as String? ?? '';
    final body = args['body'] as String? ?? '';
    final postTime = args['postTime'] as int?;

    // Parse menggunakan regex lokal — 100% on-device
    final parsed = PaymentNotificationParser.parse(
      packageName: packageName,
      title: title,
      body: body,
      postTime: postTime,
    );

    if (parsed == null) return; // Bukan notifikasi pembayaran yang valid

    final draft = PaymentDraft(
      id: 'draft_${DateTime.now().millisecondsSinceEpoch}',
      sourceApp: packageName,
      rawTitle: title,
      rawBody: body,
      amount: parsed.amount,
      merchantName: parsed.merchantName,
      mutationType: parsed.mutationType,
      createdAt: postTime != null
          ? DateTime.fromMillisecondsSinceEpoch(postTime)
          : DateTime.now(),
      suggestedCategory: parsed.suggestedCategory,
    );

    // Tambahkan ke repository dengan deduplication
    final added = await _draftRepository.addIfNotDuplicate(draft);
    if (added != null) {
      onNewDraft?.call(added);
    }
  }
}
