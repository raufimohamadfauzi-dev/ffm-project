import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_plan.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_budget_habit_proposal.dart';
import 'package:ffm_manager/features/assistant/presentation/widgets/chat/ffm_assistant_message_card.dart';
import 'package:ffm_manager/features/assistant/presentation/widgets/chat/ffm_budget_habit_proposal_preview.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets(
    'metadata waktu dan model tersembunyi dan muncul saat bubble ditekan',
    (tester) async {
      final entry = FfmAssistantChatEntry(
        isUser: false,
        text: 'Jawaban asisten.',
        sentAt: DateTime(2026, 9, 5, 9, 12, 5),
        receivedAt: DateTime(2026, 9, 5, 9, 12, 9),
        modelUsed: 'gemini-cloud',
      );

      await tester.pumpWidget(
        _wrap(
          FfmAssistantMessageCard(
            entry: entry,
            isSpeaking: false,
            teachingSaved: false,
            activityConfirmed: false,
          ),
        ),
      );

      expect(find.textContaining('Kirim 09:12:05'), findsNothing);
      expect(find.textContaining('Terima 09:12:09'), findsNothing);
      expect(find.textContaining('gemini-cloud'), findsNothing);

      await tester.tap(find.text('Jawaban asisten.'));
      await tester.pump();

      expect(find.textContaining('Kirim 09:12:05'), findsOneWidget);
      expect(find.textContaining('Terima 09:12:09'), findsOneWidget);
      expect(find.textContaining('gemini-cloud'), findsOneWidget);
    },
  );

  testWidgets(
    'metadata bubble user menampilkan waktu kirim tanpa waktu terima',
    (tester) async {
      final entry = FfmAssistantChatEntry(
        isUser: true,
        text: 'Cek saldo',
        sentAt: DateTime(2026, 9, 5, 9, 12, 5),
        modelUsed: 'user',
      );

      await tester.pumpWidget(
        _wrap(
          FfmAssistantMessageCard(
            entry: entry,
            isSpeaking: false,
            teachingSaved: false,
            activityConfirmed: false,
          ),
        ),
      );

      await tester.tap(find.text('Cek saldo'));
      await tester.pump();

      expect(find.textContaining('Kirim 09:12:05'), findsOneWidget);
      expect(find.textContaining('Terima'), findsNothing);
      expect(find.textContaining('user'), findsOneWidget);
    },
  );

  testWidgets(
    'user bubble 1 baris menampilkan tombol salin & 3 titik di luar sebelah kiri bubble',
    (tester) async {
      final entry = FfmAssistantChatEntry(
        isUser: true,
        text: 'kenapa gk biaa pindah halaman?',
      );

      await tester.pumpWidget(
        _wrap(
          FfmAssistantMessageCard(
            entry: entry,
            isSpeaking: false,
            teachingSaved: false,
            activityConfirmed: false,
            onCopyText: () {},
            onCorrectMessage: () {},
          ),
        ),
      );

      expect(find.byIcon(Icons.copy_outlined), findsOneWidget);
      expect(find.byIcon(Icons.more_horiz), findsOneWidget);
      expect(find.text('kenapa gk biaa pindah halaman?'), findsOneWidget);

      final copyBox = tester.getRect(find.byIcon(Icons.copy_outlined));
      final textBox = tester.getRect(
        find.text('kenapa gk biaa pindah halaman?'),
      );

      // Tombol copy berada di sebelah KIRI luar bubble teks (copyBox.left < textBox.left)
      expect(copyBox.left, lessThan(textBox.left));
    },
  );

  testWidgets(
    'user bubble multi-line (2 baris+) tetap menampilkan tombol di sebelah kiri luar bubble, bukan di bawah',
    (tester) async {
      final entry = FfmAssistantChatEntry(
        isUser: true,
        text: 'kenapa gk biaa pindah halaman?\ntolong bantu jelaskan',
      );

      await tester.pumpWidget(
        _wrap(
          FfmAssistantMessageCard(
            entry: entry,
            isSpeaking: false,
            teachingSaved: false,
            activityConfirmed: false,
            onCopyText: () {},
            onCorrectMessage: () {},
          ),
        ),
      );

      expect(find.byIcon(Icons.copy_outlined), findsOneWidget);
      expect(
        find.textContaining('kenapa gk biaa pindah halaman?'),
        findsOneWidget,
      );

      final copyBox = tester.getRect(find.byIcon(Icons.copy_outlined));
      final textBox = tester.getRect(
        find.textContaining('kenapa gk biaa pindah halaman?'),
      );

      // Tombol copy tetap di sebelah KIRI luar bubble teks (copyBox.left < textBox.left)
      expect(copyBox.left, lessThan(textBox.left));
    },
  );

  testWidgets(
    'menampilkan token badge pada header balasan asisten saat tokenUsage tersedia',
    (tester) async {
      final entry = FfmAssistantChatEntry(
        isUser: false,
        text: 'Ini jawaban asisten.',
        processTrace: const FfmAssistantProcessTrace(
          origin: FfmAssistantResponseOrigin.geminiCloud,
          elapsed: Duration(milliseconds: 300),
          events: [],
          tokenUsage: {
            'promptTokenCount': 1240,
            'candidatesTokenCount': 300,
            'totalTokenCount': 1540,
          },
        ),
      );

      await tester.pumpWidget(
        _wrap(
          FfmAssistantMessageCard(
            entry: entry,
            isSpeaking: false,
            teachingSaved: false,
            activityConfirmed: false,
          ),
        ),
      );

      expect(find.textContaining('1.540 token'), findsOneWidget);
    },
  );

  testWidgets(
    'menampilkan pill saran pertanyaan/tag dan memanggil onSelectSuggestion saat diklik',
    (tester) async {
      String? selected;
      final entry = FfmAssistantChatEntry(
        isUser: false,
        text: 'Silakan pilih tag untuk transaksi ini:',
        suggestedQuestions: const ['#makan-siang', '#proyek', '#liburan'],
      );

      await tester.pumpWidget(
        _wrap(
          FfmAssistantMessageCard(
            entry: entry,
            isSpeaking: false,
            teachingSaved: false,
            activityConfirmed: false,
            onSelectSuggestion: (s) => selected = s,
          ),
        ),
      );

      expect(find.text('#makan-siang'), findsOneWidget);
      expect(find.text('#proyek'), findsOneWidget);
      expect(find.text('#liburan'), findsOneWidget);

      await tester.tap(find.text('#makan-siang'));
      await tester.pump();

      expect(selected, '#makan-siang');
    },
  );

  testWidgets(
    'proposal kebiasaan anggaran menampilkan fakta dan hanya mengonfirmasi saat diketuk',
    (tester) async {
      List<FfmAssistantBudgetHabitProposalItem>? confirmedItems;
      var cancelled = 0;
      final proposal = FfmAssistantBudgetHabitProposal(
        items: [
          FfmAssistantBudgetHabitProposalItem(
            categoryId: 'food',
            categoryName: 'Makan',
            cadence: FfmAssistantBudgetHabitCadence.monthly,
            amount: 350000,
            analysisFacts: FfmAssistantBudgetHabitAnalysisFacts({
              'historicalPeriodCount': 4,
              'sampleCount': 4,
              'medianMonthlySpend': 325000,
              'trend': 'stabil',
              'monthlyTotals': [300000, 325000, 350000, 325000],
            }),
          ),
          FfmAssistantBudgetHabitProposalItem(
            categoryId: 'transport',
            categoryName: 'Transport',
            cadence: FfmAssistantBudgetHabitCadence.monthly,
            amount: 200000,
            analysisFacts: FfmAssistantBudgetHabitAnalysisFacts({}),
          ),
        ],
      );
      final actionPlan = FfmAssistantActionPlan(
        id: 'budget-habit-food',
        summary: 'Batch 1',
        createdAt: DateTime(2026, 9, 17),
        steps: const [
          FfmAssistantActionStep(
            id: 'draft',
            capabilityId: 'draft.budget',
            parameters: {'categoryId': 'food', 'periodType': 'monthly'},
          ),
        ],
        requiresConfirmation: true,
      );
      final entry = FfmAssistantChatEntry(
        isUser: false,
        text: 'Ini proposalnya.',
        intent: FfmAssistantIntent(
          rawText: 'buatkan anggaran',
          normalizedText: 'buatkan anggaran',
          type: FfmAssistantIntentType.budgetHabitAnalysis,
          confidence: 1,
          pluginMetadata: {'budgetHabitProposal': proposal},
        ),
      );

      await tester.pumpWidget(
        _wrap(
          FfmAssistantMessageCard(
            entry: entry,
            isSpeaking: false,
            teachingSaved: false,
            activityConfirmed: false,
            budgetHabitActionPlan: actionPlan,
            onConfirmBudgetHabitProposal: (items) => confirmedItems = items,
            onCancelBudgetHabitProposal: () => cancelled++,
          ),
        ),
      );

      expect(find.text('Proposal anggaran kebiasaan'), findsOneWidget);
      expect(
        find.text(
          'Belum disimpan. Pilih pos yang ingin disimpan lalu konfirmasi.',
        ),
        findsOneWidget,
      );
      expect(find.text('Makan'), findsOneWidget);
      expect(find.text('Transport'), findsNothing);
      expect(
        find.text(
          '1 pos pada batch berikutnya tetap menunggu peninjauan dan belum akan disimpan.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Bulanan'), findsOneWidget);
      expect(find.text('Bulanan  |  Rp350.000'), findsOneWidget);
      expect(find.textContaining('4 periode selesai'), findsOneWidget);
      expect(confirmedItems, isNull);

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );

      await tester.tap(find.text('Konfirmasi & simpan'));
      await tester.pump();
      expect(confirmedItems, isNull);

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.text('Konfirmasi & simpan'));
      await tester.pump();
      expect(confirmedItems, hasLength(1));
      expect(confirmedItems!.single.categoryId, 'food');

      await tester.tap(find.text('Batalkan'));
      await tester.pump();
      expect(cancelled, 1);
    },
  );

  testWidgets(
    'tombol Lihat batch berikutnya muncul setelah batch selesai dan masih ada batch lain',
    (tester) async {
      var nextBatchTapped = 0;
      final proposal = FfmAssistantBudgetHabitProposal(
        items: [
          FfmAssistantBudgetHabitProposalItem(
            categoryId: 'food',
            categoryName: 'Makan',
            cadence: FfmAssistantBudgetHabitCadence.monthly,
            amount: 350000,
            analysisFacts: FfmAssistantBudgetHabitAnalysisFacts({}),
          ),
          FfmAssistantBudgetHabitProposalItem(
            categoryId: 'transport',
            categoryName: 'Transport',
            cadence: FfmAssistantBudgetHabitCadence.monthly,
            amount: 200000,
            analysisFacts: FfmAssistantBudgetHabitAnalysisFacts({}),
          ),
        ],
      );
      final completedPlan = FfmAssistantActionPlan(
        id: 'budget-habit-batch-1',
        summary: 'Batch 1',
        createdAt: DateTime(2026, 9, 17),
        steps: const [
          FfmAssistantActionStep(
            id: 'draft',
            capabilityId: 'draft.budget',
            parameters: {'categoryId': 'food', 'periodType': 'monthly'},
          ),
        ],
        requiresConfirmation: true,
        status: FfmAssistantActionPlanStatus.completed,
      );

      await tester.pumpWidget(
        _wrap(
          FfmBudgetHabitProposalPreview(
            proposal: proposal,
            actionPlan: completedPlan,
            onConfirm: (_) {},
            onCancel: () {},
            onNextBatch: () => nextBatchTapped++,
            batchNumber: 1,
            totalBatches: 2,
            completedBatchCount: 0,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('berhasil disimpan dan diverifikasi'),
        findsOneWidget,
      );
      expect(find.text('Lihat batch berikutnya'), findsOneWidget);
      expect(find.text('Konfirmasi & simpan'), findsNothing);

      await tester.tap(find.text('Lihat batch berikutnya'));
      await tester.pump();
      expect(nextBatchTapped, 1);
    },
  );

  testWidgets(
    'batch terakhir selesai menampilkan Semua kategori sudah ditinjau',
    (tester) async {
      final proposal = FfmAssistantBudgetHabitProposal(
        items: [
          FfmAssistantBudgetHabitProposalItem(
            categoryId: 'food',
            categoryName: 'Makan',
            cadence: FfmAssistantBudgetHabitCadence.monthly,
            amount: 350000,
            analysisFacts: FfmAssistantBudgetHabitAnalysisFacts({}),
          ),
        ],
      );
      final completedPlan = FfmAssistantActionPlan(
        id: 'budget-habit-batch-final',
        summary: 'Batch 2',
        createdAt: DateTime(2026, 9, 17),
        steps: const [
          FfmAssistantActionStep(
            id: 'draft',
            capabilityId: 'draft.budget',
            parameters: {'categoryId': 'food', 'periodType': 'monthly'},
          ),
        ],
        requiresConfirmation: true,
        status: FfmAssistantActionPlanStatus.completed,
      );

      await tester.pumpWidget(
        _wrap(
          FfmBudgetHabitProposalPreview(
            proposal: proposal,
            actionPlan: completedPlan,
            onConfirm: (_) {},
            onCancel: () {},
            onNextBatch: () {},
            batchNumber: 2,
            totalBatches: 2,
            completedBatchCount: 1,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Semua kategori sudah ditinjau.'), findsOneWidget);
      expect(find.text('Lihat batch berikutnya'), findsNothing);
      expect(find.text('Konfirmasi & simpan'), findsNothing);
    },
  );

  testWidgets('summary total hidup berubah saat nominal item diedit', (
    tester,
  ) async {
    final proposal = FfmAssistantBudgetHabitProposal(
      items: [
        FfmAssistantBudgetHabitProposalItem(
          categoryId: 'food',
          categoryName: 'Makan',
          cadence: FfmAssistantBudgetHabitCadence.monthly,
          amount: 300000,
          analysisFacts: FfmAssistantBudgetHabitAnalysisFacts({}),
        ),
        FfmAssistantBudgetHabitProposalItem(
          categoryId: 'transport',
          categoryName: 'Transport',
          cadence: FfmAssistantBudgetHabitCadence.monthly,
          amount: 200000,
          analysisFacts: FfmAssistantBudgetHabitAnalysisFacts({}),
        ),
      ],
    );
    final actionPlan = FfmAssistantActionPlan(
      id: 'budget-habit-summary',
      summary: 'Batch 1',
      createdAt: DateTime(2026, 9, 17),
      steps: const [
        FfmAssistantActionStep(
          id: 'draft-food',
          capabilityId: 'draft.budget',
          parameters: {'categoryId': 'food', 'periodType': 'monthly'},
        ),
        FfmAssistantActionStep(
          id: 'draft-transport',
          capabilityId: 'draft.budget',
          parameters: {'categoryId': 'transport', 'periodType': 'monthly'},
        ),
      ],
      requiresConfirmation: true,
    );

    await tester.pumpWidget(
      _wrap(
        FfmBudgetHabitProposalPreview(
          proposal: proposal,
          actionPlan: actionPlan,
          onConfirm: (_) {},
          onCancel: () {},
        ),
      ),
    );

    expect(find.text('Total: Rp500.000 dari 2 pos dipilih.'), findsOneWidget);

    await tester.tap(find.text('Ubah nominal').first);
    await tester.pump();
    final textField = find.byType(TextField);
    await tester.enterText(textField, '400000');
    await tester.tap(find.text('Gunakan'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Total: Rp600.000 dari 2 pos dipilih.'), findsOneWidget);
  });

  testWidgets('pilih kosong tetap memblokir tombol konfirmasi', (tester) async {
    final proposal = FfmAssistantBudgetHabitProposal(
      items: [
        FfmAssistantBudgetHabitProposalItem(
          categoryId: 'food',
          categoryName: 'Makan',
          cadence: FfmAssistantBudgetHabitCadence.monthly,
          amount: 300000,
          analysisFacts: FfmAssistantBudgetHabitAnalysisFacts({}),
        ),
      ],
    );
    final actionPlan = FfmAssistantActionPlan(
      id: 'budget-habit-zero',
      summary: 'Batch 1',
      createdAt: DateTime(2026, 9, 17),
      steps: const [
        FfmAssistantActionStep(
          id: 'draft',
          capabilityId: 'draft.budget',
          parameters: {'categoryId': 'food', 'periodType': 'monthly'},
        ),
      ],
      requiresConfirmation: true,
    );

    await tester.pumpWidget(
      _wrap(
        FfmBudgetHabitProposalPreview(
          proposal: proposal,
          actionPlan: actionPlan,
          onConfirm: (_) {},
          onCancel: () {},
        ),
      ),
    );

    expect(find.text('Makan'), findsOneWidget);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(
      find.text('Pilih minimal satu pos untuk dapat menyimpan.'),
      findsOneWidget,
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(
      find.text('Pilih minimal satu pos untuk dapat menyimpan.'),
      findsNothing,
    );
  });
}
