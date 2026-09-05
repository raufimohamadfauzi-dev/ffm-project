import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/onboarding_preference.dart';
import 'package:ffm_manager/features/assistant/domain/assistant_onboarding_orchestrator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AssistantOnboardingOrchestrator Unit Tests', () {
    late AppDatabase database;
    late AssistantOnboardingOrchestrator orchestrator;
    const testHouseholdId = 'test-household-onboarding';

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      database = AppDatabase(NativeDatabase.memory());

      // Inisialisasi household default
      await database.into(database.households).insert(
        HouseholdsCompanion.insert(
          id: testHouseholdId,
          name: 'Keluarga',
          createdAt: DateTime.now(),
        ),
      );

      // Reset preference status
      await OnboardingPreference.setCompleted(false);

      orchestrator = AssistantOnboardingOrchestrator(
        database: database,
        householdId: testHouseholdId,
      );
    });

    tearDown(() async {
      await database.close();
    });

    test('Alur lengkap conversational onboarding berjalan deterministik', () async {
      // 1. Inisialisasi & Start
      final startTurn = orchestrator.start();
      expect(orchestrator.currentStep, OnboardingStep.askFamilyName);
      expect(orchestrator.isOnboardingActive, isTrue);
      expect(startTurn.isCompleted, isFalse);
      expect(startTurn.message, contains('Selamat datang di FFM'));
      expect(startTurn.suggestions, contains('Keluarga Kami'));

      // 2. Input nama keluarga
      final turn2 = await orchestrator.processInput('Keluarga Sejahtera');
      expect(orchestrator.currentStep, OnboardingStep.askAccounts);
      expect(orchestrator.isOnboardingActive, isTrue);
      expect(turn2.isCompleted, isFalse);
      expect(turn2.message, contains('Keluarga Sejahtera'));
      expect(turn2.suggestions, contains('Dompet Tunai & Bank BCA'));

      // 3. Input akun keuangan
      final turn3 = await orchestrator.processInput('Dompet Tunai & Bank BCA');
      expect(orchestrator.currentStep, OnboardingStep.completed);
      expect(orchestrator.isOnboardingActive, isFalse);
      expect(turn3.isCompleted, isTrue);
      expect(turn3.message, contains('Akun keuangan sudah siap'));
      expect(turn3.suggestions, contains('Ubah ke mode gelap 🌙'));

      // 4. Verifikasi data akun tersimpan di database lokal
      final accounts = await (database.select(database.accounts)
            ..where((t) => t.householdId.equals(testHouseholdId)))
          .get();
      expect(accounts.length, greaterThanOrEqualTo(2));
      expect(accounts.any((a) => a.name.contains('Dompet Tunai')), isTrue);
      expect(accounts.any((a) => a.name.contains('Bank BCA')), isTrue);

      // 5. Verifikasi nama keluarga terupdate
      final household = await (database.select(database.households)
            ..where((t) => t.id.equals(testHouseholdId)))
          .getSingle();
      expect(household.name, 'Keluarga Sejahtera');

      // 6. Verifikasi OnboardingPreference ditandai selesai
      final completed = await OnboardingPreference.isCompleted();
      expect(completed, isTrue);
    });

    test('evaluateAdaptiveStage transitions correctly through multi-visit lifecycle', () async {
      // 1. Awal mula: belum ada akun -> emptyData
      expect(
        await orchestrator.evaluateAdaptiveStage(),
        AdaptiveOnboardingStage.emptyData,
      );

      // 2. Buat akun -> needsFirstTransaction
      await database.into(database.accounts).insert(
        AccountsCompanion.insert(
          id: 'acc-1',
          householdId: testHouseholdId,
          name: 'Dompet Tunai',
          type: 'cash',
          createdAt: DateTime.now(),
        ),
      );
      expect(
        await orchestrator.evaluateAdaptiveStage(),
        AdaptiveOnboardingStage.needsFirstTransaction,
      );

      // Cek sapaan bimbingan transaksi pertama
      final greeting1 = await orchestrator.checkAdaptiveGreeting();
      expect(greeting1, isNotNull);
      expect(greeting1!.message, contains('transaksi pertama'));
      expect(greeting1.suggestions, contains('Beli bensin 25rb'));

      // Sapaan kedua di tahap yang sama tidak boleh spam
      final greeting1Again = await orchestrator.checkAdaptiveGreeting();
      expect(greeting1Again, isNull);

      // 3. Catat transaksi -> needsBudget
      await database.into(database.transactions).insert(
        TransactionsCompanion.insert(
          id: 'tx-1',
          householdId: testHouseholdId,
          type: 'expense',
          date: DateTime.now(),
          recordedAt: DateTime.now(),
          amount: 25000,
          createdAt: DateTime.now(),
        ),
      );
      expect(
        await orchestrator.evaluateAdaptiveStage(),
        AdaptiveOnboardingStage.needsBudget,
      );

      // Cek sapaan bimbingan anggaran
      final greeting2 = await orchestrator.checkAdaptiveGreeting();
      expect(greeting2, isNotNull);
      expect(greeting2!.message, contains('anggaran bulanan'));
      expect(greeting2.suggestions, contains('Buat anggaran makan 1.5jt'));

      // 4. Buat anggaran -> graduated
      await database.into(database.envelopeBudgets).insert(
        EnvelopeBudgetsCompanion.insert(
          id: 'bgt-1',
          householdId: testHouseholdId,
          name: 'Makan & Minum',
          allocated: const drift.Value(1500000),
          startDate: DateTime.now(),
          endDate: DateTime.now().add(const Duration(days: 30)),
          createdAt: DateTime.now(),
        ),
      );
      expect(
        await orchestrator.evaluateAdaptiveStage(),
        AdaptiveOnboardingStage.graduated,
      );
      expect(await orchestrator.checkAdaptiveGreeting(), isNull);
    });
  });
}
