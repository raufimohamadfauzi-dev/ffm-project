import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/di/injection.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_proposal_json_service.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_form_prefill.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_planner.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/hijri/domain/hijri_calendar_service.dart';
import 'package:ffm_manager/features/transaction/presentation/widgets/transfer_form_dialog.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = createInMemoryDatabaseForTests();
    getIt.registerSingleton<HijriCalendarService>(
      HijriCalendarService(database),
    );
  });

  tearDown(() async {
    await getIt.reset();
    await database.close();
  });

  group('Assistant Transaction Draft Sync Tests', () {
    test('Proposal JSON service correctly parses transfer with adminFee', () {
      final json = '''
      {
        "formatVersion": "ffm-assistant-proposal-v1",
        "proposal": {
          "type": "transaction",
          "kind": "transfer",
          "amount": 350000,
          "fromAccount": "BCA",
          "toAccount": "Dompet",
          "adminFee": 2500,
          "note": "Tarik tunai dari ATM"
        }
      }
      ''';

      final result = FfmAssistantProposalJsonService.parse(
        json,
        createdAt: DateTime(2026, 3, 1),
      );

      expect(result.draft, isNotNull);
      final draft = result.draft!;
      expect(draft.kind, FfmAssistantDraftKind.transfer);
      expect(draft.amount, 350000);
      expect(draft.fromAccountName, 'BCA');
      expect(draft.toAccountName, 'Dompet');
      expect(draft.adminFee, 2500);
      expect(draft.note, 'Tarik tunai dari ATM');
    });

    test(
      'Proposal JSON service parses receipt metadata and shopping items',
      () {
        final json = '''
      {
        "formatVersion": "ffm-assistant-proposal-v1",
        "proposal": {
          "type": "transaction",
          "kind": "expense",
          "amount": 75000,
          "category": "Belanja",
          "merchant": "Supermarket",
          "fromAccount": "BCA",
          "receiptNumber": "NOTA-8899",
          "paidAmount": 100000,
          "changeAmount": 25000,
          "items": [
            {"name": "Minyak Goreng 2L", "price": 35000, "qty": 1},
            {"name": "Beras 2.5kg", "price": 40000, "qty": 1}
          ]
        }
      }
      ''';

        final result = FfmAssistantProposalJsonService.parse(
          json,
          createdAt: DateTime(2026, 3, 1),
        );

        expect(result.draft, isNotNull);
        final draft = result.draft!;
        expect(draft.kind, FfmAssistantDraftKind.expense);
        expect(draft.amount, 75000);
        expect(draft.categoryName, 'Belanja');
        expect(draft.merchantName, 'Supermarket');
        expect(draft.formValues['receiptNumber'], 'NOTA-8899');
        expect(draft.formValues['receiptPaidAmount'], '100000');
        expect(draft.formValues['receiptChangeAmount'], '25000');
        expect(draft.formValues['itemsJson'], contains('Minyak Goreng 2L'));

        // Test prefill mapping
        final prefill = FfmAssistantFormPrefillMapper.fromDraft(draft);
        expect(prefill.values['receiptNumber'], 'NOTA-8899');
        expect(prefill.values['receiptPaidAmount'], '100000');
        expect(prefill.values['receiptChangeAmount'], '25000');
        expect(prefill.values['itemsJson'], contains('Beras 2.5kg'));
      },
    );

    test(
      'proposal transaksi lengkap mempertahankan field sampai action plan',
      () {
        final result = FfmAssistantProposalJsonService.parse('''
        {
          "formatVersion": "ffm-assistant-proposal-v1",
          "proposal": {
            "type": "transaction",
            "kind": "expense",
            "amount": 75000,
            "category": "Belanja",
            "merchant": "Supermarket",
            "fromAccount": "BCA",
            "adminFee": 1250,
            "receiptRawText": "TOTAL 75.000",
            "tax": 5000,
            "discount": 2500,
             "location": "Pasar",
             "tags": ["bulanan", "dapur"],
             "newMerchant": "Supermarket Baru",
             "newTags": ["musiman"],
             "sourceId": "source-1",
             "recurringTransactionId": "recurring-1",
             "attachmentPaths": ["/receipts/nota-1.jpg"],
             "note": "Belanja dapur"
          }
        }
        ''', createdAt: DateTime(2026, 3, 1));

        final draft = result.draft!;
        final intent = FfmAssistantIntent(
          rawText: 'catat belanja',
          normalizedText: 'catat belanja',
          type: FfmAssistantIntentType.createExpense,
          draft: draft,
        );
        final plan = const FfmAssistantActionPlanner().planFor(intent)!;
        final parameters = plan.steps
            .firstWhere((step) => step.id == 'save')
            .parameters;

        expect(parameters['amount'], 75000);
        expect(parameters['category'], 'Belanja');
        expect(parameters['fromAccount'], 'BCA');
        expect(parameters['adminFee'], 1250);
        expect(parameters['receiptRawText'], 'TOTAL 75.000');
        expect(parameters['tax'], 5000);
        expect(parameters['discount'], 2500);
        expect(parameters['tags'], 'bulanan,dapur');
        expect(parameters['newTags'], 'musiman');
        expect(parameters['newMerchant'], 'Supermarket Baru');
        expect(parameters['sourceId'], 'source-1');
        expect(parameters['recurringTransactionId'], 'recurring-1');
        expect(parameters['attachmentPathsJson'], contains('nota-1.jpg'));
      },
    );

    test('proposal daily_note menghasilkan draft Catatan Harian', () {
      final result = FfmAssistantProposalJsonService.parse('''
        {
          "formatVersion": "ffm-assistant-proposal-v1",
          "proposal": {
            "type": "daily_note",
            "title": "Panen hari ini",
            "body": "Panen pepaya 100 kg.",
            "noteDate": "2026-03-01T08:00:00.000"
          }
        }
        ''', createdAt: DateTime(2026, 3, 2));

      expect(result.draft, isNotNull);
      expect(result.draft!.kind, FfmAssistantDraftKind.dailyNote);
      expect(result.draft!.title, 'Panen hari ini');
      expect(result.draft!.note, 'Panen pepaya 100 kg.');
      expect(result.draft!.date, DateTime(2026, 3, 1, 8));
    });

    testWidgets('TransferFormDialog prefills adminFee from assistant draft', (
      tester,
    ) async {
      final now = DateTime(2026, 3, 1);
      final draft = FfmAssistantDraft(
        kind: FfmAssistantDraftKind.transfer,
        createdAt: now,
        amount: 200000,
        fromAccountName: 'BCA',
        toAccountName: 'Jago',
        adminFee: 6500,
        note: 'Transfer antar bank',
        source: 'bank_sync',
      );

      final accounts = <Account>[
        Account(
          id: 'acc-1',
          name: 'BCA',
          type: 'bank',
          householdId: 'test-household',
          openingBalance: 1000000,
          isActive: true,
          isArchived: false,
          createdAt: now,
        ),
        Account(
          id: 'acc-2',
          name: 'Jago',
          type: 'bank',
          householdId: 'test-household',
          openingBalance: 500000,
          isActive: true,
          isArchived: false,
          createdAt: now,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TransferFormDialog(accounts: accounts, assistantDraft: draft),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check that amount 200000 and adminFee 6500 are prefilled in the text fields
      expect(find.text('200000'), findsOneWidget);
      expect(find.text('6500'), findsOneWidget);
      expect(find.text('Transfer antar bank'), findsOneWidget);

      await tester.tap(find.text('Simpan transfer'));
      await tester.pumpAndSettle();
      final result = tester.takeException();
      expect(result, isNull);
    });

    testWidgets(
      'TransferFormDialog tidak memilih fallback untuk rekening asing',
      (tester) async {
        final now = DateTime(2026, 3, 1);
        final draft = FfmAssistantDraft(
          kind: FfmAssistantDraftKind.transfer,
          createdAt: now,
          amount: 200000,
          fromAccountName: 'Rekening Tidak Ada',
          toAccountName: 'Jago',
        );
        final accounts = <Account>[
          Account(
            id: 'acc-1',
            name: 'BCA',
            type: 'bank',
            householdId: 'test-household',
            openingBalance: 1000000,
            isActive: true,
            isArchived: false,
            createdAt: now,
          ),
          Account(
            id: 'acc-2',
            name: 'Jago',
            type: 'bank',
            householdId: 'test-household',
            openingBalance: 500000,
            isActive: true,
            isArchived: false,
            createdAt: now,
          ),
        ];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TransferFormDialog(
                accounts: accounts,
                assistantDraft: draft,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.textContaining('rekening asal “Rekening Tidak Ada” belum cocok'),
          findsOneWidget,
        );
        await tester.tap(find.text('Simpan transfer'));
        await tester.pumpAndSettle();
        expect(find.text('Pilih rekening asal.'), findsOneWidget);
      },
    );

    testWidgets('TransferFormDialog menolak referensi rekening ambigu', (
      tester,
    ) async {
      final now = DateTime(2026, 3, 1);
      final draft = FfmAssistantDraft(
        kind: FfmAssistantDraftKind.transfer,
        createdAt: now,
        amount: 200000,
        fromAccountName: 'BCA',
        toAccountName: 'Jago',
      );
      final accounts = <Account>[
        for (final id in ['acc-1', 'acc-2'])
          Account(
            id: id,
            name: 'BCA',
            type: 'bank',
            householdId: 'test-household',
            openingBalance: 1000000,
            isActive: true,
            isArchived: false,
            createdAt: now,
          ),
        Account(
          id: 'acc-3',
          name: 'Jago',
          type: 'bank',
          householdId: 'test-household',
          openingBalance: 500000,
          isActive: true,
          isArchived: false,
          createdAt: now,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TransferFormDialog(accounts: accounts, assistantDraft: draft),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('rekening asal “BCA” cocok dengan lebih dari satu'),
        findsOneWidget,
      );
      await tester.tap(find.text('Simpan transfer'));
      await tester.pumpAndSettle();
      expect(find.text('Pilih rekening asal.'), findsOneWidget);
    });
  });
}
