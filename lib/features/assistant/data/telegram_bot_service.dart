import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Hasil pengiriman pesan atau uji koneksi ke Telegram Bot API.
class TelegramSendResult {
  const TelegramSendResult({
    required this.success,
    required this.message,
    this.errorCode,
    this.description,
  });

  final bool success;
  final String message;
  final int? errorCode;
  final String? description;
}

/// Service komunikasi HTTP ke Telegram Bot API resmi.
class TelegramBotService {
  TelegramBotService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const Duration _timeoutDuration = Duration(seconds: 15);

  /// Mengirim pesan HTML/teks ke chat atau grup Telegram tertentu.
  Future<TelegramSendResult> sendMessage({
    required String botToken,
    required String chatId,
    required String text,
    String parseMode = 'HTML',
  }) async {
    final cleanToken = botToken.trim();
    final cleanChatId = chatId.trim();

    if (cleanToken.isEmpty) {
      return const TelegramSendResult(
        success: false,
        message: 'Token bot belum diisi.',
      );
    }
    if (cleanChatId.isEmpty) {
      return const TelegramSendResult(
        success: false,
        message: 'Chat ID belum diisi.',
      );
    }

    final url = Uri.parse('https://api.telegram.org/bot$cleanToken/sendMessage');

    try {
      final response = await _client
          .post(
            url,
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode({
              'chat_id': cleanChatId,
              'text': text,
              'parse_mode': parseMode,
              'disable_web_page_preview': true,
            }),
          )
          .timeout(_timeoutDuration);

      if (response.statusCode == 200) {
        return const TelegramSendResult(
          success: true,
          message: 'Pesan berhasil terkirim ke Telegram.',
        );
      }

      // Parsing pesan kegagalan dari respons Telegram API
      try {
        final Map<String, dynamic> body = jsonDecode(response.body);
        final errCode = body['error_code'] as int? ?? response.statusCode;
        final desc = body['description'] as String? ?? 'Terjadi kesalahan.';

        final userFriendlyMsg = _translateError(errCode, desc);
        return TelegramSendResult(
          success: false,
          errorCode: errCode,
          description: desc,
          message: userFriendlyMsg,
        );
      } catch (_) {
        return TelegramSendResult(
          success: false,
          errorCode: response.statusCode,
          message: 'Gagal mengirim pesan (HTTP ${response.statusCode}).',
        );
      }
    } on SocketException {
      return const TelegramSendResult(
        success: false,
        message: 'Koneksi internet tidak tersedia atau gagal terhubung ke Telegram.',
      );
    } on TimeoutException {
      return const TelegramSendResult(
        success: false,
        message: 'Waktu tunggu habis saat menghubungi Telegram (Timeout 15 detik).',
      );
    } catch (e) {
      return TelegramSendResult(
        success: false,
        message: 'Kesalahan tidak terduga: $e',
      );
    }
  }

  /// Menguji koneksi dengan mengirim pesan sambutan verifikasi.
  Future<TelegramSendResult> testConnection({
    required String botToken,
    required String chatId,
    String? familyName,
  }) async {
    final familyGreeting = familyName != null && familyName.trim().isNotEmpty
        ? 'Keluarga <b>${familyName.trim()}</b>'
        : 'Keluarga Anda';

    final testText =
        '🤖 <b>Koneksi Asisten FFM Berhasil!</b>\n\n'
        'Halo! Bot Telegram Asisten Keuangan FFM untuk $familyGreeting telah '
        'berhasil terhubung dan siap mengawal radar keuangan rumah tangga.\n\n'
        '✅ <i>Laporan mingguan & peringatan radar finansial akan dikirimkan ke chat ini.</i>';

    return sendMessage(
      botToken: botToken,
      chatId: chatId,
      text: testText,
    );
  }

  static String _translateError(int code, String description) {
    if (code == 401) {
      return 'Token Bot tidak valid atau salah salin. Periksa kembali token dari @BotFather.';
    }
    if (code == 400 && description.toLowerCase().contains('chat not found')) {
      return 'Chat ID tidak ditemukan. Pastikan Anda sudah menekan tombol "Start" pada bot di Telegram sebelum menguji koneksi.';
    }
    if (code == 403) {
      return 'Bot diblokir oleh pengguna atau belum diizinkan mengirim pesan ke grup.';
    }
    if (code == 429) {
      return 'Terlalu banyak permintaan ke Telegram dalam waktu singkat (Rate Limit). Tunggu sebentar.';
    }
    return 'Gagal terhubung ke Telegram: $description';
  }
}
