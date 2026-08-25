import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';

void main() {
  group('Migrasi database v37', () {
    test('upgrade dari schema 30 mempertahankan data lama dan membuat tabel Asisten, personalisasi, feedback, Catatan Harian, serta Tugas', () async {
      final executor = NativeDatabase.memory(
        setup: (database) {
          database.execute(
            'CREATE TABLE legacy_probe ('
            'id INTEGER PRIMARY KEY, label TEXT NOT NULL)',
          );
          database.execute(
            "INSERT INTO legacy_probe (id, label) VALUES (1, 'tetap ada')",
          );
          database.execute(
            'CREATE TABLE categories ('
            'id TEXT PRIMARY KEY, '
            'household_id TEXT NOT NULL, '
            'name TEXT NOT NULL)',
          );
          database.execute(
            "INSERT INTO categories (id, household_id, name) "
            "VALUES ('category-v30', 'local-household', 'Tetap Ada')",
          );
          database.execute('PRAGMA user_version = 30');
        },
      );
      final database = AppDatabase(executor);
      addTearDown(database.close);

      final version = await database
          .customSelect('PRAGMA user_version')
          .getSingle();
      final legacy = await database
          .customSelect('SELECT label FROM legacy_probe WHERE id = 1')
          .getSingle();
      final category = await database
          .customSelect(
            'SELECT name FROM categories WHERE id = \'category-v30\'',
          )
          .getSingle();
      final assistantTable = await database
          .customSelect(
            "SELECT name FROM sqlite_master "
            "WHERE type = 'table' AND name = 'assistant_unanswered_questions'",
          )
          .getSingleOrNull();
      final feedbackTable = await database
          .customSelect(
            "SELECT name FROM sqlite_master "
            "WHERE type = 'table' AND name = 'assistant_response_feedbacks'",
          )
          .getSingleOrNull();
      final dailyNotesTable = await database
          .customSelect(
            "SELECT name FROM sqlite_master "
            "WHERE type = 'table' AND name = 'daily_notes'",
          )
          .getSingleOrNull();
      final tasksTable = await database
          .customSelect(
            "SELECT name FROM sqlite_master "
            "WHERE type = 'table' AND name = 'tasks'",
          )
          .getSingleOrNull();
      final personalizationTables = await database
          .customSelect(
            "SELECT name FROM sqlite_master "
            "WHERE type = 'table' AND name IN "
            "('user_corrections', 'user_preferences', 'interaction_patterns')",
          )
          .get();

      expect(version.data['user_version'], 37);
      expect(legacy.data['label'], 'tetap ada');
      expect(category.data['name'], 'Tetap Ada');
      expect(assistantTable, isNotNull);
      expect(feedbackTable, isNotNull);
      expect(dailyNotesTable, isNotNull);
      expect(tasksTable, isNotNull);
      expect(personalizationTables, hasLength(3));
    });
  });
}
