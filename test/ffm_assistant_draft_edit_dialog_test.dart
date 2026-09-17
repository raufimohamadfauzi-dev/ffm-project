import 'package:ffm_manager/features/assistant/data/ffm_assistant_draft_feedback_service.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/assistant/presentation/widgets/ffm_assistant_draft_edit_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/features/transaction/data/services/receipt_import_models.dart';
import 'package:ffm_manager/features/reminder/domain/entities/reminder_entity.dart';

void main() {
  testWidgets('koreksi Data Utama hanya menampilkan field yang relevan', (
    tester,
  ) async {
    FfmAssistantDraft? result;
    final draft = FfmAssistantDraft(
      kind: FfmAssistantDraftKind.masterData,
      createdAt: DateTime(2026, 8, 31),
      title: 'BandarPPT1',
      categoryName: 'tag',
      note: 'Buat tag baru',
      formValues: const {'source': 'assistant'},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<FfmAssistantDraft>(
                context: context,
                builder: (_) => FfmAssistantDraftEditDialog(
                  draft: draft,
                  feedbackService: FfmAssistantDraftFeedbackService(),
                ),
              );
            },
            child: const Text('Koreksi'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Koreksi'));
    await tester.pumpAndSettle();

    expect(find.text('Ubah Draft Data Utama'), findsOneWidget);
    expect(find.text('Nama tag'), findsOneWidget);
    expect(find.text('Data Utama: tag'), findsOneWidget);
    expect(find.text('Catatan'), findsOneWidget);
    expect(find.text('Nominal (Rp)'), findsNothing);
    expect(find.text('Rekening asal'), findsNothing);
    expect(find.text('Rekening tujuan'), findsNothing);
    expect(find.text('Kategori'), findsNothing);
    expect(find.text('Target keuangan'), findsNothing);

    await tester.enterText(find.byType(TextField).first, 'BandarPPT2');
    await tester.tap(find.text('Pakai perubahan'));
    await tester.pumpAndSettle();

    expect(result?.kind, FfmAssistantDraftKind.masterData);
    expect(result?.title, 'BandarPPT2');
    expect(result?.categoryName, 'tag');
    expect(result?.formValues, const {'source': 'assistant'});
  });

  testWidgets(
    'koreksi transfer menampilkan Rekening Asal dan Tujuan + subtitle',
    (tester) async {
      FfmAssistantDraft? result;
      final draft = FfmAssistantDraft(
        kind: FfmAssistantDraftKind.transfer,
        createdAt: DateTime(2026, 9, 1),
        amount: 100000,
        fromAccountName: 'BCA',
        toAccountName: 'Tunai',
        note: 'pindah',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<FfmAssistantDraft>(
                  context: context,
                  builder: (_) => FfmAssistantDraftEditDialog(
                    draft: draft,
                    feedbackService: FfmAssistantDraftFeedbackService(),
                    accounts: const ['Tunai', 'BCA', 'ShopeePay'],
                  ),
                );
              },
              child: const Text('Koreksi'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Koreksi'));
      await tester.pumpAndSettle();

      expect(find.text('Jenis draft: Transfer Dana'), findsOneWidget);
      expect(find.text('Rekening asal'), findsOneWidget);
      expect(find.text('Rekening tujuan'), findsOneWidget);
      expect(find.text('Nominal (Rp)'), findsOneWidget);
      expect(find.text('BCA'), findsOneWidget);
      expect(find.text('Tunai'), findsOneWidget);

      await tester.tap(
        find.widgetWithText(
          DropdownButtonFormField<String?>,
          'Rekening tujuan',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('ShopeePay').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pakai perubahan'));
      await tester.pumpAndSettle();

      expect(result?.kind, FfmAssistantDraftKind.transfer);
      expect(result?.toAccountName, 'ShopeePay');
      expect(result?.fromAccountName, 'BCA');
    },
  );

  testWidgets('koreksi goalDeposit menampilkan field Target + subtitle', (
    tester,
  ) async {
    FfmAssistantDraft? result;
    final draft = FfmAssistantDraft(
      kind: FfmAssistantDraftKind.goalDeposit,
      createdAt: DateTime(2026, 9, 1),
      goalName: 'Liburan ke Bali',
      amount: 500000,
      fromAccountName: 'BCA',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<FfmAssistantDraft>(
                context: context,
                builder: (_) => FfmAssistantDraftEditDialog(
                  draft: draft,
                  feedbackService: FfmAssistantDraftFeedbackService(),
                ),
              );
            },
            child: const Text('Koreksi'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Koreksi'));
    await tester.pumpAndSettle();

    expect(find.text('Jenis draft: Setor Target'), findsOneWidget);
    expect(find.text('Target keuangan'), findsOneWidget);
    expect(find.text('Nominal setor (Rp)'), findsOneWidget);
    expect(find.text('Rekening sumber dana'), findsOneWidget);
    // Nama target baru dipakai di judul sehingga tidak diminta field terpisah
    expect(find.text('Rekening tujuan'), findsNothing);

    await tester.enterText(
      find.widgetWithText(TextField, 'Target keuangan'),
      'Dana Darurat',
    );
    await tester.tap(find.text('Pakai perubahan'));
    await tester.pumpAndSettle();

    expect(result?.kind, FfmAssistantDraftKind.goalDeposit);
    expect(result?.goalName, 'Dana Darurat');
    expect(result?.title, 'Setor Target Dana Darurat');
    expect(result?.fromAccountName, 'BCA');
  });

  testWidgets(
    'koreksi pengeluaran memuat tag, menampilkan Tag penanda (wajib), dan Rekening sumber pengeluaran',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      FfmAssistantDraft? result;
      final draft = FfmAssistantDraft(
        kind: FfmAssistantDraftKind.expense,
        createdAt: DateTime(2026, 9, 1),
        title: 'Makan Siang',
        amount: 35000,
        fromAccountName: 'BCA',
        tags: 'kuliner, kantor',
        partyName: 'Naya',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<FfmAssistantDraft>(
                  context: context,
                  builder: (_) => FfmAssistantDraftEditDialog(
                    draft: draft,
                    feedbackService: FfmAssistantDraftFeedbackService(),
                    accounts: const ['BCA', 'Tunai', 'Mandiri'],
                    masterTags: const ['rutin', 'keluarga', 'kuliner'],
                    parties: const ['Naya', 'Aisyah'],
                  ),
                );
              },
              child: const Text('Koreksi'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Koreksi'));
      await tester.pumpAndSettle();

      expect(find.text('Jenis draft: Pengeluaran'), findsOneWidget);
      expect(find.text('Tag penanda (wajib)'), findsOneWidget);
      expect(find.text('Rekening sumber pengeluaran'), findsOneWidget);
      expect(
        find.text('Pengeluaran akan mengurangi saldo rekening ini.'),
        findsOneWidget,
      );
      expect(find.text('Dipakai oleh (opsional)'), findsOneWidget);

      // Verify tag chips: 'kuliner' is in master tags and should be selected
      expect(find.text('#kuliner'), findsOneWidget);
      expect(find.text('#kantor'), findsOneWidget);
      expect(find.text('#rutin'), findsOneWidget);

      // Toggle master tag '#rutin'
      await tester.ensureVisible(find.text('#rutin'));
      await tester.tap(find.text('#rutin'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Pakai perubahan'));
      await tester.tap(find.text('Pakai perubahan'));
      await tester.pumpAndSettle();

      expect(result?.kind, FfmAssistantDraftKind.expense);
      expect(result?.tags, contains('kuliner'));
      expect(result?.tags, contains('kantor'));
      expect(result?.tags, contains('rutin'));
      expect(result?.fromAccountName, 'BCA');
      expect(result?.partyName, 'Naya');
    },
  );

  testWidgets(
    'koreksi pengeluaran menolak simpan jika tag kosong dan menampilkan pesan validasi',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      FfmAssistantDraft? result;
      final draft = FfmAssistantDraft(
        kind: FfmAssistantDraftKind.expense,
        createdAt: DateTime(2026, 9, 1),
        title: 'Bensin Motor',
        amount: 25000,
        fromAccountName: 'Tunai',
        // tags sengaja null / kosong
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showDialog<FfmAssistantDraft>(
                    context: context,
                    builder: (_) => FfmAssistantDraftEditDialog(
                      draft: draft,
                      feedbackService: FfmAssistantDraftFeedbackService(),
                      accounts: const ['Tunai', 'BCA'],
                      masterTags: const ['rutin', 'kendaraan'],
                    ),
                  );
                },
                child: const Text('Koreksi'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Koreksi'));
      await tester.pumpAndSettle();

      // Coba klik Pakai perubahan langsung tanpa tag
      await tester.ensureVisible(find.text('Pakai perubahan'));
      await tester.tap(find.text('Pakai perubahan'));
      await tester.pumpAndSettle();

      // Dialog harus tetap terbuka (result masih null) dan pesan error muncul
      expect(result, isNull);
      expect(
        find.text(
          'Pilih atau tambahkan minimal 1 tag untuk transaksi pengeluaran.',
        ),
        findsOneWidget,
      );

      // Sekarang pilih tag #kendaraan
      await tester.ensureVisible(find.text('#kendaraan'));
      await tester.tap(find.text('#kendaraan'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Pakai perubahan'));
      await tester.tap(find.text('Pakai perubahan'));
      await tester.pumpAndSettle();

      expect(result?.kind, FfmAssistantDraftKind.expense);
      expect(result?.tags, 'kendaraan');
    },
  );

  testWidgets(
    'koreksi pemasukan menampilkan Rekening tujuan pemasukan dan Sumber pemasukan',
    (tester) async {
      FfmAssistantDraft? result;
      final draft = FfmAssistantDraft(
        kind: FfmAssistantDraftKind.income,
        createdAt: DateTime(2026, 9, 1),
        title: 'Gaji Bulanan',
        amount: 5000000,
        toAccountName: 'BCA',
        partyName: 'Kantor',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<FfmAssistantDraft>(
                  context: context,
                  builder: (_) => FfmAssistantDraftEditDialog(
                    draft: draft,
                    feedbackService: FfmAssistantDraftFeedbackService(),
                    accounts: const ['BCA', 'Tunai'],
                    parties: const ['Kantor', 'Bonus'],
                  ),
                );
              },
              child: const Text('Koreksi'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Koreksi'));
      await tester.pumpAndSettle();

      expect(find.text('Jenis draft: Pemasukan'), findsOneWidget);
      expect(find.text('Tags (opsional)'), findsOneWidget);
      expect(find.text('Rekening tujuan pemasukan'), findsOneWidget);
      expect(
        find.text('Pemasukan akan menambah saldo rekening ini.'),
        findsOneWidget,
      );
      expect(find.text('Sumber pemasukan (opsional)'), findsOneWidget);

      await tester.tap(find.text('Pakai perubahan'));
      await tester.pumpAndSettle();

      expect(result?.kind, FfmAssistantDraftKind.income);
      expect(result?.toAccountName, 'BCA');
      expect(result?.partyName, 'Kantor');
    },
  );

  testWidgets('edit nominal mempertahankan semua field canonical transaksi', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    FfmAssistantDraft? result;
    final date = DateTime(2026, 9, 13);
    final draft = FfmAssistantDraft(
      kind: FfmAssistantDraftKind.expense,
      createdAt: date,
      amount: 107500,
      fromAccountName: 'Kas',
      categoryName: 'Belanja',
      merchantName: 'Pasar',
      partyName: 'Ibu',
      date: date,
      tags: 'dapur',
      newTags: 'musiman',
      newMerchant: 'Pasar',
      source: 'receipt_scan',
      sourceId: 'scan-1',
      recurringTransactionId: 'rec-1',
      linkedActivityId: 'activity-1',
      items: const [ReceiptOcrItem(name: 'Beras', price: 100000, quantity: 1)],
      tax: 10000,
      discount: 2500,
      receiptPaidAmount: 110000,
      receiptChangeAmount: 2500,
      receiptNumber: 'N-1',
      receiptRawText: 'TOTAL 107500',
      attachmentPaths: const ['/receipt/n-1.jpg'],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<FfmAssistantDraft>(
                context: context,
                builder: (_) => FfmAssistantDraftEditDialog(
                  draft: draft,
                  feedbackService: FfmAssistantDraftFeedbackService(),
                  accounts: const ['Kas'],
                ),
              );
            },
            child: const Text('Koreksi canonical'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Koreksi canonical'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Nominal (Rp)'),
      '107500',
    );
    await tester.ensureVisible(find.text('Pakai perubahan'));
    await tester.tap(find.text('Pakai perubahan'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result?.source, 'receipt_scan');
    expect(result?.sourceId, 'scan-1');
    expect(result?.recurringTransactionId, 'rec-1');
    expect(result?.linkedActivityId, 'activity-1');
    expect(result?.newTags, 'musiman');
    expect(result?.newMerchant, 'Pasar');
    expect(result?.items.single.name, 'Beras');
    expect(result?.tax, 10000);
    expect(result?.discount, 2500);
    expect(result?.receiptPaidAmount, 110000);
    expect(result?.receiptChangeAmount, 2500);
    expect(result?.receiptNumber, 'N-1');
    expect(result?.receiptRawText, 'TOTAL 107500');
    expect(result?.attachmentPaths, ['/receipt/n-1.jpg']);
  });

  final invalidDraftCases =
      <({String name, FfmAssistantDraft draft, String error})>[
        (
          name: 'rekening transfer sama',
          draft: FfmAssistantDraft(
            kind: FfmAssistantDraftKind.transfer,
            createdAt: DateTime(2026, 9, 13),
            amount: 100000,
            fromAccountName: 'BCA',
            toAccountName: 'BCA',
          ),
          error:
              'Rekening asal dan tujuan sama. Pilih dua rekening yang berbeda.',
        ),
        (
          name: 'item receipt invalid',
          draft: FfmAssistantDraft(
            kind: FfmAssistantDraftKind.expense,
            createdAt: DateTime(2026, 9, 13),
            amount: 10000,
            fromAccountName: 'Kas',
            categoryName: 'Belanja',
            tags: 'dapur',
            items: const [ReceiptOcrItem(name: '', price: 10000)],
          ),
          error: 'Setiap item harus memiliki nama, harga, jumlah, dan total yang valid.',
        ),
        (
          name: 'total pajak tidak cocok',
          draft: FfmAssistantDraft(
            kind: FfmAssistantDraftKind.expense,
            createdAt: DateTime(2026, 9, 13),
            amount: 12000,
            fromAccountName: 'Kas',
            categoryName: 'Belanja',
            tags: 'dapur',
            items: const [ReceiptOcrItem(name: 'Beras', price: 10000)],
            tax: 1000,
          ),
          error: 'Total harus sama dengan subtotal + pajak - diskon.',
        ),
        (
          name: 'dibayar dan kembalian tidak cocok',
          draft: FfmAssistantDraft(
            kind: FfmAssistantDraftKind.expense,
            createdAt: DateTime(2026, 9, 13),
            amount: 10000,
            fromAccountName: 'Kas',
            categoryName: 'Belanja',
            tags: 'dapur',
            receiptPaidAmount: 20000,
            receiptChangeAmount: 5000,
          ),
          error: 'Nominal dibayar dikurangi kembalian harus sama dengan total.',
        ),
      ];

  for (final testCase in invalidDraftCases) {
    testWidgets('menolak ${testCase.name}', (tester) async {
      tester.view.physicalSize = const Size(1080, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      FfmAssistantDraft? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showDialog<FfmAssistantDraft>(
                    context: context,
                    builder: (_) => FfmAssistantDraftEditDialog(
                      draft: testCase.draft,
                      feedbackService: FfmAssistantDraftFeedbackService(),
                      accounts: const ['Kas', 'BCA'],
                    ),
                  );
                },
                child: const Text('Koreksi invalid'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Koreksi invalid'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Pakai perubahan'));
      await tester.tap(find.text('Pakai perubahan'));
      await tester.pumpAndSettle();

      expect(result, isNull);
      expect(find.text(testCase.error), findsOneWidget);
      expect(find.text('Pakai perubahan'), findsOneWidget);
    });
  }

  testWidgets(
    'koreksi pengingat menampilkan field yang setara dengan halaman pengingat dan menyimpan recurrence, mode, serta weekdays',
    (tester) async {
      FfmAssistantDraft? result;
      final futureDate = DateTime.now().add(const Duration(days: 2));
      final draft = FfmAssistantDraft(
        kind: FfmAssistantDraftKind.reminder,
        createdAt: DateTime.now(),
        title: 'Alarm jam 06:00',
        note: 'Minum obat',
        date: futureDate,
        reminderMode: ReminderMode.notification,
        recurrenceType: ReminderRecurrenceType.once,
        weekdays: const [],
        formValues: {
          'reminderMode': 'notification',
          'recurrence': 'once',
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<FfmAssistantDraft>(
                  context: context,
                  builder: (_) => FfmAssistantDraftEditDialog(
                    draft: draft,
                    feedbackService: FfmAssistantDraftFeedbackService(),
                  ),
                );
              },
              child: const Text('Koreksi'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Koreksi'));
      await tester.pumpAndSettle();

      expect(find.text('Ubah draft di chat'), findsOneWidget);
      expect(find.text('Jenis draft: Pengingat / Alarm'), findsOneWidget);
      expect(find.text('Judul pengingat'), findsOneWidget);
      expect(find.text('Catatan tambahan (opsional)'), findsOneWidget);
      expect(find.text('Waktu mulai'), findsOneWidget);
      expect(find.text('Pengulangan'), findsOneWidget);
      expect(find.text('Tipe pengingat'), findsOneWidget);
      expect(find.text('Nada notifikasi'), findsOneWidget);

      // Edit title
      await tester.enterText(
        find.widgetWithText(TextField, 'Judul pengingat'),
        'Alarm Sahur',
      );

      // Tap Pakai perubahan
      await tester.ensureVisible(find.text('Pakai perubahan'));
      await tester.tap(find.text('Pakai perubahan'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result?.title, 'Alarm Sahur');
      expect(result?.note, 'Minum obat');
      expect(result?.reminderMode, ReminderMode.notification);
      expect(result?.recurrenceType, ReminderRecurrenceType.once);
    },
  );

  testWidgets(
    'koreksi pengingat otomatis roll over waktu lampau ke masa depan dan dapat disimpan tanpa error',
    (tester) async {
      FfmAssistantDraft? result;
      // Date in the past (10 hours ago)
      final pastDate = DateTime.now().subtract(const Duration(hours: 10));
      final draft = FfmAssistantDraft(
        kind: FfmAssistantDraftKind.reminder,
        createdAt: DateTime.now(),
        title: 'Alarm jam 06:00',
        note: 'Bangun pagi',
        date: pastDate,
        reminderMode: ReminderMode.alarm,
        recurrenceType: ReminderRecurrenceType.once,
        weekdays: const [],
        formValues: const {
          'reminderMode': 'alarm',
          'mode': 'alarm',
          'recurrence': 'once',
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<FfmAssistantDraft>(
                  context: context,
                  builder: (_) => FfmAssistantDraftEditDialog(
                    draft: draft,
                    feedbackService: FfmAssistantDraftFeedbackService(),
                  ),
                );
              },
              child: const Text('Koreksi'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Koreksi'));
      await tester.pumpAndSettle();

      // Tap Pakai perubahan directly without manual edit
      await tester.ensureVisible(find.text('Pakai perubahan'));
      await tester.tap(find.text('Pakai perubahan'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      // Auto-rolled over to future date
      expect(result!.date!.isAfter(DateTime.now()), isTrue);
      expect(result!.reminderMode, ReminderMode.alarm);
    },
  );
}
