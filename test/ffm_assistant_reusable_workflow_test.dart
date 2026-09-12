import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_learning_candidate_service.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_memory_repository.dart';

void main() {
  late AppDatabase database;
  late FfmAssistantMemoryRepository memoryRepo;
  late FfmAssistantLearningCandidateService candidateService;

  setUp(() {
    database = createInMemoryDatabaseForTests();
    memoryRepo = FfmAssistantMemoryRepository(database);
    candidateService = FfmAssistantLearningCandidateService(memoryRepo);
  });

  tearDown(() async {
    await database.close();
  });

  group('F6 Reusable Approved Workflows', () {
    test('Proposed workflow starts as pending and is not active for replay',
        () async {
      final candidate = await candidateService.proposeWorkflow(
        trigger: 'analisis pengeluaran kopi',
        steps: [
          {
            'capabilityId': 'read.transactions',
            'parameters': {'query': 'kopi'},
          },
        ],
      );

      expect(candidate.isPending, isTrue);
      expect(candidate.isApproved, isFalse);

      final pendingList = await candidateService.readPending();
      expect(pendingList.length, 1);
      expect(pendingList.first.id, candidate.id);

      final approvedList = await candidateService.readApproved();
      expect(approvedList, isEmpty);

      // Pending workflow cannot be resolved to an action plan
      final plan = candidateService.resolveApprovedPlan(candidate);
      expect(plan, isNull);
    });

    test('Approved workflow resolves into validated action plan', () async {
      final candidate = await candidateService.proposeWorkflow(
        trigger: 'rekap bulanan belanja',
        steps: [
          {
            'capabilityId': 'read.summary',
            'parameters': {'period': 'month'},
          },
        ],
      );

      final approved = await candidateService.approve(candidate);
      expect(approved.isApproved, isTrue);

      final approvedList = await candidateService.readApproved();
      expect(approvedList.length, 1);

      final match =
          await candidateService.findApprovedWorkflow('Tolong rekap bulanan belanja dong');
      expect(match, isNotNull);
      expect(match!.id, approved.id);

      final plan = candidateService.resolveApprovedPlan(match);
      expect(plan, isNotNull);
      expect(plan!.steps.length, 1);
      expect(plan.steps.first.capabilityId, 'read.summary');
      expect(plan.requiresConfirmation, isFalse); // Read-only capability
    });

    test('Workflow with mutating capability strictly requires confirmation',
        () async {
      final candidate = await candidateService.proposeWorkflow(
        trigger: 'simpan rutin donasi',
        steps: [
          {
            'capabilityId': 'mutate.save_draft',
            'parameters': {'amount': 50000},
          },
        ],
      );

      final approved = await candidateService.approve(candidate);
      final plan = candidateService.resolveApprovedPlan(approved);

      expect(plan, isNotNull);
      expect(plan!.requiresConfirmation, isTrue); // Mutating requires confirmation
    });

    test('Workflow with unknown capability is rejected safely', () async {
      final candidate = await candidateService.proposeWorkflow(
        trigger: 'perintah berbahaya',
        steps: [
          {
            'capabilityId': 'system.wipe_phone_storage',
            'parameters': {},
          },
        ],
      );

      final approved = await candidateService.approve(candidate);
      // Unknown capability must return null plan (rejected by validator)
      final plan = candidateService.resolveApprovedPlan(approved);
      expect(plan, isNull);
    });

    test('Rejected candidate is archived and no longer found', () async {
      final candidate = await candidateService.proposeWorkflow(
        trigger: 'workflow sementara',
        steps: [
          {
            'capabilityId': 'read.transactions',
            'parameters': {},
          },
        ],
      );

      await candidateService.reject(candidate);

      final pending = await candidateService.readPending();
      expect(pending, isEmpty);

      final match =
          await candidateService.findApprovedWorkflow('workflow sementara');
      expect(match, isNull);
    });
  });
}
