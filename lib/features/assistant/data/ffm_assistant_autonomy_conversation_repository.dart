import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';

class FfmAssistantAutonomyConversationRepository {
  FfmAssistantAutonomyConversationRepository(
    this._database, {
    DateTime Function()? clock,
    Uuid? uuid,
  })  : _clock = clock ?? DateTime.now,
        _uuid = uuid ?? const Uuid();

  final AppDatabase _database;
  final DateTime Function() _clock;
  final Uuid _uuid;

  Future<AutonomyConversation> createConversation({
    required String householdId,
    required String jobId,
    required String role,
    required String content,
    String? reasoning,
  }) async {
    final now = _clock();
    final id = _uuid.v4();
    final conversation = AutonomyConversation(
      id: id,
      householdId: householdId,
      jobId: jobId,
      role: role,
      content: content,
      reasoning: reasoning,
      createdAt: now,
    );
    await _database
        .into(_database.autonomyConversations)
        .insert(conversation);
    return conversation;
  }

  Future<AutonomyConversation?> getConversation(String id) async {
    final row = await (_database.select(_database.autonomyConversations)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row;
  }

  Future<List<AutonomyConversation>> getConversationsByJob(String jobId) async {
    final rows = await (_database.select(_database.autonomyConversations)
          ..where((t) => t.jobId.equals(jobId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
    return rows;
  }

  Future<List<AutonomyConversation>> getConversationsByHousehold(
    String householdId,
  ) async {
    final rows = await (_database.select(_database.autonomyConversations)
          ..where((t) => t.householdId.equals(householdId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
    return rows;
  }

  Future<void> deleteConversation(String id) async {
    await (_database.delete(_database.autonomyConversations)
          ..where((t) => t.id.equals(id)))
        .go();
  }

  Future<void> deleteConversationsByJob(String jobId) async {
    await (_database.delete(_database.autonomyConversations)
          ..where((t) => t.jobId.equals(jobId)))
        .go();
  }

  Future<void> deleteConversationsByHousehold(String householdId) async {
    await (_database.delete(_database.autonomyConversations)
          ..where((t) => t.householdId.equals(householdId)))
        .go();
  }
}
