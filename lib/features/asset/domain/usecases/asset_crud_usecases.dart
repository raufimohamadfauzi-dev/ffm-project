import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../entities/asset_entity.dart';

class GetAssets {
  const GetAssets(this.database);
  final AppDatabase database;

  Future<List<AssetEntity>> call(String householdId) async {
    final rows =
        await (database.select(database.assets)
              ..where((row) => row.householdId.equals(householdId))
              ..orderBy([(row) => OrderingTerm.asc(row.name)]))
            .get();
    return rows
        .map(
          (row) => AssetEntity(
            id: row.id,
            householdId: row.householdId,
            name: row.name,
            assetType: row.assetType,
            value: row.value,
            placement: row.placement,
            createdAt: row.createdAt,
            updatedAt: row.updatedAt,
            note: row.note,
          ),
        )
        .toList(growable: false);
  }
}

class SaveAsset {
  const SaveAsset(this.database);
  final AppDatabase database;

  Future<void> call(AssetEntity entity) async {
    await database
        .into(database.assets)
        .insertOnConflictUpdate(
          AssetsCompanion.insert(
            id: entity.id,
            householdId: entity.householdId,
            name: entity.name,
            assetType: entity.assetType,
            value: Value(entity.value),
            placement: Value(entity.placement),
            note: Value(entity.note),
            createdAt: entity.createdAt,
            updatedAt: Value(entity.updatedAt ?? DateTime.now()),
          ),
        );
  }
}

class DeleteAsset {
  const DeleteAsset(this.database);
  final AppDatabase database;

  Future<void> call(String householdId, String id) async {
    await (database.delete(database.assets)..where(
          (row) => row.householdId.equals(householdId) & row.id.equals(id),
        ))
        .go();
  }
}
