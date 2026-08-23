import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_local_model_gateway.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';

class _FakeGateway implements FfmAssistantLocalModelGateway {
  const _FakeGateway(this.proposal);
  final FfmAssistantModelProposal? proposal;

  @override
  Future<FfmAssistantModelProposal?> propose({
    required String input,
    String? imagePath,
  }) async => proposal;

  @override
  Future<FfmAssistantModelProposal?> proposeWithContext({
    required String input,
    String? imagePath,
    String? pageContext,
    List<String> capabilityIds = const <String>[],
  }) async => proposal;
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
    'interpreter menolak pertanyaan di luar domain dengan respons elegan',
    () async {
      final gateway = _FakeGateway(
        const FfmAssistantModelProposal(
          intent: FfmAssistantIntentType.outOfDomain,
          confidence: .99,
        ),
      );
      final interpreter = FfmAssistantInterpreter(
        database,
        modelGateway: gateway,
      );

      final intent = await interpreter.interpret(
        'bagaimana cara budidaya ikan lele?',
      );

      expect(intent.type, FfmAssistantIntentType.outOfDomain);
      expect(intent.response, contains('asisten keuangan keluarga untuk FFM'));
      expect(intent.response, contains('di luar fitur'));
      expect(intent.draft, isNull);
    },
  );

  test(
    'pertanyaan literasi keuangan keluarga tidak dianggap out of domain',
    () async {
      final gateway = _FakeGateway(
        const FfmAssistantModelProposal(
          intent: FfmAssistantIntentType.help,
          confidence: .99,
        ),
      );
      final interpreter = FfmAssistantInterpreter(
        database,
        modelGateway: gateway,
      );

      final intent = await interpreter.interpret(
        'bagaimana cara menabung yang baik untuk dana darurat keluarga?',
      );

      expect(intent.type, FfmAssistantIntentType.help);
      expect(intent.responseMode, FfmAssistantResponseMode.localRules);
      expect(intent.response, contains('Edukasi Menabung'));
      expect(intent.response, contains('Goals'));
    },
  );

  test('proposal help SLM untuk topik finansial yang belum punya template tetap diterima', () async {
    final gateway = _FakeGateway(
      const FfmAssistantModelProposal(
        intent: FfmAssistantIntentType.help,
        confidence: .99,
      ),
    );
    final interpreter = FfmAssistantInterpreter(
      database,
      modelGateway: gateway,
    );

    final intent = await interpreter.interpret(
      'bagaimana membagi pendapatan keluarga untuk kebutuhan dan rencana jangka panjang?',
    );

    expect(intent.type, FfmAssistantIntentType.help);
    expect(intent.responseMode, FfmAssistantResponseMode.localModel);
    expect(intent.response, isNull);
  });
}
