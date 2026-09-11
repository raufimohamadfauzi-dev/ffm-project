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
      final approvalTable = await database
          .customSelect(
            "SELECT name FROM sqlite_master "
            "WHERE type = 'table' AND name = 'assistant_agent_approvals'",
          )
          .getSingleOrNull();
      final nfcTables = await database
          .customSelect(
            "SELECT name FROM sqlite_master "
            "WHERE type = 'table' AND name IN "
            "('nfc_card_accounts', 'nfc_scan_snapshots')",
          )
          .get();
      final telegramDeliveries = await database
          .customSelect(
            "SELECT name FROM sqlite_master "
            "WHERE type = 'table' AND name = 'telegram_deliveries'",
          )
          .getSingleOrNull();

      expect(version.data['user_version'], 59);
      expect(legacy.data['label'], 'tetap ada');
      expect(category.data['name'], 'Tetap Ada');
      expect(assistantTable, isNotNull);
      expect(feedbackTable, isNotNull);
      expect(dailyNotesTable, isNotNull);
      expect(tasksTable, isNotNull);
      expect(routinesTables, hasLength(2));
      expect(scheduleTable, isNotNull);
      expect(personalizationTables, hasLength(3));
      expect(approvalTable, isNotNull);
      expect(nfcTables, hasLength(2));
      expect(telegramDeliveries, isNotNull);
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

  test('menambahkan scheduled_at pada activity_sessions lama yang belum memilikinya', () async {
    final executor = NativeDatabase.memory(
      setup: (database) {
        database.execute(
          'CREATE TABLE activity_sessions ('
          'id TEXT PRIMARY KEY, household_id TEXT NOT NULL, title TEXT NOT NULL, '
          'started_at INTEGER NOT NULL, created_at INTEGER NOT NULL)',
        );
        database.execute(
          "INSERT INTO activity_sessions "
          "(id, household_id, title, started_at, created_at) "
          "VALUES ('legacy-no-schedule', 'household', 'Aktivitas Lama', 1, 1)",
        );
        database.execute('PRAGMA user_version = 50');
      },
    );
    final database = AppDatabase(executor);
    addTearDown(database.close);

    final columns = await database
        .customSelect('PRAGMA table_info("activity_sessions")')
        .get();
    final legacy = await database
        .customSelect(
          "SELECT scheduled_at FROM activity_sessions "
          "WHERE id = 'legacy-no-schedule'",
        )
        .getSingle();

    expect(
      columns.where((row) => row.read<String>('name') == 'scheduled_at'),
      hasLength(1),
    );
    expect(legacy.data['scheduled_at'], isNull);
  });

  test(
    'menambahkan tautan sumber dan origin pada pengingat dari schema 55',
    () async {
      final executor = NativeDatabase.memory(
        setup: (database) {
          database.execute(
            'CREATE TABLE reminders ('
            'id TEXT PRIMARY KEY, household_id TEXT NOT NULL, title TEXT NOT NULL, '
            'note TEXT, scheduled_at INTEGER NOT NULL, '
            "recurrence_type TEXT NOT NULL DEFAULT 'once', "
            "weekdays_json TEXT NOT NULL DEFAULT '[]', "
            'is_active INTEGER NOT NULL DEFAULT 1, sound_uri TEXT, sound_name TEXT, '
            'default_snooze_minutes INTEGER NOT NULL DEFAULT 10, '
            'notification_id INTEGER NOT NULL, created_at INTEGER NOT NULL, '
            'updated_at INTEGER, calendar_event_id INTEGER, '
            'is_synced_to_calendar INTEGER NOT NULL DEFAULT 0, synced_at INTEGER)',
          );
          database.execute(
            "INSERT INTO reminders (id, household_id, title, scheduled_at, notification_id, created_at) "
            "VALUES ('legacy-reminder', 'local-household', 'Bayar tagihan', 1, 1, 1)",
          );
          database.execute('PRAGMA user_version = 55');
        },
      );
      final database = AppDatabase(executor);
      addTearDown(database.close);

      final columns = await database
          .customSelect('PRAGMA table_info("reminders")')
          .get();
      final legacy = await database
          .customSelect(
            "SELECT source_type, source_id FROM reminders WHERE id = 'legacy-reminder'",
          )
          .getSingle();

      expect(
        columns.where((row) => row.read<String>('name') == 'source_type'),
        hasLength(1),
      );
      expect(
        columns.where((row) => row.read<String>('name') == 'source_id'),
        hasLength(1),
      );
      expect(
        columns.where((row) => row.read<String>('name') == 'origin'),
        hasLength(1),
      );
      final reminder = await database
          .customSelect(
            "SELECT origin FROM reminders WHERE id = 'legacy-reminder'",
          )
          .getSingle();
      expect(reminder.data['origin'], 'user');
      expect(legacy.data['source_type'], isNull);
      expect(legacy.data['source_id'], isNull);
    },
  );

  group('Migrasi database v59', () {
    test('membuat index performa schema 59', () async {
      final executor = NativeDatabase.memory(
        setup: (database) {
          database.execute(
            'CREATE TABLE transactions ('
            'id TEXT PRIMARY KEY, household_id TEXT NOT NULL, category_id TEXT, '
            'merchant_id TEXT, is_deleted INTEGER NOT NULL DEFAULT 0, date INTEGER NOT NULL)',
          );
          database.execute(
            'CREATE TABLE reminders ('
            'id TEXT PRIMARY KEY, household_id TEXT NOT NULL, is_active INTEGER NOT NULL DEFAULT 1, scheduled_at INTEGER NOT NULL)',
          );
          database.execute(
            'CREATE TABLE assistant_memories ('
            'id TEXT PRIMARY KEY, household_id TEXT NOT NULL, kind TEXT NOT NULL, is_archived INTEGER NOT NULL DEFAULT 0)',
          );
          database.execute('PRAGMA user_version = 58');
        },
      );
      final database = AppDatabase(executor);
      addTearDown(database.close);

      final version = await database
          .customSelect('PRAGMA user_version')
          .getSingle();
      final schema59Indexes = await database
          .customSelect(
            "SELECT name FROM sqlite_master "
            "WHERE type = 'index' AND name IN ("
            "'idx_transactions_category_date', "
            "'idx_transactions_merchant_date', "
            "'idx_reminders_status_due', "
            "'idx_assistant_memories_kind'"
            ")",
          )
          .get();

      expect(version.data['user_version'], 59);
      expect(schema59Indexes, hasLength(4));
    });
  });
}
