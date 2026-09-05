import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/advisor/domain/entities/cash_flow_profile_models.dart';
import 'package:ffm_manager/features/advisor/domain/usecases/financial_health_calculator.dart';
import 'package:ffm_manager/features/advisor/domain/usecases/flexible_cash_flow_calculator.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_proposal_json_service.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_draft_validator.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';

void main() {
  group('Module 1: Siklus Kas & AgroTrack Draft Feature', () {
    test('ProposalJsonService mem-parsing proposal JSON siklus kas dengan benar', () {
      final json = jsonEncode({
        'formatVersion': 'ffm-assistant-proposal-v1',
        'proposal': {
          'type': 'cash_flow_profile',
          'title': 'Siklus Padi Ciherang 2026',
          'commodity': 'Padi Ciherang',
          'initialCapital': 10000000,
          'estimatedInflow': 35000000,
          'dailyLivingBudget': 75000,
          'dailyOperationalBudget': 50000,
          'daysRemaining': 90,
          'cycleProfileType': 'agriculture',
          'note': 'Musim tanam rendeng',
        },
      });

      final result = FfmAssistantProposalJsonService.parse(
        json,
        createdAt: DateTime(2026, 9, 1),
      );

      expect(result.draft, isNotNull);
      final draft = result.draft!;
      expect(draft.kind, FfmAssistantDraftKind.cashFlowProfile);
      expect(draft.title, 'Siklus Padi Ciherang 2026');
      expect(draft.commodityOrBusinessType, 'Padi Ciherang');
      expect(draft.initialCapital, 10000000);
      expect(draft.estimatedInflow, 35000000);
      expect(draft.dailyLivingBudget, 75000);
      expect(draft.dailyOperationalBudget, 50000);
      expect(draft.cycleProfileType, 'agriculture');
    });

    test('FfmAssistantDraftValidator memvalidasi draft cashFlowProfile', () {
      // Valid draft
      final validDraft = FfmAssistantDraft(
        kind: FfmAssistantDraftKind.cashFlowProfile,
        createdAt: DateTime(2026, 9, 1),
        title: 'Siklus Jagung Hibrida',
        commodityOrBusinessType: 'Jagung',
        initialCapital: 5000000,
        estimatedInflow: 18000000,
        dailyLivingBudget: 50000,
        dailyOperationalBudget: 30000,
      );

      final issues = FfmAssistantDraftValidator.validate(validDraft);
      expect(issues.where((i) => i.blocksContinuation), isEmpty);

      // Draft tanpa judul atau komoditas
      final invalidDraft = FfmAssistantDraft(
        kind: FfmAssistantDraftKind.cashFlowProfile,
        createdAt: DateTime(2026, 9, 1),
        title: '',
        commodityOrBusinessType: '',
      );

      final invalidIssues = FfmAssistantDraftValidator.validate(invalidDraft);
      expect(invalidIssues.any((i) => i.code == 'cycle_name_required'), isTrue);
    });
  });

  group('Module 2: Conversational Multi-Turn Draft Revision System', () {
    late dynamic database;
    late FfmAssistantInterpreter interpreter;

    setUp(() async {
      database = createInMemoryDatabaseForTests();
      interpreter = FfmAssistantInterpreter(database);

      // Tambahkan rekening aktif di database
      await database.into(database.accounts).insert(
            AccountsCompanion.insert(
              id: 'bca',
              householdId: AppContext.householdId,
              name: 'BCA',
              type: 'bank',
              createdAt: DateTime(2026, 8, 1),
            ),
          );
      await database.into(database.accounts).insert(
            AccountsCompanion.insert(
              id: 'tunai',
              householdId: AppContext.householdId,
              name: 'Tunai',
              type: 'cash',
              createdAt: DateTime(2026, 8, 1),
            ),
          );

      // Tambahkan kategori aktif di database
      await database.into(database.categories).insert(
            CategoriesCompanion.insert(
              id: 'makanan',
              householdId: AppContext.householdId,
              name: 'Makanan',
              type: 'expense',
              createdAt: DateTime(2026, 8, 1),
            ),
          );
      await database.into(database.categories).insert(
            CategoriesCompanion.insert(
              id: 'transportasi',
              householdId: AppContext.householdId,
              name: 'Transportasi',
              type: 'expense',
              createdAt: DateTime(2026, 8, 1),
            ),
          );
    });

    tearDown(() async => database.close());

    test('Mengoreksi nominal draft saat user berkata "bukan 50rb tapi 75rb"', () async {
      final activeDraft = FfmAssistantDraft(
        kind: FfmAssistantDraftKind.expense,
        createdAt: DateTime(2026, 9, 1),
        title: 'Makan Siang',
        amount: 50000,
        fromAccountName: 'BCA',
        categoryName: 'Makanan',
      );

      final result = await interpreter.interpret(
        'bukan 50rb tapi 75rb',
        activeDraft: activeDraft,
      );

      expect(result.draft, isNotNull);
      expect(result.draft!.amount, 75000);
      expect(result.response, contains('75.000'));
      expect(result.response, contains('disesuaikan'));
    });

    test('Mengoreksi rekening draft dengan grounding database', () async {
      final activeDraft = FfmAssistantDraft(
        kind: FfmAssistantDraftKind.expense,
        createdAt: DateTime(2026, 9, 1),
        title: 'Beli Bensin',
        amount: 30000,
        fromAccountName: 'BCA',
        categoryName: 'Transportasi',
      );

      // Rekening Tunai ada di DB -> berhasil diubah
      final resultValid = await interpreter.interpret(
        'pakai rekening Tunai',
        activeDraft: activeDraft,
      );

      expect(resultValid.draft, isNotNull);
      expect(resultValid.draft!.fromAccountName, 'Tunai');
      expect(resultValid.response, contains('Tunai'));

      // Rekening Mandiri tidak ada di DB -> memberikan peringatan & daftar rekening aktif
      final resultUngrounded = await interpreter.interpret(
        'ganti rekening ke Mandiri',
        activeDraft: activeDraft,
      );

      expect(resultUngrounded.response, contains('Mandiri'));
      expect(resultUngrounded.response, contains('belum terdaftar di Data Utama'));
    });

    test('Mengoreksi kategori draft dengan grounding database', () async {
      final activeDraft = FfmAssistantDraft(
        kind: FfmAssistantDraftKind.expense,
        createdAt: DateTime(2026, 9, 1),
        title: 'Pengeluaran Sore',
        amount: 25000,
        fromAccountName: 'BCA',
        categoryName: 'Makanan',
      );

      // Kategori Transportasi ada di DB
      final resultValid = await interpreter.interpret(
        'ganti kategori ke Transportasi',
        activeDraft: activeDraft,
      );

      expect(resultValid.draft, isNotNull);
      expect(resultValid.draft!.categoryName, 'Transportasi');

      // Kategori Hiburan tidak ada di DB
      final resultUngrounded = await interpreter.interpret(
        'kategori Hiburan',
        activeDraft: activeDraft,
      );

      expect(resultUngrounded.response, contains('Hiburan'));
      expect(resultUngrounded.response, contains('belum terdaftar di Data Utama'));
    });

    test('Membatalkan draft aktif saat user berkata "batalkan draft"', () async {
      final activeDraft = FfmAssistantDraft(
        kind: FfmAssistantDraftKind.expense,
        createdAt: DateTime(2026, 9, 1),
        title: 'Belanja',
        amount: 100000,
      );

      final result = await interpreter.interpret(
        'batalkan draft',
        activeDraft: activeDraft,
      );

      expect(result.type, FfmAssistantIntentType.cancel);
      expect(result.response, contains('dibatalkan'));
      expect(result.response, contains('Belum ada data yang disimpan'));
    });

    test('Mengoreksi field siklus kas AgroTrack secara multi-turn', () async {
      final activeDraft = FfmAssistantDraft(
        kind: FfmAssistantDraftKind.cashFlowProfile,
        createdAt: DateTime(2026, 9, 1),
        title: 'Siklus Padi',
        commodityOrBusinessType: 'Padi',
        initialCapital: 5000000,
        estimatedInflow: 20000000,
        dailyLivingBudget: 50000,
        dailyOperationalBudget: 40000,
      );

      final result = await interpreter.interpret(
        'modal awal jadi 8 juta dan komoditas Jagung',
        activeDraft: activeDraft,
      );

      expect(result.draft, isNotNull);
      expect(result.draft!.initialCapital, 8000000);
      expect(result.draft!.commodityOrBusinessType, 'Jagung');
    });

    test('Membuat draft siklus kas offline dari kalimat bahasa alami', () async {
      final result = await interpreter.interpret(
        'buat siklus tani komoditas Padi Ciherang modal 10jt estimasi panen 35jt',
      );

      expect(result.draft, isNotNull);
      expect(result.draft!.kind, FfmAssistantDraftKind.cashFlowProfile);
      expect(result.draft!.commodityOrBusinessType, contains('Padi'));
      expect(result.draft!.initialCapital, 10000000);
      expect(result.draft!.estimatedInflow, 35000000);
    });
  });

  group('Module 3: Deterministic Financial Health & AgroTrack Runway', () {
    test('Kalkulator 4 pilar kesehatan keuangan menghitung skor deterministik', () {
      const calculator = FinancialHealthCalculator();
      final score = calculator.calculate(
        const FinancialHealthInput(
          totalIncome: 10000000,
          totalExpenses: 6000000,
          totalMonthlyInstallments: 1500000,
          emergencyFundAmount: 20000000,
          averageMonthlyExpenses: 6000000,
          totalAssets: 50000000,
          totalLiabilities: 10000000,
        ),
      );

      expect(score.totalScore, greaterThan(60));
      expect(score.savingsRate, closeTo(0.4, 0.01)); // (10jt - 6jt) / 10jt = 40%
      expect(score.debtToIncomeRatio, closeTo(0.15, 0.01)); // 1.5jt / 10jt = 15%
      expect(score.emergencyMonths, closeTo(3.33, 0.05)); // 20jt / 6jt = 3.33 bulan
      expect(score.netWorth, 40000000); // 50jt - 10jt = 40jt
    });

    test('Kalkulator AgroTrack Runway menghitung ketahanan kas dan safe daily spend', () {
      const calculator = FlexibleCashFlowCalculator();
      final result = calculator.calculateRunway(
        effectiveLiquidCash: 12000000,
        dailyLivingBudget: 50000,
        dailyOperationalBudget: 50000,
        daysRemainingToHarvest: 90,
      );

      // Burn rate: 50rb + 50rb = 100rb/hari
      // Runway: 12jt / 100rb = 120 hari (> 90 hari sisa panen -> Safe)
      expect(result.runwayDays, 120);
      expect(result.healthStatus, CycleHealthStatus.safe);
      expect(result.deficitDays, 0);
      expect(result.safeToSpendDaily, greaterThan(0));
    });
  });
}
