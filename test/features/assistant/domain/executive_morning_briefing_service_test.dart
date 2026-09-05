import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/domain/services/executive_morning_briefing_service.dart';

void main() {
  group('ExecutiveMorningBriefingService', () {
    late AppDatabase db;
    late ExecutiveMorningBriefingService service;
    const householdId = 'test-household-briefing';

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase(NativeDatabase.memory());
      service = ExecutiveMorningBriefingService(
        database: db,
      );

      // Seed household
      await db.into(db.households).insert(
        HouseholdsCompanion.insert(
          id: householdId,
          name: 'Keluarga Bahagia',
          createdAt: DateTime.now(),
        ),
      );

      // Seed accounts
      await db.into(db.accounts).insert(
        AccountsCompanion.insert(
          id: 'acc-cash',
          householdId: householdId,
          name: 'Dompet Tunai',
          type: 'cash',
          openingBalance: const drift.Value(200000),
          createdAt: DateTime.now(),
        ),
      );
      await db.into(db.accounts).insert(
        AccountsCompanion.insert(
          id: 'acc-bank',
          householdId: householdId,
          name: 'Bank BCA',
          type: 'bank',
          openingBalance: const drift.Value(1000000),
          createdAt: DateTime.now(),
        ),
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('isMorningTime returns true between 05:00 and 09:59', () {
      expect(service.isMorningTime(now: DateTime(2026, 9, 5, 4, 59)), isFalse);
      expect(service.isMorningTime(now: DateTime(2026, 9, 5, 5, 0)), isTrue);
      expect(service.isMorningTime(now: DateTime(2026, 9, 5, 7, 30)), isTrue);
      expect(service.isMorningTime(now: DateTime(2026, 9, 5, 9, 59)), isTrue);
      expect(service.isMorningTime(now: DateTime(2026, 9, 5, 10, 0)), isFalse);
      expect(service.isMorningTime(now: DateTime(2026, 9, 5, 14, 0)), isFalse);
    });

    test('shouldPresentBriefing only returns true once per day during morning', () async {
      final morningTime = DateTime(2026, 9, 5, 7, 0);
      expect(await service.shouldPresentBriefing(householdId, now: morningTime), isTrue);

      await service.markBriefingPresented(householdId, now: morningTime);
      expect(await service.shouldPresentBriefing(householdId, now: morningTime), isFalse);

      // Next day morning should return true again
      final nextDayMorning = DateTime(2026, 9, 6, 6, 30);
      expect(await service.shouldPresentBriefing(householdId, now: nextDayMorning), isTrue);
    });

    test('generateBriefing calculates cash balance, yesterday expense, and builds script', () async {
      final today = DateTime(2026, 9, 5, 8, 0);
      final yesterday = DateTime(2026, 9, 4, 15, 0);

      // Seed yesterday expense (-75.000)
      await db.into(db.transactions).insert(
        TransactionsCompanion.insert(
          id: 'tx-yesterday',
          householdId: householdId,
          type: 'expense',
          date: yesterday,
          recordedAt: yesterday,
          amount: 75000,
          accountId: const drift.Value('acc-cash'),
          createdAt: yesterday,
          isDeleted: const drift.Value(false),
        ),
      );

      // Seed reminder for today
      await db.into(db.reminders).insert(
        RemindersCompanion.insert(
          id: 'rem-today',
          householdId: householdId,
          title: 'Bayar Listrik PLN',
          scheduledAt: DateTime(2026, 9, 5, 9, 0),
          notificationId: 101,
          createdAt: yesterday,
          isActive: const drift.Value(true),
        ),
      );

      final briefing = await service.generateBriefing(householdId, now: today);

      expect(briefing.familyName, 'Keluarga Bahagia');
      // Opening balance: 200k + 1000k = 1.200k minus 75k = 1.125.000
      expect(briefing.totalCashBalance, 1125000);
      expect(briefing.yesterdayExpense, 75000);
      expect(briefing.dueItems, contains(contains('Bayar Listrik PLN')));

      expect(briefing.greeting, contains('Keluarga Bahagia'));
      expect(briefing.textSummary, contains('Rp 1.125.000'));
      expect(briefing.textSummary, contains('Rp 75.000'));
      expect(briefing.spokenScript, contains('Keluarga Bahagia'));
      expect(briefing.spokenScript, contains('Rp 1.125.000'));
    });
  });
}
