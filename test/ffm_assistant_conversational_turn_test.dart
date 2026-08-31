import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';

void main() {
  late AppDatabase database;
  late FfmAssistantInterpreter interpreter;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    interpreter = FfmAssistantInterpreter(database);
  });

  tearDown(() async {
    await database.close();
  });

  group('Conversational Turn Awareness', () {
    test('merespon tanggapan "ada" setelah asisten menyapa dan menawarkan bantuan', () async {
      const lastAssistantGreeting =
          'Halo! Aku Asisten FFM, siap membantu mencatat transaksi...\n\nAda yang bisa kubantu hari ini?';

      final intent = await interpreter.interpret(
        'ada',
        lastAssistantMessage: lastAssistantGreeting,
      );

      expect(intent.type, FfmAssistantIntentType.help);
      expect(intent.response, contains('Aku siap membantu'));
      expect(intent.response, contains('Catat transaksi'));
      expect(intent.confidence, greaterThanOrEqualTo(0.95));
    });

    test('merespon tanggapan "iya" / "mau" setelah asisten menyapa', () async {
      const lastAssistantGreeting =
          'Halo! Aku Asisten FFM... Ada yang bisa kubantu hari ini?';

      final intent = await interpreter.interpret(
        'iya mau',
        lastAssistantMessage: lastAssistantGreeting,
      );

      expect(intent.type, FfmAssistantIntentType.help);
      expect(intent.response, contains('Aku siap membantu'));
    });

    test('merespon penolakan sopan "tidak" / "makasih" setelah asisten menyapa', () async {
      const lastAssistantGreeting =
          'Halo! Aku Asisten FFM... Ada yang bisa kubantu hari ini?';

      final intent = await interpreter.interpret(
        'tidak ada, makasih',
        lastAssistantMessage: lastAssistantGreeting,
      );

      expect(intent.type, FfmAssistantIntentType.help);
      expect(intent.response, contains('tidak masalah'));
    });

    test('interpretMany meneruskan lastAssistantMessage ke interpret', () async {
      const lastAssistantGreeting =
          'Halo! Aku Asisten FFM... Ada yang bisa kubantu hari ini?';

      final intents = await interpreter.interpretMany(
        'ada',
        lastAssistantMessage: lastAssistantGreeting,
      );

      expect(intents.length, 1);
      expect(intents.first.type, FfmAssistantIntentType.help);
      expect(intents.first.response, contains('Aku siap membantu'));
    });

    test('tanpa konteks pesan sapaan, pesan umum tetap diproses secara independen', () async {
      final intent = await interpreter.interpret('halo asisten');
      expect(intent.type, FfmAssistantIntentType.help);
      expect(intent.response, anyOf(contains('Halo!'), contains('Hai!')));
    });

    test('perintah "pindah ke halaman riwayat asisten" langsung membuka Pengetahuan Asisten secara instan', () async {
      final intent = await interpreter.interpret('pindah ke halaman riwayat asisten');
      expect(intent.type, FfmAssistantIntentType.openPage);
      expect(intent.destination, FfmAssistantDestination.assistantTraining);
      expect(intent.response, contains('Pengetahuan Asisten'));
    });
  });
}
