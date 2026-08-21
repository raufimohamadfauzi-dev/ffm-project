import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_context.dart';
import '../../data/repositories/activity_repository.dart';
import '../../domain/entities/activity_entity.dart';

class ActivityState {
  const ActivityState({
    this.sessions = const [],
    this.entries = const [],
    this.checkpoints = const {},
    this.activeSession,
    this.loading = false,
    this.saving = false,
    this.error,
  });

  final List<ActivitySessionEntity> sessions;
  final List<ActivityJournalEntryEntity> entries;
  final Map<String, List<ActivityCheckpointEntity>> checkpoints;
  final ActivitySessionEntity? activeSession;
  final bool loading;
  final bool saving;
  final String? error;

  ActivityState copyWith({
    List<ActivitySessionEntity>? sessions,
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
      final active = await repository.getActiveSession(AppContext.householdId);
      final checkpointMap = <String, List<ActivityCheckpointEntity>>{};
      for (final session in sessions) {
        checkpointMap[session.id] = await repository.getCheckpoints(session.id);
      }
      emit(
        state.copyWith(
          sessions: sessions,
          entries: entries,
          checkpoints: checkpointMap,
          activeSession: active,
          loading: false,
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
  }) async {
    final now = startedAt ?? DateTime.now();
    await _save(() async {
      final current = await repository.getActiveSession(AppContext.householdId);
      if (current != null) {
        throw StateError('Selesaikan aktivitas yang sedang berjalan dulu.');
      }
      await repository.saveSession(
        ActivitySessionEntity(
          id: _uuid.v4(),
          householdId: AppContext.householdId,
          title: title,
          category: category,
          startedAt: now,
          status: ActivitySessionStatus.active,
          notes: notes,
          createdAt: DateTime.now(),
        ),
      );
    });
  }

  Future<void> finishSession({DateTime? endedAt}) async {
    final current =
        state.activeSession ??
        await repository.getActiveSession(AppContext.householdId);
    if (current == null) return;
    final end = endedAt ?? DateTime.now();
    await _save(
      () => repository.saveSession(
        ActivitySessionEntity(
          id: current.id,
          householdId: current.householdId,
          title: current.title,
          category: current.category,
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
  }) async {
    final session =
        state.activeSession ??
        await repository.getActiveSession(AppContext.householdId);
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
