import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_local_model_gateway.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_planner.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:flutter_test/flutter_test.dart';

class _ImageObservationGateway implements FfmAssistantLocalModelGateway {
  const _ImageObservationGateway(this._proposal);

  final FfmAssistantModelProposal _proposal;

  @override
  Future<FfmAssistantModelProposal?> propose({
    required String input,
    String? imagePath,
  }) async => _proposal;

  @override
  Future<FfmAssistantModelProposal?> proposeWithContext({
    required String input,
    String? imagePath,
    String? pageContext,
    String? conversationHistory,
    List<String> capabilityIds = const <String>[],
  }) async => _proposal;
}

class _DiagnosedNullImageGateway
    implements FfmAssistantLocalModelGateway, FfmAssistantVisionDiagnostics {
  const _DiagnosedNullImageGateway(this.lastVisionFailure);

  @override
  final FfmAssistantVisionFailure lastVisionFailure;

  @override
  Future<FfmAssistantModelProposal?> propose({
    required String input,
    String? imagePath,
  }) async => null;

  @override
  Future<FfmAssistantModelProposal?> proposeWithContext({
    required String input,
    String? imagePath,
    String? pageContext,
    String? conversationHistory,
    List<String> capabilityIds = const <String>[],
  }) async => null;
}

void main() {
  test('observasi screenshot model menjadi jawaban chat tanpa draf', () async {
    final database = createInMemoryDatabaseForTests();
    addTearDown(database.close);
    final interpreter = FfmAssistantInterpreter(
      database,
      modelGateway: const _ImageObservationGateway(
        FfmAssistantModelProposal(
          intent: FfmAssistantIntentType.help,
          confidence: .9,
          notes: 'Gambar menampilkan layar error Flutter dengan teks Invalid argument(s): 380.0.',
        ),
      ),
    );

    final intent = await interpreter.interpret(
      'gambar apa ini?',
      imagePath: '/private/assistant_chat_media/screenshot.jpg',
      currentDestination: FfmAssistantDestination.otherMenu,
    );

    expect(intent.type, FfmAssistantIntentType.help);
    expect(intent.draft, isNull);
    expect(intent.response, contains('Invalid argument(s): 380.0'));
    expect(intent.responseOrigin, FfmAssistantResponseOrigin.localSlm);
    expect(intent.response, isNot(contains('Lainnya berisi jalan')));
  });

  test(
    'gambar tanpa proposal valid menjadi fallback SLM, bukan bantuan halaman',
    () async {
      final database = createInMemoryDatabaseForTests();
      addTearDown(database.close);
      final interpreter = FfmAssistantInterpreter(
        database,
        modelGateway: const _DiagnosedNullImageGateway(
          FfmAssistantVisionFailure(
            FfmAssistantVisionFailureCode.nativeInitializationFailed,
          ),
        ),
      );

      final intent = await interpreter.interpret(
        'gambar apa itu?',
        imagePath: '/private/assistant_chat_media/screenshot.jpg',
        currentDestination: FfmAssistantDestination.otherMenu,
      );

      expect(intent.type, FfmAssistantIntentType.unknown);
      expect(intent.responseOrigin, FfmAssistantResponseOrigin.localFallback);
      expect(
        intent.visionFailure?.code,
        FfmAssistantVisionFailureCode.nativeInitializationFailed,
      );
      expect(
        intent.response,
        contains('mesin visi lokal belum berhasil disiapkan'),
      );
      expect(intent.response, isNot(contains('Lainnya berisi jalan')));
    },
  );

  test(
    'nota gambar hanya menjadi draft transaksi yang wajib dikonfirmasi',
    () async {
      final database = createInMemoryDatabaseForTests();
      addTearDown(database.close);
      final interpreter = FfmAssistantInterpreter(
        database,
        modelGateway: _ImageObservationGateway(
          FfmAssistantModelProposal(
            intent: FfmAssistantIntentType.createExpense,
            confidence: .9,
            draft: FfmAssistantDraft(
              kind: FfmAssistantDraftKind.expense,
              createdAt: DateTime(2026, 8, 25),
              title: 'Toko Uji',
              amount: 25000,
              categoryName: 'Makan',
            ),
          ),
        ),
      );

      final intent = await interpreter.interpret(
        'catat dari nota ini',
        imagePath: '/private/assistant_chat_media/receipt.jpg',
        currentDestination: FfmAssistantDestination.transactions,
      );
      final plan = FfmAssistantActionPlanner().planFor(intent);

      expect(intent.type, FfmAssistantIntentType.createExpense);
      expect(intent.draft?.kind, FfmAssistantDraftKind.expense);
      expect(intent.draft?.amount, 25000);
      expect(intent.needsConfirmation, isTrue);
      expect(intent.responseOrigin, FfmAssistantResponseOrigin.localSlm);
      expect(
        plan?.steps.map((step) => step.capabilityId),
        containsAll(<String>['draft.expense', 'mutate.save_draft']),
      );
      expect(await database.select(database.transactions).get(), isEmpty);
    },
  );
}
