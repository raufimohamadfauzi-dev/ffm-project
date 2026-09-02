// ignore: unused_import
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_financial_snapshot_service.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_proposal_json_service.dart';
import 'package:ffm_manager/features/assistant/data/ffm_gemini_read_capability_service.dart';
import 'package:ffm_manager/features/hijri/domain/hijri_calendar_service.dart';

void main() {
  late AppDatabase database;
  late FfmAssistantFinancialSnapshotService snapshot;
  late FfmGeminiReadCapabilityService readService;

  setUp(() {
    database = createInMemoryDatabaseForTests();
    snapshot = FfmAssistantFinancialSnapshotService(
      database,
      HijriCalendarService(database),
    );
    readService = FfmGeminiReadCapabilityService(snapshot);
  });

  tearDown(() async {
    await database.close();
  });

  group('Promoted capabilities allowlist & schema', () {
    test('allowlist hanya read.summary dan read.transactions', () {
      expect(
        FfmAssistantProposalJsonService.geminiReadCapabilityIds,
        contains('read.summary'),
      );
      expect(
        FfmAssistantProposalJsonService.geminiReadCapabilityIds,
        contains('read.transactions'),
      );
      expect(
        FfmAssistantProposalJsonService.geminiReadCapabilityIds,
        contains('read.assets'),
      );
      expect(
        FfmAssistantProposalJsonService.geminiReadCapabilityIds,
        contains('read.budget'),
      );
      expect(
        FfmAssistantProposalJsonService.geminiReadCapabilityIds,
        isNot(contains('read.accounts')),
      );

      const blocked = [
        'read.accounts',
        'read.categories',
      ];
      for (final id in blocked) {
        final parsed = FfmAssistantProposalJsonService.parseReadCapabilityRequest(
          '{"formatVersion":"ffm-assistant-capability-request-v1","kind":"read_capability_request","capabilityId":"$id","arguments":{}}',
        );
        expect(parsed.request, isNull, reason: id);
        expect(parsed.error, isNotNull, reason: id);
      }
    });

    test('read.summary evidence bounded, privacy, wording', () async {
      final now = DateTime(2026, 8, 15);
      await database
          .into(database.transactions)
          .insert(
            TransactionsCompanion.insert(
              id: 'inc-1',
              householdId: AppContext.householdId,
              type: 'income',
              amount: 5000000,
              date: now,
              recordedAt: now,
              createdAt: now,
            ),
          );
      final request =
          FfmAssistantProposalJsonService.parseReadCapabilityRequest(
            '{"formatVersion":"ffm-assistant-capability-request-v1","kind":"read_capability_request","capabilityId":"read.summary","arguments":{}}',
          ).request!;
      final evidence = await readService.execute(
        request,
        householdId: AppContext.householdId,
        now: now,
      );

      expect(evidence, contains('income=5000000'));
      expect(evidence, contains('quality='));
      expect(evidence, contains('Financial snapshot'));
      expect(evidence.length, lessThan(800));
      expect(evidence, isNot(contains('inc-1'))); // no raw ID
      expect(evidence, isNot(contains('merchant')));
    });

    test('read.transactions max 8, privacy, bounded', () async {
      final now = DateTime(2026, 8, 15);
      for (var i = 0; i < 12; i++) {
        await database
            .into(database.transactions)
            .insert(
              TransactionsCompanion.insert(
                id: 'tx-$i',
                householdId: AppContext.householdId,
                type: i.isEven ? 'income' : 'expense',
                amount: 100000 + i * 1000,
                date: now.subtract(Duration(days: i)),
                recordedAt: now,
                createdAt: now,
              ),
            );
      }
      final parsed = FfmAssistantProposalJsonService.parseReadCapabilityRequest(
        '{"formatVersion":"ffm-assistant-capability-request-v1","kind":"read_capability_request","capabilityId":"read.transactions","arguments":{"startDate":"2026-08-10","endDate":"2026-08-15"}}',
      );
      expect(parsed.error, isNull);
      final evidence = await readService.execute(
        parsed.request!,
        householdId: AppContext.householdId,
        now: now,
      );

      expect(evidence, contains('Transaction digest'));
      expect(evidence, isNot(contains('tx-0'))); // no ID
      expect(
        evidence,
        contains(
          'Detail merchant, catatan, rekening, kategori, dan ID tidak tersedia',
        ),
      );
      expect(evidence, isNot(contains('merchant=')));
      expect(evidence, isNot(contains('kategori=')));
      // Max 8 items: count ';' separators should be <=7 or evidence contains at most 8 dates
      final dateMatches = RegExp(r'\d{4}-\d{2}-\d{2}')
          .allMatches(evidence)
          .length;
      expect(dateMatches, lessThanOrEqualTo(8));
    });

    test('read.transactions arg validation: range, bulan, 14 hari', () async {
      final now = DateTime(2026, 8, 15);
      // Rentang >14 hari ditolak di parser
      final tooLong =
          FfmAssistantProposalJsonService.parseReadCapabilityRequest(
            '{"formatVersion":"ffm-assistant-capability-request-v1","kind":"read_capability_request","capabilityId":"read.transactions","arguments":{"startDate":"2026-08-01","endDate":"2026-08-20"}}',
          );
      expect(tooLong.error, isNotNull);
      expect(tooLong.request, isNull);

      // Di luar bulan berjalan ditolak di executor (parser lolos)
      final outOfMonth =
          FfmAssistantProposalJsonService.parseReadCapabilityRequest(
            '{"formatVersion":"ffm-assistant-capability-request-v1","kind":"read_capability_request","capabilityId":"read.transactions","arguments":{"startDate":"2026-07-01","endDate":"2026-07-10"}}',
          ).request!;
      expect(
        () => readService.execute(
          outOfMonth,
          householdId: AppContext.householdId,
          now: now,
        ),
        throwsA(isA<StateError>()),
      );

      // Half range (hanya start) ditolak di parser
      final half = FfmAssistantProposalJsonService.parseReadCapabilityRequest(
        '{"formatVersion":"ffm-assistant-capability-request-v1","kind":"read_capability_request","capabilityId":"read.transactions","arguments":{"startDate":"2026-08-10"}}',
      );
      expect(half.error, isNotNull);
      expect(half.request, isNull);
    });

    test('read.transactions tanpa argumen mengambil seluruh bulan', () async {
      final now = DateTime(2026, 8, 15);
      final parsed = FfmAssistantProposalJsonService.parseReadCapabilityRequest(
        '{"formatVersion":"ffm-assistant-capability-request-v1","kind":"read_capability_request","capabilityId":"read.transactions","arguments":{}}',
      ).request!;
      final evidence = await readService.execute(
        parsed,
        householdId: AppContext.householdId,
        now: now,
      );
      expect(evidence, contains('Transaction digest'));
      expect(evidence, contains('rentang=seluruh_bulan'));
    });

    test(
      'evidence wording second call tidak bocorkan capability lain',
      () async {
        final now = DateTime(2026, 8, 15);
        final request =
            FfmAssistantProposalJsonService.parseReadCapabilityRequest(
              '{"formatVersion":"ffm-assistant-capability-request-v1","kind":"read_capability_request","capabilityId":"read.summary","arguments":{}}',
            ).request!;
        final evidence = await readService.execute(
          request,
          householdId: AppContext.householdId,
          now: now,
        );
        // Wording harus authoritative dan bounded
        expect(evidence, contains('Financial snapshot lokal bounded'));
        expect(evidence, isNot(contains('read.accounts')));
        expect(evidence, isNot(contains('SELECT')));
      },
    );
  });
}
