import '../../data/repositories/activity_repository.dart';
import '../entities/activity_entity.dart';

class GetActivitySessions {
  const GetActivitySessions(this.repository);
  final ActivityRepository repository;

  Future<List<ActivitySessionEntity>> call(String householdId) =>
      repository.getSessions(householdId);
}

class GetActivityEntries {
  const GetActivityEntries(this.repository);
  final ActivityRepository repository;

  Future<List<ActivityJournalEntryEntity>> call(String householdId) =>
      repository.getEntries(householdId);
}

class GetActivityCheckpoints {
  const GetActivityCheckpoints(this.repository);
  final ActivityRepository repository;

  Future<List<ActivityCheckpointEntity>> call(String sessionId) =>
      repository.getCheckpoints(sessionId);
}

class GetActiveActivitySession {
  const GetActiveActivitySession(this.repository);
  final ActivityRepository repository;

  Future<ActivitySessionEntity?> call(String householdId) =>
      repository.getActiveSession(householdId);
}

class SaveActivitySession {
  const SaveActivitySession(this.repository);
  final ActivityRepository repository;

  Future<void> call(ActivitySessionEntity entity) =>
      repository.saveSession(entity);
}

class SaveActivityCheckpoint {
  const SaveActivityCheckpoint(this.repository);
  final ActivityRepository repository;

  Future<void> call(ActivityCheckpointEntity entity) =>
      repository.saveCheckpoint(entity);
}

class SaveActivityEntry {
  const SaveActivityEntry(this.repository);
  final ActivityRepository repository;

  Future<void> call(ActivityJournalEntryEntity entity) =>
      repository.saveEntry(entity);
}

class ArchiveActivitySession {
  const ArchiveActivitySession(this.repository);
  final ActivityRepository repository;

  Future<void> call(String householdId, String id) =>
      repository.archiveSession(householdId, id);
}

class ArchiveActivityEntry {
  const ArchiveActivityEntry(this.repository);
  final ActivityRepository repository;

  Future<void> call(String householdId, String id) =>
      repository.archiveEntry(householdId, id);
}
