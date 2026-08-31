import 'ffm_assistant_autonomy_repository.dart';

class FfmAssistantAutonomyTriggerService {
  FfmAssistantAutonomyTriggerService(this._repository);

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
    } on Object {
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
}
