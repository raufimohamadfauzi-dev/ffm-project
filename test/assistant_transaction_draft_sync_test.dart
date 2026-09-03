import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/di/injection.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_proposal_json_service.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_form_prefill.dart';
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

    test('Proposal JSON service parses receipt metadata and shopping items', () {
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
    });
  });
}
