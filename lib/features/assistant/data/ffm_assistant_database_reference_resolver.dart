import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/ffm_assistant_reference_resolver.dart';

/// Resolves user-facing draft references against the authoritative household DB.
/// The caller must handle all three outcomes before executing a mutation.
class FfmAssistantDatabaseReferenceResolver {
  const FfmAssistantDatabaseReferenceResolver({
    required this._database,
    required this._householdId,
  });

  final AppDatabase _database;
  final String _householdId;

  Future<FfmAssistantReferenceResolution<Account>> account(String? name) async {
    final rows =
        await (_database.select(_database.accounts)..where(
              (row) =>
                  row.householdId.equals(_householdId) &
                  row.isActive.equals(true) &
                  row.isArchived.equals(false),
            ))
            .get();
    return FfmAssistantReferenceResolver.resolve(name, rows, (row) => row.name);
  }

  Future<FfmAssistantReferenceResolution<Category>> category(
    String? name, {
    String? type,
  }) async {
    final rows =
        await (_database.select(_database.categories)..where(
              (row) =>
                  row.householdId.equals(_householdId) &
                  row.isActive.equals(true),
            ))
            .get();
    final filtered = type == null
        ? rows
        : rows.where((row) => row.type == type).toList(growable: false);
    return FfmAssistantReferenceResolver.resolve(
      name,
      filtered,
      (row) => row.name,
    );
  }

  Future<FfmAssistantReferenceResolution<Merchant>> merchant(
    String? name,
  ) async {
    final rows =
        await (_database.select(_database.merchants)..where(
              (row) =>
                  row.householdId.equals(_householdId) &
                  row.isActive.equals(true),
            ))
            .get();
    return FfmAssistantReferenceResolver.resolve(name, rows, (row) => row.name);
  }

  Future<FfmAssistantReferenceResolution<Tag>> tag(String? name) async {
    final rows =
        await (_database.select(_database.tags)..where(
              (row) =>
                  row.householdId.equals(_householdId) &
                  row.isArchived.equals(false),
            ))
            .get();
    return FfmAssistantReferenceResolver.resolve(name, rows, (row) => row.name);
  }

  Future<FfmAssistantReferenceResolution<Goal>> goal(String? name) async {
    final rows =
        await (_database.select(_database.goals)..where(
              (row) =>
                  row.householdId.equals(_householdId) &
                  row.isActive.equals(true),
            ))
            .get();
    return FfmAssistantReferenceResolver.resolve(name, rows, (row) => row.name);
  }

  /// Accepts either a stable activity ID or an exact title reference.
  Future<FfmAssistantReferenceResolution<ActivitySession>> activity(
    String? reference,
  ) async {
    final rows =
        await (_database.select(_database.activitySessions)..where(
              (row) =>
                  row.householdId.equals(_householdId) &
                  row.isArchived.equals(false),
            ))
            .get();
    final normalized = reference?.trim().toLowerCase();
    if (normalized != null && normalized.isNotEmpty) {
      final idMatches = rows.where((row) => row.id == reference).toList();
      if (idMatches.length == 1) {
        return FfmAssistantReferenceResolution.resolved(idMatches.single);
      }
    }
    return FfmAssistantReferenceResolver.resolve(
      reference,
      rows,
      (row) => row.title,
    );
  }
}
