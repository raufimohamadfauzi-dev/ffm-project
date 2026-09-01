import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_context.dart';
import '../../data/repositories/activity_repository.dart';
import '../../domain/entities/activity_entity.dart';
import '../../domain/activity_voice.dart';

class ActivityState {
  const ActivityState({
    this.sessions = const [],
    this.activeSessions = const [],
    this.entries = const [],
    this.checkpoints = const {},
    this.notes = const [],
    this.linkedCosts = const {},
    this.habitSuggestions = const [],
    this.activeSession,
    this.loading = false,
    this.saving = false,
    this.error,
    this.revision = 0,
    this.lastUpdatedAt,
  });

  final List<ActivitySessionEntity> sessions;
  final List<ActivitySessionEntity> activeSessions;
  final List<ActivityJournalEntryEntity> entries;
  final Map<String, List<ActivityCheckpointEntity>> checkpoints;
  final List<ActivityNoteEntity> notes;
  final Map<String, int> linkedCosts;
  final List<String> habitSuggestions;
  final ActivitySessionEntity? activeSession;
  final bool loading;
  final bool saving;
  final String? error;
  final int revision;
  final DateTime? lastUpdatedAt;

  ActivityLiveSnapshot toSnapshot() => ActivityLiveSnapshot(
    activeSessions: List<ActivitySessionEntity>.unmodifiable(activeSessions),
    checkpoints: Map<String, List<ActivityCheckpointEntity>>.unmodifiable(
      checkpoints.map(
        (k, v) => MapEntry(k, List<ActivityCheckpointEntity>.unmodifiable(v)),
      ),
    ),
    notes: List<ActivityNoteEntity>.unmodifiable(notes),
    revision: revision,
    lastUpdatedAt: lastUpdatedAt ?? DateTime.now(),
  );

  ActivityState copyWith({
    List<ActivitySessionEntity>? sessions,
    List<ActivitySessionEntity>? activeSessions,
    List<ActivityJournalEntryEntity>? entries,
    Map<String, List<ActivityCheckpointEntity>>? checkpoints,
    List<ActivityNoteEntity>? notes,
    Map<String, int>? linkedCosts,
    List<String>? habitSuggestions,
    ActivitySessionEntity? activeSession,
    bool clearActiveSession = false,
    bool? loading,
    bool? saving,
    String? error,
    bool clearError = false,
    int? revision,
    DateTime? lastUpdatedAt,
  }) => ActivityState(
    sessions: sessions ?? this.sessions,
    activeSessions: activeSessions ?? this.activeSessions,
    entries: entries ?? this.entries,
    checkpoints: checkpoints ?? this.checkpoints,
    notes: notes ?? this.notes,
    linkedCosts: linkedCosts ?? this.linkedCosts,
    habitSuggestions: habitSuggestions ?? this.habitSuggestions,
    activeSession: clearActiveSession
        ? null
        : activeSession ?? this.activeSession,
    loading: loading ?? this.loading,
    saving: saving ?? this.saving,
    error: clearError ? null : error ?? this.error,
    revision: revision ?? this.revision,
    lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
  );
}

class ActivityBloc extends Cubit<ActivityState> {
  ActivityBloc(this.repository) : super(const ActivityState());

  final ActivityRepository repository;
  static const _uuid = Uuid();

  Future<void> load() async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      // Trigger migration once
      await repository.migrateOldData(AppContext.householdId);

      final sessions = await repository.getSessions(AppContext.householdId);
      final entries = await repository.getEntries(AppContext.householdId);
      final activeSessions = await repository.recoverActiveSessions(
        AppContext.householdId,
      );
      final notes = await repository.getNotes(AppContext.householdId);

      // Fetch habit suggestions
      final habits =
          await (repository.database.select(
                repository.database.assistantMemories,
              )..where(
                (row) =>
                    row.householdId.equals(AppContext.householdId) &
                    row.kind.equals('habit') &
                    row.isArchived.equals(false),
              ))
              .get();
      final currentHour = DateTime.now().hour;
      final suggestions = habits
          .where((h) {
            final typicalHour = h.metadataJson.contains('typicalHour')
                ? (jsonDecode(h.metadataJson) as Map)['typicalHour'] as int?
                : null;
            return typicalHour == null ||
                (typicalHour - currentHour).abs() <= 2;
          })
          .map((h) => h.triggerText.replaceFirst('aktivitas:', ''))
          .toList();

