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
    this.activeSession,
    this.loading = false,
    this.saving = false,
    this.error,
  });

  final List<ActivitySessionEntity> sessions;
  final List<ActivitySessionEntity> activeSessions;
  final List<ActivityJournalEntryEntity> entries;
  final Map<String, List<ActivityCheckpointEntity>> checkpoints;
  final ActivitySessionEntity? activeSession;
  final bool loading;
  final bool saving;
  final String? error;

  ActivityState copyWith({
    List<ActivitySessionEntity>? sessions,
    List<ActivitySessionEntity>? activeSessions,
    List<ActivityJournalEntryEntity>? entries,
    Map<String, List<ActivityCheckpointEntity>>? checkpoints,
    ActivitySessionEntity? activeSession,
    bool clearActiveSession = false,
    bool? loading,
    bool? saving,
    String? error,
    bool clearError = false,
  }) => ActivityState(
    sessions: sessions ?? this.sessions,
    activeSessions: activeSessions ?? this.activeSessions,
    entries: entries ?? this.entries,
    checkpoints: checkpoints ?? this.checkpoints,
    activeSession: clearActiveSession
        ? null
        : activeSession ?? this.activeSession,
    loading: loading ?? this.loading,
    saving: saving ?? this.saving,
    error: clearError ? null : error ?? this.error,
  );
}

class ActivityBloc extends Cubit<ActivityState> {
  ActivityBloc(this.repository) : super(const ActivityState());

  final ActivityRepository repository;
  static const _uuid = Uuid();

  Future<void> load() async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      final sessions = await repository.getSessions(AppContext.householdId);
      final entries = await repository.getEntries(AppContext.householdId);
      final activeSessions = await repository.recoverActiveSessions(
        AppContext.householdId,
      );
      final active = activeSessions.firstOrNull;
      final checkpointMap = <String, List<ActivityCheckpointEntity>>{};
      for (final session in sessions) {
        checkpointMap[session.id] = await repository.getCheckpoints(session.id);
      }
      emit(
        state.copyWith(
          sessions: sessions,
          activeSessions: activeSessions,
          entries: entries,
          checkpoints: checkpointMap,
          activeSession: active,
          clearActiveSession: active == null,
          loading: false,
          saving: false,
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
    String? notes,
    DateTime? startedAt,
    String? parentSessionId,
  }) async {
    final now = startedAt ?? DateTime.now();
    await _save(() async {
      if (parentSessionId != null) {
        final parent = await repository.getSession(
          AppContext.householdId,
          parentSessionId,
        );
        if (parent == null || parent.status != ActivitySessionStatus.active) {
          throw StateError('Aktivitas induknya sudah tidak berjalan.');
        }
      }
      await repository.saveSession(
        ActivitySessionEntity(
          id: _uuid.v4(),
          householdId: AppContext.householdId,
          title: title,
          category: category,
          parentSessionId: parentSessionId,
          startedAt: now,
          status: ActivitySessionStatus.active,
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
        ActivitySessionEntity(
          id: current.id,
          householdId: current.householdId,
          title: current.title,
          category: current.category,
          parentSessionId: current.parentSessionId,
          startedAt: current.startedAt,
          endedAt: end,
          status: ActivitySessionStatus.completed,
          notes: current.notes,
          isArchived: current.isArchived,
          createdAt: current.createdAt,
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
          category: 'lainnya',
          notes: 'Dimulai lewat voice: ${intent.rawTranscript}',
        );
      case ActivityVoiceIntentType.startChild:
        final title = intent.targetTitle;
        final parentId = intent.parentSessionId;
        if (title == null || title.trim().isEmpty || parentId == null) {
          throw StateError('Aktivitas atau induknya belum jelas.');
        }
        await startSession(
          title: title,
          category: 'lainnya',
          notes: 'Dimulai lewat voice: ${intent.rawTranscript}',
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
