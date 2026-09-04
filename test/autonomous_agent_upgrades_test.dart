import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_draft_feedback_service.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_memory_repository.dart';
import 'package:ffm_manager/features/assistant/data/ffm_personal_memory_service.dart';
import 'package:ffm_manager/features/assistant/domain/detectors/micro_expense_leak_detector.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_plan.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_planner.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_execution_limits.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_insight.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Tahap 2 - Modul 3A: Self-Learning dari Koreksi Pengguna', () {
    late AppDatabase database;
    late FfmAssistantMemoryRepository memoryRepo;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      database = AppDatabase(NativeDatabase.memory());
      memoryRepo = FfmAssistantMemoryRepository(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('ekstraksi rule koreksi merchant ke kategori', () async {
      final feedbackService = FfmAssistantDraftFeedbackService();
      final memoryService =
          FfmPersonalMemoryService(memoryRepo, feedbackService);

      final originalDraft = FfmAssistantDraft(
        kind: FfmAssistantDraftKind.expense,
        amount: 25000,
        merchantName: 'Kopi Kenangan',
        categoryName: 'Lain-lain',
        slmFieldValues: {'category': 'Lain-lain'},
        createdAt: DateTime(2026, 9, 4),
      );

      final editedDraft = originalDraft.copyWith(
        categoryName: 'Minuman',
      );

      // User mengoreksi kategori menjadi Minuman
      feedbackService.recordDraftEdit(
        originalDraft: originalDraft,
        editedDraft: editedDraft,
        timestamp: DateTime(2026, 9, 4),
      );

      // Rule harus dipelajari oleh feedbackService
      expect(feedbackService.learnedRules.length, 1);
      final rule = feedbackService.learnedRules.first;
      expect(rule.key, 'merchant_category_kopi kenangan');
      expect(rule.value, 'Minuman');
      expect(rule.label, contains('Kopi Kenangan'));

      // Rule harus tersimpan ke memory repository
      final allMemories = await memoryService.readAll();
      expect(
        allMemories.any(
          (m) =>
              m.key == 'merchant_category_kopi kenangan' &&
              m.value == 'Minuman',
        ),
        isTrue,
      );
    });

    test('ekstraksi rule koreksi judul transaksi tanpa merchant', () async {
      final feedbackService = FfmAssistantDraftFeedbackService();
      final memoryService =
          FfmPersonalMemoryService(memoryRepo, feedbackService);

      final originalDraft = FfmAssistantDraft(
        kind: FfmAssistantDraftKind.expense,
        amount: 100000,
        title: 'Token Listrik PLN',
        categoryName: 'Lain-lain',
        slmFieldValues: {'category': 'Lain-lain'},
        createdAt: DateTime(2026, 9, 4),
      );

      final editedDraft = originalDraft.copyWith(
        categoryName: 'Tagihan Listrik',
      );

      feedbackService.recordDraftEdit(
        originalDraft: originalDraft,
        editedDraft: editedDraft,
        timestamp: DateTime(2026, 9, 4),
      );

      expect(feedbackService.learnedRules.length, 1);
      final rule = feedbackService.learnedRules.first;
      expect(rule.key, 'item_category_token listrik pln');
      expect(rule.value, 'Tagihan Listrik');

      final allMemories = await memoryService.readAll();
      expect(
        allMemories.any(
          (m) =>
              m.key == 'item_category_token listrik pln' &&
              m.value == 'Tagihan Listrik',
        ),
        isTrue,
      );
    });

    test('ekstraksi rule preferensi akun pembayaran saat dikoreksi', () async {
      final feedbackService = FfmAssistantDraftFeedbackService();
      final memoryService =
          FfmPersonalMemoryService(memoryRepo, feedbackService);

      final originalDraft = FfmAssistantDraft(
        kind: FfmAssistantDraftKind.expense,
        amount: 50000,
        merchantName: 'Indomaret',
        fromAccountName: 'Dompet Tunai',
        slmFieldValues: {'fromAccount': 'Dompet Tunai'},
        createdAt: DateTime(2026, 9, 4),
      );

      final editedDraft = originalDraft.copyWith(
        fromAccountName: 'BCA',
      );

      feedbackService.recordDraftEdit(
        originalDraft: originalDraft,
        editedDraft: editedDraft,
        timestamp: DateTime(2026, 9, 4),
      );

      expect(feedbackService.learnedRules.length, 1);
      final rule = feedbackService.learnedRules.first;
      expect(rule.key, 'preferred_account');
      expect(rule.value, 'BCA');

      final allMemories = await memoryService.readAll();
      expect(
        allMemories.any(
          (m) =>
              m.key == 'preferred_account' &&
              m.value == 'BCA',
        ),
        isTrue,
      );
    });
  });

  group('Tahap 2 - Modul 3B: Detektor Kebocoran Halus (MicroExpenseLeakDetector)', () {
    late AppDatabase database;
    late MicroExpenseLeakDetector detector;
    const householdId = 'test-household-leak';

    setUp(() {
      database = AppDatabase(NativeDatabase.memory());
      detector = MicroExpenseLeakDetector(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('mendeteksi kebocoran halus biaya admin & pengeluaran kecil berulang', () async {
      final now = DateTime(2026, 9, 4, 12);

      // Insert 4 pengeluaran admin fee kecil (< Rp 30.000)
      for (var i = 1; i <= 4; i++) {
        await database.into(database.transactions).insert(
          TransactionsCompanion(
            id: Value('fee_$i'),
            householdId: const Value(householdId),
            type: const Value('expense'),
            amount: const Value(2500),
            note: const Value('Biaya admin transfer BI-Fast'),
            date: Value(now.subtract(Duration(days: i))),
            recordedAt: Value(now.subtract(Duration(days: i))),
            createdAt: Value(now.subtract(Duration(days: i))),
          ),
        );
      }

      // Insert 2 pengeluaran jajan kecil
      for (var i = 5; i <= 6; i++) {
        await database.into(database.transactions).insert(
          TransactionsCompanion(
            id: Value('jajan_$i'),
            householdId: const Value(householdId),
            type: const Value('expense'),
            amount: const Value(20000),
            note: const Value('Kopi susu senja'),
            date: Value(now.subtract(Duration(days: i))),
            recordedAt: Value(now.subtract(Duration(days: i))),
            createdAt: Value(now.subtract(Duration(days: i))),
          ),
        );
      }

      // Insert 1 pengeluaran besar (bukan micro-expense)
      await database.into(database.transactions).insert(
        TransactionsCompanion(
          id: const Value('big_expense'),
          householdId: const Value(householdId),
          type: const Value('expense'),
          amount: const Value(200000),
          note: const Value('Belanja Bulanan Supermarket'),
          date: Value(now.subtract(const Duration(days: 2))),
          recordedAt: Value(now.subtract(const Duration(days: 2))),
          createdAt: Value(now.subtract(const Duration(days: 2))),
        ),
      );

      final insight = await detector.detect(
        householdId: householdId,
        now: now,
      );

      expect(insight, isNotNull);
      expect(insight!.type, FfmAssistantInsightType.microExpenseLeak);
      expect(insight.title, contains('Kebocoran Halus'));
      expect(insight.summary, contains('transaksi kecil'));
      expect(insight.summary, contains('biaya admin'));
      expect(insight.evidence['microCount'], 6);
      expect(insight.evidence['totalMicroExpense'], 50000); // 4 * 2500 + 2 * 20000
      expect(insight.evidence['totalFeeExpense'], 10000); // 4 * 2500
      expect(insight.evidence['monthlyProjected'], isNotNull);
    });

    test('mengabaikan income dan transfer dari perhitungan kebocoran', () async {
      final now = DateTime(2026, 9, 4, 12);

      // Insert 5 transaksi bertipe income atau transfer dengan nominal kecil
      for (var i = 1; i <= 5; i++) {
        await database.into(database.transactions).insert(
          TransactionsCompanion(
            id: Value('inc_$i'),
            householdId: const Value(householdId),
            type: const Value('income'),
            amount: const Value(10000),
            date: Value(now.subtract(Duration(days: i))),
            recordedAt: Value(now.subtract(Duration(days: i))),
            createdAt: Value(now.subtract(Duration(days: i))),
          ),
        );
      }

      final insight = await detector.detect(
        householdId: householdId,
        now: now,
      );

      expect(insight, isNull);
    });
  });

  group('Tahap 2 - Modul 3C: Orkestrator Rencana Aksi Bertahap (Multi-Step Action Plan)', () {
    test('merancang composite plan dengan verifikasi berurutan per mutasi', () {
      const planner = FfmAssistantActionPlanner();

      final drafts = [
        FfmAssistantDraft(
          kind: FfmAssistantDraftKind.goal,
          title: 'Dana Darurat 10 Juta',
          amount: 2000000,
          createdAt: DateTime(2026, 9, 4),
        ),
        FfmAssistantDraft(
          kind: FfmAssistantDraftKind.budget,
          categoryName: 'Hiburan',
          amount: 300000,
          createdAt: DateTime(2026, 9, 4),
        ),
      ];

      final plan = planner.planCompositePlan(
        summary: 'Target Dana Darurat & Alokasi Pos Hiburan',
        drafts: drafts,
      );

      expect(plan, isNotNull);
      expect(plan!.isComposite, isTrue);
      expect(plan.requiresConfirmation, isTrue);
      expect(plan.workflowSafetyIssue, isNull);

      // Pastikan prerequisite reads digabung dan terdeduplikasi
      final readSteps =
          plan.steps.where((s) => s.capabilityId.startsWith('read.'));
      expect(
        readSteps.map((s) => s.capabilityId),
        containsAll(['read.goals', 'read.budget']),
      );

      // Pastikan step drafting, mutation, dan verification tersusun rapi
      final saveSteps =
          plan.steps.where((s) => s.capabilityId.startsWith('mutate.'));
      final verifySteps =
          plan.steps.where((s) => s.capabilityId.startsWith('verify.'));
      expect(saveSteps.length, 2);
      expect(verifySteps.length, 2);

      // Setiap mutasi wajib memiliki idempotency key unik
      final idempotencyKeys = saveSteps
          .map((s) => s.parameters['_idempotencyKey']?.toString())
          .toSet();
      expect(idempotencyKeys.length, 2);
    });

    test('memblokir jika rencana bertahap melebihi batas langkah (budget limit)', () {
      const planner = FfmAssistantActionPlanner();

      // Buat 4 draf (masing-masing 3 step = 12 steps, melebihi maxStepsPerPlan = 8)
      final excessiveDrafts = [
        FfmAssistantDraft(
          kind: FfmAssistantDraftKind.goal,
          title: 'Goal 1',
          createdAt: DateTime(2026, 9, 4),
        ),
        FfmAssistantDraft(
          kind: FfmAssistantDraftKind.budget,
          categoryName: 'Budget 1',
          createdAt: DateTime(2026, 9, 4),
        ),
        FfmAssistantDraft(
          kind: FfmAssistantDraftKind.reminder,
          title: 'Reminder 1',
          createdAt: DateTime(2026, 9, 4),
        ),
        FfmAssistantDraft(
          kind: FfmAssistantDraftKind.task,
          title: 'Task 1',
          createdAt: DateTime(2026, 9, 4),
        ),
      ];

      final plan = planner.planCompositePlan(
        summary: 'Rencana aksi terlalu besar',
        drafts: excessiveDrafts,
      );

      expect(plan, isNotNull);
      expect(plan!.status, FfmAssistantActionPlanStatus.blockedByBudget);
      expect(
        plan.blockedReason,
        FfmAssistantBudgetBlockReason.tooManySteps.name,
      );
      expect(
        plan.summary,
        FfmAssistantExecutionLimits.tooComplexMessage,
      );
    });
  });
}
