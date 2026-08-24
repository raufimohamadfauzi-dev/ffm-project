import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/audit_logger.dart';
import '../../../../core/di/injection.dart';
import '../../../assistant/presentation/widgets/ffm_agent_status_indicator.dart';
import '../entities/asset_entity.dart';

FfmAgentStatusController? _statusController() =>
    getIt.isRegistered<FfmAgentStatusController>()
    ? getIt<FfmAgentStatusController>()
    : null;

class GetAssets {
  const GetAssets(this.database);
  final AppDatabase database;

  Future<List<AssetEntity>> call(String householdId) async {
    final rows =
        await (database.select(database.assets)
              ..where(
                (row) =>
                    row.householdId.equals(householdId) &
                    row.isArchived.equals(false),
              )
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
            isArchived: row.isArchived,
          ),
        )
        .toList(growable: false);
  }
}

class SaveAsset {
  const SaveAsset(this.database);
  final AppDatabase database;

  Future<void> call(AssetEntity entity) async {
    _statusController()?.working(
      'Menyimpan aset dan memperbarui konteks asisten...',
    );
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
            isArchived: Value(entity.isArchived),
          ),
        );
    await AuditLogger(database).record(
      action: 'simpan aset',
      entity: 'asset',
      householdId: entity.householdId,
      newValue: {
        'id': entity.id,
        'name': entity.name,
        'assetType': entity.assetType,
        'value': entity.value,
        'placement': entity.placement,
      },
    );
    _statusController()?.done('Aset tersimpan; konteks asisten diperbarui.');
  }
}

class ArchiveAsset {
  const ArchiveAsset(this.database);
  final AppDatabase database;

  Future<void> call(String householdId, String id) async {
    _statusController()?.working('Mengarsipkan aset...');
    await (database.update(database.assets)..where(
          (row) => row.householdId.equals(householdId) & row.id.equals(id),
        ))
        .write(
          AssetsCompanion(
            isArchived: const Value(true),
            updatedAt: Value(DateTime.now()),
          ),
        );
    await AuditLogger(database).record(
      action: 'arsip aset',
      entity: 'asset',
      householdId: householdId,
      newValue: {'id': id, 'isArchived': true},
    );
    _statusController()?.done('Aset diarsipkan.');
  }
}
