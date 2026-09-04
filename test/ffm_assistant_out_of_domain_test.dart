import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';

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
      final interpreter = FfmAssistantInterpreter(database);

      final intent = await interpreter.interpret(
        'bagaimana cara budidaya ikan lele?',
      );

      expect(intent.responseOrigin, FfmAssistantResponseOrigin.cloudError);
      expect(intent.response, contains('belum siap'));
      expect(intent.draft, isNull);
    },
  );

  test(
    'pertanyaan literasi keuangan keluarga tidak dianggap out of domain',
    () async {
      final interpreter = FfmAssistantInterpreter(database);

      final intent = await interpreter.interpret(
        'bagaimana cara menabung yang baik untuk dana darurat keluarga?',
      );

      expect(intent.type, FfmAssistantIntentType.help);
      expect(intent.responseMode, FfmAssistantResponseMode.localRules);
      expect(intent.response, contains('Edukasi Menabung'));
      expect(intent.response, contains('Goals'));
    },
  );

  test(
    'pertanyaan finansial terbuka menunggu Gemini saat belum diverifikasi',
    () async {
      final interpreter = FfmAssistantInterpreter(database);

      final intent = await interpreter.interpret(
        'jelaskan perbedaan antara hujan dan gerimis secara singkat',
      );

      expect(intent.responseOrigin, FfmAssistantResponseOrigin.cloudError);
      expect(intent.response, contains('belum siap'));
      expect(intent.draft, isNull);
    },
  );
}
