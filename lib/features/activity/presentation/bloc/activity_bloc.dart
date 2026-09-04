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
  bool _migrated = false;
  bool _healingDone = false;

  Future<void> load() async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      // Trigger migration once per app session
      if (!_migrated) {
        await repository.migrateOldData(AppContext.householdId);
        _migrated = true;
      }

      var sessions = await repository.getSessions(AppContext.householdId);

      // Auto-healing 1x untuk data catatan lama agar tidak berstatus 'active' atau 'berjalan'
      if (!_healingDone) {
        _healingDone = true;
        var needsReload = false;
        for (final session in sessions) {
          if (session.isHistory &&
              (session.endedAt == null ||
                  session.status != ActivitySessionStatus.completed)) {
            await repository.saveSession(
              session.copyWith(
                endedAt: session.startedAt,
                status: ActivitySessionStatus.completed,
                isCompleted: true,
                updatedAt: DateTime.now(),
              ),
            );
            needsReload = true;
          }
        }
        if (needsReload) {
          sessions = await repository.getSessions(AppContext.householdId);
        }
      }

      final entries = await repository.getEntries(AppContext.householdId);
      final activeSessionsRaw = await repository.recoverActiveSessions(
        AppContext.householdId,
      );
      // Sesi catatan tidak boleh berada di activeSessions
      final activeSessions = activeSessionsRaw
          .where((s) => !s.isHistory && s.status == ActivitySessionStatus.active)
          .toList();
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
          endedAt: (resolvedKind == ActivityKind.note ||
                  resolvedKind == ActivityKind.event ||
                  mode == ActivityMode.history)
              ? now
              : null,
          scheduledAt: scheduledAt,
          dueDate: dueDate,
          isAllDay: isAllDay,
          isCompleted: (resolvedKind == ActivityKind.note ||
                  resolvedKind == ActivityKind.event ||
                  mode == ActivityMode.history)
              ? true
              : isCompleted,
          priority: priority,
          status: (resolvedKind == ActivityKind.note ||
                  resolvedKind == ActivityKind.event ||
                  mode == ActivityMode.history)
              ? ActivitySessionStatus.completed
              : ((resolvedKind == ActivityKind.timer ||
                      resolvedKind == ActivityKind.task)
                  ? ActivitySessionStatus.active
                  : ActivitySessionStatus.completed),
          notes: notes,
          createdAt: DateTime.now(),
        ),
      );
    });
  }

  Future<void> finishSession({String? sessionId, DateTime? endedAt}) async {
    if (sessionId == null && state.activeSessions.length > 1) {
      throw StateError(
        'Ada ${state.activeSessions.length} aktivitas yang sedang berjalan. Sebutkan nama aktivitas yang ingin diselesaikan.',
      );
    }
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

  Future<void> editCheckpoint({
    required String checkpointId,
    required String label,
    String? place,
    String? note,
    DateTime? occurredAt,
  }) async {
    ActivityCheckpointEntity? existing;
    for (final list in state.checkpoints.values) {
      for (final cp in list) {
        if (cp.id == checkpointId) {
          existing = cp;
          break;
        }
      }
      if (existing != null) break;
    }
    if (existing == null) return;
    final updated = existing.copyWith(
      label: label.trim().isEmpty ? existing.label : label.trim(),
      place: place,
      note: note,
      occurredAt: occurredAt ?? existing.occurredAt,
    );
    await _save(() => repository.saveCheckpoint(updated));
  }

  Future<void> deleteCheckpoint(String checkpointId) async {
    await _save(() => repository.deleteCheckpoint(checkpointId));
  }

  Future<void> updateSession({
    required String sessionId,
    required String title,
    required String category,
    String? categoryId,
    String? notes,
    DateTime? startedAt,
    DateTime? endedAt,
    int? priority,
  }) async {
    final current = await repository.getSession(AppContext.householdId, sessionId);
    if (current == null) return;
    final resolvedCategory = await repository.resolveActiveActivityCategory(
      householdId: AppContext.householdId,
      categoryId: categoryId,
      categoryName: category,
    );
    final updated = current.copyWith(
      title: title.trim().isEmpty ? current.title : title.trim(),
      category: resolvedCategory?.name ?? category,
      categoryId: resolvedCategory?.id ?? categoryId ?? current.categoryId,
      notes: notes,
      startedAt: startedAt ?? current.startedAt,
      endedAt: current.isHistory
          ? (startedAt ?? current.startedAt)
          : (endedAt ?? current.endedAt),
      priority: priority,
      updatedAt: DateTime.now(),
    );
    await _save(() => repository.saveSession(updated));
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
        final title = intent.targetTitle ?? intent.rawTranscript;
        if (title.trim().isEmpty) {
          throw StateError('Nama aktivitasnya belum jelas.');
        }
        final cleanNotes =
            (intent.rawTranscript.trim().isNotEmpty &&
                    intent.rawTranscript.trim().toLowerCase() !=
                        title.trim().toLowerCase())
                ? intent.rawTranscript.trim()
                : null;
        await startSession(
          title: title.trim(),
          category: intent.category,
          categoryId: intent.categoryId,
          kind: intent.kind,
          notes: cleanNotes,
          startedAt: intent.startedAt,
        );
      case ActivityVoiceIntentType.startChild:
        final title = intent.targetTitle ?? intent.rawTranscript;
        final parentId = intent.parentSessionId;
        if (title.trim().isEmpty || parentId == null) {
          throw StateError('Aktivitas atau induknya belum jelas.');
        }
        final cleanNotes =
            (intent.rawTranscript.trim().isNotEmpty &&
                    intent.rawTranscript.trim().toLowerCase() !=
                        title.trim().toLowerCase())
                ? intent.rawTranscript.trim()
                : null;
        await startSession(
          title: title.trim(),
          category: intent.category,
          categoryId: intent.categoryId,
          kind: intent.kind,
          notes: cleanNotes,
          startedAt: intent.startedAt,
          parentSessionId: parentId,
        );
      case ActivityVoiceIntentType.finish:
        final sessionId = intent.targetSessionId;
        if (sessionId == null) {
          if (state.activeSessions.length > 1) {
            throw StateError(
              'Ada ${state.activeSessions.length} aktivitas yang sedang berjalan. Sebutkan nama aktivitas yang ingin diselesaikan.',
            );
          }
          if (state.activeSessions.isEmpty) {
            throw StateError('Tidak ada aktivitas aktif yang bisa diselesaikan.');
          }
        }
        await finishSession(
          sessionId: sessionId ?? state.activeSessions.first.id,
        );
      case ActivityVoiceIntentType.checkpoint:
        final sessionId = intent.targetSessionId;
        final label = intent.checkpointLabel ?? 'Update';
        if (sessionId == null) {
          throw StateError('Pilih aktivitas tujuan untuk update ini.');
        }
        await addCheckpoint(
          sessionId: sessionId,
          label: label,
          note: intent.rawTranscript,
        );
      case ActivityVoiceIntentType.note:
        final sessionId = intent.targetSessionId;
        if (sessionId == null) {
          final title = intent.targetTitle ??
              (intent.checkpointLabel?.isNotEmpty == true
                  ? intent.checkpointLabel!
                  : intent.rawTranscript);
          if (title.trim().isEmpty) {
            throw StateError('Nama aktivitas belum jelas.');
          }
          final cleanNotes =
              (intent.rawTranscript.trim().isNotEmpty &&
                      intent.rawTranscript.trim().toLowerCase() !=
                          title.trim().toLowerCase())
                  ? intent.rawTranscript.trim()
                  : null;
          await startSession(
            title: title.trim(),
            category: intent.category,
            categoryId: intent.categoryId,
            kind: intent.kind,
            notes: cleanNotes,
            startedAt: intent.startedAt,
          );
        } else {
          await addCheckpoint(
            sessionId: sessionId,
            label: intent.checkpointLabel ?? 'Catatan',
            note: intent.rawTranscript,
          );
        }
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

  Future<void> saveSession(ActivitySessionEntity entity) async {
    await _save(() => repository.saveSession(entity));
  }

  Future<bool> togglePriority(String id) async {
    final session = state.sessions.where((s) => s.id == id).firstOrNull;
    if (session == null) return false;

    final currentPriority = session.priority;
    final newPriority = currentPriority > 0 ? 0 : 1;

    // Proteksi batas maksimal 10 aktivitas prioritas aktif
    if (newPriority > 0) {
      final activePriorityCount = state.sessions
          .where((s) => s.priority > 0 && !s.isArchived && s.status != ActivitySessionStatus.completed)
          .length;
      if (activePriorityCount >= 10) {
        emit(state.copyWith(
          error: 'Maksimal 10 aktivitas prioritas aktif yang diizinkan.',
        ));
        return false;
      }
    }

    final updated = session.copyWith(
      priority: newPriority,
      updatedAt: DateTime.now(),
    );
    await _save(() => repository.saveSession(updated));
    return true;
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
