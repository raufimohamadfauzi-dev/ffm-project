import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../../reminder/domain/entities/reminder_entity.dart';
import '../ffm_assistant_insight.dart';
import '../ffm_assistant_models.dart';

/// Membuat satu proposal pengingat untuk komitmen aktif yang belum tertaut.
/// Detector ini tidak menyimpan pengingat atau menjadwalkan notifikasi.
class ReminderSuggestionDetector {
  const ReminderSuggestionDetector(this._database);

  final AppDatabase _database;

  Future<FfmAssistantInsight?> detect({
    required String householdId,
    required DateTime now,
  }) async {
    final linkedSources = await _linkedSources(householdId);
    final candidates = <_Candidate>[
      ...await _liabilities(householdId, now, linkedSources),
      ...await _receivables(householdId, now, linkedSources),
      ...await _goals(householdId, now, linkedSources),
      ...await _recurringTransactions(householdId, now, linkedSources),
    ]..sort((left, right) => left.at.compareTo(right.at));
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
  });

  final ReminderSourceType sourceType;
  final String sourceId;
  final String sourceName;
  final String title;
  final String note;
  final DateTime at;
  final int priority;
}
