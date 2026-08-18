import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../entities/goal_entity.dart';

class GetGoals {
  const GetGoals(this.database);
  final AppDatabase database;

  Future<List<GoalEntity>> call(String householdId) async {
    final rows = await (database.select(database.goals)
          ..where((row) => row.householdId.equals(householdId) & row.isActive.equals(true))
          ..orderBy([(row) => OrderingTerm.asc(row.targetDate)]))
        .get();
    return rows.map(_toEntity).toList(growable: false);
  }

  GoalEntity _toEntity(Goal row) => GoalEntity(
    id: row.id,
    householdId: row.householdId,
    name: row.name,
    targetAmount: row.targetAmount,
    currentAmount: row.currentAmount,
    targetDate: row.targetDate ?? DateTime.now(),
    categoryId: row.categoryId,
    isActive: row.isActive,
    createdAt: row.createdAt,
  );
}

class GetGoal {
  const GetGoal(this.database);
  final AppDatabase database;

  Future<GoalEntity?> call(String householdId, String id) async {
    final row = await (database.select(database.goals)
          ..where((item) => item.householdId.equals(householdId) & item.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return null;
    return GoalEntity(
      id: row.id,
      householdId: row.householdId,
      name: row.name,
      targetAmount: row.targetAmount,
      currentAmount: row.currentAmount,
      targetDate: row.targetDate ?? DateTime.now(),
      categoryId: row.categoryId,
      isActive: row.isActive,
      createdAt: row.createdAt,
    );
  }
}

class SaveGoal {
  const SaveGoal(this.database);
  final AppDatabase database;

  Future<void> call(GoalEntity entity) async {
    await database.into(database.goals).insertOnConflictUpdate(
      GoalsCompanion.insert(
        id: entity.id,
        householdId: entity.householdId,
        name: entity.name,
        targetAmount: entity.targetAmount,
        currentAmount: Value(entity.currentAmount),
        targetDate: Value(entity.targetDate),
        categoryId: Value(entity.categoryId),
        isActive: Value(entity.isActive),
        createdAt: entity.createdAt ?? DateTime.now(),
      ),
    );
  }
}

class DeleteGoal {
  const DeleteGoal(this.database);
  final AppDatabase database;

  Future<void> call(String householdId, String id) async {
    await (database.update(database.goals)
          ..where((row) => row.householdId.equals(householdId) & row.id.equals(id)))
        .write(const GoalsCompanion(isActive: Value(false)));
  }
}
