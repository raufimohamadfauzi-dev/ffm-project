import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/diagnostics/app_diagnostics_service.dart';
import '../../../../core/network/supabase_config.dart';
import '../../../advisor/data/cash_flow_profile_repository.dart';
import '../../data/telegram_config_repository.dart';
import '../../../reminder/domain/entities/reminder_entity.dart';
import '../ffm_assistant_insight.dart';
import '../ffm_assistant_models.dart';

/// Membuat satu proposal pengingat untuk komitmen aktif yang belum tertaut.
/// Detector ini tidak menyimpan pengingat atau menjadwalkan notifikasi.
class ReminderSuggestionDetector {
  const ReminderSuggestionDetector(
    this._database, {
    this.diagnostics,
    this.telegramConfig,
    this.cashFlowProfiles,
    this.supabaseConfig,
    this.enableCompleteness = false,
  });

  final AppDatabase _database;
  final AppDiagnosticsService? diagnostics;
  final TelegramConfigRepository? telegramConfig;
  final CashFlowProfileRepository? cashFlowProfiles;
  final SupabaseConfig? supabaseConfig;
  final bool enableCompleteness;

  Future<FfmAssistantInsight?> detect({
    required String householdId,
    required DateTime now,
  }) async {
    final linkedSources = await _linkedSources(householdId);
    final candidates =
        <_Candidate>[
          ...await _liabilities(householdId, now, linkedSources),
          ...await _receivables(householdId, now, linkedSources),
          ...await _goals(householdId, now, linkedSources),
          ...await _recurringTransactions(householdId, now, linkedSources),
          ...await _activities(householdId, now, linkedSources),
          ...await _tasks(householdId, now, linkedSources),
          if (enableCompleteness)
            ...await _dataCompleteness(householdId, now, linkedSources),
        ]..sort((left, right) {
          if (left.isCompleteness != right.isCompleteness) {
            return left.isCompleteness ? 1 : -1;
          }
          final byTime = left.at.compareTo(right.at);
          return byTime == 0 ? right.priority.compareTo(left.priority) : byTime;
        });
    if (candidates.isEmpty) return null;

    final candidate = candidates.first;
    final scheduledAt = candidate.at.isAfter(now)
        ? candidate.at
        : now.add(const Duration(hours: 1));
    return FfmAssistantInsight(
      id: const Uuid().v4(),
      householdId: householdId,
      type: FfmAssistantInsightType.reminderSuggestion,
      severity: FfmAssistantInsightSeverity.info,
      priority: candidate.priority,
      confidence: 1,
      title: 'Buat pengingat untuk ${candidate.sourceType.label}',
      summary:
          '${candidate.sourceName} dijadwalkan pada ${_dateLabel(candidate.at)} dan belum memiliki pengingat tertaut.',
      evidence: {
        'sourceType': candidate.sourceType.storageValue,
        'sourceId': candidate.sourceId,
        'scheduledAt': candidate.at.toIso8601String(),
      },
      suggestedAction: 'Tinjau draft pengingat',
      destination: FfmAssistantDestination.reminders,
      actionPayload: {
        'type': 'reminder_suggestion',
        'title': candidate.title,
        'note': candidate.note,
        'scheduledAt': scheduledAt.toIso8601String(),
        'sourceType': candidate.sourceType.storageValue,
        'sourceId': candidate.sourceId,
      },
      createdAt: now,
      expiresAt: scheduledAt.add(const Duration(days: 7)),
      dedupeKey:
          'reminder-suggestion:${candidate.sourceType.storageValue}:${candidate.sourceId}:${scheduledAt.year}-${scheduledAt.month}',
    );
  }

  Future<Set<String>> _linkedSources(String householdId) async {
    final reminders = await (_database.select(
      _database.reminders,
    )..where((row) => row.householdId.equals(householdId))).get();
    return reminders
        .where((row) => row.sourceType != null && row.sourceId != null)
        .map((row) => '${row.sourceType}:${row.sourceId}')
        .toSet();
  }

