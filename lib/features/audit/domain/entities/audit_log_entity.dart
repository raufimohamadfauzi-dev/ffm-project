import 'dart:convert';

class AuditLogEntity {
  const AuditLogEntity({
    required this.id,
    required this.householdId,
    required this.action,
    required this.entity,
    required this.timestamp,
    this.oldValue,
    this.newValue,
  });

  final String id;
  final String householdId;
  final String action;
  final String entity;
  final String? oldValue;
  final String? newValue;
  final DateTime timestamp;

  Set<String> get changedFields {
    final fields = <String>{};
    for (final raw in [oldValue, newValue]) {
      if (raw == null || raw.trim().isEmpty) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          fields.addAll(
            decoded.keys.whereType<String>().where(
              (key) => !_isSensitiveKey(key),
            ),
          );
        }
      } catch (_) {
        // Nilai lama bisa berasal dari versi aplikasi yang tidak memakai JSON.
      }
    }
    return fields;
  }

  static bool _isSensitiveKey(String key) {
    final normalized = key.toLowerCase();
    return normalized.contains('pin') ||
        normalized.contains('password') ||
        normalized.contains('credential') ||
        normalized.contains('token') ||
        normalized.contains('secret');
  }
}
