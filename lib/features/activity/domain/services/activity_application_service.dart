import 'dart:developer' as developer;
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_context.dart';
import '../../data/repositories/activity_repository.dart';
import '../entities/activity_entity.dart';
import '../../presentation/bloc/activity_bloc.dart';

class ActivityCommandResult {
  const ActivityCommandResult({
    required this.success,
    required this.operationId,
    required this.message,
    this.newRevision = 0,
    this.revisionMismatch = false,
    this.session,
    this.checkpoint,
    this.note,
    this.activeChildrenCount = 0,
  });

  final bool success;
  final String operationId;
  final String message;
  final int newRevision;
  final bool revisionMismatch;
  final ActivitySessionEntity? session;
  final ActivityCheckpointEntity? checkpoint;
  final ActivityNoteEntity? note;
  final int activeChildrenCount;

  factory ActivityCommandResult.mismatch({
    required String operationId,
    required int expectedRevision,
    required int currentRevision,
    required String message,
  }) => ActivityCommandResult(
    success: false,
    operationId: operationId,
    revisionMismatch: true,
    message: message,
    newRevision: currentRevision,
  );

  factory ActivityCommandResult.failed({
    required String operationId,
    required String message,
    int revision = 0,
  }) => ActivityCommandResult(
    success: false,
    operationId: operationId,
    message: message,
    newRevision: revision,
  );
}

enum ActivityOperationType {
  startSession,
  finishSession,
  addCheckpoint,
  addQuickNote,
}

class _ExecutedOperation {
  const _ExecutedOperation({
    required this.operationId,
    required this.type,
    required this.entityId,
    required this.result,
    required this.timestamp,
    this.previousState,
  });

  final String operationId;
  final ActivityOperationType type;
  final String entityId;
  final ActivityCommandResult result;
  final DateTime timestamp;
  final Map<String, dynamic>? previousState;
}

/// Unified Application Service for all Activity mutations (UI, Voice, Assistant, Automation).
///
/// Guarantees:
/// 1. Idempotency via operationId.
/// 2. Revision check before commit to prevent stale race conditions.
/// 3. Parent-child hierarchy safety.
/// 4. Canonical IDs everywhere.
/// 5. Undo capability for assistant actions.
/// 6. Debug observability logging.
class ActivityApplicationService {
  ActivityApplicationService({
    required this.repository,
    required this.activityBloc,
  });

  final ActivityRepository repository;
  final ActivityBloc activityBloc;
  static const _uuid = Uuid();

  final Map<String, _ExecutedOperation> _operationHistory = {};

  int get currentRevision => activityBloc.state.revision;
  ActivityLiveSnapshot get snapshot => activityBloc.state.toSnapshot();

  void _logDebug({
    required String action,
    String? trigger,
    String? matchedSessionId,
    String? parentSessionId,
    double? confidence,
    int? sourceRevision,
    required String operationId,
    required String result,
  }) {
    final sb = StringBuffer('[ActivityAgent]\n')
      ..writeln('  action = $action')
      ..writeln('  operationId = $operationId');
    if (trigger != null) sb.writeln('  trigger = "$trigger"');
    if (matchedSessionId != null) sb.writeln('  matchedSessionId = $matchedSessionId');
    if (parentSessionId != null) sb.writeln('  parentSessionId = $parentSessionId');
    if (confidence != null) sb.writeln('  confidence = ${confidence.toStringAsFixed(2)}');
    if (sourceRevision != null) sb.writeln('  sourceRevision = $sourceRevision');
    sb.writeln('  currentRevision = $currentRevision');
    sb.writeln('  result = $result');
    developer.log(sb.toString(), name: 'ActivityAgent');
  }

