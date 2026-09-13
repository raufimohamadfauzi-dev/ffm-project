import 'dart:convert';

import 'package:ffm_manager/features/assistant/data/ffm_assistant_proposal_json_service.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_planner.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_draft_validator.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/transaction/data/services/receipt_import_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final createdAt = DateTime(2026, 9, 13, 10);

  test('expense JSON -> typed draft -> planner preserves canonical fields', () {
    final result = FfmAssistantProposalJsonService.parse('''
      {
        "formatVersion": "ffm-assistant-proposal-v1",
        "proposal": {
          "type": "transaction",
          "kind": "expense",
          "amount": 104000,
          "account": "BCA",
          "accountId": "account-1",
          "categoryName": "Belanja",
          "categoryId": "category-1",
          "categoryType": "expense",
          "categoryReferenceStatus": "resolved",
          "merchant": "Toko Maju",
          "merchantId": "merchant-1",
          "newMerchant": "Toko Maju Baru",
          "tags": ["dapur", "bulanan"],
          "newTags": "promo",
          "items": [
            {"name": "Beras", "price": 50000, "qty": 2, "subtotal": 100000}
          ],
          "tax": 5000,
          "discount": 1000,
          "paidAmount": 110000,
          "changeAmount": 6000,
          "receiptNumber": "INV-1",
          "receiptRawText": "TOTAL 104000",
          "attachmentPaths": ["/receipt/inv-1.jpg"],
          "source": "receipt_import",
          "sourceId": "source-1",
          "recurringTransactionId": "recurring-1",
          "linkedActivityId": "activity-1",
          "location": "Pasar",
          "date": "2026-09-12T08:30:00"
        }
      }
      ''', createdAt: createdAt);

    expect(result.error, isNull);
    final draft = result.draft!;
    expect(draft.items.single.calculatedTotal, 100000);
    expect(draft.receiptNumber, 'INV-1');
    expect(draft.linkedActivityId, 'activity-1');
    expect(draft.formValues['accountId'], 'account-1');
    expect(FfmAssistantDraftValidator.validate(draft), isEmpty);

    final plan = const FfmAssistantActionPlanner().planFor(
      FfmAssistantIntent(
        rawText: 'catat belanja',
        normalizedText: 'catat belanja',
        type: FfmAssistantIntentType.createExpense,
        draft: draft,
      ),
    )!;
    final parameters = plan.steps
        .firstWhere((step) => step.id == 'save')
        .parameters;
    final item =
        (jsonDecode(parameters['itemsJson']! as String) as List).single as Map;
    expect(parameters, containsPair('tags', 'dapur,bulanan'));
    expect(parameters, containsPair('newTags', 'promo'));
    expect(parameters, containsPair('merchant', 'Toko Maju'));
    expect(parameters, containsPair('newMerchant', 'Toko Maju Baru'));
    expect(parameters, containsPair('receiptNumber', 'INV-1'));
    expect(parameters, containsPair('receiptPaidAmount', 110000));
    expect(parameters, containsPair('receiptChangeAmount', 6000));
    expect(parameters, containsPair('source', 'receipt_import'));
    expect(parameters, containsPair('sourceId', 'source-1'));
    expect(parameters, containsPair('recurringTransactionId', 'recurring-1'));
    expect(parameters, containsPair('linkedActivityId', 'activity-1'));
    expect(parameters['attachmentPaths'], ['/receipt/inv-1.jpg']);
    expect(item['qty'], 2);
    expect(item['price'], 50000);
    expect(item['subtotal'], 100000);
  });

  test('income and transfer aliases preserve account references and date', () {
    for (final entry in <(String, String)>[
      ('income', 'toAccount'),
      ('transfer', 'fromAccount'),
    ]) {
      final accountFields = entry.$1 == 'income'
          ? '"account": "Tunai", "category": "Gaji"'
          : '"fromAccount": "BCA", "toAccount": "Tunai"';
      final result = FfmAssistantProposalJsonService.parse(
        '{"formatVersion":"ffm-assistant-proposal-v1","proposal":'
        '{"type":"transaction","kind":"${entry.$1}","amount":1000,'
        '$accountFields,"date":"2026-09-13"}}',
        createdAt: createdAt,
      );
      final draft = result.draft!;
      final plan = const FfmAssistantActionPlanner().planFor(
        FfmAssistantIntent(
          rawText: entry.$1,
          normalizedText: entry.$1,
          type: entry.$1 == 'income'
              ? FfmAssistantIntentType.createIncome
              : FfmAssistantIntentType.createTransfer,
          draft: draft,
        ),
      )!;
      final parameters = plan.steps
          .firstWhere((step) => step.id == 'save')
          .parameters;
      expect(parameters[entry.$2], isNotEmpty);
      expect(parameters['date'], startsWith('2026-09-13'));
      expect(FfmAssistantDraftValidator.validate(draft), isEmpty);
    }
  });

  test('copyWith preserves unedited Phase 1 canonical fields', () {
    final original = FfmAssistantDraft(
      kind: FfmAssistantDraftKind.expense,
      createdAt: createdAt,
      amount: 100,
      fromAccountName: 'Tunai',
      categoryName: 'Belanja',
      merchantName: 'Warung',
      tags: 'harian',
      newTags: 'baru',
      newMerchant: 'Warung',
      items: const [ReceiptOcrItem(name: 'Item', price: 100)],
      receiptNumber: 'R-1',
      source: 'assistant',
      sourceId: 's-1',
      recurringTransactionId: 'r-1',
      linkedActivityId: 'a-1',
      attachmentPaths: const ['/r.jpg'],
      date: createdAt,
    );

    final edited = original.copyWith(amount: 200);

    expect(edited.amount, 200);
    expect(edited.merchantName, original.merchantName);
    expect(edited.tags, original.tags);
    expect(edited.newTags, original.newTags);
    expect(edited.newMerchant, original.newMerchant);
    expect(edited.items, same(original.items));
    expect(edited.receiptNumber, original.receiptNumber);
    expect(edited.sourceId, original.sourceId);
    expect(edited.recurringTransactionId, original.recurringTransactionId);
    expect(edited.linkedActivityId, original.linkedActivityId);
    expect(edited.attachmentPaths, same(original.attachmentPaths));
    expect(edited.date, original.date);
  });

  test('validator rejects item and receipt formula conflicts', () {
    final draft = FfmAssistantDraft(
      kind: FfmAssistantDraftKind.expense,
      createdAt: createdAt,
      amount: 120,
      fromAccountName: 'Tunai',
      categoryName: 'Belanja',
      date: createdAt,
      items: const [
        ReceiptOcrItem(name: 'Item', price: 50, quantity: 2, lineTotal: 90),
      ],
      tax: 10,
      discount: 5,
      receiptPaidAmount: 130,
      receiptChangeAmount: 5,
    );

    final codes = FfmAssistantDraftValidator.validate(draft)
        .map((issue) => issue.code)
        .toSet();
    expect(codes, contains('receipt_item_invalid'));
    expect(codes, contains('receipt_total_mismatch'));
    expect(codes, contains('receipt_payment_mismatch'));
  });

  test('validator rejects invalid amount, item quantity, and item price', () {
    final issues = FfmAssistantDraftValidator.validate(
      FfmAssistantDraft(
        kind: FfmAssistantDraftKind.expense,
        createdAt: createdAt,
        amount: 0,
        fromAccountName: 'Tunai',
        categoryName: 'Belanja',
        date: createdAt,
        items: const [
          ReceiptOcrItem(name: 'Harga nol', price: 0),
          ReceiptOcrItem(name: 'Jumlah nol', price: 100, quantity: 0),
        ],
      ),
    );
    final codes = issues.map((issue) => issue.code).toList();
    expect(codes, contains('amount_invalid'));
    expect(codes, contains('receipt_item_invalid'));
  });

  test(
    'validator checks date, category type, and available reference status',
    () {
      final issues = FfmAssistantDraftValidator.validate(
        FfmAssistantDraft(
          kind: FfmAssistantDraftKind.income,
          createdAt: createdAt,
          amount: 1000,
          toAccountName: 'Tunai',
          categoryName: 'Gaji',
          formValues: const {
            'categoryType': 'expense',
            'categoryReferenceStatus': 'ambiguous',
            'accountIsArchived': true,
          },
        ),
      );
      final codes = issues.map((issue) => issue.code).toSet();
      expect(codes, contains('transaction_date_required'));
      expect(codes, contains('transaction_category_type_mismatch'));
      expect(codes, contains('transaction_reference_unresolved'));
      expect(codes, contains('transaction_reference_archived'));
    },
  );

  test('parser rejects an impossible transaction calendar date', () {
    final result = FfmAssistantProposalJsonService.parse(
      '{"formatVersion":"ffm-assistant-proposal-v1","proposal":'
      '{"type":"transaction","kind":"expense","amount":1000,'
      '"fromAccount":"Tunai","category":"Belanja","date":"2026-02-30"}}',
      createdAt: createdAt,
    );

    expect(result.draft, isNull);
    expect(result.error, 'Tanggal transaksi tidak valid.');
  });
}
