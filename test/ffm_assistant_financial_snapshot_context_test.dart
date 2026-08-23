import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_local_model_gateway.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';

class _CapturingGateway implements FfmAssistantLocalModelGateway {
  String? pageContext;

  @override
  Future<FfmAssistantModelProposal?> propose({
    required String input,
    String? imagePath,
  }) async => const FfmAssistantModelProposal(
    intent: FfmAssistantIntentType.help,
    confidence: .95,
  );

  @override
  Future<FfmAssistantModelProposal?> proposeWithContext({
    required String input,
    String? imagePath,
    String? pageContext,
    List<String> capabilityIds = const <String>[],
  }) async {
    this.pageContext = pageContext;
    return const FfmAssistantModelProposal(
      intent: FfmAssistantIntentType.help,
      confidence: .95,
    );
  }
}

void main() {
  late AppDatabase database;

  setUp(() {
    database = createInMemoryDatabaseForTests();
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'context SLM memakai snapshot agregat dan bukan raw transaction rows',
    () async {
      final now = DateTime(2026, 8, 23);
      await database
          .into(database.transactions)
          .insert(
            TransactionsCompanion.insert(
              id: 'income-context',
              householdId: AppContext.householdId,
              type: 'income',
              amount: 8000000,
              date: now,
              recordedAt: now,
              createdAt: now,
              note: const Value('Rahasia keluarga'),
            ),
          );
      await database
          .into(database.transactions)
          .insert(
            TransactionsCompanion.insert(
              id: 'expense-context',
              householdId: AppContext.householdId,
              type: 'expense',
              amount: -3000000,
              date: now,
              recordedAt: now,
              createdAt: now,
            ),
          );

      final gateway = _CapturingGateway();
      final interpreter = FfmAssistantInterpreter(
        database,
        modelGateway: gateway,
        clock: () => now,
      );

      final intent = await interpreter.interpret(
        'bagaimana membagi pendapatan keluarga untuk kebutuhan dan rencana jangka panjang?',
      );

      expect(intent.type, FfmAssistantIntentType.help);
      expect(intent.responseMode, FfmAssistantResponseMode.localModel);
      expect(gateway.pageContext, contains('income=8000000'));
      expect(gateway.pageContext, contains('expenses=3000000'));
      expect(gateway.pageContext, contains('quality=sufficient'));
      expect(gateway.pageContext, isNot(contains('Rahasia keluarga')));
    },
  );
}
