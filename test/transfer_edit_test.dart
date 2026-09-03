import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/di/injection.dart';
import 'package:ffm_manager/features/hijri/domain/hijri_calendar_service.dart';
import 'package:ffm_manager/features/transaction/presentation/widgets/transaction_summary_cards.dart';
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

  final now = DateTime(2026, 9, 3, 10, 0);
  final List<Account> accounts = [
    Account(
      id: 'acc-1',
      householdId: 'house-1',
      name: 'Bank Mandiri',
      type: 'bank',
      openingBalance: 10000000,
      createdAt: now,
      isActive: true,
      isArchived: false,
    ),
    Account(
      id: 'acc-2',
      householdId: 'house-1',
      name: 'Dompet Tunai',
      type: 'cash',
      openingBalance: 2000000,
      createdAt: now,
      isActive: true,
      isArchived: false,
    ),
  ];

  final existingTransfer = Transfer(
    id: 'trf-123',
    householdId: 'house-1',
    fromAccountId: 'acc-1',
    toAccountId: 'acc-2',
    amount: 500000,
    adminFee: 2500,
    feeTransactionId: 'fee-123',
    date: now,
    recordedAt: now,
    note: 'Tarik tunai untuk belanja pasar',
    isDeleted: false,
  );

  testWidgets('TransferFormDialog memuat data existingTransfer dan menampilkan label edit', (tester) async {
    TransferDraft? submittedDraft;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                submittedDraft = await showDialog<TransferDraft>(
                  context: context,
                  builder: (_) => TransferFormDialog(
                    accounts: accounts,
                    existingTransfer: existingTransfer,
                  ),
                );
              },
              child: const Text('Buka Dialog'),
            ),
          ),
        ),
      ),
    );

    // Buka dialog
    await tester.tap(find.text('Buka Dialog'));
    await tester.pumpAndSettle();

    // Verifikasi Judul & Label Edit
    expect(find.text('Edit transfer saldo'), findsOneWidget);
    expect(find.text('Perbarui transfer'), findsOneWidget);

    // Verifikasi Prefill Nilai
    expect(find.text('500000'), findsOneWidget);
    expect(find.text('2500'), findsOneWidget);
    expect(find.text('Tarik tunai untuk belanja pasar'), findsOneWidget);

    // Simpan dialog
    await tester.tap(find.text('Perbarui transfer'));
    await tester.pumpAndSettle();

    expect(submittedDraft, isNotNull);
    expect(submittedDraft!.amount, 500000);
    expect(submittedDraft!.adminFee, 2500);
    expect(submittedDraft!.fromAccountId, 'acc-1');
    expect(submittedDraft!.toAccountId, 'acc-2');
    expect(submittedDraft!.note, 'Tarik tunai untuk belanja pasar');
  });

  testWidgets('TransferHistoryCard menampilkan aksi edit dan memanggil onEdit', (tester) async {
    var editCalled = false;
    var deleteCalled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              TransferHistoryCard(
                transfer: existingTransfer,
                fromLabel: 'Bank Mandiri',
                toLabel: 'Dompet Tunai',
                dateLabel: (d) => '03/09/2026',
                onEdit: () => editCalled = true,
                onDelete: () => deleteCalled = true,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Buka menu konteks
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('Edit transfer'), findsOneWidget);
    expect(find.text('Hapus transfer'), findsOneWidget);

    // Klik Edit
    await tester.tap(find.text('Edit transfer'));
    await tester.pumpAndSettle();

    expect(editCalled, isTrue);
    expect(deleteCalled, isFalse);
  });
}
