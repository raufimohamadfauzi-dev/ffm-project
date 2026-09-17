import '../../../../core/database/app_context.dart';
import '../../data/repositories/audit_log_repository.dart';
import '../entities/audit_log_entity.dart';

class GetAuditLogs {
  const GetAuditLogs(this.repository);

  final AuditLogRepository repository;

  Future<List<AuditLogEntity>> call({
    String? action,
    String? entity,
    DateTime? from,
    DateTime? to,
    String? search,
    int limit = 200,
    int offset = 0,
  }) {
    return repository.getLogs(
      householdId: AppContext.householdId,
      action: action,
      entity: entity,
      from: from,
      to: to,
      search: search,
      limit: limit,
      offset: offset,
    );
  }
}
