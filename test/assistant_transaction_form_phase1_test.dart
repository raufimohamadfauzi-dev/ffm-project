import 'package:drift/drift.dart' as drift;
import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/di/injection.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_form_prefill.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/transaction/data/services/receipt_import_models.dart';
import 'package:ffm_manager/features/transaction/domain/entities/transaction_entity.dart';
import 'package:ffm_manager/features/transaction/presentation/pages/transaction_form_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;

  setUp(() async {
    database = createInMemoryDatabaseForTests();
    await configureDependencies(database: database);
    final now = DateTime(2026, 9, 13);
    await database
        .into(database.accounts)
        .insert(
          AccountsCompanion.insert(
            id: 'cash',
            householdId: AppContext.householdId,
            name: 'Kas',
            type: 'cash',
            openingBalance: const drift.Value(1000000),
            createdAt: now,
          ),
        );
    await database
        .into(database.categories)
        .insert(
          CategoriesCompanion.insert(
            id: 'salary',
            householdId: AppContext.householdId,
            name: 'Bonus Tahunan QA',
            type: 'income',
            createdAt: now,
          ),
        );
    await database
        .into(database.categories)
        .insert(
          CategoriesCompanion.insert(
            id: 'shopping',
            householdId: AppContext.householdId,
            name: 'Belanja Salah Tipe QA',
            type: 'expense',
            createdAt: now,
          ),
        );
  });

  tearDown(() async {
    await database.close();
    await getIt.reset();
  });

  Future<ValueNotifier<TransactionDraft?>> openForm(
    WidgetTester tester,
    FfmAssistantDraft draft,
  ) async {
    final result = ValueNotifier<TransactionDraft?>(null);
    addTearDown(result.dispose);
    final prefill = FfmAssistantFormPrefillMapper.fromDraft(draft);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final drafts = await Navigator.of(context)
                  .push<List<TransactionDraft>>(
                    MaterialPageRoute(
                      builder: (_) => TransactionFormPage(
                        initialType: TransactionType.income,
                        initialAmount: draft.amount,
                        initialAccountName: draft.toAccountName,
                        initialCategoryName: draft.categoryName,
                        initialNote: draft.note,
                        initialDate: draft.date,
                        initialPartyName: draft.partyName,
                        initialAttachmentPaths: draft.attachmentPaths,
                        assistantMerchantName: draft.merchantName,
                        assistantPrefill: prefill,
                      ),
                    ),
                  );
              result.value = drafts?.firstOrNull;
            },
            child: const Text('Buka form'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Buka form'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('form income menghasilkan draft dari prefill canonical', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final draft = FfmAssistantDraft(
      kind: FfmAssistantDraftKind.income,
      createdAt: DateTime(2026, 9, 13),
      amount: 500000,
      toAccountName: 'Kas',
      categoryName: 'Bonus Tahunan QA',
      partyName: 'Kantor',
      note: 'Bonus',
      date: DateTime(2026, 9, 12),
      source: 'payroll',
      sourceId: 'pay-1',
      recurringTransactionId: 'rec-1',
      linkedActivityId: 'activity-1',
      receiptNumber: 'R-1',
      receiptPaidAmount: 500000,
      receiptChangeAmount: 0,
      receiptRawText: 'TOTAL 500000',
      items: const [ReceiptOcrItem(name: 'Bonus', price: 500000)],
      attachmentPaths: const ['/receipt/r-1.jpg'],
    );

    final result = await openForm(tester, draft);
    await tester.ensureVisible(find.text('Simpan transaksi'));
    await tester.tap(find.text('Simpan transaksi'));
    await tester.pumpAndSettle();
    await tester.pump();

    expect(result.value?.type, TransactionType.income);
    expect(result.value?.amount, 500000);
    expect(result.value?.accountId, 'cash');
    expect(result.value?.categoryId, 'salary');
    expect(result.value?.partyName, 'Kantor');
    expect(result.value?.source, 'payroll');
    expect(result.value?.sourceId, 'pay-1');
    expect(result.value?.recurringTransactionId, 'rec-1');
    expect(result.value?.linkedActivityId, 'activity-1');
    expect(result.value?.receiptNumber, 'R-1');
    expect(result.value?.receiptPaidAmount, 500000);
    expect(result.value?.receiptChangeAmount, 0);
    expect(result.value?.receiptRawText, 'TOTAL 500000');
    expect(result.value?.items.single.name, 'Bonus');
    expect(result.value?.attachmentPaths, ['/receipt/r-1.jpg']);
  });

  testWidgets('form income tidak memilih kategori expense dengan nama draft', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final draft = FfmAssistantDraft(
      kind: FfmAssistantDraftKind.income,
      createdAt: DateTime(2026, 9, 13),
      amount: 500000,
      toAccountName: 'Kas',
      categoryName: 'Belanja Salah Tipe QA',
      date: DateTime(2026, 9, 12),
    );

    await openForm(tester, draft);
    await tester.ensureVisible(find.text('Simpan transaksi'));
    await tester.tap(find.text('Simpan transaksi'));
    await tester.pumpAndSettle();

    expect(find.text('Pilih kategori dulu.'), findsOneWidget);
    expect(find.text('Tambah pemasukan'), findsOneWidget);
  });
}
