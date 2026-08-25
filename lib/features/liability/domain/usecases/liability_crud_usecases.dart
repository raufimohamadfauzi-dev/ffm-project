import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/audit_logger.dart';
import '../entities/liability_entity.dart';

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
  }
}

class DeleteLiability {
  const DeleteLiability(this.database);
  final AppDatabase database;

  Future<void> call(String householdId, String id) async {
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
  }
}
