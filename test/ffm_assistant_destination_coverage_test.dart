import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';

void main() {
  test('katalog mencakup seluruh destination submenu Gemini-only', () {
    final names = FfmAssistantCatalog.pages.map((page) => page.name).toSet();
    expect(
      names,
      containsAll(const [
        'Log aktivitas',
        'Pemasukan berkala',
        'Pusat privasi',
        'Struktur database',
        'Intelligence Dashboard',
      ]),
    );
    expect(
      FfmAssistantCatalog.pages,
      hasLength(FfmAssistantDestination.values.length - 1),
    );
    expect(
      FfmAssistantCatalog.pages.map((page) => page.destination).toSet(),
      hasLength(FfmAssistantDestination.values.length - 1),
    );
  });

  test(
    'permintaan daftar lengkap menu lainnya memuat semua kartu UI',
    () async {
      final database = createInMemoryDatabaseForTests();
      try {
        final interpreter = FfmAssistantInterpreter(database);
        final intent = await interpreter.interpret(
          'Tampilkan daftar lengkap semua menu yang ada di bagian Lainnya beserta fungsinya',
        );
        expect(intent.type, FfmAssistantIntentType.listPages);
        expect(intent.destination, FfmAssistantDestination.otherMenu);
        expect(intent.response, isNotNull);
        for (final item in FfmAssistantCatalog.otherMenuItems) {
          expect(intent.response, contains(item.name));
          expect(intent.response, contains(item.description));
        }
        expect(FfmAssistantCatalog.otherMenuItems, hasLength(13));
      } finally {
        await database.close();
      }
    },
  );

  test('perintah buka mengenali seluruh submenu baru', () async {
    final database = createInMemoryDatabaseForTests();
    try {
      final interpreter = FfmAssistantInterpreter(database);
      const cases = <String, FfmAssistantDestination>{
        'log aktivitas': FfmAssistantDestination.activityLog,

        'pemasukan berkala': FfmAssistantDestination.recurringTransaction,

        'pusat privasi': FfmAssistantDestination.privacyCenter,
        'struktur database': FfmAssistantDestination.databaseStructure,

        'gemini cloud': FfmAssistantDestination.intelligenceDashboard,
        'analisa': FfmAssistantDestination.analysis,
      };
      for (final entry in cases.entries) {
        final intent = await interpreter.interpret('buka ${entry.key}');
        expect(intent.type, FfmAssistantIntentType.openPage, reason: entry.key);
        expect(intent.destination, entry.value, reason: entry.key);
      }
    } finally {
      await database.close();
    }
  });
}
