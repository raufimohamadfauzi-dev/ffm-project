import 'dart:async';

import 'package:flutter/foundation.dart';

import 'ffm_assistant_autonomy_repository.dart';

class FfmAssistantAutonomyTriggerService {
  FfmAssistantAutonomyTriggerService(
    this._repository, {
    this.evaluateNow,
    this.coalesceWindow = const Duration(milliseconds: 300),
  });

  static const _maxPayloadEntries = 12;
  static const _maxStringLength = 200;
  static const _blockedKeyFragments = <String>{
    'prompt',
    'input',
    'token',
    'password',
    'secret',
    'credential',
    'raw',
    'content',
  };

  final FfmAssistantAutonomyRepository _repository;
  final Future<void> Function(String householdId)? evaluateNow;
  final Duration coalesceWindow;
  final Map<String, Timer> _debounceTimers = {};

  /// Menghentikan seluruh timer debounce yang aktif.
  void dispose() {
    for (final timer in _debounceTimers.values) {
      timer.cancel();
    }
    _debounceTimers.clear();
  }

  /// Mengantrekan trigger aplikasi tanpa menjalankan capability atau LLM.
  /// Hanya metadata scalar yang aman dan terbatas yang boleh masuk payload.
  Future<bool> emit({
    required String triggerId,
    required String type,
    required String householdId,
    DateTime? occurredAt,
    String? entityId,
    String? activityId,
    Map<String, Object?> payload = const {},
  }) {
    final normalizedTriggerId = triggerId.trim();
    final normalizedType = type.trim();
    final normalizedHouseholdId = householdId.trim();
    if (normalizedTriggerId.isEmpty ||
        normalizedType.isEmpty ||
        normalizedHouseholdId.isEmpty) {
      return Future.value(false);
    }
    return _repository.enqueueEvent(
      FfmAssistantAutonomyEvent(
        id: 'trigger:$normalizedType:$normalizedTriggerId',
        type: normalizedType,
        occurredAt: occurredAt ?? DateTime.now(),
        householdId: normalizedHouseholdId,
        entityId: _safeString(entityId),
        activityId: _safeString(activityId),
        payload: _sanitizePayload(payload),
      ),
    );
  }

  Future<void> emitSafely({
    required String triggerId,
    required String type,
    required String householdId,
    DateTime? occurredAt,
    String? entityId,
    String? activityId,
    Map<String, Object?> payload = const {},
  }) async {
    try {
      await emit(
        triggerId: triggerId,
        type: type,
        householdId: householdId,
        occurredAt: occurredAt,
        entityId: entityId,
        activityId: activityId,
        payload: payload,
      );
      final evaluate = evaluateNow;
      if (evaluate != null) {
        if (coalesceWindow == Duration.zero) {
          unawaited(
            evaluate(householdId).catchError((e, st) {
              if (kDebugMode) {
                debugPrint('Autonomy trigger evaluateNow error: $e\n$st');
              }
            }),
          );
        } else {
          // Coalesce event berdekatan agar tidak memicu eksekusi evaluasi ganda (F1.5)
          _debounceTimers[householdId]?.cancel();
          _debounceTimers[householdId] = Timer(coalesceWindow, () {
            _debounceTimers.remove(householdId);
            unawaited(
              evaluate(householdId).catchError((e, st) {
                if (kDebugMode) {
                  debugPrint('Autonomy trigger evaluateNow error: $e\n$st');
                }
              }),
            );
          });
        }
      }
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint('Autonomy trigger emit error: $e\n$st');
      }
      // Trigger persistence must never roll back an authoritative data write.
    }
  }

  String? _safeString(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    return normalized.length <= _maxStringLength
        ? normalized
        : normalized.substring(0, _maxStringLength);
  }

  Map<String, Object?> _sanitizePayload(Map<String, Object?> payload) {
    final sanitized = <String, Object?>{};
    for (final entry in payload.entries) {
      if (sanitized.length >= _maxPayloadEntries) break;
      final key = entry.key.trim();
      final loweredKey = key.toLowerCase();
      if (key.isEmpty ||
          _blockedKeyFragments.any(loweredKey.contains) ||
          sanitized.containsKey(key)) {
        continue;
      }
      final value = entry.value;
      if (value is String) {
        sanitized[key] = _safeString(value);
      } else if (value is num || value is bool) {
        sanitized[key] = value;
      }
    }
    return sanitized;
  }

  /// Emit LLM job trigger untuk job yang membutuhkan LLM reasoning.
  ///
  /// [jobType] - Tipe job otonom (budget_adjust, reminder_check, dll)
  /// [userPrompt] - Prompt untuk LLM
  /// [context] - Context tambahan untuk LLM
  /// [householdId] - Household ID
  /// [triggerId] - Optional trigger ID (jika tidak disediakan, akan digenerate otomatis)
  Future<bool> emitLlmJob({
    required String jobType,
    required String userPrompt,
    String? context,
    required String householdId,
    String? triggerId,
  }) {
    final normalizedJobType = jobType.trim();
    final normalizedUserPrompt = userPrompt.trim();
    final normalizedHouseholdId = householdId.trim();
    if (normalizedJobType.isEmpty ||
        normalizedUserPrompt.isEmpty ||
        normalizedHouseholdId.isEmpty) {
      return Future.value(false);
    }

    final finalTriggerId = triggerId ?? 'llm:$normalizedJobType:${DateTime.now().millisecondsSinceEpoch}';

    return emit(
      triggerId: finalTriggerId,
      type: 'autonomy.llm.job',
      householdId: normalizedHouseholdId,
      payload: <String, Object?>{
        'jobType': normalizedJobType,
        'userPrompt': normalizedUserPrompt,
        if (context != null && context.isNotEmpty) 'context': context,
      },
    );
  }
}
