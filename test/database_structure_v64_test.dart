import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/database/ffm_database_structure_service.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_query_tools.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Struktur database v64', () {
    test('metadata dinamis mengikuti seluruh tabel runtime Drift', () async {
      final database = createInMemoryDatabaseForTests();
      addTearDown(database.close);
      final structure = await FfmDatabaseStructureService(database).read();
      final runtimeTables = database.allTables
          .map((table) => table.actualTableName)
          .toSet();

      expect(structure.tableCount, runtimeTables.length);
      expect(
        structure.tables.map((table) => table.tableName).toSet(),
        runtimeTables,
      );
      expect(structure.missingDescriptions, isEmpty);
      expect(structure.tables.every((table) => table.columnCount > 0), isTrue);
    });

    test(
      'Asisten menjelaskan metadata struktur tanpa membaca data finansial',
      () async {
        final database = createInMemoryDatabaseForTests();
        addTearDown(database.close);
        final registry = FfmAssistantQueryRegistry(database);

        final answer = await registry.tryAnswer(
          'jelasin struktur database aplikasi FFM',
          householdId: AppContext.householdId,
        );

        expect(answer, isNotNull);
        expect(answer!.title, 'Struktur database FFM');
        expect(answer.message, contains('metadata'));
        expect(answer.message, contains('bukan isi transaksi'));
        expect(answer.message, isNot(contains('Rp')));
      },
    );

    test('interpreter memprioritaskan pertanyaan data aplikasi sebagai struktur database', () async {
      final database = createInMemoryDatabaseForTests();
      addTearDown(database.close);
      final intent = await FfmAssistantInterpreter(database)
          .interpret('ada data apa saja di aplikasi FFM?');

      expect(intent.type, FfmAssistantIntentType.queryData);
      expect(intent.response, contains('Struktur database FFM'));
      expect(intent.response, contains('bukan isi transaksi'));
    });

    test('setiap destination punya penjelasan halaman yang tidak kosong', () {
      for (final destination in FfmAssistantDestination.values) {
        expect(FfmAssistantCatalog.detailFor(destination).trim(), isNotEmpty);
      }
    });
  });
}
