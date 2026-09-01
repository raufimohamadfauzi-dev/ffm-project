import 'package:ffm_manager/features/assistant/domain/ffm_assistant_cloud_context.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_reasoning_context.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_verified_fact_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('context Data Utama hanya membawa field relevan tanpa ID internal', () {
    final context = FfmAssistantCloudDraftContext.fromDraft(
      FfmAssistantDraft(
        kind: FfmAssistantDraftKind.masterData,
        createdAt: DateTime(2026, 8, 31),
        title: 'BandarPPT1',
        categoryName: 'tag',
        note: 'Tag presentasi',
        amount: 987654321,
        fromAccountName: 'Rekening yang tidak relevan',
        formValues: const {
          'details': 'Presentasi kerja',
          'targetId': 'internal-secret-id',
          'source': 'gemini_proposal',
        },
      ),
    );

    expect(context.kind, FfmAssistantDraftKind.masterData);
    expect(context.fields, {
      'target': 'tag',
      'name': 'BandarPPT1',
      'field.details': 'Presentasi kerja',
      'note': 'Tag presentasi',
    });
    expect(context.toBoundedPrompt(), isNot(contains('987654321')));
    expect(context.toBoundedPrompt(), isNot(contains('internal-secret-id')));
    expect(
      context.toBoundedPrompt(),
      isNot(contains('Rekening yang tidak relevan')),
    );
  });

  test('context pengeluaran tidak membawa field transaksi lain', () {
    final context = FfmAssistantCloudDraftContext.fromDraft(
      FfmAssistantDraft(
        kind: FfmAssistantDraftKind.expense,
        createdAt: DateTime(2026, 8, 31),
        amount: 25000,
        title: 'Makan siang',
        fromAccountName: 'Tunai',
        toAccountName: 'Tidak relevan',
        categoryName: 'Makanan',
        goalName: 'Tidak relevan',
        date: DateTime(2026, 8, 31),
      ),
    );

    expect(context.fields['amount'], '25000');
    expect(context.fields['fromAccount'], 'Tunai');
    expect(context.fields['category'], 'Makanan');
    expect(context.fields, isNot(contains('toAccount')));
    expect(context.fields, isNot(contains('goal')));
  });

  test('cloud context envelope memprioritaskan fakta dan tetap bounded', () {
    final reasoning = FfmAssistantReasoningContext(
      request: 'analisis pengeluaran bulan ini',
      capturedAt: DateTime(2026, 8, 31),
      currentPage: FfmAssistantDestination.analysis,
      pageSummary: List.filled(300, 'ringkasan').join(' '),
      modelReady: true,
    );
    final envelope = FfmAssistantCloudContextEnvelope(
      capturedAt: DateTime(2026, 8, 31),
      routingMode: FfmAssistantRoutingMode.geminiCloud,
      requestClass: FfmAssistantCloudRequestClass.analysis,
      evidenceScope: const FfmAssistantReasoningEvidenceScope(
        includeFinancialSummary: true,
        includeMasterData: false,
        includeRecentTransactions: true,
      ),
      currentDestination: FfmAssistantDestination.analysis,
      reasoningContext: reasoning,
      verifiedFacts: FfmVerifiedFacts(
        capturedAt: DateTime(2026, 8, 31),
        householdId: 'tidak-boleh-dirender',
        financialSummary: const FfmFinancialSummaryFact(
          totalAccounts: 2,
          totalBalance: 5000000,
          totalActiveLiabilities: 0,
          totalDebt: 0,
          totalActiveGoals: 1,
          totalGoalProgress: 100000,
          totalGoalTarget: 1000000,
          netWorth: 5000000,
        ),
      ),
      activeDraft: FfmAssistantCloudDraftContext.fromDraft(
        FfmAssistantDraft(
          kind: FfmAssistantDraftKind.masterData,
          createdAt: DateTime(2026, 8, 31),
          title: 'Prioritas',
          categoryName: 'tag',
        ),
      ),
      conversationHistory: List.filled(500, 'riwayat').join(' '),
      cloudMemoryContext: List.filled(500, 'cloud').join(' '),
    );

    final prompt = envelope.toBoundedPrompt(maxCharacters: 1600);

    expect(prompt.length, lessThanOrEqualTo(1600));
    expect(prompt, contains(FfmAssistantCloudContextEnvelope.schemaVersion));
    expect(prompt, contains('ACTIVE DRAFT'));
    expect(prompt, contains('VERIFIED FACTS'));
    expect(prompt, isNot(contains('tidak-boleh-dirender')));
  });

  test(
    'active draft membawa review version, missing fields, warnings, dan status',
    () {
      final draft = FfmAssistantDraft(
        kind: FfmAssistantDraftKind.expense,
        createdAt: DateTime(2026, 8, 31),
        amount: 0,
        title: 'Makan',
        fromAccountName: 'Tunai',
        categoryName: 'Makanan',
        date: DateTime(2026, 8, 31),
      );
      final review = FfmAssistantDraftReview(
        draft: draft,
        version: 2,
        issues: const [
          FfmAssistantDraftIssue(
            code: 'amount_required',
            severity: FfmAssistantDraftIssueSeverity.required,
            message: 'Nominal wajib diisi',
            field: 'amount',
          ),
          FfmAssistantDraftIssue(
            code: 'category_warning',
            severity: FfmAssistantDraftIssueSeverity.warning,
            message: 'Kategori tidak umum',
            field: 'category',
          ),
        ],
      );
      final context = FfmAssistantCloudDraftContext.fromDraft(
        draft,
        review: review,
      );

      expect(context.reviewVersion, 2);
      expect(context.missingFields, contains('amount'));
      expect(
        context.warnings.any((w) => w.contains('Kategori tidak umum')),
        isTrue,
      );
      expect(context.status, 'blocked');
      final prompt = context.toBoundedPrompt();
      expect(prompt, contains('reviewVersion=2'));
      expect(prompt, contains('status=blocked'));
      expect(prompt, contains('missing=amount'));
      expect(prompt, contains('blocked'));
    },
  );

  test('capability evidence bertipe dirender bounded dengan metadata', () {
    final reasoning = FfmAssistantReasoningContext(
      request: 'ringkasan bulan ini',
      capturedAt: DateTime(2026, 8, 31),
      modelReady: true,
    );
    final envelope = FfmAssistantCloudContextEnvelope(
      capturedAt: DateTime(2026, 8, 31),
      routingMode: FfmAssistantRoutingMode.geminiCloud,
      requestClass: FfmAssistantCloudRequestClass.summary,
      evidenceScope: const FfmAssistantReasoningEvidenceScope(
        includeFinancialSummary: true,
        includeMasterData: false,
        includeRecentTransactions: false,
      ),
      reasoningContext: reasoning,
      verifiedFacts: FfmVerifiedFacts(
        capturedAt: DateTime(2026, 8, 31),
        householdId: 'h1',
        financialSummary: const FfmFinancialSummaryFact(
          totalAccounts: 1,
          totalBalance: 1000,
          totalActiveLiabilities: 0,
          totalDebt: 0,
          totalActiveGoals: 0,
          totalGoalProgress: 0,
          totalGoalTarget: 0,
          netWorth: 1000,
        ),
      ),
      capabilityEvidences: [
        FfmAssistantCloudCapabilityEvidence(
          capabilityId: 'read.summary',
          validatedArguments: const {},
          capturedAt: DateTime(2026, 8, 31, 10, 0),
          boundedSummary: 'income=5000; expenses=3000',
          dataQuality: 'sufficient',
        ),
      ],
    );

    final prompt = envelope.toBoundedPrompt();
    expect(prompt, contains('CAPABILITY EVIDENCE'));
    expect(prompt, contains('read.summary'));
    expect(prompt, contains('sufficient'));
    expect(prompt.length, lessThanOrEqualTo(8000));
  });
}
