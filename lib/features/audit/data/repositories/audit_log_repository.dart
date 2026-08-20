import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../domain/entities/audit_log_entity.dart';

abstract interface class AuditLogRepository {
  Future<List<AuditLogEntity>> getLogs({
    required String householdId,
    String? action,
    DateTime? from,
    DateTime? to,
    String? search,
    int limit = 200,
  });
}

class SqliteAuditLogRepository implements AuditLogRepository {
  const SqliteAuditLogRepository(this.database);

  final AppDatabase database;

  Future<void> _ensureTable() async {
    await database.customStatement(
      'CREATE TABLE IF NOT EXISTS audit_logs ('
      'id TEXT PRIMARY KEY, household_id TEXT NOT NULL, action TEXT NOT NULL, '
      'entity TEXT NOT NULL, old_value TEXT, new_value TEXT, timestamp INTEGER NOT NULL)',
    );
  }

  @override
  Future<List<AuditLogEntity>> getLogs({
    required String householdId,
    String? action,
    DateTime? from,
    DateTime? to,
    String? search,
    int limit = 200,
  }) async {
    await _ensureTable();
    final clauses = <String>['household_id = ?'];
    final variables = <Variable>[Variable.withString(householdId)];

    if (action != null && action.isNotEmpty) {
      clauses.add('action = ?');
      variables.add(Variable.withString(action));
    }
    if (from != null) {
      clauses.add('timestamp >= ?');
      variables.add(Variable.withInt(from.microsecondsSinceEpoch));
    }
    if (to != null) {
      clauses.add('timestamp < ?');
      variables.add(Variable.withInt(to.microsecondsSinceEpoch));
    }
    final query = search?.trim();
    if (query != null && query.isNotEmpty) {
      clauses.add(
        '(action LIKE ? OR entity LIKE ? OR old_value LIKE ? OR new_value LIKE ?)',
      );
      final pattern = '%$query%';
      for (var index = 0; index < 4; index++) {
        variables.add(Variable.withString(pattern));
      }
    }

    final safeLimit = limit.clamp(1, 500);
    final rows = await database
        .customSelect(
          'SELECT id, household_id, action, entity, old_value, new_value, timestamp '
          'FROM audit_logs WHERE ${clauses.join(' AND ')} '
          'ORDER BY timestamp DESC LIMIT $safeLimit',
          variables: variables,
        )
        .get();
    return rows
        .map(
          (row) => AuditLogEntity(
            id: row.read<String>('id'),
            householdId: row.read<String>('household_id'),
            action: row.read<String>('action'),
            entity: row.read<String>('entity'),
            oldValue: row.readNullable<String>('old_value'),
            newValue: row.readNullable<String>('new_value'),
            timestamp: DateTime.fromMicrosecondsSinceEpoch(
              row.read<int>('timestamp'),
            ),
          ),
        )
        .toList(growable: false);
  }
}
