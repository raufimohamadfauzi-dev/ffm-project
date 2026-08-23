import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';

void main() {
  test(
    'setiap halaman katalog mengenali kemampuan, isi, dan status generik',
    () {
      for (final page in FfmAssistantCatalog.pages) {
        final alias = page.aliases.first;
        final capability = FfmAssistantCatalog.classifyBasicQuestion(
          'apakah bisa $alias?',
        );
        final contents = FfmAssistantCatalog.classifyBasicQuestion(
          'ada apa saja di $alias?',
        );
        final completeness = FfmAssistantCatalog.classifyBasicQuestion(
          '$alias sudah lengkap?',
        );

        expect(capability?.page.destination, page.destination);
        expect(capability?.kind, FfmAssistantBasicQuestionKind.capability);
        expect(contents?.page.destination, page.destination);
        expect(contents?.kind, FfmAssistantBasicQuestionKind.contents);
        expect(completeness?.page.destination, page.destination);
        expect(completeness?.kind, FfmAssistantBasicQuestionKind.completeness);
      }
    },
  );

  test('status section non-data dijawab jujur tanpa mengada-ada', () {
    final question = FfmAssistantCatalog.classifyBasicQuestion(
      'model lokal sudah lengkap?',
    );

    expect(question?.page.destination, FfmAssistantDestination.localModel);
    expect(
      FfmAssistantCatalog.answerBasicQuestion(question!),
      contains('bukan section data'),
    );
  });
}
