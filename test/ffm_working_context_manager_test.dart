import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_chat_history_repository.dart';
import 'package:ffm_manager/features/assistant/data/ffm_working_context_manager.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_personal_context.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('FfmWorkingContext', () {
    test('toJson serializes all fields', () {
      final context = FfmWorkingContext(
        lastUserIntent: 'query_amount',
        lastReferencedEntity: 'food',
        currentTopic: 'spending',
        currentPeriod: 'current_month',
        currentGoal: 'savings_target',
        pendingClarification: 'Which account?',
        lastActionResult: 'navigate',
        lastUpdatedAt: DateTime(2026, 8, 25),
      );

      final json = context.toJson();
      expect(json['lastUserIntent'], 'query_amount');
      expect(json['lastReferencedEntity'], 'food');
      expect(json['currentTopic'], 'spending');
      expect(json['currentPeriod'], 'current_month');
      expect(json['currentGoal'], 'savings_target');
      expect(json['pendingClarification'], 'Which account?');
      expect(json['lastActionResult'], 'navigate');
      expect(json['lastUpdatedAt'], isNotNull);
    });

    test('fromJson restores all fields', () {
      final json = {
        'lastUserIntent': 'create',
        'lastReferencedEntity': 'transport',
        'currentTopic': 'income',
        'currentPeriod': 'current_week',
        'currentGoal': 'buy_car',
        'pendingClarification': null,
        'lastActionResult': 'success',
        'lastUpdatedAt': '2026-08-25T10:00:00.000',
      };

      final context = FfmWorkingContext.fromJson(json);
      expect(context.lastUserIntent, 'create');
      expect(context.lastReferencedEntity, 'transport');
      expect(context.currentTopic, 'income');
      expect(context.currentPeriod, 'current_week');
      expect(context.currentGoal, 'buy_car');
      expect(context.pendingClarification, isNull);
      expect(context.lastActionResult, 'success');
      expect(context.lastUpdatedAt, DateTime(2026, 8, 25, 10, 0, 0));
    });

    test('toJson/fromJson roundtrip preserves data', () {
      final original = FfmWorkingContext(
        lastUserIntent: 'view',
        currentTopic: 'liabilities',
        lastUpdatedAt: DateTime.now(),
      );
      final restored = FfmWorkingContext.fromJson(original.toJson());
      expect(restored.lastUserIntent, original.lastUserIntent);
      expect(restored.currentTopic, original.currentTopic);
    });

    test('isExpired returns true for old context', () {
      final old = FfmWorkingContext(
        lastUpdatedAt: DateTime.now().subtract(const Duration(hours: 25)),
      );
      expect(old.isExpired, true);
    });

    test('isExpired returns false for recent context', () {
      final recent = FfmWorkingContext(
        lastUpdatedAt: DateTime.now(),
      );
      expect(recent.isExpired, false);
    });

    test('isExpired returns true for null lastUpdatedAt', () {
      const noDate = FfmWorkingContext();
      expect(noDate.isExpired, true);
    });

    test('clear returns empty context', () {
      final context = FfmWorkingContext(
        lastUserIntent: 'test',
        currentTopic: 'spending',
      );
      final cleared = context.clear();
      expect(cleared.lastUserIntent, isNull);
      expect(cleared.currentTopic, isNull);
    });
  });

  group('FfmWorkingContextManager', () {
    test('updateAfterTurn persists context', () async {
      final history = FfmAssistantChatHistoryRepository();
      final manager = FfmWorkingContextManager(
        chatHistoryRepository: history,
      );

      await manager.updateAfterTurn(
        userQuery: 'pengeluaran bulan ini',
        assistantResponse: 'query_amount',
        extractedEntities: {
          'topic': 'spending',
          'period': 'current_month',
          'intent': 'query_amount',
        },
      );

      expect(manager.currentContext.currentTopic, 'spending');
      expect(manager.currentContext.currentPeriod, 'current_month');
      expect(manager.currentContext.lastUserIntent, 'query_amount');
      expect(manager.currentContext.lastUpdatedAt, isNotNull);
    });

    test('rebuildFromHistory loads persisted context', () async {
      final prefs = await SharedPreferences.getInstance();
      final history = FfmAssistantChatHistoryRepository();
      final manager = FfmWorkingContextManager(
        chatHistoryRepository: history,
        preferences: prefs,
      );

      await manager.updateAfterTurn(
        userQuery: 'target nabung',
        assistantResponse: 'create',
        extractedEntities: {
          'topic': 'goals',
          'intent': 'create',
        },
      );

      final manager2 = FfmWorkingContextManager(
        chatHistoryRepository: history,
        preferences: prefs,
      );
      await manager2.rebuildFromHistory();

      expect(manager2.currentContext.currentTopic, 'goals');
    });

    test('clear resets context and persists', () async {
      final history = FfmAssistantChatHistoryRepository();
      final manager = FfmWorkingContextManager(
        chatHistoryRepository: history,
      );

      await manager.updateAfterTurn(
        userQuery: 'test',
        assistantResponse: null,
        extractedEntities: {'topic': 'spending'},
      );

      expect(manager.currentContext.currentTopic, 'spending');

      await manager.clear();
      expect(manager.currentContext.currentTopic, isNull);
    });

    test('setPendingClarification works', () async {
      final history = FfmAssistantChatHistoryRepository();
      final manager = FfmWorkingContextManager(
        chatHistoryRepository: history,
      );

      expect(manager.hasPendingClarification, false);

      await manager.setPendingClarification('Which account?');
      expect(manager.hasPendingClarification, true);
      expect(manager.currentContext.pendingClarification, 'Which account?');
    });

    test('summary includes lastUpdatedAt', () async {
      final history = FfmAssistantChatHistoryRepository();
      final manager = FfmWorkingContextManager(
        chatHistoryRepository: history,
      );

      await manager.updateAfterTurn(
        userQuery: 'test',
        assistantResponse: null,
        extractedEntities: {},
      );

      final s = manager.summary;
      expect(s['lastUpdatedAt'], isNotNull);
    });

    test('extractSimpleEntities detects more topics', () async {
      final history = FfmAssistantChatHistoryRepository();
      final manager = FfmWorkingContextManager(
        chatHistoryRepository: history,
      );

      await manager.updateAfterTurn(
        userQuery: 'lihat hutang saya',
        assistantResponse: null,
        extractedEntities: {},
      );

      expect(manager.currentContext.currentTopic, 'liabilities');
    });
  });
}
