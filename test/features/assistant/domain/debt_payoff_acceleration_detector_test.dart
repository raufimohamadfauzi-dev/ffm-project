import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/domain/detectors/debt_payoff_acceleration_detector.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_insight.dart';

void main() {
  group('DebtPayoffAccelerationDetector', () {
    late AppDatabase db;
    late DebtPayoffAccelerationDetector detector;
    const householdId = 'household-debt-test';

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      detector = DebtPayoffAccelerationDetector(db);

      // Seed household
      await db.into(db.households).insert(
        HouseholdsCompanion.insert(
          id: householdId,
          name: 'Keluarga Finansial Sehat',
          createdAt: DateTime.now(),
        ),
      );

      // Seed envelope budget with 5.000.000 (generating ~500.000 surplus suggestion)
      await db.into(db.envelopeBudgets).insert(
        EnvelopeBudgetsCompanion.insert(
          id: 'env-1',
          householdId: householdId,
          name: 'Belanja Bulanan',
          allocated: const drift.Value(5000000),
          startDate: DateTime(2026, 9, 1),
          endDate: DateTime(2026, 9, 30),
          createdAt: DateTime.now(),
        ),
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('returns null when no active liabilities exist', () async {
      final insight = await detector.detect(
        householdId: householdId,
        now: DateTime(2026, 9, 8),
      );
      expect(insight, isNull);
    });

    test('detects and generates debt payoff acceleration insight with Avalanche and Snowball options', () async {
      // Seed two liabilities: one with higher interest (Avalanche target) and one with smaller balance (Snowball target)
      await db.into(db.liabilities).insert(
        LiabilitiesCompanion.insert(
          id: 'debt-cc',
          householdId: householdId,
          name: 'Kartu Kredit Mandiri',
          originalAmount: 10000000,
          remainingBalance: 6000000,
          monthlyInstallment: const drift.Value(500000),
          interestRate: const drift.Value(24.0), // High interest
          startDate: DateTime(2026, 1, 1),
          dueDate: drift.Value(DateTime(2027, 1, 1)),
          isActive: const drift.Value(true),
          createdAt: DateTime(2026, 1, 1),
        ),
      );

      await db.into(db.liabilities).insert(
        LiabilitiesCompanion.insert(
          id: 'debt-koperasi',
          householdId: householdId,
          name: 'Koperasi Simpan Pinjam',
          originalAmount: 5000000,
          remainingBalance: 2000000, // Smaller balance
          monthlyInstallment: const drift.Value(200000),
          interestRate: const drift.Value(6.0),
          startDate: DateTime(2026, 1, 1),
          dueDate: drift.Value(DateTime(2027, 6, 1)),
          isActive: const drift.Value(true),
          createdAt: DateTime(2026, 1, 1),
        ),
      );

      final insight = await detector.detect(
        householdId: householdId,
        now: DateTime(2026, 9, 8),
      );

      expect(insight, isNotNull);
      expect(insight!.type, equals(FfmAssistantInsightType.debtPayoffAcceleration));
      expect(insight.title, contains('Strategi Percepatan Hutang'));
      expect(insight.summary, contains('Avalanche'));
      expect(insight.summary, contains('Kartu Kredit Mandiri'));
      expect(insight.suggestedAction, equals('Terapkan Alokasi Pelunasan'));
      expect(insight.actionPayload?['type'], equals('debt_payoff_allocation'));
      expect(insight.evidence['suggestedExtraPayment'], isNotNull);
    });
  });
}
