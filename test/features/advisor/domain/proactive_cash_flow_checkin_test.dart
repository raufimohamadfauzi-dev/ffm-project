import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ffm_manager/features/advisor/data/cash_flow_profile_repository.dart';
import 'package:ffm_manager/features/advisor/domain/entities/cash_flow_profile_models.dart';
import 'package:ffm_manager/features/advisor/domain/services/proactive_cash_flow_checkin_service.dart';

void main() {
  group('ProactiveCashFlowCheckInService', () {
    late CashFlowProfileRepository repository;
    late ProactiveCashFlowCheckInService service;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      repository = CashFlowProfileRepository();
      service = ProactiveCashFlowCheckInService(repository);
    });

    test('returns null when no active profiles exist', () async {
      final prompt = await service.evaluateCheckIn('house_123');
      expect(prompt, isNull);
    });

    test('returns agriculture check-in prompt with 3 suggestions when agriculture profile is active', () async {
      final now = DateTime.now();
      final profile = CashFlowProfile(
        id: 'prof_agri_1',
        householdId: 'house_123',
        profileType: CashFlowProfileType.agriculture,
        name: 'Kebun Jagung Blok B',
        commodityOrBusinessType: 'Jagung Hibrida',
        startDate: now.subtract(const Duration(days: 30)),
        targetHarvestDate: now.add(const Duration(days: 45)),
        initialCapital: 5000000,
        estimatedInflow: 18000000,
        dailyLivingBudget: 75000,
        dailyOperationalBudget: 25000,
        isActive: true,
      );
      await repository.saveProfile(profile);

      final prompt = await service.evaluateCheckIn('house_123');
      expect(prompt, isNotNull);
      expect(prompt!.profile.id, equals('prof_agri_1'));
      expect(prompt.greetingMessage, contains('Kebun Jagung Blok B'));
      expect(prompt.greetingMessage, contains('Jagung Hibrida'));
      expect(prompt.greetingMessage, contains('Wawancara Status Tani & Kebun'));
      expect(prompt.suggestedQuestions.length, equals(3));
      expect(prompt.suggestedQuestions.any((q) => q.contains('panen')), isTrue);
    });

    test('returns business check-in prompt when business profile is active', () async {
      final now = DateTime.now();
      final profile = CashFlowProfile(
        id: 'prof_biz_1',
        householdId: 'house_123',
        profileType: CashFlowProfileType.business,
        name: 'Toko Kelontong Berkah',
        commodityOrBusinessType: 'Retail & Sembako',
        startDate: now.subtract(const Duration(days: 10)),
        targetHarvestDate: now.add(const Duration(days: 20)),
        initialCapital: 10000000,
        estimatedInflow: 25000000,
        dailyLivingBudget: 100000,
        isActive: true,
      );
      await repository.saveProfile(profile);

      final prompt = await service.evaluateCheckIn('house_123');
      expect(prompt, isNotNull);
      expect(prompt!.profile.id, equals('prof_biz_1'));
      expect(prompt.greetingMessage, contains('Toko Kelontong Berkah'));
      expect(prompt.greetingMessage, contains('Wawancara Status Usaha & Operasional'));
      expect(prompt.suggestedQuestions.length, equals(3));
    });
  });
}
