import 'package:ffm_manager/features/assistant/data/ffm_assistant_draft_feedback_service.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/assistant/presentation/widgets/ffm_assistant_draft_edit_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

  testWidgets('koreksi transfer menampilkan Rekening Asal dan Tujuan + subtitle', (
    tester,
  ) async {
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
    expect(find.textContaining('Contoh: BCA, Tunai'), findsWidgets);

    await tester.enterText(
      find.widgetWithText(TextField, 'Rekening tujuan'),
      'ShopeePay',
    );
    await tester.tap(find.text('Pakai perubahan'));
    await tester.pumpAndSettle();

    expect(result?.kind, FfmAssistantDraftKind.transfer);
    expect(result?.toAccountName, 'ShopeePay');
    expect(result?.fromAccountName, 'BCA');
  });

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
    expect(find.text('Rekening sumber dana (opsional)'), findsOneWidget);
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
  });
}
