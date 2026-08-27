import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Households,
    Categories,
    Merchants,
    Tags,
    Accounts,
    TransactionParties,
    Transactions,
    TransactionItems,
    TransactionTags,
    Attachments,
    Transfers,
    EnvelopeBudgets,
    EnvelopeTransfers,
    Assets,
    Goals,
    Liabilities,
    Receivables,
    RecurringTransactions,
    RecurringTransactionRuns,
    Reminders,
    ReminderHistories,
    ActivitySessions,
    ActivityCheckpoints,
    ActivityEntries,
    DailyNotes,
    Tasks,
    DailyRoutines,
    DailyRoutineCompletions,
    ScheduleEntries,
    AccountReconciliationLogs,
    HijriSettings,
    HijriMonthOverrides,
    HijriCorrectionLogs,
    AssistantMemories,
    AssistantLearningExamples,
    AssistantUnansweredQuestions,
    AssistantResponseFeedbacks,
    UserCorrections,
    UserPreferences,
    InteractionPatterns,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  factory AppDatabase.openDefault() => AppDatabase(_openConnection());

  @override
  int get schemaVersion => 41;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      await _createActivityIndexes();
      await _createDailyNoteIndexes();
      await _createTaskIndexes();
      await _createDailyRoutineIndexes();
      await _createScheduleIndexes();
      await _createAssistantMemoryIndexes();
      await _createAssistantLearningIndexes();
      await _createAssistantUnansweredQuestionIndexes();
      await _createAssistantResponseFeedbackIndexes();
      await _createPersonalizationIndexes();
      await _seedInitialData();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      // Jangan memanggil createAll() saat upgrade. Setiap tabel atau kolom
      // baru dibuat hanya pada batas versi asalnya agar database pengguna lama
      // tidak mencoba membuat ulang tabel yang sudah ada.
      if (from < 21) {
        await m.addColumn(tags, tags.isArchived);
      }
      if (from < 22) {
        await m.addColumn(transactions, transactions.receiptRawText);
        await m.addColumn(transactions, transactions.receiptNumber);
        await m.addColumn(transactions, transactions.receiptPaidAmount);
        await m.addColumn(transactions, transactions.receiptChangeAmount);
      }
      if (from < 23) {
        await m.addColumn(transactions, transactions.sourceId);
        await m.addColumn(transactions, transactions.recurringTransactionId);
        await m.addColumn(
          recurringTransactions,
          recurringTransactions.sourceId,
        );
        await m.addColumn(recurringTransactions, recurringTransactions.note);
      }
      if (from < 24) {
        await m.addColumn(
          recurringTransactions,
          recurringTransactions.ratePercent,
        );
        await m.addColumn(
          recurringTransactions,
          recurringTransactions.calcMode,
        );
        await m.createTable(accountReconciliationLogs);
      }
      if (from < 25) {
        await _seedInitialData();
      }
      if (from < 26) {
        await m.addColumn(assets, assets.isArchived);
      }
      if (from < 27) {
        await m.createTable(reminders);
        await m.createTable(reminderHistories);
      }
      if (from < 28) {
        await m.createTable(activitySessions);
        await m.createTable(activityCheckpoints);
        await m.createTable(activityEntries);
        await _createActivityIndexes();
      }
      if (from < 29) {
        await m.addColumn(activitySessions, activitySessions.parentSessionId);
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_activity_sessions_parent '
          'ON activity_sessions (parent_session_id)',
        );
      }
      if (from < 30) {
        await m.addColumn(categories, categories.defaultBudgetPeriod);
        await _applyDefaultBudgetPeriods();
      }
      if (from < 31) {
        await m.createTable(assistantMemories);
        await _createAssistantMemoryIndexes();
      }
      if (from < 32) {
        await m.createTable(assistantLearningExamples);
        await _createAssistantLearningIndexes();
      }
      if (from < 33) {
        await m.createTable(assistantUnansweredQuestions);
        await _createAssistantUnansweredQuestionIndexes();
      }
      if (from < 34) {
        await m.createTable(userCorrections);
        await m.createTable(userPreferences);
        await m.createTable(interactionPatterns);
        await _createPersonalizationIndexes();
      }
      if (from < 35) {
        await m.createTable(assistantResponseFeedbacks);
        await _createAssistantResponseFeedbackIndexes();
      }
      if (from < 36) {
        await m.createTable(dailyNotes);
        await _createDailyNoteIndexes();
      }
      if (from < 37) {
        await m.createTable(tasks);
        await _createTaskIndexes();
      }
      if (from < 38) {
        await m.createTable(dailyRoutines);
        await m.createTable(dailyRoutineCompletions);
        await _createDailyRoutineIndexes();
      }
      if (from < 39) {
        await m.createTable(scheduleEntries);
        await _createScheduleIndexes();
      }
      if (from < 40 &&
          await _hasColumns('categories', const [
            'type',
            'default_budget_period',
            'is_active',
            'created_at',
          ])) {
        await _seedActivityCategories();
      }
      if (from < 41 &&
          await _hasTable('activity_sessions') &&
          !await _hasColumns('activity_sessions', const ['kind'])) {
        await customStatement(
          "ALTER TABLE activity_sessions "
          "ADD COLUMN kind TEXT NOT NULL DEFAULT 'timer'",
        );
      }
      if (from < 20) {
        await _seedInitialData();
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Future<bool> _hasTable(String table) async {
    final row = await customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      variables: [Variable.withString(table)],
    ).getSingleOrNull();
    return row != null;
  }

  Future<bool> _hasColumns(String table, List<String> columns) async {
    final rows = await customSelect('PRAGMA table_info("$table")').get();
    final available = rows.map((row) => row.read<String>('name')).toSet();
    return columns.every(available.contains);
  }

  Future<void> _createActivityIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_activity_sessions_household_started '
      'ON activity_sessions (household_id, started_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_activity_sessions_parent '
      'ON activity_sessions (parent_session_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_activity_checkpoints_session_sequence '
      'ON activity_checkpoints (session_id, sequence)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_activity_entries_household_started_type '
      'ON activity_entries (household_id, started_at, activity_type)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_activity_entries_session '
      'ON activity_entries (session_id)',
    );
  }

  Future<void> _createDailyNoteIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_daily_notes_household_date '
      'ON daily_notes (household_id, note_date, is_archived)',
    );
  }

  Future<void> _createTaskIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_tasks_household_status_due '
      'ON tasks (household_id, is_archived, status, due_date)',
    );
  }

  Future<void> _createDailyRoutineIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_daily_routines_household_active '
      'ON daily_routines (household_id, is_archived, is_active, title)',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_daily_routine_completions_day '
      'ON daily_routine_completions (routine_id, routine_date)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_daily_routine_completions_household_day '
      'ON daily_routine_completions (household_id, routine_date)',
    );
  }

  Future<void> _createScheduleIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_schedule_entries_household_date '
      'ON schedule_entries '
      '(household_id, is_archived, scheduled_date, is_all_day, start_minutes)',
    );
  }

  Future<void> _createAssistantMemoryIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_assistant_memories_household_kind '
      'ON assistant_memories (household_id, kind, is_archived)',
    );
  }

  Future<void> _createAssistantLearningIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_assistant_learning_examples_household '
      'ON assistant_learning_examples '
      '(household_id, is_archived, intent_label, created_at)',
    );
  }

  Future<void> _createAssistantUnansweredQuestionIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_assistant_unanswered_questions_open '
      'ON assistant_unanswered_questions '
      '(household_id, is_resolved, updated_at)',
    );
  }

  Future<void> _createAssistantResponseFeedbackIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_assistant_response_feedbacks_review '
      'ON assistant_response_feedbacks '
      '(household_id, review_status, is_archived, updated_at)',
    );
  }

  Future<void> _createPersonalizationIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_user_corrections_lookup '
      'ON user_corrections '
      '(household_id, merchant_name, field_name, timestamp)',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_user_preferences_key '
      'ON user_preferences (household_id, preference_key)',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_interaction_patterns_lookup '
      'ON interaction_patterns (household_id, merchant_name, field_name)',
    );
  }

  Future<void> _applyDefaultBudgetPeriods() async {
    const defaults = <(String, String, String)>[
      ('Makan & minum', 'expense', 'weekly'),
      ('Belanja rumah', 'expense', 'monthly'),
      ('Belanja pasar', 'expense', 'weekly'),
      ('Transportasi', 'expense', 'weekly'),
      ('BBM motor', 'expense', 'weekly'),
      ('BBM mobil', 'expense', 'weekly'),
      ('Tagihan', 'expense', 'monthly'),
      ('Tagihan rumah', 'expense', 'monthly'),
      ('Listrik & air', 'expense', 'monthly'),
      ('Gas LPG', 'expense', 'monthly'),
      ('Pulsa & internet', 'expense', 'monthly'),
      ('Beras', 'expense', 'monthly'),
      ('Sabun & kebersihan', 'expense', 'monthly'),
      ('Kebutuhan dapur', 'expense', 'monthly'),
      ('Kesehatan', 'expense', 'monthly'),
      ('Sandal & sepatu', 'expense', 'none'),
      ('Pakaian', 'expense', 'none'),
      ('Perlengkapan rumah', 'expense', 'none'),
      ('Servis kendaraan', 'expense', 'none'),
      ('Perawatan kendaraan', 'expense', 'none'),
      ('Kebutuhan sekolah', 'expense', 'none'),
      ('Kebutuhan musiman', 'expense', 'none'),
      ('Pertanian', 'expense', 'none'),
      ('Biaya admin', 'expense', 'none'),
      ('Lainnya', 'expense', 'none'),
    ];
    final existing = await (select(
      categories,
    )..where((row) => row.householdId.equals('local-household'))).get();
    for (final (name, type, period) in defaults) {
      Category? match;
      for (final row in existing) {
        if (row.type == type &&
            row.name.trim().toLowerCase() == name.toLowerCase()) {
          match = row;
          break;
        }
      }
      if (match == null) {
        final slug = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
        await into(categories).insert(
          CategoriesCompanion.insert(
            id: 'seed-$type-$slug',
            householdId: 'local-household',
            name: name,
            type: type,
            defaultBudgetPeriod: Value(period),
            createdAt: DateTime.now(),
          ),
        );
      } else if (match.defaultBudgetPeriod == 'none' && period != 'none') {
        await (update(categories)..where((row) => row.id.equals(match!.id)))
            .write(CategoriesCompanion(defaultBudgetPeriod: Value(period)));
      }
    }
  }

  Future<void> _seedActivityCategories() async {
    const activityCategories = <(String, String)>[
      ('Perjalanan', 'activity'),
      ('Belanja', 'activity'),
      ('Pekerjaan', 'activity'),
      ('Keluarga', 'activity'),
      ('Lainnya', 'activity'),
    ];
    final existing =
        await (select(categories)..where(
              (row) =>
                  row.householdId.equals('local-household') &
                  row.type.equals('activity'),
            ))
            .get();
    for (final (name, type) in activityCategories) {
      Category? match;
      for (final row in existing) {
        if (row.type == type &&
            row.name.trim().toLowerCase() == name.toLowerCase()) {
          match = row;
          break;
        }
      }
      if (match == null) {
        final slug = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
        await into(categories).insert(
          CategoriesCompanion.insert(
            id: 'seed-$type-$slug',
            householdId: 'local-household',
            name: name,
            type: type,
            defaultBudgetPeriod: const Value('none'),
            createdAt: DateTime.now(),
          ),
        );
      }
    }
  }

  Future<void> _seedInitialData() async {
    final now = DateTime.now();
    await into(households).insertOnConflictUpdate(
      HouseholdsCompanion.insert(
        id: 'local-household',
        name: 'Keluarga',
        createdAt: now,
        updatedAt: Value(now),
      ),
    );
    const categories = <(String, String, String)>[
      ('Makan & minum', 'expense', 'weekly'),
      ('Belanja rumah', 'expense', 'monthly'),
      ('Belanja pasar', 'expense', 'weekly'),
      ('Transportasi', 'expense', 'weekly'),
      ('BBM motor', 'expense', 'weekly'),
      ('BBM mobil', 'expense', 'weekly'),
      ('Tagihan', 'expense', 'monthly'),
      ('Tagihan rumah', 'expense', 'monthly'),
      ('Listrik & air', 'expense', 'monthly'),
      ('Gas LPG', 'expense', 'monthly'),
      ('Pulsa & internet', 'expense', 'monthly'),
      ('Beras', 'expense', 'monthly'),
      ('Sabun & kebersihan', 'expense', 'monthly'),
      ('Kebutuhan dapur', 'expense', 'monthly'),
      ('Kesehatan', 'expense', 'monthly'),
      ('Sandal & sepatu', 'expense', 'none'),
      ('Pakaian', 'expense', 'none'),
      ('Perlengkapan rumah', 'expense', 'none'),
      ('Servis kendaraan', 'expense', 'none'),
      ('Perawatan kendaraan', 'expense', 'none'),
      ('Kebutuhan sekolah', 'expense', 'none'),
      ('Kebutuhan musiman', 'expense', 'none'),
      ('Gaji', 'income', 'none'),
      ('Usaha', 'income', 'none'),
      ('Hadiah & bantuan', 'income', 'none'),
      ('Biaya admin', 'expense', 'none'),
      ('Pertanian', 'expense', 'none'),
      ('Lainnya', 'expense', 'none'),
    ];
    for (final (name, type, period) in categories) {
      await into(this.categories).insertOnConflictUpdate(
        CategoriesCompanion.insert(
          id: 'seed-$type-${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}',
          householdId: 'local-household',
          name: name,
          type: type,
          defaultBudgetPeriod: Value(period),
          createdAt: now,
        ),
      );
    }
  }
}

QueryExecutor _openConnection() {
  return LazyDatabase(() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File(p.join(directory.path, 'ffm.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}

AppDatabase createInMemoryDatabaseForTests() =>
    AppDatabase(NativeDatabase.memory());