  Future<List<_Candidate>> _liabilities(
    String householdId,
    DateTime now,
    Set<String> linkedSources,
  ) async {
    final rows =
        await (_database.select(_database.liabilities)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isActive.equals(true),
            ))
            .get();
    final deadline = now.add(const Duration(days: 14));
    return rows
        .where(
          (row) =>
              row.remainingBalance > 0 &&
              row.dueDate != null &&
              !row.dueDate!.isAfter(deadline) &&
              !linkedSources.contains('liability:${row.id}'),
        )
        .map(
          (row) => _Candidate(
            sourceType: ReminderSourceType.liability,
            sourceId: row.id,
            sourceName: 'Hutang ${row.name}',
            title: 'Bayar hutang: ${row.name}',
            note: 'Terkait hutang ${row.name}.',
            at: _normalizeReminderTime(row.dueDate!),
            priority: 82,
          ),
        )
        .toList(growable: false);
  }

  Future<List<_Candidate>> _receivables(
    String householdId,
    DateTime now,
    Set<String> linkedSources,
  ) async {
    final rows =
        await (_database.select(_database.receivables)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isActive.equals(true),
            ))
            .get();
    final deadline = now.add(const Duration(days: 14));
    return rows
        .where(
          (row) =>
              row.remainingBalance > 0 &&
              row.dueDate != null &&
              !row.dueDate!.isAfter(deadline) &&
              !linkedSources.contains('receivable:${row.id}'),
        )
        .map(
          (row) => _Candidate(
            sourceType: ReminderSourceType.receivable,
            sourceId: row.id,
            sourceName: 'Piutang ${row.name}',
            title: 'Tagih piutang: ${row.name}',
            note: 'Terkait piutang ${row.name}.',
            at: _normalizeReminderTime(row.dueDate!),
            priority: 76,
          ),
        )
        .toList(growable: false);
  }

  Future<List<_Candidate>> _goals(
    String householdId,
    DateTime now,
    Set<String> linkedSources,
  ) async {
    final rows =
        await (_database.select(_database.goals)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isActive.equals(true) &
                  row.targetDate.isNotNull(),
            ))
            .get();
    final deadline = now.add(const Duration(days: 30));
    return rows
        .where(
          (row) =>
              row.currentAmount < row.targetAmount &&
              row.targetDate != null &&
              !row.targetDate!.isAfter(deadline) &&
              !linkedSources.contains('goal:${row.id}'),
        )
        .map(
          (row) => _Candidate(
            sourceType: ReminderSourceType.goal,
            sourceId: row.id,
            sourceName: 'Target ${row.name}',
            title: 'Cek progres target: ${row.name}',
            note: 'Terkait target keuangan ${row.name}.',
            at: _normalizeReminderTime(row.targetDate!),
            priority: 64,
          ),
        )
        .toList(growable: false);
  }

  Future<List<_Candidate>> _recurringTransactions(
    String householdId,
    DateTime now,
    Set<String> linkedSources,
  ) async {
    final rows =
        await (_database.select(_database.recurringTransactions)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isActive.equals(true),
            ))
            .get();
    final deadline = now.add(const Duration(days: 14));
    return rows
        .where(
          (row) => !linkedSources.contains('recurring_transaction:${row.id}'),
        )
        .map((row) => (row: row, at: _nextRecurringDate(row, now)))
        .where(
          (item) =>
              !item.at.isAfter(deadline) &&
              (item.row.endDate == null || !item.at.isAfter(item.row.endDate!)),
        )
        .map(
          (item) => _Candidate(
            sourceType: ReminderSourceType.recurringTransaction,
            sourceId: item.row.id,
            sourceName: 'Jadwal rutin ${item.row.name}',
            title: 'Cek jadwal rutin: ${item.row.name}',
            note: 'Terkait jadwal transaksi rutin ${item.row.name}.',
            at: _normalizeReminderTime(item.at),
            priority: item.row.type == 'expense' ? 72 : 58,
          ),
        )
        .toList(growable: false);
  }

  Future<List<_Candidate>> _activities(
    String householdId,
    DateTime now,
    Set<String> linkedSources,
  ) async {
    final rows =
        await (_database.select(_database.activitySessions)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isArchived.equals(false) &
                  row.isCompleted.equals(false),
            ))
            .get();
    final deadline = now.add(const Duration(days: 30));
    return rows
        .map((row) => (row: row, at: row.scheduledAt ?? row.dueDate))
        .where(
          (item) =>
              item.at != null &&
              !item.at!.isAfter(deadline) &&
              !linkedSources.contains('activity:${item.row.id}'),
        )
        .map(
          (item) => _Candidate(
            sourceType: ReminderSourceType.activity,
            sourceId: item.row.id,
            sourceName: item.row.title,
            title: 'Jalankan aktivitas: ${item.row.title}',
            note: item.row.notes ?? 'Terkait aktivitas yang dicatat di FFM.',
            at: _normalizeReminderTime(item.at!),
            priority: item.row.priority.clamp(40, 90),
          ),
        )
        .toList(growable: false);
  }

  Future<List<_Candidate>> _tasks(
    String householdId,
    DateTime now,
    Set<String> linkedSources,
  ) async {
    final rows =
        await (_database.select(_database.tasks)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isArchived.equals(false) &
                  row.status.isNotIn(const ['completed', 'cancelled']),
            ))
            .get();
    final deadline = now.add(const Duration(days: 30));
    return rows
        .where(
          (row) =>
              row.dueDate != null &&
              !row.dueDate!.isAfter(deadline) &&
              !linkedSources.contains('task:${row.id}'),
        )
        .map(
          (row) => _Candidate(
            sourceType: ReminderSourceType.task,
            sourceId: row.id,
            sourceName: row.title,
            title: 'Kerjakan tugas: ${row.title}',
            note: row.note ?? 'Terkait tugas yang dicatat di FFM.',
            at: _normalizeReminderTime(row.dueDate!),
            priority: 68,
          ),
        )
        .toList(growable: false);
  }

  Future<List<_Candidate>> _dataCompleteness(
    String householdId,
    DateTime now,
    Set<String> linkedSources,
  ) async {
    final candidates = <_Candidate>[];
    final household = await (_database.select(
      _database.households,
    )..where((row) => row.id.equals(householdId))).getSingleOrNull();
    final preferences = await (_database.select(
      _database.userPreferences,
    )..where((row) => row.householdId.equals(householdId))).get();
    final preferenceValues = <String, String>{
      for (final item in preferences) item.preferenceKey: item.preferenceValue,
    };
    final periodKey = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final familyProfileSourceId = 'family_profile:$periodKey';
    final setupAt = now.add(const Duration(hours: 1));
    final hasFamilyProfile =
        household != null &&
        [
          household.husbandName,
          household.wifeName,
          preferenceValues['profile_name'],
          preferenceValues['profile_occupation'],
          preferenceValues['profile_routine'],
          preferenceValues['profile_goals'],
        ].any((value) => value?.trim().isNotEmpty == true);
    if (!hasFamilyProfile &&
        !linkedSources.contains('family_profile:$familyProfileSourceId')) {
      candidates.add(
        _Candidate(
          sourceType: ReminderSourceType.familyProfile,
          sourceId: familyProfileSourceId,
          sourceName: 'Profil keluarga',
          title: 'Lengkapi profil keluarga',
          note: 'Isi profil keluarga agar asisten dapat memberi saran yang lebih relevan.',
          at: setupAt,
          priority: 72,
          isCompleteness: true,
        ),
      );
    }

    final accountCount =
        await (_database.select(_database.accounts)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isActive.equals(true) &
                  row.isArchived.equals(false),
            ))
            .get();
    if (accountCount.isEmpty &&
        !linkedSources.contains('account_setup:setup:$periodKey')) {
      candidates.add(
        _Candidate(
          sourceType: ReminderSourceType.accountSetup,
          sourceId: 'setup:$periodKey',
          sourceName: 'Rekening',
          title: 'Tambahkan rekening atau kas',
          note: 'Isi rekening agar saldo dan transaksi keluarga dapat dihitung dengan benar.',
          at: setupAt,
          priority: 74,
          isCompleteness: true,
        ),
      );
    }

    final goals =
        await (_database.select(_database.goals)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isActive.equals(true),
            ))
            .get();
    if (goals.isEmpty &&
        !linkedSources.contains('goal_setup:setup:$periodKey')) {
      candidates.add(
        _Candidate(
          sourceType: ReminderSourceType.goalSetup,
          sourceId: 'setup:$periodKey',
          sourceName: 'Target keuangan',
          title: 'Buat target keuangan',
          note: 'Tambahkan target agar asisten dapat membantu memantau progres keluarga.',
          at: setupAt,
          priority: 52,
          isCompleteness: true,
        ),
      );
    }

    final budgets =
        await (_database.select(_database.envelopeBudgets)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isActive.equals(true),
            ))
            .get();
    if (budgets.isEmpty &&
        !linkedSources.contains('budget_setup:setup:$periodKey')) {
      candidates.add(
        _Candidate(
          sourceType: ReminderSourceType.budgetSetup,
          sourceId: 'setup:$periodKey',
          sourceName: 'Anggaran',
          title: 'Atur anggaran keluarga',
          note: 'Buat anggaran agar asisten dapat memperingatkan saat pengeluaran mendekati batas.',
          at: setupAt,
          priority: 50,
          isCompleteness: true,
        ),
      );
    }

    if (cashFlowProfiles != null &&
        (await cashFlowProfiles!.getActiveProfile(householdId)) == null &&
        !linkedSources.contains('cash_flow_profile:setup:$periodKey')) {
      candidates.add(
        _Candidate(
          sourceType: ReminderSourceType.cashFlowProfile,
          sourceId: 'setup:$periodKey',
          sourceName: 'Siklus kas',
          title: 'Isi siklus kas keluarga',
          note:
              'Isi pemasukan dan pola kas agar analisis arus kas lebih akurat.',
          at: setupAt,
          priority: 48,
          isCompleteness: true,
        ),
      );
    }

    if (supabaseConfig != null) {
      final cloudValues = await Future.wait([
        supabaseConfig!.getUrl(),
        supabaseConfig!.getAnonKey(),
        supabaseConfig!.getGeminiKey(),
      ]);
      if (cloudValues.any((value) => value?.trim().isEmpty != false) &&
          !linkedSources.contains('cloud_setup:setup:$periodKey')) {
        candidates.add(
          _Candidate(
            sourceType: ReminderSourceType.cloudSetup,
            sourceId: 'setup:$periodKey',
            sourceName: 'Cloud asisten',
            title: 'Lengkapi koneksi Cloud Asisten',
            note: 'Isi konfigurasi Supabase/Gemini bila ingin memakai sinkronisasi dan reasoning cloud.',
            at: setupAt,
            priority: 44,
            isCompleteness: true,
          ),
        );
      }
    }

    if (telegramConfig != null) {
      final config = await telegramConfig!.loadConfig();
      final telegramSourceId = 'setup:$periodKey';
      if (!config.isConfigured &&
          !linkedSources.contains('telegram:$telegramSourceId')) {
        candidates.add(
          _Candidate(
            sourceType: ReminderSourceType.telegram,
            sourceId: telegramSourceId,
            sourceName: 'Telegram',
            title: 'Hubungkan Telegram keluarga',
            note: 'Isi konfigurasi Telegram agar alarm dan laporan otonom dapat dikirim di luar aplikasi.',
            at: setupAt,
            priority: 58,
            isCompleteness: true,
          ),
        );
      }
    }

    final latestError = await diagnostics?.latestEntry();
    if (latestError != null) {
      final sourceId =
          '${latestError.code}:${latestError.occurredAt.toIso8601String()}';
      if (!linkedSources.contains('diagnostics:$sourceId')) {
        candidates.add(
          _Candidate(
            sourceType: ReminderSourceType.diagnostics,
            sourceId: sourceId,
            sourceName: latestError.feature,
            title: 'Periksa masalah aplikasi',
            note: '${latestError.code}: ${latestError.summary}',
            at: setupAt,
            priority: 80,
            isCompleteness: true,
          ),
        );
      }
    }

    final openFeedback = await (_database.select(
      _database.assistantResponseFeedbacks,
    )..where(
          (row) =>
              row.householdId.equals(householdId) &
              row.isArchived.equals(false) &
              row.reviewStatus.isNotIn(const ['fixed', 'rejected']),
        )).get();
    final openQuestions = await (_database.select(
      _database.assistantUnansweredQuestions,
    )..where(
          (row) =>
              row.householdId.equals(householdId) &
              row.isResolved.equals(false),
        )).get();
    final latestIssue = [
      ...openFeedback.map(
        (row) => (id: 'feedback:${row.id}', at: row.createdAt, note: row.note),
      ),
      ...openQuestions.map(
        (row) => (
          id: 'unanswered:${row.id}',
          at: row.updatedAt ?? row.createdAt,
          note: row.questionText,
        ),
      ),
    ]..sort((left, right) => right.at.compareTo(left.at));
    if (latestIssue.isNotEmpty &&
        !linkedSources.contains('assistant_log:${latestIssue.first.id}')) {
      candidates.add(
        _Candidate(
          sourceType: ReminderSourceType.assistantLog,
          sourceId: latestIssue.first.id,
          sourceName: 'Asisten Log',
          title: 'Tinjau masalah di Asisten Log',
          note: latestIssue.first.note?.trim().isNotEmpty == true
              ? latestIssue.first.note!
              : 'Ada feedback atau pertanyaan yang belum ditinjau di Asisten Log.',
          at: setupAt,
          priority: 86,
          isCompleteness: true,
        ),
      );
    }
    return candidates;
  }

  DateTime _nextRecurringDate(RecurringTransaction row, DateTime now) {
    var result = row.startDate;
    while (!result.isAfter(now)) {
      result = switch (row.periodType) {
        'daily' => result.add(const Duration(days: 1)),
        'weekly' => result.add(const Duration(days: 7)),
        'biweekly' => result.add(const Duration(days: 14)),
        _ => DateTime(
          result.year,
          result.month + 1,
          result.day,
          result.hour,
          result.minute,
        ),
      };
    }
    return result;
  }

  /// Jika waktu adalah 00:00:00 (date-only dari date picker), dorong ke 08:00
  /// agar notifikasi muncul di jam wajar, bukan tengah malam.
  DateTime _normalizeReminderTime(DateTime value) {
    if (value.hour == 0 && value.minute == 0 && value.second == 0) {
      return DateTime(value.year, value.month, value.day, 8, 0);
    }
    return value;
  }

  String _dateLabel(DateTime value) {
    final date =
        '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
    if (value.hour == 0 && value.minute == 0) return date;
    final time =
        '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
    return '$date $time';
  }
}

class _Candidate {
  const _Candidate({
    required this.sourceType,
    required this.sourceId,
    required this.sourceName,
    required this.title,
    required this.note,
    required this.at,
    required this.priority,
    this.isCompleteness = false,
  });

  final ReminderSourceType sourceType;
  final String sourceId;
  final String sourceName;
  final String title;
  final String note;
  final DateTime at;
  final int priority;
  final bool isCompleteness;
}