      final active = activeSessions.firstOrNull;
      final checkpointMap = <String, List<ActivityCheckpointEntity>>{};
      final costMap = <String, int>{};
      for (final session in sessions) {
        checkpointMap[session.id] = await repository.getCheckpoints(session.id);
        costMap[session.id] = await repository.getActivityLinkedCost(
          session.id,
        );
      }
      emit(
        state.copyWith(
          sessions: sessions,
          activeSessions: activeSessions,
          entries: entries,
          checkpoints: checkpointMap,
          notes: notes,
          linkedCosts: costMap,
          habitSuggestions: suggestions,
          activeSession: active,
          clearActiveSession: active == null,
          loading: false,
          saving: false,
          revision: state.revision + 1,
          lastUpdatedAt: DateTime.now(),
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          loading: false,
          error: 'Data aktivitas belum bisa dimuat: $error',
        ),
      );
    }
  }

  Future<void> startSession({
    required String title,
    required String category,
    String? categoryId,
    ActivityKind kind = ActivityKind.timer,
    ActivityMode? mode,
    String? notes,
    DateTime? startedAt,
    DateTime? scheduledAt,
    DateTime? dueDate,
    bool isAllDay = false,
    bool isCompleted = false,
    int priority = 0,
    String? parentSessionId,
    // Activity Intelligence Upgrade fields
    String? activityGroupId,
    String? subjectType,
    String? subjectId,
  }) async {
    var finalTitle = title.trim();
    var finalParentId = parentSessionId;

    // Smart Syntax Detect: '>' means child of last active session
    if (finalTitle.startsWith('>') && state.activeSessions.isNotEmpty) {
      finalTitle = finalTitle.substring(1).trim();
      finalParentId ??= state.activeSessions.last.id;
    }

    if (finalTitle.isEmpty) return;

    // Parser/UI bertanggung jawab memilih mode. BLoC tidak mendeteksi ulang
    // karena dapat membatalkan intent eksplisit seperti "mulai belanja".
    final resolvedKind = mode?.activityKind ?? kind;

    final now = startedAt ?? DateTime.now();
    await _save(() async {
      final resolvedCategory = await repository.resolveActiveActivityCategory(
        householdId: AppContext.householdId,
        categoryId: categoryId,
        categoryName: category,
      );
      if (resolvedCategory == null) {
        throw StateError(
          'Pilih kategori aktivitas yang tersedia di Data Utama sebelum menyimpan.',
        );
      }
      if (finalParentId != null) {
        final parent = await repository.getSession(
          AppContext.householdId,
          finalParentId!,
        );
        if (parent == null || parent.status != ActivitySessionStatus.active) {
          // If parent is not active, fallback to root or throw if explicitly requested
          if (parentSessionId != null) {
            throw StateError('Aktivitas induknya sudah tidak berjalan.');
          }
          finalParentId = null;
        }
      }
      await repository.saveSession(
        ActivitySessionEntity(
          id: _uuid.v4(),
          householdId: AppContext.householdId,
          title: finalTitle,
          category: resolvedCategory.name,
          categoryId: resolvedCategory.id,
          kind: resolvedKind,
          parentSessionId: finalParentId,
          // Activity Intelligence Upgrade fields
          activityGroupId: activityGroupId,
          subjectType: subjectType,
          subjectId: subjectId,
          startedAt: now,
          scheduledAt: scheduledAt,
          dueDate: dueDate,
          isAllDay: isAllDay,
          isCompleted: isCompleted,
          priority: priority,
          status:
              (resolvedKind == ActivityKind.timer ||
                  resolvedKind == ActivityKind.task)
              ? ActivitySessionStatus.active
              : ActivitySessionStatus.completed,
          notes: notes,
          createdAt: DateTime.now(),
        ),
      );
    });
  }

  Future<void> finishSession({String? sessionId, DateTime? endedAt}) async {
    final current = sessionId == null
        ? state.activeSession ??
              await repository.getActiveSession(AppContext.householdId)
        : await repository.getSession(AppContext.householdId, sessionId);
    if (current == null) return;
    final end = endedAt ?? DateTime.now();
    await _save(
      () => repository.saveSession(
        current.copyWith(
          endedAt: end,
          status: ActivitySessionStatus.completed,
          isCompleted: true,
          updatedAt: DateTime.now(),
        ),
      ),
    );
  }

  Future<void> addCheckpoint({
    required String label,
    String? place,
    String? note,
    DateTime? occurredAt,
    String? sessionId,
  }) async {
    final session = sessionId == null
        ? state.activeSession ??
              await repository.getActiveSession(AppContext.householdId)
        : await repository.getSession(AppContext.householdId, sessionId);
    if (session == null) return;
    final existing =
        state.checkpoints[session.id] ??
        await repository.getCheckpoints(session.id);
    await _save(
      () => repository.saveCheckpoint(
        ActivityCheckpointEntity(
          id: _uuid.v4(),
          sessionId: session.id,
          label: label,
          place: place,
          occurredAt: occurredAt ?? DateTime.now(),
          sequence: existing.length + 1,
          note: note,
          createdAt: DateTime.now(),
        ),
      ),
    );
  }

  Future<void> addNote({
    required String text,
    required String category,
    double? numericValue,
    String? unit,
    double? latitude,
    double? longitude,
    String? linkedSessionId,
    ActivityEntrySource source = ActivityEntrySource.manual,
  }) async {
    await _save(
      () => repository.saveNote(
        ActivityNoteEntity(
          id: _uuid.v4(),
          householdId: AppContext.householdId,
          text: text,
          category: category,
          numericValue: numericValue,
          unit: unit,
          latitude: latitude,
          longitude: longitude,
          createdAt: DateTime.now(),
          linkedSessionId: linkedSessionId,
          source: source,
        ),
      ),
    );
  }

  Future<void> archiveNote(String id) async {
    await _save(() => repository.archiveNote(AppContext.householdId, id));
  }

  Future<void> executeVoiceIntent(ActivityVoiceIntent intent) async {
    if (!intent.canConfirm) {
      throw StateError(
        intent.ambiguityReason ?? 'Perintah voice belum siap dikonfirmasi.',
      );
    }
    switch (intent.type) {
      case ActivityVoiceIntentType.start:
        final title = intent.targetTitle;
        if (title == null || title.trim().isEmpty) {
          throw StateError('Nama aktivitasnya belum jelas.');
        }
        await startSession(
          title: title,
          category: intent.category,
          categoryId: intent.categoryId,
          kind: intent.kind,
          notes: 'Dimulai lewat voice: ${intent.rawTranscript}',
          startedAt: intent.startedAt,
        );
      case ActivityVoiceIntentType.startChild:
        final title = intent.targetTitle;
        final parentId = intent.parentSessionId;
        if (title == null || title.trim().isEmpty || parentId == null) {
          throw StateError('Aktivitas atau induknya belum jelas.');
        }
        await startSession(
          title: title,
          category: intent.category,
          categoryId: intent.categoryId,
          kind: intent.kind,
          notes: 'Dimulai lewat voice: ${intent.rawTranscript}',
          startedAt: intent.startedAt,
          parentSessionId: parentId,
        );
      case ActivityVoiceIntentType.finish:
        final sessionId = intent.targetSessionId;
        if (sessionId == null) throw StateError('Sesi target belum dipilih.');
        await finishSession(sessionId: sessionId);
      case ActivityVoiceIntentType.checkpoint:
        final sessionId = intent.targetSessionId;
        final label = intent.checkpointLabel;
        if (sessionId == null || label == null || label.trim().isEmpty) {
          throw StateError('Sesi atau update belum jelas.');
        }
        await addCheckpoint(
          sessionId: sessionId,
          label: label,
          note: 'Dicatat lewat voice: ${intent.rawTranscript}',
        );
      case ActivityVoiceIntentType.note:
        final sessionId = intent.targetSessionId;
        if (sessionId == null) {
          throw StateError('Pilih aktivitas tujuan untuk catatan voice ini.');
        }
        await addCheckpoint(
          sessionId: sessionId,
          label: 'Catatan suara',
          note: intent.rawTranscript,
        );
      case ActivityVoiceIntentType.confirm:
      case ActivityVoiceIntentType.cancel:
      case ActivityVoiceIntentType.unknown:
        throw StateError('Perintah voice belum bisa dijalankan.');
    }
    await repository.recordVoiceCommand(
      householdId: AppContext.householdId,
      rawTranscript: intent.rawTranscript,
      normalizedText: intent.normalizedText,
      intent: intent.type.name,
      status: ActivityVoiceStatus.confirmed.name,
      targetSessionId: intent.targetSessionId ?? intent.parentSessionId,
      confidence: intent.confidence,
      resultMessage: 'Aksi voice berhasil disimpan.',
    );
  }

  Future<void> recordVoiceIntent(
    ActivityVoiceIntent intent, {
    required ActivityVoiceStatus status,
    String? resultMessage,
  }) => repository.recordVoiceCommand(
    householdId: AppContext.householdId,
    rawTranscript: intent.rawTranscript,
    normalizedText: intent.normalizedText,
    intent: intent.type.name,
    status: status.name,
    targetSessionId: intent.targetSessionId ?? intent.parentSessionId,
    confidence: intent.confidence,
    resultMessage: resultMessage,
  );

  Future<void> saveEntry(ActivityJournalEntryEntity entity) async {
    await _save(() => repository.saveEntry(entity));
  }

  Future<void> archiveSession(String id) async {
    await _save(() => repository.archiveSession(AppContext.householdId, id));
  }

  Future<void> deleteSessionPermanently(String id) async {
    await _save(
      () => repository.deleteSessionPermanently(AppContext.householdId, id),
    );
  }

  Future<void> archiveEntry(String id) async {
    await _save(() => repository.archiveEntry(AppContext.householdId, id));
  }

  Future<void> _save(Future<void> Function() operation) async {
    emit(state.copyWith(saving: true, clearError: true));
    try {
      await operation();
      await load();
    } catch (error) {
      emit(state.copyWith(saving: false, error: error.toString()));
    }
  }
}
