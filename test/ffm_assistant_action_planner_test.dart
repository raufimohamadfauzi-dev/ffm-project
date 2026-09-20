import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_plan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_planner.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_form_prefill.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_reference_resolver.dart';

void main() {
  test('planner membuat navigasi untuk intent halaman', () {
    final intent = FfmAssistantIntent(
      rawText: 'buka anggaran',
      normalizedText: 'buka anggaran',
      type: FfmAssistantIntentType.openPage,
      destination: FfmAssistantDestination.budget,
      response: 'Membuka Anggaran.',
    );

    final plan = const FfmAssistantActionPlanner().planFor(intent);

    expect(plan, isNotNull);
    expect(plan!.steps.single.capabilityId, 'navigate.budget');
    expect(plan.requiresConfirmation, isFalse);
  });

  test('planner membuat draft dan save gate untuk intent transaksi', () {
    final intent = FfmAssistantIntent(
      rawText: 'catat makan 50000',
      normalizedText: 'catat makan 50000',
      type: FfmAssistantIntentType.createExpense,
      destination: FfmAssistantDestination.transactions,
      draft: FfmAssistantDraft(
        kind: FfmAssistantDraftKind.expense,
        amount: 50000,
        categoryName: 'Makanan',
        createdAt: DateTime(2026, 8, 23),
      ),
    );

    final plan = const FfmAssistantActionPlanner().planFor(intent);

    expect(plan, isNotNull);
    expect(plan!.steps.map((step) => step.capabilityId), [
      'read.accounts',
      'read.categories',
      'navigate.transactions',
      'draft.expense',
      'mutate.save_draft',
      'verify.saved_draft',
    ]);
    expect(plan.requiresConfirmation, isTrue);
    expect(plan.hasMutation, isTrue);
    expect(plan.workflowSafetyIssue, isNull);
    expect(const FfmAssistantActionPlanner().planFor(intent)!.id, plan.id);
  });

  test('planner mengarahkan reminder bertarget ke jalur update', () {
    final intent = FfmAssistantIntent(
      rawText: 'ubah alarm pagi',
      normalizedText: 'ubah alarm pagi',
      type: FfmAssistantIntentType.createReminder,
      draft: FfmAssistantDraft(
        kind: FfmAssistantDraftKind.reminder,
        title: 'Alarm Pagi',
        date: DateTime(2026, 9, 19, 6),
        soundUri: 'content://ringtone/new',
        soundName: 'Nada Baru',
        createdAt: DateTime(2026, 9, 18),
        formValues: const {'targetId': 'reminder-1'},
      ),
    );

    final plan = const FfmAssistantActionPlanner().planFor(intent)!;
    expect(plan.steps.map((step) => step.capabilityId), [
      'read.reminders',
      'draft.reminder_update',
      'mutate.update',
      'verify.reminder_mutation',
    ]);
    final save = plan.steps.firstWhere((step) => step.id == 'save');
    expect(save.parameters['targetId'], 'reminder-1');
    expect(save.parameters['soundName'], 'Nada Baru');
    expect(save.parameters['operation'], 'update');
  });

  test('planner menjaga reminder baru tetap berada di jalur create', () {
    final intent = FfmAssistantIntent(
      rawText: 'buat pengingat alarm pagi',
      normalizedText: 'buat pengingat alarm pagi',
      type: FfmAssistantIntentType.createReminder,
      draft: FfmAssistantDraft(
        kind: FfmAssistantDraftKind.reminder,
        title: 'Alarm Pagi',
        date: DateTime(2026, 9, 20, 6),
        createdAt: DateTime(2026, 9, 19),
      ),
    );

    final plan = const FfmAssistantActionPlanner().planFor(intent)!;

    expect(plan.steps.map((step) => step.capabilityId), [
      'read.reminders',
      'draft.reminder',
      'mutate.save_draft',
      'verify.saved_draft',
    ]);
    expect(
      plan.steps.every((step) => step.parameters['targetId'] == null),
      isTrue,
    );
  });

  test('canonical draft fields tidak dapat ditimpa formValues', () {
    final intent = FfmAssistantIntent(
      rawText: 'transfer 100000',
      normalizedText: 'transfer 100000',
      type: FfmAssistantIntentType.createTransfer,
      draft: FfmAssistantDraft(
        kind: FfmAssistantDraftKind.transfer,
        createdAt: DateTime(2026, 8, 23),
        amount: 100000,
        fromAccountName: 'Bank Utama',
        toAccountName: 'Tunai',
        adminFee: 2500,
        formValues: const {
          'amount': '999',
          'fromAccount': 'Rekening Salah',
          'toAccount': 'Tujuan Salah',
          'adminFee': '1',
          'uiOnly': 'preserved',
        },
      ),
    );

    final plan = const FfmAssistantActionPlanner().planFor(intent)!;
    final parameters = plan.steps
        .firstWhere((step) => step.id == 'save')
        .parameters;

    expect(parameters['amount'], 100000);
    expect(parameters['fromAccount'], 'Bank Utama');
    expect(parameters['toAccount'], 'Tunai');
    expect(parameters['adminFee'], 2500);
    expect(parameters['uiOnly'], 'preserved');
  });

  test(
    'prefill mempertahankan metadata tetapi memprioritaskan field canonical',
    () {
      final draft = FfmAssistantDraft(
        kind: FfmAssistantDraftKind.expense,
        createdAt: DateTime(2026, 8, 23),
        amount: 75000,
        fromAccountName: 'BCA',
        categoryName: 'Belanja',
        receiptRawText: 'TOTAL 75.000',
        formValues: const {
          'amount': '999',
          'fromAccountName': 'Rekening Salah',
          'uiOnly': 'preserved',
        },
      );

      final prefill = FfmAssistantFormPrefillMapper.fromDraft(draft);

      expect(prefill.values['amount'], '75000');
      expect(prefill.values['fromAccountName'], 'BCA');
      expect(prefill.values['receiptRawText'], 'TOTAL 75.000');
      expect(prefill.values['uiOnly'], 'preserved');
    },
  );

  test('reference resolver membedakan resolved, missing, dan ambiguous', () {
    const candidates = ['BCA', 'Tunai', 'BCA'];

    final resolved = FfmAssistantReferenceResolver.resolve(
      ' tunai ',
      candidates,
      (value) => value,
    );
    final missing = FfmAssistantReferenceResolver.resolve(
      'Jago',
      candidates,
      (value) => value,
    );
    final ambiguous = FfmAssistantReferenceResolver.resolve(
      'bca',
      candidates,
      (value) => value,
    );

    expect(resolved.status, FfmAssistantReferenceStatus.resolved);
    expect(resolved.value, 'Tunai');
    expect(missing.status, FfmAssistantReferenceStatus.missing);
    expect(ambiguous.status, FfmAssistantReferenceStatus.ambiguous);
    expect(ambiguous.matches, hasLength(2));
  });

  test('planner menyiapkan alur payment Hutang dan Piutang dengan satu mutasi dan verifikasi', () {
    final liabilityIntent = FfmAssistantIntent(
      rawText: 'bayar hutang andi 500000',
      normalizedText: 'bayar hutang andi 500000',
      type: FfmAssistantIntentType.createLiabilityPayment,
      destination: FfmAssistantDestination.liabilities,
      draft: FfmAssistantDraft(
        kind: FfmAssistantDraftKind.liabilityPayment,
        amount: 500000,
        title: 'Hutang Andi',
        partyName: 'Andi',
        createdAt: DateTime(2026, 8, 23),
        formValues: {
          'entity': 'liability',
          'targetId': 'liab-1',
          'accountId': 'acct-1',
        },
      ),
    );

    final liabilityPlan = const FfmAssistantActionPlanner().planFor(
      liabilityIntent,
    )!;
    expect(liabilityPlan.steps.map((step) => step.capabilityId), [
      'read.liabilities',
      'navigate.liabilities',
      'draft.liability_payment',
      'mutate.debt_payment',
      'verify.debt_payment',
    ]);
    expect(liabilityPlan.requiresConfirmation, isTrue);
    expect(liabilityPlan.workflowSafetyIssue, isNull);

    final receivableIntent = FfmAssistantIntent(
      rawText: 'terima piutang andi 250000',
      normalizedText: 'terima piutang andi 250000',
      type: FfmAssistantIntentType.createReceivablePayment,
      destination: FfmAssistantDestination.liabilities,
      draft: FfmAssistantDraft(
        kind: FfmAssistantDraftKind.receivablePayment,
        amount: 250000,
        title: 'Piutang Andi',
        partyName: 'Andi',
        createdAt: DateTime(2026, 8, 23),
        formValues: {
          'entity': 'receivable',
          'targetId': 'recv-2',
          'accountId': 'acct-2',
        },
      ),
    );

    final receivablePlan = const FfmAssistantActionPlanner().planFor(
      receivableIntent,
    )!;
    expect(receivablePlan.steps.map((step) => step.capabilityId), [
      'read.receivable',
      'navigate.liabilities',
      'draft.receivable_payment',
      'mutate.debt_payment',
      'verify.debt_payment',
    ]);
    expect(receivablePlan.requiresConfirmation, isTrue);
    expect(receivablePlan.workflowSafetyIssue, isNull);
  });

  test('guard workflow memblokir multi-mutasi dan mutasi tanpa verifikasi', () {
    final multiMutation = FfmAssistantActionPlan(
      id: 'unsafe-multi',
      summary: 'uji',
      createdAt: DateTime(2026, 8, 24),
      requiresConfirmation: true,
      steps: const [
        FfmAssistantActionStep(id: 'save-a', capabilityId: 'mutate.save_draft'),
        FfmAssistantActionStep(id: 'save-b', capabilityId: 'mutate.archive'),
      ],
    );
    final noVerification = FfmAssistantActionPlan(
      id: 'unsafe-verify',
      summary: 'uji',
      createdAt: DateTime(2026, 8, 24),
      requiresConfirmation: true,
      steps: const [
        FfmAssistantActionStep(id: 'save', capabilityId: 'mutate.save_draft'),
      ],
    );

    expect(multiMutation.workflowSafetyIssue, contains('lebih dari satu'));
    expect(noVerification.workflowSafetyIssue, contains('pembacaan ulang'));
  });
}
