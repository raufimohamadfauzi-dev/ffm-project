import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_insight_repository.dart';
import 'package:ffm_manager/features/assistant/data/telegram_bot_service.dart';
import 'package:ffm_manager/features/assistant/data/telegram_config_repository.dart';
import 'package:ffm_manager/features/assistant/data/telegram_delivery_processor.dart';
import 'package:ffm_manager/features/assistant/data/telegram_delivery_repository.dart';
import 'package:ffm_manager/features/assistant/domain/autonomous_evaluation_coordinator.dart';
import 'package:ffm_manager/features/transaction/domain/usecases/transaction_crud_usecases.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fixed = DateTime(2026, 9, 9, 9, 0);

  late AppDatabase db;
  late TelegramDeliveryRepository repo;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    db = createInMemoryDatabaseForTests();
    repo = TelegramDeliveryRepository(db, now: () => fixed);
  });

  tearDown(() async {
    await db.close();
  });

  Future<TelegramConfigRepository> configRepo({
    bool enabled = true,
    String botToken = 'BOT',
    String chatId = 'CHAT',
    bool notify = true,
    int minAmount = 1,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final config = TelegramConfigRepository(preferences: prefs);
    await config.saveConfig(
      TelegramConfig(
        botToken: botToken,
        chatId: chatId,
        isEnabled: enabled,
        notifyOnNewTransaction: notify,
        notifyMinAmount: minAmount,
      ),
    );
    return config;
  }

  Future<TelegramDeliveryProcessor> readyProcessor(
    TelegramConfigRepository configRepo, {
    required http.Client client,
    DateTime Function()? clock,
  }) async {
    return TelegramDeliveryProcessor(
      repository: repo,
      botService: TelegramBotService(client: client),
      configRepository: configRepo,
      clock: clock ?? () => fixed,
    );
  }

  http.Response okResponse({Map<String, dynamic>? body, String? text}) =>
      http.Response(
        jsonEncode(
          body ??
              {
                'ok': true,
                'result': {'message_id': 1, 'text': text ?? ''},
              },
        ),
        200,
      );

  group('TelegramDeliveryRepository', () {
    test(
      'enqueue creates a pending row and deduplicates on deliveryId',
      () async {
        final created = await repo.enqueue(
          deliveryId: 'd-1',
          householdId: 'house',
          operation: 'alert',
          messageText: 'pesan',
          createdAt: fixed,
        );
        expect(created, isTrue);

        final dup = await repo.enqueue(
          deliveryId: 'd-1',
          householdId: 'house',
          operation: 'alert',
          messageText: 'pesan',
          createdAt: fixed,
        );
        expect(dup, isFalse);

        final rows = await repo.recentDeliveries(householdId: 'house');
        expect(rows, hasLength(1));
        expect(rows.single.status, 'pending');
        expect(rows.single.retryable, isTrue);
        expect(rows.single.attemptCount, 0);
      },
    );

    test(
      'enqueue deduplicates on dedupeKey even with different deliveryId',
      () async {
        await repo.enqueue(
          deliveryId: 'd-2',
          householdId: 'house',
          operation: 'alert',
          messageText: 'pesan',
          dedupeKey: 'weekly-key',
          createdAt: fixed,
        );
        final conflict = await repo.enqueue(
          deliveryId: 'd-3',
          householdId: 'house',
          operation: 'alert',
          messageText: 'pesan',
          dedupeKey: 'weekly-key',
          createdAt: fixed,
        );
        expect(conflict, isFalse);

        final rows = await repo.recentDeliveries(householdId: 'house');
        expect(rows, hasLength(1));
        expect(rows.single.deliveryId, 'd-2');
      },
    );

    test(
      'pendingDue filters pending/failed retryable and due items, oldest first',
      () async {
        String enqueueAt(DateTime at) {
          var deliveryId = 'p';
          deliveryId += at.microsecondsSinceEpoch.toString();
          return deliveryId;
        }

        await repo.enqueue(
          deliveryId: enqueueAt(fixed),
          householdId: 'house',
          operation: 'alert',
          messageText: '1',
          createdAt: fixed,
        );
        await repo.enqueue(
          deliveryId: enqueueAt(fixed.add(const Duration(minutes: 1))),
          householdId: 'house',
          operation: 'alert',
          messageText: '2',
          createdAt: fixed.add(const Duration(minutes: 1)),
        );
        await repo.enqueue(
          deliveryId: enqueueAt(fixed.add(const Duration(minutes: 2))),
          householdId: 'house',
          operation: 'alert',
          messageText: '3',
          createdAt: fixed.add(const Duration(minutes: 2)),
        );

        // '3' gagal permanen (tidak retryable) -> tidak boleh muncul.
        await repo.markFailed(
          enqueueAt(fixed.add(const Duration(minutes: 2))),
          error: 'permanent',
          retryable: false,
          at: fixed,
        );

        final due = await repo.pendingDue(householdId: 'house', now: fixed);
        expect(due.map((r) => r.messageText), ['1', '2']);

        // Pesan yang belum jatuh tempo tidak dipilih.
        await repo.markFailed(
          enqueueAt(fixed.add(const Duration(minutes: 1))),
          error: 'temporer',
          retryable: true,
          nextAttemptAt: fixed.add(const Duration(minutes: 5)),
          attemptCount: 1,
          maxAttempts: 3,
          at: fixed,
        );
        final afterBackoff = await repo.pendingDue(
          householdId: 'house',
          now: fixed.add(const Duration(minutes: 1)),
        );
        expect(afterBackoff.map((r) => r.messageText), ['1']);

        final afterDue = await repo.pendingDue(
          householdId: 'house',
          now: fixed.add(const Duration(minutes: 6)),
        );
        expect(afterDue.map((r) => r.messageText), ['1', '2']);
      },
    );

    test(
      'claim is atomic: single winner, increments attempt, respects due time',
      () async {
        await repo.enqueue(
          deliveryId: 'c-1',
          householdId: 'house',
          operation: 'alert',
          messageText: 'pesan',
          createdAt: fixed,
        );

        expect(await repo.claim('c-1', now: fixed), isTrue);
        expect(await repo.claim('c-1', now: fixed), isFalse);

        var row = await repo.deliveryById('c-1');
        expect(row!.status, 'processing');
        expect(row.attemptCount, 1);

        // Pesan yang belum jatuh tempo tidak bisa diklaim.
        await repo.markFailed(
          'c-1',
          error: 'temporer',
          retryable: true,
          nextAttemptAt: fixed.add(const Duration(minutes: 4)),
          attemptCount: 1,
          maxAttempts: 3,
          at: fixed,
        );
        expect(await repo.claim('c-1', now: fixed), isFalse);
        expect(
          await repo.claim('c-1', now: fixed.add(const Duration(minutes: 5))),
          isTrue,
        );

        row = await repo.deliveryById('c-1');
        expect(row!.attemptCount, 2);
      },
    );

    test('markSent flips status and disables retry', () async {
      await repo.enqueue(
        deliveryId: 's-1',
        householdId: 'house',
        operation: 'alert',
        messageText: 'pesan',
        createdAt: fixed,
      );
      await repo.claim('s-1', now: fixed);
      await repo.markSent('s-1', sentAt: fixed);

      final row = await repo.deliveryById('s-1');
      expect(row!.status, 'sent');
      expect(row.retryable, isFalse);
      expect(row.sentAt, fixed);
      expect(row.nextAttemptAt, isNull);
      expect(await repo.pendingCount(householdId: 'house'), 0);
    });

    test('markFailed distinguishes permanent and retryable failures', () async {
      await repo.enqueue(
        deliveryId: 'f-1',
        householdId: 'house',
        operation: 'alert',
        messageText: 'pesan',
        createdAt: fixed,
      );
      await repo.claim('f-1', now: fixed);
      await repo.markFailed(
        'f-1',
        error: 'token salah',
        retryable: false,
        at: fixed,
      );

      var row = await repo.deliveryById('f-1');
      expect(row!.status, 'failed');
      expect(row.retryable, isFalse);
      expect(row.nextAttemptAt, isNull);
      expect(row.lastError, 'token salah');

      await repo.enqueue(
        deliveryId: 'f-2',
        householdId: 'house',
        operation: 'alert',
        messageText: 'pesan',
        createdAt: fixed,
      );
      await repo.claim('f-2', now: fixed);
      await repo.markFailed(
        'f-2',
        error: 'timeout',
        retryable: true,
        nextAttemptAt: fixed.add(const Duration(minutes: 5)),
        attemptCount: 1,
        maxAttempts: 3,
        at: fixed,
      );

      row = await repo.deliveryById('f-2');
      expect(row!.retryable, isTrue);
      expect(row.nextAttemptAt, fixed.add(const Duration(minutes: 5)));

      expect(await repo.pendingCount(householdId: 'house'), 1);
    });

    test('markSkipped stops retry without sending', () async {
      await repo.enqueue(
        deliveryId: 'sk-1',
        householdId: 'house',
        operation: 'alert',
        messageText: 'pesan',
        createdAt: fixed,
      );
      await repo.claim('sk-1', now: fixed);
      await repo.markSkipped('sk-1', reason: 'kredensial berubah', at: fixed);

      final row = await repo.deliveryById('sk-1');
      expect(row!.status, 'skipped');
      expect(row.retryable, isFalse);
      expect(await repo.pendingCount(householdId: 'house'), 0);
    });
  });

  group('TelegramDeliveryProcessor', () {
    test('sends a pending delivery and records status when HTTP 200', () async {
      final config = await configRepo();
      final captured = <String>[];
      final processor = await readyProcessor(
        config,
        client: MockClient((req) async {
          captured.add(jsonDecode(req.body)['text'] as String);
          return okResponse();
        }),
      );

      await repo.enqueue(
        deliveryId: 'p-1',
        householdId: 'house',
        operation: 'alert',
        messageText: 'alarm mendekat',
        credentialFingerprint:
            TelegramConfigRepository.credentialFingerprintFor('BOT', 'CHAT'),
        createdAt: fixed,
      );

      final sent = await processor.processPending(householdId: 'house');
      expect(sent, 1);
      expect(captured, ['alarm mendekat']);

      final row = await repo.deliveryById('p-1');
      expect(row!.status, 'sent');
      expect(
        (await config.loadOperationalStatus()).lastDeliveryStatus,
        TelegramDeliveryStatus.sent,
      );
    });

    test('skips deliveries when integration is disabled', () async {
      final config = await configRepo(enabled: false);
      final processor = await readyProcessor(
        config,
        client: MockClient((req) async => okResponse()),
      );

      await repo.enqueue(
        deliveryId: 'off-1',
        householdId: 'house',
        operation: 'alert',
        messageText: 'pesan',
        credentialFingerprint:
            TelegramConfigRepository.credentialFingerprintFor('BOT', 'CHAT'),
        createdAt: fixed,
      );

      final sent = await processor.processPending(householdId: 'house');
      expect(sent, 0);
      final row = await repo.deliveryById('off-1');
      expect(row!.status, 'skipped');
    });

    test('skips deliveries whose credential fingerprint changed', () async {
      final config = await configRepo();
      final processor = await readyProcessor(
        config,
        client: MockClient((req) async => okResponse()),
      );

      await repo.enqueue(
        deliveryId: 'old-1',
        householdId: 'house',
        operation: 'alert',
        messageText: 'pesan lama',
        credentialFingerprint:
            TelegramConfigRepository.credentialFingerprintFor('OLD', 'OLD'),
        createdAt: fixed,
      );

      final sent = await processor.processPending(householdId: 'house');
      expect(sent, 0);
      final row = await repo.deliveryById('old-1');
      expect(row!.status, 'skipped');
      expect(row.retryable, isFalse);
    });

    test('marks 401 as permanent and does not retry', () async {
      final config = await configRepo();
      final processor = await readyProcessor(
        config,
        client: MockClient((req) async {
          return http.Response(
            jsonEncode({
              'ok': false,
              'error_code': 401,
              'description': 'Unauthorized',
            }),
            401,
          );
        }),
      );

      await repo.enqueue(
        deliveryId: 'perm-1',
        householdId: 'house',
        operation: 'alert',
        messageText: 'pesan',
        credentialFingerprint:
            TelegramConfigRepository.credentialFingerprintFor('BOT', 'CHAT'),
        createdAt: fixed,
      );

      final sent = await processor.processPending(householdId: 'house');
      expect(sent, 0);
      final row = await repo.deliveryById('perm-1');
      expect(row!.status, 'failed');
      expect(row.retryable, isFalse);
      expect(row.nextAttemptAt, isNull);
      expect(row.lastError, isNotEmpty);
    });

    test('marks 5xx as retryable with exponential backoff', () async {
      final config = await configRepo();
      final processor = await readyProcessor(
        config,
        client: MockClient((req) async => http.Response('server error', 500)),
      );

      await repo.enqueue(
        deliveryId: 'retry-1',
        householdId: 'house',
        operation: 'alert',
        messageText: 'pesan',
        credentialFingerprint:
            TelegramConfigRepository.credentialFingerprintFor('BOT', 'CHAT'),
        createdAt: fixed,
      );

      final sent = await processor.processPending(householdId: 'house');
      expect(sent, 0);
      final row = await repo.deliveryById('retry-1');
      expect(row!.status, 'failed');
      expect(row.retryable, isTrue);
      expect(row.nextAttemptAt, fixed.add(const Duration(minutes: 5)));
      expect(row.lastError, isNotEmpty);
    });

    test(
      'sent weekly.report completes the weekly claim and records sent time',
      () async {
        final config = await configRepo();
        final processor = await readyProcessor(
          config,
          client: MockClient((req) async => okResponse()),
        );

        await repo.enqueue(
          deliveryId: 'weekly-1',
          householdId: 'house',
          operation: 'weekly.report',
          messageText: 'Laporan mingguan',
          entityId: 'period-1',
          credentialFingerprint:
              TelegramConfigRepository.credentialFingerprintFor('BOT', 'CHAT'),
          createdAt: fixed,
        );

        final sent = await processor.processPending(householdId: 'house');
        expect(sent, 1);
        expect(await config.loadLastWeeklyReportSent(), fixed);

        final row = await repo.deliveryById('weekly-1');
        expect(row!.status, 'sent');
      },
    );
  });

  group('Durable transaction notification', () {
    test('saving a transaction enqueues a durable notification row', () async {
      final config = await configRepo();
      final usecase = SaveTransaction(
        db,
        telegramConfigRepository: config,
        telegramDeliveryRepository: repo,
      );

      await usecase(
        TransactionEntity(
          id: 'tx-1',
          householdId: 'house',
          date: fixed,
          categoryId: null,
          amount: 120000,
          owner: 'Naya',
          recordedAt: fixed,
          updatedAt: fixed,
        ),
      );

      final rows = await repo.recentDeliveries(householdId: 'house', limit: 10);
      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row.operation, 'transaction.new');
      expect(row.status, 'pending');
      expect(row.entityId, 'tx-1');
      expect(
        row.dedupeKey,
        'telegram:transaction:tx-1:${fixed.microsecondsSinceEpoch}',
      );
      expect(
        row.credentialFingerprint,
        TelegramConfigRepository.credentialFingerprintFor('BOT', 'CHAT'),
      );
    });

    test('saving a transaction processes the Telegram queue immediately when wired', () async {
      final config = await configRepo();
      var requests = 0;
      final processor = await readyProcessor(
        config,
        client: MockClient((request) async {
          requests++;
          return okResponse();
        }),
      );
      final usecase = SaveTransaction(
        db,
        telegramConfigRepository: config,
        telegramDeliveryRepository: repo,
        telegramDeliveryProcessor: processor,
      );

      await usecase(
        TransactionEntity(
          id: 'tx-immediate',
          householdId: 'house',
          date: fixed,
          categoryId: null,
          amount: 120000,
          owner: 'Naya',
          recordedAt: fixed,
          updatedAt: fixed,
        ),
      );

      expect(requests, 1);
      expect(
        (await repo.recentDeliveries(householdId: 'house')).single.status,
        'sent',
      );
    });

    test(
      're-saving the same transaction stamps does not duplicate the message',
      () async {
        final config = await configRepo();
        final usecase = SaveTransaction(
          db,
          telegramConfigRepository: config,
          telegramDeliveryRepository: repo,
        );
        final entity = TransactionEntity(
          id: 'tx-2',
          householdId: 'house',
          date: fixed,
          categoryId: null,
          amount: 80000,
          owner: 'Naya',
          recordedAt: fixed,
          updatedAt: fixed,
        );

        await usecase(entity);
        await usecase(entity);

        expect(await repo.pendingCount(householdId: 'house'), 1);
      },
    );

    test(
      'edit stamps produce a transaction.edit message while keeps the old one',
      () async {
        final config = await configRepo();
        final usecase = SaveTransaction(
          db,
          telegramConfigRepository: config,
          telegramDeliveryRepository: repo,
        );
        final entity = TransactionEntity(
          id: 'tx-3',
          householdId: 'house',
          date: fixed,
          categoryId: null,
          amount: 90000,
          owner: 'Naya',
          recordedAt: fixed,
          updatedAt: fixed,
        );

        await usecase(entity);
        final edited = entity.copyWith(
          amount: 95000,
          updatedAt: fixed.add(const Duration(minutes: 1)),
        );
        await usecase(edited);

        final rows = await repo.recentDeliveries(
          householdId: 'house',
          limit: 10,
        );
        expect(rows, hasLength(2));
        expect(rows.map((r) => r.operation).toSet(), {
          'transaction.new',
          'transaction.edit',
        });
        expect(
          rows.firstWhere((r) => r.operation == 'transaction.edit').entityId,
          'tx-3',
        );
      },
    );

    test('transactions below the notify threshold are not enqueued', () async {
      final config = await configRepo(minAmount: 50000);
      final usecase = SaveTransaction(
        db,
        telegramConfigRepository: config,
        telegramDeliveryRepository: repo,
      );

      await usecase(
        TransactionEntity(
          id: 'tx-small',
          householdId: 'house',
          date: fixed,
          categoryId: null,
          amount: 5000,
          owner: 'Naya',
          recordedAt: fixed,
          updatedAt: fixed,
        ),
      );

      expect(await repo.pendingCount(householdId: 'house'), 0);
    });

    test(
      'notifications stay disabled when notifyOnNewTransaction is off',
      () async {
        final config = await configRepo(notify: false);
        final usecase = SaveTransaction(
          db,
          telegramConfigRepository: config,
          telegramDeliveryRepository: repo,
        );

        await usecase(
          TransactionEntity(
            id: 'tx-no-notify',
            householdId: 'house',
            date: fixed,
            categoryId: null,
            amount: 100000,
            owner: 'Naya',
            recordedAt: fixed,
            updatedAt: fixed,
          ),
        );

        expect(await repo.pendingCount(householdId: 'house'), 0);
      },
    );
  });

  group('Coordinator durable weekly report', () {
    test('uses the outbox and returns success when delivery is sent', () async {
      final config = await configRepo();
      var sentText = '';
      final processor = await readyProcessor(
        config,
        client: MockClient((req) async {
          sentText = jsonDecode(req.body)['text'] as String;
          return okResponse();
        }),
      );

      final coordinator = AutonomousEvaluationCoordinator(
        database: db,
        insightRepository: FfmAssistantInsightRepository(
          db,
          clock: () => fixed,
        ),
        clock: () => fixed,
        telegramBotService: TelegramBotService(
          client: MockClient((req) async => okResponse()),
        ),
        telegramConfigRepository: config,
        telegramDeliveryRepository: repo,
        telegramDeliveryProcessor: processor,
      );

      final success = await coordinator.checkAndSendWeeklyReport(
        householdId: 'house-weekly',
        force: true,
      );

      expect(success, isTrue);
      expect(sentText, contains('Laporan Keuangan Mingguan'));
      expect(await config.loadLastWeeklyReportSent(), fixed);

      final rows = await repo.recentDeliveries(
        householdId: 'house-weekly',
        limit: 10,
      );
      expect(rows, hasLength(1));
      expect(rows.single.operation, 'weekly.report');
      expect(rows.single.status, 'sent');
    });

    test(
      'returns false and keeps the row failed when Telegram rejects',
      () async {
        final config = await configRepo();
        final processor = await readyProcessor(
          config,
          client: MockClient((req) async {
            return http.Response(
              jsonEncode({
                'ok': false,
                'error_code': 400,
                'description': 'Bad Request',
              }),
              400,
            );
          }),
        );

        final coordinator = AutonomousEvaluationCoordinator(
          database: db,
          insightRepository: FfmAssistantInsightRepository(
            db,
            clock: () => fixed,
          ),
          clock: () => fixed,
          telegramBotService: TelegramBotService(
            client: MockClient((req) async => okResponse()),
          ),
          telegramConfigRepository: config,
          telegramDeliveryRepository: repo,
          telegramDeliveryProcessor: processor,
        );

        final success = await coordinator.checkAndSendWeeklyReport(
          householdId: 'house-fail',
          force: true,
        );

        expect(success, isFalse);
        final rows = await repo.recentDeliveries(
          householdId: 'house-fail',
          limit: 10,
        );
        expect(rows, hasLength(1));
        expect(rows.single.operation, 'weekly.report');
        expect(rows.single.status, 'failed');
        expect(rows.single.retryable, isFalse);
      },
    );
  });

  group('Credential fingerprint', () {
    test(
      'recordVerificationResult stores fingerprint only on success',
      () async {
        SharedPreferences.setMockInitialValues({});
        final config = await configRepo();

        await config.recordVerificationResult(
          ok: true,
          at: fixed,
          botToken: 'BOT',
          chatId: 'CHAT',
        );
        var status = await config.loadOperationalStatus();
        expect(status.lastVerifiedOk, isTrue);
        expect(
          status.verificationFingerprint,
          TelegramConfigRepository.credentialFingerprintFor('BOT', 'CHAT'),
        );

        // Kredensial berubah + uji gagal -> fingerprint dibersihkan.
        await config.recordVerificationResult(
          ok: false,
          at: fixed.add(const Duration(minutes: 1)),
          botToken: 'NEW_TOKEN',
          chatId: 'CHAT',
        );
        status = await config.loadOperationalStatus();
        expect(status.lastVerifiedOk, isFalse);
        expect(status.verificationFingerprint, isNull);
      },
    );

    test('clearConfig removes the fingerprint', () async {
      SharedPreferences.setMockInitialValues({});
      final config = await configRepo();
      await config.recordVerificationResult(
        ok: true,
        at: fixed,
        botToken: 'BOT',
        chatId: 'CHAT',
      );

      await config.clearConfig();

      final status = await config.loadOperationalStatus();
      expect(status.verificationFingerprint, isNull);
    });
  });
}
