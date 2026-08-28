import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/features/assistant/data/ffm_assistant_work_item_service.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_work_item.dart';

void main() {
  group('FfmAssistantWorkItemService', () {
    late FfmAssistantWorkItemService service;

    setUp(() {
      service = const FfmAssistantWorkItemService();
    });

    test(
      'single command with complete draft produces high confidence work item',
      () {
        final draft = FfmAssistantDraft(
          kind: FfmAssistantDraftKind.expense,
          createdAt: DateTime(2026, 8, 28),
          amount: 50000,
          title: 'Makan Siang',
          categoryName: 'Makanan',
          fromAccountName: 'Tunai',
          date: DateTime(2026, 8, 28),
        );

        final intent = FfmAssistantIntent(
          rawText: 'catat beli makan 50rb',
          normalizedText: 'catat beli makan 50rb',
          type: FfmAssistantIntentType.createExpense,
          destination: FfmAssistantDestination.transactions,
          draft: draft,
          responseOrigin: FfmAssistantResponseOrigin.agentOrchestrator,
        );

        final result = service.intentsToWorkItems(
          [intent],
          'catat beli makan 50rb',
          'catat beli makan 50rb',
        );

        expect(result.workItems.length, 1);
        final workItem = result.workItems.first;
        expect(workItem.confidence, FfmAssistantWorkItemConfidence.high);
        expect(workItem.isReadyForDraft, true);
        expect(workItem.needsClarification, false);
        expect(workItem.knownFields.length, greaterThan(0));
        expect(workItem.unknownFields, isEmpty);
      },
    );

    test(
      'single command with clarification produces low confidence work item',
      () {
        final intent = FfmAssistantIntent(
          rawText: 'catat beli makan',
          normalizedText: 'catat beli makan',
          type: FfmAssistantIntentType.createExpense,
          destination: FfmAssistantDestination.transactions,
          clarification: 'Berapa nominal pengeluaran untuk makan?',
          responseOrigin: FfmAssistantResponseOrigin.agentOrchestrator,
        );

        final result = service.intentsToWorkItems(
          [intent],
          'catat beli makan',
          'catat beli makan',
        );

        expect(result.workItems.length, 1);
        final workItem = result.workItems.first;
        expect(workItem.confidence, FfmAssistantWorkItemConfidence.low);
        expect(workItem.isReadyForDraft, false);
        expect(workItem.needsClarification, true);
        expect(
          workItem.clarificationQuestion,
          'Berapa nominal pengeluaran untuk makan?',
        );
      },
    );

    test('two commands across different pages produce separate work items', () {
      final expenseDraft = FfmAssistantDraft(
        kind: FfmAssistantDraftKind.expense,
        createdAt: DateTime(2026, 8, 28),
        amount: 50000,
        title: 'Makan Siang',
        categoryName: 'Makanan',
        fromAccountName: 'Tunai',
        date: DateTime(2026, 8, 28),
      );

      final budgetDraft = FfmAssistantDraft(
        kind: FfmAssistantDraftKind.budget,
        createdAt: DateTime(2026, 8, 28),
        amount: 500000,
        categoryName: 'Makanan',
        note: 'Anggaran makan bulan ini',
      );

      final intents = [
        FfmAssistantIntent(
          rawText: 'catat beli makan 50rb',
          normalizedText: 'catat beli makan 50rb',
          type: FfmAssistantIntentType.createExpense,
          destination: FfmAssistantDestination.transactions,
          draft: expenseDraft,
          responseOrigin: FfmAssistantResponseOrigin.agentOrchestrator,
        ),
        FfmAssistantIntent(
          rawText: 'buat anggaran makan 500rb',
          normalizedText: 'buat anggaran makan 500rb',
          type: FfmAssistantIntentType.createBudget,
          destination: FfmAssistantDestination.budget,
          draft: budgetDraft,
          responseOrigin: FfmAssistantResponseOrigin.agentOrchestrator,
        ),
      ];

      final result = service.intentsToWorkItems(
        intents,
        'catat beli makan 50rb; buat anggaran makan 500rb',
        'catat beli makan 50rb; buat anggaran makan 500rb',
      );

      expect(result.workItems.length, 2);
      expect(result.summary, '2 pekerjaan dipahami');

      final expenseItem = result.workItems[0];
      expect(expenseItem.intent, FfmAssistantIntentType.createExpense);
      expect(
        expenseItem.targetDestination,
        FfmAssistantDestination.transactions,
      );

      final budgetItem = result.workItems[1];
      expect(budgetItem.intent, FfmAssistantIntentType.createBudget);
      expect(budgetItem.targetDestination, FfmAssistantDestination.budget);
    });

    test('unknown intent type is skipped in work items', () {
      final intent = FfmAssistantIntent(
        rawText: 'apa kabar',
        normalizedText: 'apa kabar',
        type: FfmAssistantIntentType.unknown,
        responseOrigin: FfmAssistantResponseOrigin.agentOrchestrator,
      );

      final result = service.intentsToWorkItems(
        [intent],
        'apa kabar',
        'apa kabar',
      );

      expect(result.workItems.length, 0);
      expect(result.summary, 'Tidak ada pekerjaan dipahami');
    });

    test('help intent type is skipped in work items', () {
      final intent = FfmAssistantIntent(
        rawText: 'bantu saya',
        normalizedText: 'bantu saya',
        type: FfmAssistantIntentType.help,
        responseOrigin: FfmAssistantResponseOrigin.agentOrchestrator,
      );

      final result = service.intentsToWorkItems(
        [intent],
        'bantu saya',
        'bantu saya',
      );

      expect(result.workItems.length, 0);
    });

    test('validator menentukan field wajib yang belum ada tanpa menebak', () {
      final draft = FfmAssistantDraft(
        kind: FfmAssistantDraftKind.transfer,
        createdAt: DateTime(2026, 8, 28),
        amount: 50000,
        fromAccountName: 'Tunai',
        // Rekening tujuan wajib untuk transfer tetapi tidak diisi.
      );

      final intent = FfmAssistantIntent(
        rawText: 'transfer 50rb dari Tunai',
        normalizedText: 'transfer 50rb dari tunai',
        type: FfmAssistantIntentType.createTransfer,
        destination: FfmAssistantDestination.transactions,
        draft: draft,
        responseOrigin: FfmAssistantResponseOrigin.agentOrchestrator,
      );

      final result = service.intentsToWorkItems(
        [intent],
        'transfer 50rb dari Tunai',
        'transfer 50rb dari tunai',
      );

      expect(result.workItems.length, 1);
      final workItem = result.workItems.first;
      expect(workItem.confidence, FfmAssistantWorkItemConfidence.low);
      expect(workItem.unknownFields, contains('rekening tujuan'));
      expect(workItem.clarificationQuestion, contains('rekening tujuan'));
    });

    test('work item mempertahankan intent sumber dari Gemini atau Agent', () {
      final intent = FfmAssistantIntent(
        rawText: 'catat makan 50rb',
        normalizedText: 'catat makan 50rb',
        type: FfmAssistantIntentType.createExpense,
        destination: FfmAssistantDestination.transactions,
        draft: FfmAssistantDraft(
          kind: FfmAssistantDraftKind.expense,
          createdAt: DateTime(2026, 8, 28),
          amount: 50000,
        ),
        response: 'Draft dari Gemini siap ditinjau.',
        responseOrigin: FfmAssistantResponseOrigin.geminiCloud,
      );

      final result = service.intentsToWorkItems(
        [intent],
        intent.rawText,
        intent.normalizedText,
      );

      expect(result.intents, [intent]);
      expect(result.workItems.single.sourceIntent, same(intent));
      expect(result.single, same(intent));
    });

    test('result summary reflects number of work items', () {
      final intents = List.generate(
        3,
        (index) => FfmAssistantIntent(
          rawText: 'command $index',
          normalizedText: 'command $index',
          type: FfmAssistantIntentType.createExpense,
          destination: FfmAssistantDestination.transactions,
          responseOrigin: FfmAssistantResponseOrigin.agentOrchestrator,
        ),
      );

      final result = service.intentsToWorkItems(
        intents,
        'command 0; command 1; command 2',
        'command 0; command 1; command 2',
      );

      expect(result.summary, '3 pekerjaan dipahami');
      expect(result.hasReadyItems, false); // No drafts, so medium confidence
    });

    test('needsClarification is true if any work item needs clarification', () {
      final intents = [
        FfmAssistantIntent(
          rawText: 'catat beli makan',
          normalizedText: 'catat beli makan',
          type: FfmAssistantIntentType.createExpense,
          destination: FfmAssistantDestination.transactions,
          clarification: 'Berapa nominal?',
          responseOrigin: FfmAssistantResponseOrigin.agentOrchestrator,
        ),
        FfmAssistantIntent(
          rawText: 'buat anggaran',
          normalizedText: 'buat anggaran',
          type: FfmAssistantIntentType.createBudget,
          destination: FfmAssistantDestination.budget,
          responseOrigin: FfmAssistantResponseOrigin.agentOrchestrator,
        ),
      ];

      final result = service.intentsToWorkItems(
        intents,
        'catat beli makan; buat anggaran',
        'catat beli makan; buat anggaran',
      );

      expect(result.needsClarification, true);
    });

    test('work item summary provides human-readable description', () {
      final draft = FfmAssistantDraft(
        kind: FfmAssistantDraftKind.expense,
        createdAt: DateTime(2026, 8, 28),
        amount: 50000,
        title: 'Makan Siang',
        categoryName: 'Makanan',
        fromAccountName: 'Tunai',
        date: DateTime(2026, 8, 28),
      );

      final intent = FfmAssistantIntent(
        rawText: 'catat beli makan 50rb',
        normalizedText: 'catat beli makan 50rb',
        type: FfmAssistantIntentType.createExpense,
        destination: FfmAssistantDestination.transactions,
        draft: draft,
        responseOrigin: FfmAssistantResponseOrigin.agentOrchestrator,
      );

      final result = service.intentsToWorkItems(
        [intent],
        'catat beli makan 50rb',
        'catat beli makan 50rb',
      );

      final workItem = result.workItems.first;
      expect(workItem.summary, contains('Catat pengeluaran'));
      expect(workItem.summary, contains('Transaksi'));
    });
  });

  group('FfmAssistantWorkItem', () {
    test(
      'draft queue menyimpan status terpisah dan reset menghapus antrean',
      () {
        final intent = FfmAssistantIntent(
          rawText: 'catat makan 50rb',
          normalizedText: 'catat makan 50rb',
          type: FfmAssistantIntentType.createExpense,
        );
        final review = FfmAssistantDraftReview(
          draft: FfmAssistantDraft(
            kind: FfmAssistantDraftKind.expense,
            createdAt: DateTime(2026, 8, 28),
            amount: 50000,
          ),
          version: 1,
          issues: const [],
        );
        final session = FfmAssistantChatSession();
        session.draftQueue.add(
          FfmAssistantDraftQueueItem(
            id: 'draft-1',
            intent: intent,
            review: review,
            targetDestination: FfmAssistantDestination.transactions,
            createdAt: review.draft.createdAt,
            status: FfmAssistantDraftQueueStatus.ready,
          ),
        );
        session.activeDraftQueueId = 'draft-1';

        final opening = session.draftQueue.single.copyWith(
          status: FfmAssistantDraftQueueStatus.openingForm,
        );
        expect(opening.canOpen, isFalse);
        expect(
          session.draftQueue.single.status,
          FfmAssistantDraftQueueStatus.ready,
        );

        session.reset();
        expect(session.draftQueue, isEmpty);
        expect(session.activeDraftQueueId, isNull);
      },
    );

    test('dua draft lintas halaman tetap terisolasi saat satu dibatalkan', () {
      final session = FfmAssistantChatSession();
      FfmAssistantDraftQueueItem item(
        String id,
        FfmAssistantDraftKind kind,
        FfmAssistantDestination destination,
      ) {
        final draft = FfmAssistantDraft(
          kind: kind,
          createdAt: DateTime(2026, 8, 28),
          amount: 50000,
        );
        return FfmAssistantDraftQueueItem(
          id: id,
          intent: FfmAssistantIntent(
            rawText: id,
            normalizedText: id,
            type: kind == FfmAssistantDraftKind.budget
                ? FfmAssistantIntentType.createBudget
                : FfmAssistantIntentType.createExpense,
            destination: destination,
            draft: draft,
          ),
          review: FfmAssistantDraftReview(
            draft: draft,
            version: 1,
            issues: const [],
          ),
          targetDestination: destination,
          createdAt: draft.createdAt,
          status: FfmAssistantDraftQueueStatus.ready,
        );
      }

      session.draftQueue.addAll([
        item(
          'expense',
          FfmAssistantDraftKind.expense,
          FfmAssistantDestination.transactions,
        ),
        item(
          'budget',
          FfmAssistantDraftKind.budget,
          FfmAssistantDestination.budget,
        ),
      ]);
      session.draftQueue[0] = session.draftQueue[0].copyWith(
        status: FfmAssistantDraftQueueStatus.cancelled,
      );

      expect(
        session.draftQueue[0].status,
        FfmAssistantDraftQueueStatus.cancelled,
      );
      expect(session.draftQueue[1].status, FfmAssistantDraftQueueStatus.ready);
      expect(
        session.draftQueue[1].targetDestination,
        FfmAssistantDestination.budget,
      );
    });

    test('isReadyForDraft returns true only for high confidence', () {
      final highItem = FfmAssistantWorkItem(
        id: '1',
        intent: FfmAssistantIntentType.createExpense,
        targetDestination: FfmAssistantDestination.transactions,
        confidence: FfmAssistantWorkItemConfidence.high,
        knownFields: const [],
        unknownFields: const [],
        ambiguousFields: const [],
      );

      final mediumItem = FfmAssistantWorkItem(
        id: '2',
        intent: FfmAssistantIntentType.createExpense,
        targetDestination: FfmAssistantDestination.transactions,
        confidence: FfmAssistantWorkItemConfidence.medium,
        knownFields: const [],
        unknownFields: const [],
        ambiguousFields: const [],
      );

      final lowItem = FfmAssistantWorkItem(
        id: '3',
        intent: FfmAssistantIntentType.createExpense,
        targetDestination: FfmAssistantDestination.transactions,
        confidence: FfmAssistantWorkItemConfidence.low,
        knownFields: const [],
        unknownFields: const [],
        ambiguousFields: const [],
      );

      expect(highItem.isReadyForDraft, true);
      expect(mediumItem.isReadyForDraft, false);
      expect(lowItem.isReadyForDraft, false);
    });

    test(
      'needsClarification returns true when clarificationQuestion is set',
      () {
        final withClarification = FfmAssistantWorkItem(
          id: '1',
          intent: FfmAssistantIntentType.createExpense,
          targetDestination: FfmAssistantDestination.transactions,
          confidence: FfmAssistantWorkItemConfidence.low,
          knownFields: const [],
          unknownFields: const [],
          ambiguousFields: const [],
          clarificationQuestion: 'Berapa nominal?',
        );

        final withoutClarification = FfmAssistantWorkItem(
          id: '2',
          intent: FfmAssistantIntentType.createExpense,
          targetDestination: FfmAssistantDestination.transactions,
          confidence: FfmAssistantWorkItemConfidence.high,
          knownFields: const [],
          unknownFields: const [],
          ambiguousFields: const [],
        );

        expect(withClarification.needsClarification, true);
        expect(withoutClarification.needsClarification, false);
      },
    );
  });

  group('FfmAssistantUnderstandingResult', () {
    test('summary returns correct message based on work item count', () {
      final empty = FfmAssistantUnderstandingResult(
        workItems: const [],
        intents: const [],
        rawText: '',
        normalizedText: '',
      );

      final single = FfmAssistantUnderstandingResult(
        workItems: [
          FfmAssistantWorkItem(
            id: '1',
            intent: FfmAssistantIntentType.createExpense,
            targetDestination: FfmAssistantDestination.transactions,
            confidence: FfmAssistantWorkItemConfidence.high,
            knownFields: const [],
            unknownFields: const [],
            ambiguousFields: const [],
          ),
        ],
        intents: const [],
        rawText: '',
        normalizedText: '',
      );

      final multiple = FfmAssistantUnderstandingResult(
        workItems: [
          FfmAssistantWorkItem(
            id: '1',
            intent: FfmAssistantIntentType.createExpense,
            targetDestination: FfmAssistantDestination.transactions,
            confidence: FfmAssistantWorkItemConfidence.high,
            knownFields: const [],
            unknownFields: const [],
            ambiguousFields: const [],
          ),
          FfmAssistantWorkItem(
            id: '2',
            intent: FfmAssistantIntentType.createBudget,
            targetDestination: FfmAssistantDestination.budget,
            confidence: FfmAssistantWorkItemConfidence.high,
            knownFields: const [],
            unknownFields: const [],
            ambiguousFields: const [],
          ),
        ],
        intents: const [],
        rawText: '',
        normalizedText: '',
      );

      expect(empty.summary, 'Tidak ada pekerjaan dipahami');
      expect(single.summary, '1 pekerjaan dipahami');
      expect(multiple.summary, '2 pekerjaan dipahami');
    });

    test('hasReadyItems returns true if any work item is high confidence', () {
      final withReady = FfmAssistantUnderstandingResult(
        workItems: [
          FfmAssistantWorkItem(
            id: '1',
            intent: FfmAssistantIntentType.createExpense,
            targetDestination: FfmAssistantDestination.transactions,
            confidence: FfmAssistantWorkItemConfidence.high,
            knownFields: const [],
            unknownFields: const [],
            ambiguousFields: const [],
          ),
          FfmAssistantWorkItem(
            id: '2',
            intent: FfmAssistantIntentType.createBudget,
            targetDestination: FfmAssistantDestination.budget,
            confidence: FfmAssistantWorkItemConfidence.low,
            knownFields: const [],
            unknownFields: const [],
            ambiguousFields: const [],
          ),
        ],
        intents: const [],
        rawText: '',
        normalizedText: '',
      );

      final withoutReady = FfmAssistantUnderstandingResult(
        workItems: [
          FfmAssistantWorkItem(
            id: '1',
            intent: FfmAssistantIntentType.createExpense,
            targetDestination: FfmAssistantDestination.transactions,
            confidence: FfmAssistantWorkItemConfidence.medium,
            knownFields: const [],
            unknownFields: const [],
            ambiguousFields: const [],
          ),
        ],
        intents: const [],
        rawText: '',
        normalizedText: '',
      );

      expect(withReady.hasReadyItems, true);
      expect(withoutReady.hasReadyItems, false);
    });
  });
}