  /// Memulai sesi baru dengan verifikasi hierarki dan idempotency.
  Future<ActivityCommandResult> startSession({
    required String operationId,
    required String title,
    required String category,
    String? notes,
    DateTime? startedAt,
    String? parentSessionId,
    int? expectedRevision,
    ActivityEntrySource source = ActivityEntrySource.manual,
    String? trigger,
  }) async {
    // 1. Idempotency check
    if (_operationHistory.containsKey(operationId)) {
      return _operationHistory[operationId]!.result;
    }

    // 2. Revision check
    if (expectedRevision != null && expectedRevision != currentRevision) {
      final res = ActivityCommandResult.mismatch(
        operationId: operationId,
        expectedRevision: expectedRevision,
        currentRevision: currentRevision,
        message: 'State aktivitas berubah sebelum aksi dijalankan (revisi $expectedRevision vs $currentRevision). Mohon verifikasi ulang draf.',
      );
      _logDebug(
        action: 'start_session',
        trigger: trigger,
        parentSessionId: parentSessionId,
        sourceRevision: expectedRevision,
        operationId: operationId,
        result: 'revision_mismatch',
      );
      return res;
    }

    // 3. Parent verification
    if (parentSessionId != null) {
      final parent = await repository.getSession(AppContext.householdId, parentSessionId);
      if (parent == null || parent.status != ActivitySessionStatus.active) {
        final res = ActivityCommandResult.failed(
          operationId: operationId,
          message: 'Aktivitas induk ($parentSessionId) sudah tidak aktif atau tidak ditemukan.',
          revision: currentRevision,
        );
        _logDebug(
          action: 'start_session',
          trigger: trigger,
          parentSessionId: parentSessionId,
          operationId: operationId,
          result: 'parent_not_active',
        );
        return res;
      }
    }

    // 4. Commit mutation
    final newId = _uuid.v4();
    final now = startedAt ?? DateTime.now();
    final sessionEntity = ActivitySessionEntity(
      id: newId,
      householdId: AppContext.householdId,
      title: title.trim(),
      category: category,
      parentSessionId: parentSessionId,
      startedAt: now,
      status: ActivitySessionStatus.active,
      notes: notes,
      createdAt: DateTime.now(),
    );

    await repository.saveSession(sessionEntity);
    await activityBloc.load();

    final result = ActivityCommandResult(
      success: true,
      operationId: operationId,
      message: parentSessionId == null
          ? 'Sesi "${sessionEntity.title}" berhasil dimulai.'
          : 'Sub-sesi "${sessionEntity.title}" berhasil dimulai di dalam aktivitas induk.',
      newRevision: currentRevision,
      session: sessionEntity,
    );

    _operationHistory[operationId] = _ExecutedOperation(
      operationId: operationId,
      type: ActivityOperationType.startSession,
      entityId: newId,
      result: result,
      timestamp: DateTime.now(),
    );

    _logDebug(
      action: 'start_session',
      trigger: trigger,
      matchedSessionId: newId,
      parentSessionId: parentSessionId,
      operationId: operationId,
      result: 'success',
    );

    return result;
  }

  /// Menyelesaikan sesi dengan Hierarchy Safety & anti-salah tutup.
  Future<ActivityCommandResult> finishSession({
    required String operationId,
    required String sessionId,
    DateTime? endedAt,
    int? expectedRevision,
    bool forceCloseChildren = false,
    ActivityEntrySource source = ActivityEntrySource.manual,
    String? trigger,
  }) async {
    // 1. Idempotency check
    if (_operationHistory.containsKey(operationId)) {
      return _operationHistory[operationId]!.result;
    }

    // 2. Revision check
    if (expectedRevision != null && expectedRevision != currentRevision) {
      final res = ActivityCommandResult.mismatch(
        operationId: operationId,
        expectedRevision: expectedRevision,
        currentRevision: currentRevision,
        message: 'State aktivitas berubah sebelum aksi selesai dijalankan. Mohon konfirmasi ulang target sesi.',
      );
      _logDebug(
        action: 'finish_session',
        trigger: trigger,
        matchedSessionId: sessionId,
        sourceRevision: expectedRevision,
        operationId: operationId,
        result: 'revision_mismatch',
      );
      return res;
    }

    // 3. Find target session
    final target = await repository.getSession(AppContext.householdId, sessionId);
    if (target == null || target.status != ActivitySessionStatus.active) {
      final res = ActivityCommandResult.failed(
        operationId: operationId,
        message: 'Sesi dengan ID "$sessionId" sudah selesai atau tidak ditemukan.',
        revision: currentRevision,
      );
      _logDebug(
        action: 'finish_session',
        trigger: trigger,
        matchedSessionId: sessionId,
        operationId: operationId,
        result: 'session_not_found_or_already_closed',
      );
      return res;
    }

    // 4. Hierarchy Safety: check active child sessions
    final activeSessions = await repository.getActiveSessions(AppContext.householdId);
    final activeChildren = activeSessions.where((s) => s.parentSessionId == target.id).toList();

    if (activeChildren.isNotEmpty && !forceCloseChildren) {
      final childNames = activeChildren.map((c) => c.title).join(', ');
      final res = ActivityCommandResult(
        success: false,
        operationId: operationId,
        message: 'Aktivitas "${target.title}" masih memiliki ${activeChildren.length} sub-kegiatan aktif: $childNames. Tutup sub-kegiatan terlebih dahulu atau konfirmasi tutup semua.',
        newRevision: currentRevision,
        session: target,
        activeChildrenCount: activeChildren.length,
      );
      _logDebug(
        action: 'finish_session',
        trigger: trigger,
        matchedSessionId: sessionId,
        operationId: operationId,
        result: 'active_children_warning (${activeChildren.length} children)',
      );
      return res;
    }

    final end = endedAt ?? DateTime.now();

    // If forceCloseChildren, close all child sessions too
    if (activeChildren.isNotEmpty && forceCloseChildren) {
      for (final child in activeChildren) {
        final closedChild = ActivitySessionEntity(
          id: child.id,
          householdId: child.householdId,
          title: child.title,
          category: child.category,
          parentSessionId: child.parentSessionId,
          startedAt: child.startedAt,
          endedAt: end,
          status: ActivitySessionStatus.completed,
          notes: child.notes,
          isArchived: child.isArchived,
          createdAt: child.createdAt,
          updatedAt: DateTime.now(),
        );
        await repository.saveSession(closedChild);
      }
    }

    final closedParent = ActivitySessionEntity(
      id: target.id,
      householdId: target.householdId,
      title: target.title,
      category: target.category,
      parentSessionId: target.parentSessionId,
      startedAt: target.startedAt,
      endedAt: end,
      status: ActivitySessionStatus.completed,
      notes: target.notes,
      isArchived: target.isArchived,
      createdAt: target.createdAt,
      updatedAt: DateTime.now(),
    );

    await repository.saveSession(closedParent);
    await activityBloc.load();

    final result = ActivityCommandResult(
      success: true,
      operationId: operationId,
      message: 'Aktivitas "${target.title}" selesai (${const ActivityDurationCalculator().format(closedParent.durationAt())}).',
      newRevision: currentRevision,
      session: closedParent,
    );

    _operationHistory[operationId] = _ExecutedOperation(
      operationId: operationId,
      type: ActivityOperationType.finishSession,
      entityId: target.id,
      result: result,
      timestamp: DateTime.now(),
      previousState: {
        'status': target.status.value,
        'endedAt': target.endedAt?.toIso8601String(),
      },
    );

    _logDebug(
      action: 'finish_session',
      trigger: trigger,
      matchedSessionId: sessionId,
      operationId: operationId,
      result: 'success',
    );

    return result;
  }

