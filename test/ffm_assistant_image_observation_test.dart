import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_local_model_gateway.dart';
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

class _NullImageGateway implements FfmAssistantLocalModelGateway {
  const _NullImageGateway();

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
        modelGateway: const _NullImageGateway(),
      );

      final intent = await interpreter.interpret(
        'gambar apa itu?',
        imagePath: '/private/assistant_chat_media/screenshot.jpg',
        currentDestination: FfmAssistantDestination.otherMenu,
      );

      expect(intent.type, FfmAssistantIntentType.unknown);
      expect(intent.responseOrigin, FfmAssistantResponseOrigin.localFallback);
      expect(intent.response, contains('hasil gambar yang valid'));
      expect(intent.response, isNot(contains('Lainnya berisi jalan')));
    },
  );
}
