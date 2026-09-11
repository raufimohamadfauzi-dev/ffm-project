import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:uuid/uuid.dart';

import '../data/payment_draft_repository.dart';
import '../data/payment_notification_parser.dart';
import '../data/payment_analytics_service.dart';

/// Jembatan antara Flutter dan FfmNotificationListenerService di Android.
///
/// Bertanggung jawab untuk:
/// 1. Memeriksa apakah izin Notification Access sudah diberikan.
/// 2. Membuka halaman pengaturan Android untuk meminta izin.
/// 3. Menerima notifikasi mentah dari Android dan memprosesnya via parser lokal.
/// 4. Menyimpan hasil parsing sebagai PaymentDraft (tanpa mutasi langsung).
/// 5. Mengirim notifikasi saat draft baru tersedia.
/// 6. Tracking analytics untuk parser success rate.
class NotificationListenerBridge {
  NotificationListenerBridge(this._draftRepository);

  final PaymentDraftRepository _draftRepository;
  final PaymentAnalyticsService _analytics = PaymentAnalyticsService();

  static const _accessChannel = MethodChannel('ffm/notification_access');
  static const _notifChannel = MethodChannel('ffm/notification_listener');
  static const _uuid = Uuid();
  
  static const _paymentDraftChannelId = 'ffm_payment_drafts';
  static const _paymentDraftChannelName = 'Draft Pembayaran';
  static const _paymentDraftChannelDescription = 'Notifikasi untuk draft pembayaran yang terdeteksi';
  
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  bool _notificationsInitialized = false;

  /// Callback saat draft baru berhasil ditambahkan.
  void Function(PaymentDraft draft)? onNewDraft;

  /// Mulai mendengarkan notifikasi dari Android.
  void startListening() {
    _initializeNotifications();
    _notifChannel.setMethodCallHandler(_handleIncomingNotification);
    _consumePendingNotifications();
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

  Future<void> _initializeNotifications() async {
    if (_notificationsInitialized) return;
    
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    
    await _notificationsPlugin.initialize(
      settings: const InitializationSettings(android: android),
    );
    
    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _paymentDraftChannelId,
            _paymentDraftChannelName,
            description: _paymentDraftChannelDescription,
            importance: Importance.defaultImportance,
          ),
        );
    
    _notificationsInitialized = true;
  }

  Future<void> _showDraftNotification(PaymentDraft draft) async {
    if (!_notificationsInitialized) return;
    
    final isDebit = draft.mutationType == PaymentMutationType.debit;
    final typeLabel = isDebit ? 'Pengeluaran' : 'Pemasukan';
    final emoji = isDebit ? '💸' : '💰';
    
    final androidDetails = AndroidNotificationDetails(
      _paymentDraftChannelId,
      _paymentDraftChannelName,
      channelDescription: _paymentDraftChannelDescription,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    
    final notificationDetails = NotificationDetails(android: androidDetails);
    
    await _notificationsPlugin.show(
      id: draft.id.hashCode,
      title: 'Draft Pembayaran Baru',
      body: '$emoji $typeLabel ${draft.formattedAmount} dari ${draft.accountLabel}',
      notificationDetails: notificationDetails,
      payload: draft.id,
    );
  }

  Future<void> _handleIncomingNotification(MethodCall call) async {
    if (call.method != 'onNotification') return;

    final args = call.arguments as Map<dynamic, dynamic>?;
    if (args == null) return;

    await _processNotification(args);
  }

  Future<void> _consumePendingNotifications() async {
    try {
      final pending = await _notifChannel.invokeMethod<List<dynamic>>(
        'consumePendingNotifications',
      );
      for (final item in pending ?? const <dynamic>[]) {
        if (item is Map) await _processNotification(item);
      }
    } on PlatformException {
      // Older Android builds may not expose the queue method.
    }
  }

  Future<void> _processNotification(Map<dynamic, dynamic> args) async {
    final packageName = args['packageName'] as String? ?? '';
    final title = args['title'] as String? ?? '';
    final body = args['body'] as String? ?? '';
    final postTime = args['postTime'] as int?;

    // Track analytics: notification received
    await _analytics.recordNotificationReceived();

    // Parse menggunakan regex lokal — 100% on-device
    final parsed = PaymentNotificationParser.parse(
      packageName: packageName,
      title: title,
      body: body,
      postTime: postTime,
    );

    if (parsed == null) {
      // Track analytics: failed parse
      await _analytics.recordFailedParse(packageName, 'no_parse_result');
      return; // Bukan notifikasi pembayaran yang valid
    }

    // Track analytics: successful parse
    await _analytics.recordSuccessfulParse(packageName);

    final draft = PaymentDraft(
      id: 'draft_${_uuid.v4()}',
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
      // Show notification untuk draft baru
      await _showDraftNotification(added);
    }
  }
}
