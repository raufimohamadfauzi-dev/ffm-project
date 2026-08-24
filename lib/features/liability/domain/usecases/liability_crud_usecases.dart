import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/audit_logger.dart';
import '../../../../core/di/injection.dart';
import '../../../assistant/presentation/widgets/ffm_agent_status_indicator.dart';
import '../entities/liability_entity.dart';

FfmAgentStatusController? _statusController() =>
    getIt.isRegistered<FfmAgentStatusController>()
    ? getIt<FfmAgentStatusController>()
    : null;

class GetLiabilities {
  const GetLiabilities(this.database);
  final AppDatabase database;

  Future<List<LiabilityEntity>> call(String householdId) async {
    final rows =
        await (database.select(database.liabilities)
              ..where(
                (row) =>
                    row.householdId.equals(householdId) &
                    row.isActive.equals(true),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.dueDate)]))
            .get();
    return rows
        .map(
          (row) => LiabilityEntity(
            id: row.id,
            householdId: row.householdId,
            name: row.name,
            originalAmount: row.originalAmount,
            remainingBalance: row.remainingBalance,
            monthlyInstallment: row.monthlyInstallment,
            interestRate: row.interestRate,
            startDate: row.startDate,
            dueDate: row.dueDate ?? row.startDate,
            updatedAt: row.createdAt,
            note: row.note,
          ),
        )
        .toList(growable: false);
  }
}

class SaveLiability {
  const SaveLiability(this.database);
  final AppDatabase database;

  Future<void> call(LiabilityEntity entity) async {
    _statusController()?.working(
      'Menyimpan hutang dan memperbarui konteks asisten...',
    );
    await database
        .into(database.liabilities)
        .insertOnConflictUpdate(
          LiabilitiesCompanion.insert(
            id: entity.id,
            householdId: entity.householdId,
            name: entity.name,
            originalAmount: entity.originalAmount,
            remainingBalance: entity.remainingBalance,
            monthlyInstallment: Value(entity.monthlyInstallment),
            interestRate: Value(entity.interestRate ?? 0),
            startDate: entity.startDate,
            dueDate: Value(entity.dueDate),
            note: Value(entity.note),
            createdAt: entity.updatedAt,
          ),
        );
    await AuditLogger(database).record(
      action: 'simpan hutang',
      entity: 'liability',
      householdId: entity.householdId,
      newValue: {
        'id': entity.id,
        'name': entity.name,
        'originalAmount': entity.originalAmount,
        'remainingBalance': entity.remainingBalance,
      },
    );
    _statusController()?.done('Hutang tersimpan; konteks asisten diperbarui.');
  }
}

class DeleteLiability {
  const DeleteLiability(this.database);
  final AppDatabase database;

  Future<void> call(String householdId, String id) async {
    _statusController()?.working('Mengarsipkan hutang...');
    await (database.update(database.liabilities)..where(
          (row) => row.householdId.equals(householdId) & row.id.equals(id),
        ))
        .write(const LiabilitiesCompanion(isActive: Value(false)));
    await AuditLogger(database).record(
      action: 'arsip hutang',
      entity: 'liability',
      householdId: householdId,
      newValue: {'id': id, 'isActive': false},
    );
    _statusController()?.done('Hutang diarsipkan.');
  }
}
