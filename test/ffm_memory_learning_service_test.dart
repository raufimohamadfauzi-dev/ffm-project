import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_memory_repository.dart';
import 'package:ffm_manager/features/assistant/data/ffm_memory_learning_service.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_memory_candidate.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_memory_type.dart';

import 'package:drift/drift.dart';

void main() {
  late AppDatabase database;
  late FfmAssistantMemoryRepository memoryRepository;
  late FfmMemoryLearningService service;

  setUp(() {
    database = createInMemoryDatabaseForTests();
    memoryRepository = FfmAssistantMemoryRepository(database);
    service = FfmMemoryLearningService(memoryRepository: memoryRepository);
  });

  tearDown(() async {
    await database.close();
  });

  group('extractCandidates', () {
    test('extracts name pattern', () async {
      final candidates = await service.extractCandidates(
        userQuery: 'panggil saya Budi',
        assistantResponse: null,
        usedMemories: [],
      );

      expect(candidates, isNotEmpty);
      expect(candidates.first.key, 'preferred_name');
      expect(candidates.first.type, FfmMemoryType.identity);
    });

    test('extracts payday pattern', () async {
      final candidates = await service.extractCandidates(
        userQuery: 'gajian tiap tanggal 25',
        assistantResponse: null,
        usedMemories: [],
      );

      expect(candidates, isNotEmpty);
      expect(candidates.first.key, 'payday');
    });

    test('extracts food budget pattern', () async {
      final candidates = await service.extractCandidates(
        userQuery: 'budget makan perbulan 2 juta',
        assistantResponse: null,
        usedMemories: [],
      );

      expect(candidates, isNotEmpty);
      expect(candidates.first.key, 'budget_food');
    });

    test('extracts savings target pattern', () async {
      final candidates = await service.extractCandidates(
        userQuery: 'target nabung 10 juta',
        assistantResponse: null,
        usedMemories: [],
      );

      expect(candidates, isNotEmpty);
      expect(candidates.first.key, 'savings_target');
    });

    test('extracts correction pattern', () async {
      final candidates = await service.extractCandidates(
        userQuery: 'bukan kategori makan, harusnya transportasi',
        assistantResponse: 'Kategori sudah diubah.',
        usedMemories: [],
      );

      expect(candidates, isNotEmpty);
      final correction =
          candidates.where((c) => c.type == FfmMemoryType.correction);
      expect(correction, isNotEmpty);
    });

    test('extracts time-based habits', () async {
      final candidates = await service.extractCandidates(
        userQuery: 'setiap pagi saya cek pengeluaran',
        assistantResponse: null,
        usedMemories: [],
      );

      expect(candidates, isNotEmpty);
      final habits =
          candidates.where((c) => c.type == FfmMemoryType.habit);
      expect(habits, isNotEmpty);
    });

    test('returns empty for generic queries', () async {
      final candidates = await service.extractCandidates(
        userQuery: 'halo',
        assistantResponse: null,
        usedMemories: [],
      );

      expect(candidates, isEmpty);
    });

    test('extracts usage-based patterns when many memories used', () async {
      final usedMemories = List.generate(
        5,
        (i) => FfmMemoryCandidate(
          id: 'mem-$i',
          type: FfmMemoryType.explicitFact,
          key: 'key-$i',
          value: 'value-$i',
          evidence: FfmMemoryEvidence(
            source: FfmMemorySource.userExplicit,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            confidence: 0.8,
            approved: true,
          ),
        ),
      );

      final candidates = await service.extractCandidates(
        userQuery: 'test query',
        assistantResponse: null,
        usedMemories: usedMemories,
      );

      final usageBased =
          candidates.where((c) => c.sourceId == 'usage-analysis');
      expect(usageBased, isNotEmpty);
    });
  });

  group('validateCandidates', () {
    test('removes duplicates against existing memories', () async {
      final existing = [
        FfmMemoryCandidate(
          id: 'existing-1',
          type: FfmMemoryType.identity,
          key: 'preferred_name',
          value: 'Budi',
          evidence: FfmMemoryEvidence(
            source: FfmMemorySource.userExplicit,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            confidence: 0.8,
            approved: true,
          ),
        ),
      ];

      final candidates = [
        const FfmMemoryPromotionCandidate(
          type: FfmMemoryType.identity,
          key: 'preferred_name',
          value: 'Budi',
          confidence: 0.7,
        ),
      ];

      final validated = service.validateCandidates(candidates, existing);
      expect(validated, isEmpty);
    });

    test('removes contradicting memories', () async {
      final existing = [
        FfmMemoryCandidate(
          id: 'existing-1',
          type: FfmMemoryType.identity,
          key: 'preferred_name',
          value: 'Budi',
          evidence: FfmMemoryEvidence(
            source: FfmMemorySource.userExplicit,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            confidence: 0.9,
            approved: true,
          ),
        ),
      ];

      final candidates = [
        const FfmMemoryPromotionCandidate(
          type: FfmMemoryType.identity,
          key: 'preferred_name',
          value: 'Andi',
          confidence: 0.7,
        ),
      ];

      final validated = service.validateCandidates(candidates, existing);
      expect(validated, isEmpty);
    });

    test('keeps valid candidates', () async {
      final candidates = [
        const FfmMemoryPromotionCandidate(
          type: FfmMemoryType.identity,
          key: 'preferred_name',
          value: 'Budi',
          confidence: 0.7,
        ),
      ];

      final validated = service.validateCandidates(candidates, []);
      expect(validated.length, 1);
    });

    test('rejects empty key', () {
      final candidates = [
        const FfmMemoryPromotionCandidate(
          type: FfmMemoryType.identity,
          key: '',
          value: 'Budi',
          confidence: 0.7,
        ),
      ];

      final validated = service.validateCandidates(candidates, []);
      expect(validated, isEmpty);
    });

    test('rejects empty value', () {
      final candidates = [
        const FfmMemoryPromotionCandidate(
          type: FfmMemoryType.identity,
          key: 'name',
          value: '',
          confidence: 0.7,
        ),
      ];

      final validated = service.validateCandidates(candidates, []);
      expect(validated, isEmpty);
    });
  });

  group('promoteCandidates', () {
    test('promotes non-approval candidates to repository', () async {
      final candidates = [
        const FfmMemoryPromotionCandidate(
          type: FfmMemoryType.behavioralPattern,
          key: 'frequent_topic_explicitFact',
          value: 'explicitFact',
          confidence: 0.6,
          requiresApproval: false,
        ),
      ];

      final promoted = await service.promoteCandidates(
        candidates: candidates,
        requireApproval: false,
      );

      expect(promoted.length, 1);
      expect(promoted.first.type, FfmMemoryType.behavioralPattern);

      final saved = await memoryRepository.readActive();
      expect(saved, isNotEmpty);
    });
  });

  group('trackMemoryUsage', () {
    test('increments useCount and importance', () async {
      final record = await memoryRepository.save(
        kind: 'identity',
        triggerText: 'name',
        valueText: 'Budi',
        metadata: {'useCount': 0, 'importance': 0.5},
      );

      await service.trackMemoryUsage(
        [record.id],
        repository: memoryRepository,
      );

      final updated = await memoryRepository.readActive();
      final match = updated.where((m) => m.id == record.id).first;
      expect(match.metadata['useCount'], 1);
      expect(
        (match.metadata['importance'] as num).toDouble(),
        greaterThan(0.5),
      );
    });
  });

  group('applyMemoryDecay', () {
    test('archives old low-importance unused memories', () async {
      final oldDate = DateTime.now().subtract(const Duration(days: 365));
      await database.into(database.assistantMemories).insert(
        AssistantMemoriesCompanion(
          id: const Value('old-memory'),
          householdId: const Value('local-household'),
          kind: const Value('preference'),
          triggerText: const Value('old_key'),
          valueText: const Value('old_value'),
          metadataJson: const Value('{"useCount":0,"importance":0.15}'),
          createdAt: Value(oldDate),
        ),
      );

      await service.applyMemoryDecay(
        repository: memoryRepository,
        maxAge: const Duration(days: 30),
      );

      final active = await memoryRepository.readActive();
      expect(active.where((m) => m.id == 'old-memory'), isEmpty);
    });

    test('preserves high-importance memories', () async {
      final oldDate = DateTime.now().subtract(const Duration(days: 365));
      await database.into(database.assistantMemories).insert(
        AssistantMemoriesCompanion(
          id: const Value('important-memory'),
          householdId: const Value('local-household'),
          kind: const Value('identity'),
          triggerText: const Value('important_key'),
          valueText: const Value('important_value'),
          metadataJson: const Value('{"useCount":0,"importance":0.9}'),
          createdAt: Value(oldDate),
        ),
      );

      await service.applyMemoryDecay(
        repository: memoryRepository,
        maxAge: const Duration(days: 30),
      );

      final active = await memoryRepository.readActive();
      expect(active.where((m) => m.id == 'important-memory'), isNotEmpty);
    });

    test('preserves frequently used memories', () async {
      final oldDate = DateTime.now().subtract(const Duration(days: 365));
      await database.into(database.assistantMemories).insert(
        AssistantMemoriesCompanion(
          id: const Value('used-memory'),
          householdId: const Value('local-household'),
          kind: const Value('preference'),
          triggerText: const Value('used_key'),
          valueText: const Value('used_value'),
          metadataJson: const Value('{"useCount":5,"importance":0.3}'),
          createdAt: Value(oldDate),
        ),
      );

      await service.applyMemoryDecay(
        repository: memoryRepository,
        maxAge: const Duration(days: 30),
      );

      final active = await memoryRepository.readActive();
      expect(active.where((m) => m.id == 'used-memory'), isNotEmpty);
    });
  });
}