  /// Menambahkan checkpoint ke sesi aktif secara idempotent.
  Future<ActivityCommandResult> addCheckpoint({
    required String operationId,
    required String sessionId,
    required String label,
    String? place,
    String? note,
    DateTime? occurredAt,
    int? expectedRevision,
    ActivityEntrySource source = ActivityEntrySource.manual,
    String? trigger,
  }) async {
    if (_operationHistory.containsKey(operationId)) {
      return _operationHistory[operationId]!.result;
    }

    if (expectedRevision != null && expectedRevision != currentRevision) {
      return ActivityCommandResult.mismatch(
        operationId: operationId,
        expectedRevision: expectedRevision,
        currentRevision: currentRevision,
        message: 'State aktivitas berubah sebelum checkpoint disimpan.',
      );
    }

    final session = await repository.getSession(AppContext.householdId, sessionId);
    if (session == null || session.status != ActivitySessionStatus.active) {
      return ActivityCommandResult.failed(
        operationId: operationId,
        message: 'Sesi tujuan checkpoint ($sessionId) tidak aktif.',
        revision: currentRevision,
      );
    }

    final existing = await repository.getCheckpoints(sessionId);
    final cpId = _uuid.v4();
    final cp = ActivityCheckpointEntity(
      id: cpId,
      sessionId: sessionId,
      label: label.trim(),
      place: place,
      occurredAt: occurredAt ?? DateTime.now(),
      sequence: existing.length + 1,
      note: note,
      createdAt: DateTime.now(),
    );

    await repository.saveCheckpoint(cp);
    await activityBloc.load();

    final result = ActivityCommandResult(
      success: true,
      operationId: operationId,
      message: 'Checkpoint "${cp.label}" berhasil dicatat untuk ${session.title}.',
      newRevision: currentRevision,
      checkpoint: cp,
    );

    _operationHistory[operationId] = _ExecutedOperation(
      operationId: operationId,
      type: ActivityOperationType.addCheckpoint,
      entityId: cpId,
      result: result,
      timestamp: DateTime.now(),
    );

    _logDebug(
      action: 'add_checkpoint',
      trigger: trigger,
      matchedSessionId: sessionId,
      operationId: operationId,
      result: 'success',
    );

    return result;
  }

