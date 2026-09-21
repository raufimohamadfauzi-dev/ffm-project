import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';

class FfmAssistantAutonomyJobRepository {
  FfmAssistantAutonomyJobRepository(
    this._database, {
    DateTime Function()? clock,
    Uuid? uuid,
  })  : _clock = clock ?? DateTime.now,
        _uuid = uuid ?? const Uuid();

  final AppDatabase _database;
  final DateTime Function() _clock;
  final Uuid _uuid;

  Future<AutonomyJob> createJob({
    required String householdId,
    required String type,
    Map<String, Object?>? triggerData,
  }) async {
    final now = _clock();
    final id = _uuid.v4();
    final job = AutonomyJob(
      id: id,
      householdId: householdId,
      type: type,
      status: 'pending',
      triggerData: triggerData != null ? jsonEncode(triggerData) : null,
      createdAt: now,
      updatedAt: now,
    );
    await _database.into(_database.autonomyJobs).insert(job);
    return job;
  }

  Future<AutonomyJob?> getJob(String id) async {
    final row = await (_database.select(_database.autonomyJobs)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row;
  }

  Future<List<AutonomyJob>> getJobsByHousehold(String householdId) async {
    final rows = await (_database.select(_database.autonomyJobs)
          ..where((t) => t.householdId.equals(householdId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
    return rows;
  }

  Future<List<AutonomyJob>> getJobsByStatus(
    String householdId,
    String status,
  ) async {
    final rows = await (_database.select(_database.autonomyJobs)
          ..where((t) =>
              t.householdId.equals(householdId) & t.status.equals(status))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
    return rows;
  }

  Future<List<AutonomyJob>> getJobsByType(
    String householdId,
    String type,
  ) async {
    final rows = await (_database.select(_database.autonomyJobs)
          ..where((t) =>
              t.householdId.equals(householdId) & t.type.equals(type))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
    return rows;
  }

  Future<void> updateJobStatus(
    String id,
    String status, {
    DateTime? startedAt,
    DateTime? completedAt,
    Map<String, Object?>? decisionData,
    Map<String, Object?>? resultData,
  }) async {
    final now = _clock();
    await (_database.update(_database.autonomyJobs)..where((t) => t.id.equals(id)))
        .write(AutonomyJobsCompanion(
      status: Value(status),
      startedAt: startedAt != null ? Value(startedAt) : const Value.absent(),
      completedAt:
          completedAt != null ? Value(completedAt) : const Value.absent(),
      decisionData: decisionData != null
          ? Value(jsonEncode(decisionData))
          : const Value.absent(),
      resultData: resultData != null
          ? Value(jsonEncode(resultData))
          : const Value.absent(),
      updatedAt: Value(now),
    ));
  }

  Future<void> deleteJob(String id) async {
    await (_database.delete(_database.autonomyJobs)..where((t) => t.id.equals(id)))
        .go();
  }

  Future<void> deleteJobsByHousehold(String householdId) async {
    await (_database.delete(_database.autonomyJobs)
          ..where((t) => t.householdId.equals(householdId)))
        .go();
  }
}
