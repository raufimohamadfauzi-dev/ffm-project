import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:ffm_manager/features/assistant/data/telegram_bot_service.dart';
import 'package:ffm_manager/features/assistant/data/telegram_config_repository.dart';
import 'package:ffm_manager/features/assistant/data/telegram_message_formatter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TelegramMessageFormatter Tests', () {
    test('formatWeeklyReport generates formatted Indonesian HTML with family names', () {
      final html = TelegramMessageFormatter.formatWeeklyReport(
        familyName: 'Makmur',
        husbandName: 'Raufi',
        wifeName: 'Naya',
        totalExpense: 1750000,
        totalIncome: 3500000,
        topExpenseCategory: 'Operasional Kebun',
        topExpenseAmount: 850000,
        cashBalance: 6200000,
        healthScore: 85,
        headline: 'Arus kas sehat dan cadangan operasional aman.',
      );

      expect(html, contains('Keluarga <b>Makmur</b>'));
      expect(html, contains('Halo Bapak Raufi & Ibu Naya'));
      expect(html, contains('Rp 1.750.000'));
      expect(html, contains('Rp 3.500.000'));
      expect(html, contains('Operasional Kebun'));
      expect(html, contains('Rp 850.000'));
      expect(html, contains('Rp 6.200.000'));
      expect(html, contains('85/100'));
      expect(html, contains('Arus kas sehat dan cadangan operasional aman.'));
    });

    test('formatAlertMessage produces clean alert layout with recommendations', () {
      final alert = TelegramMessageFormatter.formatAlertMessage(
        title: 'Lonjakan Belanja Pupuk',
        summary: 'Pengeluaran pupuk minggu ini melebihi 150% dari rata-rata.',
        recommendation: 'Tinjau kembali stok gudang sebelum pembelian berikutnya.',
      );

      expect(alert, contains('⚠️ <b>Peringatan Radar Asisten FFM</b>'));
      expect(alert, contains('Lonjakan Belanja Pupuk'));
      expect(alert, contains('melebihi 150%'));
      expect(alert, contains('Saran: Tinjau kembali stok gudang'));
    });

    test('formatNewTransactionMessage formats expense and income notifications properly', () {
      final expenseMsg = TelegramMessageFormatter.formatNewTransactionMessage(
        type: 'expense',
        amount: 350000,
        categoryOrDescription: 'Pupuk NPK 50kg',
        categoryName: 'Operasional Kebun',
        accountName: 'Rekening BCA',
        recordedBy: 'Bapak',
        transactionDate: DateTime(2026, 9, 4, 14, 30),
      );

      expect(expenseMsg, contains('🛒 <b>Catatan Pengeluaran Baru</b>'));
      expect(expenseMsg, contains('Rp 350.000'));
      expect(expenseMsg, contains('Operasional Kebun'));
      expect(expenseMsg, contains('Pupuk NPK 50kg'));
      expect(expenseMsg, contains('Rekening BCA'));
      expect(expenseMsg, contains('Bapak'));
      expect(expenseMsg, contains('Waktu:'));

      final incomeMsg = TelegramMessageFormatter.formatNewTransactionMessage(
        type: 'income',
        amount: 5000000,
        categoryOrDescription: 'Penjualan Jagung',
        accountName: 'Rekening BRI',
      );

      expect(incomeMsg, contains('💰 <b>Pemasukan Baru Masuk</b>'));
      expect(incomeMsg, contains('Rp 5.000.000'));
      expect(incomeMsg, contains('Penjualan Jagung'));
      expect(incomeMsg, contains('Rekening BRI'));
    });
  });

  group('TelegramConfigRepository Tests', () {
    late TelegramConfigRepository repository;
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      FlutterSecureStorage.setMockInitialValues({});
      repository = TelegramConfigRepository(
        preferences: prefs,
      );
    });

    test('default configuration is unconfigured and disabled', () async {
      final config = await repository.loadConfig();
      expect(config.botToken, isEmpty);
      expect(config.chatId, isEmpty);
      expect(config.isEnabled, isFalse);
      expect(config.isConfigured, isFalse);
      expect(config.isReady, isFalse);
    });

    test('saveConfig persists tokens and preferences correctly', () async {
      const config = TelegramConfig(
        botToken: '123456:ABC-DEF-XYZ',
        chatId: '-100987654321',
        isEnabled: true,
        weeklyReportEnabled: true,
        alertsEnabled: false,
        notifyOnNewTransaction: true,
        notifyMinAmount: 75000,
      );

      await repository.saveConfig(config);

      final loaded = await repository.loadConfig();
      expect(loaded.botToken, equals('123456:ABC-DEF-XYZ'));
      expect(loaded.chatId, equals('-100987654321'));
      expect(loaded.isEnabled, isTrue);
      expect(loaded.weeklyReportEnabled, isTrue);
      expect(loaded.alertsEnabled, isFalse);
      expect(loaded.notifyOnNewTransaction, isTrue);
      expect(loaded.notifyMinAmount, equals(75000));
      expect(loaded.isConfigured, isTrue);
      expect(loaded.isReady, isTrue);
    });

    test('lastWeeklyReportSent can be saved and loaded accurately', () async {
      expect(await repository.loadLastWeeklyReportSent(), isNull);

      final now = DateTime(2026, 9, 4, 15, 0, 0);
      await repository.saveLastWeeklyReportSent(now);

      final loaded = await repository.loadLastWeeklyReportSent();
      expect(loaded, isNotNull);
      expect(loaded!.year, equals(2026));
      expect(loaded.month, equals(9));
      expect(loaded.day, equals(4));
    });

    test('clearConfig wipes stored credentials and tracking data', () async {
      await repository.saveConfig(const TelegramConfig(
        botToken: 'token123',
        chatId: 'chat456',
        isEnabled: true,
      ));
      await repository.saveLastWeeklyReportSent(DateTime.now());

      await repository.clearConfig();

      final reloaded = await repository.loadConfig();
      expect(reloaded.botToken, isEmpty);
      expect(reloaded.chatId, isEmpty);
      expect(reloaded.isEnabled, isFalse);
      expect(await repository.loadLastWeeklyReportSent(), isNull);
    });
  });

  group('TelegramBotService Tests with Mock HTTP Client', () {
    test('sendMessage returns success when Telegram returns HTTP 200', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.toString(), contains('api.telegram.org/botMY_TOKEN/sendMessage'));
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['chat_id'], equals('12345'));
        expect(body['text'], equals('Halo dunia'));
        expect(body['parse_mode'], equals('HTML'));

        return http.Response(jsonEncode({'ok': true, 'result': {'message_id': 1}}), 200);
      });

      final service = TelegramBotService(client: mockClient);
      final result = await service.sendMessage(
        botToken: 'MY_TOKEN',
        chatId: '12345',
        text: 'Halo dunia',
      );

      expect(result.success, isTrue);
      expect(result.message, contains('berhasil terkirim'));
    });

    test('sendMessage translates 401 Unauthorized to user-friendly Indonesian error', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'ok': false,
            'error_code': 401,
            'description': 'Unauthorized',
          }),
          401,
        );
      });

      final service = TelegramBotService(client: mockClient);
      final result = await service.sendMessage(
        botToken: 'BAD_TOKEN',
        chatId: '12345',
        text: 'Halo',
      );

      expect(result.success, isFalse);
      expect(result.errorCode, equals(401));
      expect(result.message, contains('Token Bot tidak valid'));
    });

    test('sendMessage translates 400 Chat Not Found to helpful instruction', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'ok': false,
            'error_code': 400,
            'description': 'Bad Request: chat not found',
          }),
          400,
        );
      });

      final service = TelegramBotService(client: mockClient);
      final result = await service.sendMessage(
        botToken: 'MY_TOKEN',
        chatId: 'INVALID_CHAT',
        text: 'Halo',
      );

      expect(result.success, isFalse);
      expect(result.errorCode, equals(400));
      expect(result.message, contains('Chat ID tidak ditemukan'));
      expect(result.message, contains('Start'));
    });

    test('sendMessage rejects empty token or chat ID without sending HTTP request', () async {
      var requestSent = false;
      final mockClient = MockClient((request) async {
        requestSent = true;
        return http.Response('', 200);
      });

      final service = TelegramBotService(client: mockClient);

      final r1 = await service.sendMessage(botToken: '', chatId: '12345', text: 'Test');
      expect(r1.success, isFalse);
      expect(r1.message, contains('Token bot belum diisi'));

      final r2 = await service.sendMessage(botToken: 'TOKEN', chatId: '', text: 'Test');
      expect(r2.success, isFalse);
      expect(r2.message, contains('Chat ID belum diisi'));

      expect(requestSent, isFalse);
    });

    test('testConnection constructs greeting and sends to Telegram', () async {
      var sentText = '';
      final mockClient = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        sentText = body['text'] as String;
        return http.Response(jsonEncode({'ok': true}), 200);
      });

      final service = TelegramBotService(client: mockClient);
      final res = await service.testConnection(
        botToken: 'TOKEN',
        chatId: '12345',
        familyName: 'Fauzi',
      );

      expect(res.success, isTrue);
      expect(sentText, contains('Keluarga <b>Fauzi</b>'));
      expect(sentText, contains('Koneksi Asisten FFM Berhasil!'));
    });
  });
}
