import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';

void main() {
  group('Migrasi database v41', () {
    test('upgrade dari schema 30 mempertahankan data lama dan membuat tabel Asisten, personalisasi, feedback, Catatan Harian, Tugas, Rutinitas, serta Jadwal', () async {
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
      final routinesTables = await database
          .customSelect(
            "SELECT name FROM sqlite_master "
            "WHERE type = 'table' AND name IN "
            "('daily_routines', 'daily_routine_completions')",
          )
          .get();
      final scheduleTable = await database
          .customSelect(
            "SELECT name FROM sqlite_master "
            "WHERE type = 'table' AND name = 'schedule_entries'",
          )
          .getSingleOrNull();
      final personalizationTables = await database
          .customSelect(
            "SELECT name FROM sqlite_master "
            "WHERE type = 'table' AND name IN "
            "('user_corrections', 'user_preferences', 'interaction_patterns')",
          )
          .get();

      expect(version.data['user_version'], 41);
      expect(legacy.data['label'], 'tetap ada');
      expect(category.data['name'], 'Tetap Ada');
      expect(assistantTable, isNotNull);
      expect(feedbackTable, isNotNull);
      expect(dailyNotesTable, isNotNull);
      expect(tasksTable, isNotNull);
      expect(routinesTables, hasLength(2));
      expect(scheduleTable, isNotNull);
      expect(personalizationTables, hasLength(3));
    });

    test(
      'menambahkan kind pada activity_sessions lama yang belum memilikinya',
      () async {
        final executor = NativeDatabase.memory(
          setup: (database) {
            database.execute(
              'CREATE TABLE activity_sessions ('
              'id TEXT PRIMARY KEY, '
              'household_id TEXT NOT NULL, '
              'title TEXT NOT NULL, '
              'parent_session_id TEXT, '
              'category TEXT NOT NULL DEFAULT \'lainnya\', '
              'started_at INTEGER NOT NULL, '
              'ended_at INTEGER, '
              'scheduled_at INTEGER, '
              'due_date INTEGER, '
              'is_all_day INTEGER NOT NULL DEFAULT 0, '
              'is_completed INTEGER NOT NULL DEFAULT 0, '
              'priority INTEGER NOT NULL DEFAULT 0, '
              'status TEXT NOT NULL DEFAULT \'active\', '
              'notes TEXT, '
              'is_archived INTEGER NOT NULL DEFAULT 0, '
              'created_at INTEGER NOT NULL, '
              'updated_at INTEGER)',
            );
            database.execute(
              "INSERT INTO activity_sessions "
              "(id, household_id, title, started_at, created_at) "
              "VALUES ('legacy-activity', 'household', 'Aktivitas Lama', 1, 1)",
            );
            database.execute('PRAGMA user_version = 40');
          },
        );
        final database = AppDatabase(executor);
        addTearDown(database.close);

        final columns = await database
            .customSelect('PRAGMA table_info("activity_sessions")')
            .get();
        final kind = columns.where((row) => row.read<String>('name') == 'kind');
        final legacy = await database
            .customSelect(
              "SELECT kind, title FROM activity_sessions WHERE id = 'legacy-activity'",
            )
            .getSingle();

        expect(kind, hasLength(1));
        expect(legacy.data['kind'], 'timer');
        expect(legacy.data['title'], 'Aktivitas Lama');
      },
    );
  });
}
