import '../../../core/database/app_database.dart';
import 'telegram_bot_service.dart';
import 'telegram_config_repository.dart';
import 'telegram_delivery_repository.dart';

/// Memproses antrean pengiriman Telegram secara durabel.
///
/// Satu siklus: membaca konfigurasi aktif, mengambil pesan yang jatuh tempo,
/// mengklaim tiap pesan secara atomik, memverifikasi kredensial (fingerprint),
/// lalu mengirim. Kegagalan sementara diantrekan ulang dengan backoff;
/// kegagalan permanen (mis. token tidak valid) dan kredensial yang berubah
/// tidak pernah memicu pengiriman ulang.
class TelegramDeliveryProcessor {
  TelegramDeliveryProcessor({
    required this.repository,
    required this.botService,
    required this.configRepository,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final TelegramDeliveryRepository repository;
  final TelegramBotService botService;
  final TelegramConfigRepository configRepository;
  final DateTime Function() _clock;

  /// Memproses pesan yang sudah jatuh tempo. Mengembalikan jumlah pesan yang
  /// BENAR-BENAR terkirim pada siklus ini.
  Future<int> processPending({
    String householdId = TelegramDeliveryRepository.householdId,
    int limit = 10,
  }) async {
    final now = _clock();
    final TelegramConfig config;
    try {
      config = await configRepository.loadConfig();
    } catch (_) {
      // Jangan mengirim dengan kredensial yang tidak dapat dibaca: status
      // kegagalan dicatat agar terlihat di halaman setup, bukan hilang diam-diam.
      await configRepository.recordDeliveryStatus(
        status: TelegramDeliveryStatus.failed,
        message:
            'Pengaturan Telegram tidak dapat dibaca sehingga pengiriman '
            'dilewati pada siklus ini.',
      );
      return 0;
    }

    final fingerprint = TelegramConfigRepository.credentialFingerprintFor(
      config.botToken,
      config.chatId,
    );
    final deliveries = await repository.pendingDue(
      householdId: householdId,
      limit: limit,
      now: now,
    );

    var sent = 0;
    for (final delivery in deliveries) {
      if (!await repository.claim(delivery.deliveryId, now: now)) continue;
      final attempt = delivery.attemptCount + 1;

      // Pesan dibuat untuk kredensial lama (token/chat berubah setelah
      // diantrekan) tidak boleh diteruskan ke tujuan baru.
      if (delivery.credentialFingerprint != null &&
          delivery.credentialFingerprint!.isNotEmpty &&
          delivery.credentialFingerprint != fingerprint) {
        await repository.markSkipped(
          delivery.deliveryId,
          reason:
              'Kredensial berubah setelah pesan diantrekan; pesan tidak '
              'dikirim ke kredensial baru.',
          at: now,
        );
        await configRepository.recordDeliveryStatus(
          status: TelegramDeliveryStatus.failed,
          message: 'Kredensial berubah; pesan tertunda dibatalkan.',
        );
        continue;
      }

      if (!config.isReady) {
        await repository.markSkipped(
          delivery.deliveryId,
          reason: 'Integrasi Telegram tidak aktif saat pengiriman.',
          at: now,
        );
        await configRepository.recordDeliveryStatus(
          status: TelegramDeliveryStatus.none,
          message: 'Integrasi Telegram tidak aktif; pengiriman dihentikan.',
        );
        continue;
      }

      final result = await botService.sendMessage(
        botToken: config.botToken,
        chatId: config.chatId,
        text: delivery.messageText,
      );

      if (result.success) {
        await repository.markSent(delivery.deliveryId, sentAt: _clock());
        await _onSent(delivery, now);
        sent++;
      } else {
        await _onFailed(delivery, result, attempt, now);
      }
    }
    return sent;
  }

  Future<void> _onSent(TelegramDelivery delivery, DateTime now) async {
    await configRepository.recordDeliveryStatus(
      status: TelegramDeliveryStatus.sent,
      message: _sentMessageFor(delivery.operation),
    );
    // Pengiriman laporan mingguan menuntaskan klaim dan mencatat waktu
    // terkirim agar evaluasi berikutnya tidak membuat laporan ganda.
    if (delivery.operation == 'weekly.report' &&
        delivery.householdId.isNotEmpty) {
      // ignore: avoid_catches_without_on_clauses
      try {
        await configRepository.saveLastWeeklyReportSent(now);
        await configRepository.completeWeeklyReport(
          periodKey: delivery.householdId,
          now: now,
        );
      } catch (_) {}
    }
  }

  Future<void> _onFailed(
    TelegramDelivery delivery,
    TelegramSendResult result,
    int attempt,
    DateTime now,
  ) async {
    final permanent = _isPermanentFailure(result);
    await repository.markFailed(
      delivery.deliveryId,
      error: result.message,
      retryable: !permanent,
      nextAttemptAt: permanent ? null : now.add(_backoffFor(attempt)),
      attemptCount: attempt,
      maxAttempts: delivery.maxAttempts,
      at: now,
    );
    await configRepository.recordDeliveryStatus(
      status: TelegramDeliveryStatus.failed,
      message: result.message,
    );
  }

  /// Error yang menunjukkan masalah konfigurasi (bukan gangguan sesaat)
  /// dianggap permanen dan tidak diantrekan ulang. 429 (rate limit), 5xx,
  /// timeout, dan masalah jaringan tetap retryable.
  bool _isPermanentFailure(TelegramSendResult result) {
    final code = result.errorCode;
    if (code == null) return false;
    if (code == 429) return false;
    return code < 500;
  }

  Duration _backoffFor(int attempt) {
    final minutes = attempt * 5;
    return Duration(minutes: minutes > 30 ? 30 : minutes);
  }

  String _sentMessageFor(String operation) {
    switch (operation) {
      case 'weekly.report':
        return 'Laporan mingguan terkirim.';
      case 'alert':
        return 'Peringatan radar terkirim.';
      case 'transaction.new':
        return 'Notifikasi transaksi baru terkirim.';
      case 'transaction.edit':
        return 'Notifikasi perubahan transaksi terkirim.';
      default:
        return 'Pesan Telegram terkirim.';
    }
  }
}