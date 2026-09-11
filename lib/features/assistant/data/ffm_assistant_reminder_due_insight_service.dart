import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../reminder/data/repositories/reminder_repository.dart';
import '../../reminder/domain/entities/reminder_entity.dart';
import '../domain/ffm_assistant_insight.dart';
import '../domain/ffm_assistant_models.dart';
import 'ffm_assistant_autonomy_repository.dart';
import 'ffm_assistant_insight_repository.dart';

/// Membuat usulan tindak lanjut untuk pengingat yang memiliki sumber keuangan
/// aktif. Layanan ini hanya menulis insight; tidak pernah membuat transaksi.
class FfmAssistantReminderDueInsightService {
  FfmAssistantReminderDueInsightService(
    this._database,
    this._reminderRepository,
    this._insightRepository, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase _database;
  final ReminderRepository _reminderRepository;
  final FfmAssistantInsightRepository _insightRepository;
  final DateTime Function() _clock;

  Future<void> createFor(FfmAssistantAutonomyEvent event) async {
    final reminderId = event.payload['reminderId']?.toString().trim();
    final historyId = event.payload['historyId']?.toString().trim();
    if (reminderId == null ||
        reminderId.isEmpty ||
        historyId == null ||
        historyId.isEmpty) {
      return;
    }

    final reminder = await _reminderRepository.getReminder(
      event.householdId,
      reminderId,
    );
    final history = await _reminderRepository.getHistoryById(
      householdId: event.householdId,
      historyId: historyId,
    );
    if (reminder == null ||
        history == null ||
        history.reminderId != reminder.id ||
        history.status == ReminderHistoryStatus.completed ||
        history.status == ReminderHistoryStatus.cancelled ||
        history.status == ReminderHistoryStatus.snoozed ||
        reminder.sourceType == null ||
        reminder.sourceId == null) {
      return;
    }

    final sourceLabel = await _resolveActiveSource(reminder);
    if (sourceLabel == null) return;

    final now = _clock();
    await _insightRepository.saveInsight(
      FfmAssistantInsight(
        id: const Uuid().v4(),
        householdId: event.householdId,
        type: FfmAssistantInsightType.reminderDue,
        severity: FfmAssistantInsightSeverity.info,
        priority: 72,
        confidence: 1,
        title: 'Pengingat jatuh tempo: $sourceLabel',
        summary:
            '“${reminder.title}” sudah waktunya. Tinjau pengingat untuk memilih tindakan yang sesuai.',
        evidence: {
          'reminderId': reminder.id,
          'historyId': history.id,
          'sourceType': reminder.sourceType!.storageValue,
          'sourceId': reminder.sourceId!,
        },
        suggestedAction: 'Tinjau pengingat',
        destination: FfmAssistantDestination.reminders,
        createdAt: now,
        expiresAt: now.add(const Duration(days: 7)),
        dedupeKey: 'reminder-due:${history.id}',
      ),
    );
  }

  Future<String?> _resolveActiveSource(ReminderEntity reminder) async {
    final sourceId = reminder.sourceId!;
    final householdId = reminder.householdId;
    return switch (reminder.sourceType!) {
      ReminderSourceType.liability => _liabilityLabel(householdId, sourceId),
      ReminderSourceType.receivable => _receivableLabel(householdId, sourceId),
      ReminderSourceType.goal => _goalLabel(householdId, sourceId),
      ReminderSourceType.recurringTransaction => _recurringLabel(
        householdId,
        sourceId,
      ),
      ReminderSourceType.activity => null,
      ReminderSourceType.task => null,
      _ => null,
    };
  }

  Future<String?> _liabilityLabel(String householdId, String id) async {
    final row =
        await (_database.select(_database.liabilities)..where(
              (table) =>
                  table.householdId.equals(householdId) &
                  table.id.equals(id) &
                  table.isActive.equals(true),
            ))
            .getSingleOrNull();
    return row == null || row.remainingBalance <= 0
        ? null
        : 'hutang ${row.name}';
  }

  Future<String?> _receivableLabel(String householdId, String id) async {
    final row =
        await (_database.select(_database.receivables)..where(
              (table) =>
                  table.householdId.equals(householdId) &
                  table.id.equals(id) &
                  table.isActive.equals(true),
            ))
            .getSingleOrNull();
    return row == null || row.remainingBalance <= 0
        ? null
        : 'piutang ${row.name}';
  }

  Future<String?> _goalLabel(String householdId, String id) async {
    final row =
        await (_database.select(_database.goals)..where(
              (table) =>
                  table.householdId.equals(householdId) &
                  table.id.equals(id) &
                  table.isActive.equals(true),
            ))
            .getSingleOrNull();
    return row == null || row.currentAmount >= row.targetAmount
        ? null
        : 'target ${row.name}';
  }

  Future<String?> _recurringLabel(String householdId, String id) async {
    final row =
        await (_database.select(_database.recurringTransactions)..where(
              (table) =>
                  table.householdId.equals(householdId) &
                  table.id.equals(id) &
                  table.isActive.equals(true),
            ))
            .getSingleOrNull();
    return row == null ? null : 'jadwal rutin ${row.name}';
  }
}
