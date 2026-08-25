import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_personal_context.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_memory_candidate.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_memory_type.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_context_relevance.dart';

void main() {
  group('Personal Context Integration Tests', () {
    test('Context pack structure - valid context pack creation', () {
      final context = FfmPersonalContext(
        query: 'bulan ini saya boros gak?',
        normalizedQuery: 'bulan ini saya boros tidak',
        detectedTopic: 'spending_analysis',
        detectedEntities: {'period': 'current_month'},
        detectedIntent: 'financial_analysis',
        workingContext: [],
        personalFacts: [],
        preferences: [],
        goals: [
          FfmMemoryCandidate(
            id: 'goal1',
            type: FfmMemoryType.goal,
            key: 'savings_target',
            value: '10000000',
            evidence: FfmMemoryEvidence(
              source: FfmMemorySource.userExplicit,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
              confidence: 1.0,
              approved: true,
            ),
            importance: 1.0,
          ),
        ],
        behaviorPatterns: [],
        episodes: [],
        corrections: [],
        dataContext: FfmDataContext(
          period: 'current_month',
          requiresFinancialSummary: true,
        ),
        responsePreferences: const FfmResponsePreferences(
          concise: true,
          useIndonesian: true,
        ),
        capturedAt: DateTime.now(),
      );

      expect(context.query, 'bulan ini saya boros gak?');
      expect(context.detectedTopic, 'spending_analysis');
      expect(context.goals.length, 1);
      expect(context.goals.first.type, FfmMemoryType.goal);
      expect(context.responsePreferences.concise, true);
      expect(context.totalMemoryCount, 1);
      expect(context.isEmpty, false);
    });

    test('Working context - context persistence across turns', () {
      final initialContext = const FfmWorkingContext(
        currentTopic: 'spending',
        currentPeriod: 'current_month',
      );

      final updatedContext = FfmWorkingContext(
        lastUserIntent: 'query_amount',
        lastReferencedEntity: 'food',
        currentTopic: initialContext.currentTopic,
        currentPeriod: initialContext.currentPeriod,
      );

      expect(updatedContext.currentTopic, 'spending');
      expect(updatedContext.currentPeriod, 'current_month');
      expect(updatedContext.lastUserIntent, 'query_amount');
      expect(updatedContext.lastReferencedEntity, 'food');
    });

    test('Response preferences - preference extraction from memories', () {
      final preferences = [
        FfmMemoryCandidate(
          id: 'pref1',
          type: FfmMemoryType.preference,
          key: 'response_style',
          value: 'concise',
          evidence: FfmMemoryEvidence(
            source: FfmMemorySource.userExplicit,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            confidence: 1.0,
            approved: true,
          ),
        ),
        FfmMemoryCandidate(
          id: 'pref2',
          type: FfmMemoryType.preference,
          key: 'language',
          value: 'Indonesian',
          evidence: FfmMemoryEvidence(
            source: FfmMemorySource.userExplicit,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            confidence: 1.0,
            approved: true,
          ),
        ),
      ];

      // Simulate preference extraction logic
      var concise = false;
      var useIndonesian = true;

      for (final pref in preferences) {
        if (pref.key == 'response_style' && pref.value == 'concise') {
          concise = true;
        }
        if (pref.key == 'language' && pref.value.contains('Indonesia')) {
          useIndonesian = true;
        }
      }

      expect(concise, true);
      expect(useIndonesian, true);
    });

    test('Data context - page-specific requirements', () {
      final budgetContext = FfmDataContext(
        period: 'current_month',
        requiresFinancialSummary: true,
        requiresMasterData: true,
        requiresRecentTransactions: false,
        customRequests: ['active_budgets', 'budget_variance'],
      );

      expect(budgetContext.period, 'current_month');
      expect(budgetContext.requiresFinancialSummary, true);
      expect(budgetContext.requiresMasterData, true);
      expect(budgetContext.customRequests, contains('active_budgets'));
    });

    test('Memory evidence - tracking confidence and approval', () {
      final evidence = FfmMemoryEvidence(
        source: FfmMemorySource.userExplicit,
        sourceId: 'user123',
        createdAt: DateTime(2026, 8, 20),
        updatedAt: DateTime(2026, 8, 25),
        confidence: 0.95,
        approved: true,
        lastUsedAt: DateTime.now(),
        useCount: 5,
      );

      expect(evidence.source, FfmMemorySource.userExplicit);
      expect(evidence.confidence, 0.95);
      expect(evidence.approved, true);
      expect(evidence.useCount, 5);

      final updatedEvidence = evidence.markUsed();
      expect(updatedEvidence.useCount, 6);
      expect(updatedEvidence.lastUsedAt, isNotNull);
    });

    test('Memory candidate - validity and conflict detection', () {
      final validCandidate = FfmMemoryCandidate(
        id: 'valid1',
        type: FfmMemoryType.preference,
        key: 'response_style',
        value: 'concise',
        evidence: FfmMemoryEvidence(
          source: FfmMemorySource.userExplicit,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          confidence: 0.9,
          approved: true,
        ),
      );

      expect(validCandidate.isValid, true);

      final invalidCandidate = FfmMemoryCandidate(
        id: 'invalid1',
        type: FfmMemoryType.preference,
        key: 'response_style',
        value: 'concise',
        evidence: FfmMemoryEvidence(
          source: FfmMemorySource.inferredPattern,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          confidence: 0.2, // Low confidence
          approved: false,
        ),
        status: FfmMemoryStatus.archived,
      );

      expect(invalidCandidate.isValid, false);

      // Conflict detection
      final conflictingCandidate = FfmMemoryCandidate(
        id: 'conflict1',
        type: FfmMemoryType.preference,
        key: 'response_style',
        value: 'detailed', // Different value
        evidence: FfmMemoryEvidence(
          source: FfmMemorySource.userExplicit,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          confidence: 0.9,
          approved: true,
        ),
      );

      expect(validCandidate.conflictsWith(conflictingCandidate), true);
      expect(validCandidate.isDuplicateOf(conflictingCandidate), false);
    });

    test('Context budget - limits per memory type', () {
      final strictBudget = FfmContextBudget(
        workingMemoryMax: 5,
        personalFactsMax: 5,
        preferencesMax: 3,
        goalsMax: 3,
        maxTotalItems: 20,
      );

      expect(strictBudget.workingMemoryMax, 5);
      expect(strictBudget.preferencesMax, 3);
      expect(strictBudget.maxTotalItems, 20);
    });

    test('Promotion candidate - validation and sensitive data detection', () {
      final validCandidate = FfmMemoryPromotionCandidate(
        type: FfmMemoryType.preference,
        key: 'response_style',
        value: 'concise',
        confidence: 0.8,
        reason: 'User explicitly requested short answers',
        requiresApproval: true,
      );

      expect(validCandidate.isValid, true);
      expect(validCandidate.isSensitive, false);

      final sensitiveCandidate = FfmMemoryPromotionCandidate(
        type: FfmMemoryType.explicitFact,
        key: 'password',
        value: 'secret123',
        confidence: 0.9,
        requiresApproval: true,
      );

      expect(sensitiveCandidate.isSensitive, true);
    });
  });
}