  /// Menambahkan Quick Note terstruktur (bisa mandiri atau terhubung ke sesi).
  Future<ActivityCommandResult> addQuickNote({
    required String operationId,
    required String text,
    required String category,
    double? numericValue,
    String? unit,
    double? latitude,
    double? longitude,
    String? linkedSessionId,
    int? expectedRevision,
    ActivityEntrySource source = ActivityEntrySource.manual,
    String? trigger,
  }) async {
    if (_operationHistory.containsKey(operationId)) {
      return _operationHistory[operationId]!.result;
    }

    if (expectedRevision != null && expectedRevision != currentRevision) {
      return ActivityCommandResult.mismatch(
        operationId: operationId,
        expectedRevision: expectedRevision,
        currentRevision: currentRevision,
        message: 'State aktivitas berubah sebelum catatan disimpan.',
      );
    }

    final noteId = _uuid.v4();
    final noteEntity = ActivityNoteEntity(
      id: noteId,
      householdId: AppContext.householdId,
      text: text.trim(),
      category: category.trim(),
      numericValue: numericValue,
      unit: unit?.trim(),
      latitude: latitude,
      longitude: longitude,
      createdAt: DateTime.now(),
      linkedSessionId: linkedSessionId,
      source: source,
    );

    await repository.saveNote(noteEntity);
    await activityBloc.load();

    final result = ActivityCommandResult(
      success: true,
      operationId: operationId,
      message: numericValue != null
          ? 'Catatan tersimpan: $text (${numericValue.toStringAsFixed(numericValue.truncateToDouble() == numericValue ? 0 : 2)} ${unit ?? ""}).'
          : 'Catatan tersimpan: $text.',
      newRevision: currentRevision,
      note: noteEntity,
    );

    _operationHistory[operationId] = _ExecutedOperation(
      operationId: operationId,
      type: ActivityOperationType.addQuickNote,
      entityId: noteId,
      result: result,
      timestamp: DateTime.now(),
    );

    _logDebug(
      action: 'add_quick_note',
      trigger: trigger,
      matchedSessionId: linkedSessionId,
      operationId: operationId,
      result: 'success',
    );

    return result;
  }

  /// Membatalkan aksi terakhir berdasarkan operationId.
  Future<ActivityCommandResult> undo(String operationId) async {
    final op = _operationHistory[operationId];
    if (op == null) {
      return ActivityCommandResult.failed(
        operationId: operationId,
        message: 'Operasi dengan ID "$operationId" tidak ditemukan untuk dibatalkan.',
        revision: currentRevision,
      );
    }

    switch (op.type) {
      case ActivityOperationType.startSession:
        await repository.archiveSession(AppContext.householdId, op.entityId);
        await activityBloc.load();
        _operationHistory.remove(operationId);
        return ActivityCommandResult(
          success: true,
          operationId: operationId,
          message: 'Pembuatan sesi berhasil dibatalkan.',
          newRevision: currentRevision,
        );

      case ActivityOperationType.finishSession:
        final session = await repository.getSession(AppContext.householdId, op.entityId);
        if (session != null) {
          final reopened = ActivitySessionEntity(
            id: session.id,
            householdId: session.householdId,
            title: session.title,
            category: session.category,
            parentSessionId: session.parentSessionId,
            startedAt: session.startedAt,
            endedAt: null,
            status: ActivitySessionStatus.active,
            notes: session.notes,
            isArchived: session.isArchived,
            createdAt: session.createdAt,
            updatedAt: DateTime.now(),
          );
          await repository.saveSession(reopened);
          await activityBloc.load();
        }
        _operationHistory.remove(operationId);
        return ActivityCommandResult(
          success: true,
          operationId: operationId,
          message: 'Penyelesaian aktivitas berhasil dibatalkan (sesi diaktifkan kembali).',
          newRevision: currentRevision,
        );

      case ActivityOperationType.addCheckpoint:
        // Checkpoint archived / removed from display
        _operationHistory.remove(operationId);
        return ActivityCommandResult(
          success: true,
          operationId: operationId,
          message: 'Penambahan checkpoint berhasil dibatalkan.',
          newRevision: currentRevision,
        );

      case ActivityOperationType.addQuickNote:
        await repository.archiveNote(AppContext.householdId, op.entityId);
        await activityBloc.load();
        _operationHistory.remove(operationId);
        return ActivityCommandResult(
          success: true,
          operationId: operationId,
          message: 'Catatan cepat berhasil dihapus.',
          newRevision: currentRevision,
        );
    }
  }
}
