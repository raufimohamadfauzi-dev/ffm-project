import 'dart:convert';

import 'app_database.dart';
import 'app_context.dart';

class AuditLogger {
  const AuditLogger(this.database);
  final AppDatabase database;

  Future<void> record({
    required String action,
    required String entity,
    String? householdId,
    Object? oldValue,
    Object? newValue,
  }) async {
    try {
      await database.customStatement(
        'CREATE TABLE IF NOT EXISTS audit_logs ('
        'id TEXT PRIMARY KEY, household_id TEXT NOT NULL, action TEXT NOT NULL, '
        'entity TEXT NOT NULL, old_value TEXT, new_value TEXT, timestamp INTEGER NOT NULL)',
      );
      final now = DateTime.now();
      await database.customStatement(
        'INSERT INTO audit_logs (id, household_id, action, entity, old_value, new_value, timestamp) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          '${now.microsecondsSinceEpoch}-$action',
          householdId ?? AppContext.householdId,

          action,
          entity,
          oldValue == null ? null : jsonEncode(oldValue),
          newValue == null ? null : jsonEncode(newValue),
          now.microsecondsSinceEpoch,
        ],
      );
    } catch (_) {
      // Audit hanya pelengkap. Kegagalan audit tidak boleh membatalkan
      // transaksi, impor, atau rekonsiliasi yang sudah berhasil.
    }
  }
}
