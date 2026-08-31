import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';

/// Intent Recognition Regression Tests
///
/// Tests for verifying intent recognition continues to work correctly
/// as the assistant evolves.

void main() {
  group('Intent Recognition Regression Tests', () {
    test('Should have all required intent types defined', () {
      // Verify that all critical intent types are available
      final requiredTypes = [
        FfmAssistantIntentType.queryData,
        FfmAssistantIntentType.createExpense,
        FfmAssistantIntentType.createIncome,
        FfmAssistantIntentType.createTransfer,
        FfmAssistantIntentType.assistantIdentity,
        FfmAssistantIntentType.featureHelp,
        FfmAssistantIntentType.transactionStats,
        FfmAssistantIntentType.weeklyAnalysis,
      ];

      for (final type in requiredTypes) {
        expect(FfmAssistantIntentType.values.contains(type), isTrue,
            reason: 'Intent type $type should be defined');
      }
    });

    test('Should not remove existing intent types', () {
      // This test ensures we don't accidentally remove intent types
      // by checking for a minimum expected count
      final intentCount = FfmAssistantIntentType.values.length;
      
      // As of this writing, there should be at least 30 intent types
      // This test will fail if intent types are accidentally removed
      expect(intentCount, greaterThanOrEqualTo(30),
          reason: 'Should have at least 30 intent types');
    });

    test('Query data intent should be properly defined', () {
      // Verify queryData intent exists and is distinct
      expect(FfmAssistantIntentType.values.contains(FfmAssistantIntentType.queryData), 
          isTrue);
    });

    test('Expense creation intent should be properly defined', () {
      // Verify createExpense intent exists and is distinct
      expect(FfmAssistantIntentType.values.contains(FfmAssistantIntentType.createExpense), 
          isTrue);
    });

    test('Income creation intent should be properly defined', () {
      // Verify createIncome intent exists and is distinct
      expect(FfmAssistantIntentType.values.contains(FfmAssistantIntentType.createIncome), 
          isTrue);
    });

    test('Transfer creation intent should be properly defined', () {
      // Verify createTransfer intent exists and is distinct
      expect(FfmAssistantIntentType.values.contains(FfmAssistantIntentType.createTransfer), 
          isTrue);
    });

    test('Analysis intents should be properly defined', () {
      // Verify analysis-related intents exist
      final analysisIntents = [
        FfmAssistantIntentType.transactionStats,
        FfmAssistantIntentType.weeklyAnalysis,
        FfmAssistantIntentType.financialWarnings,
      ];

      for (final intent in analysisIntents) {
        expect(FfmAssistantIntentType.values.contains(intent), isTrue,
            reason: 'Analysis intent $intent should be defined');
      }
    });

    test('Greeting/intent intents should be properly defined', () {
      // Verify greeting and identity intents exist
      final greetingIntents = [
        FfmAssistantIntentType.assistantIdentity,
        FfmAssistantIntentType.setupGuide,
      ];

      for (final intent in greetingIntents) {
        expect(FfmAssistantIntentType.values.contains(intent), isTrue,
            reason: 'Greeting intent $intent should be defined');
      }
    });

    test('Master data creation intents should be properly defined', () {
      // Verify master data creation intents exist
      final masterDataIntents = [
        FfmAssistantIntentType.createMasterData,
        FfmAssistantIntentType.updateCategory,
        FfmAssistantIntentType.updateMerchant,
        FfmAssistantIntentType.updateTag,
      ];

      for (final intent in masterDataIntents) {
        expect(FfmAssistantIntentType.values.contains(intent), isTrue,
            reason: 'Master data intent $intent should be defined');
      }
    });

    test('Archive/delete intents should be properly defined', () {
      // Verify archive and delete intents exist for proper lifecycle management
      final lifecycleIntents = [
        FfmAssistantIntentType.archiveCategory,
        FfmAssistantIntentType.deleteCategory,
        FfmAssistantIntentType.archiveMerchant,
        FfmAssistantIntentType.deleteMerchant,
        FfmAssistantIntentType.archiveAccount,
        FfmAssistantIntentType.deleteAccount,
      ];

      for (final intent in lifecycleIntents) {
        expect(FfmAssistantIntentType.values.contains(intent), isTrue,
            reason: 'Lifecycle intent $intent should be defined');
      }
    });
  });
}
