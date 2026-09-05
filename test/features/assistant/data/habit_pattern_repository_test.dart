import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ffm_manager/features/assistant/data/habit_pattern_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HabitPatternRepository', () {
    late HabitPatternRepository repository;
    const householdId = 'test-household-1';

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      repository = HabitPatternRepository();
    });

    test('new pattern is not suppressed', () async {
      final isSuppressed = await repository.isPatternSuppressed(
        householdId,
        'pat_1',
      );
      expect(isSuppressed, isFalse);
    });

    test('snoozing a pattern suppresses it within duration', () async {
      final now = DateTime(2026, 9, 5, 10, 0);
      await repository.snoozePattern(
        householdId,
        'pat_1',
        duration: const Duration(days: 7),
        now: now,
      );

      final isSuppressedNow = await repository.isPatternSuppressed(
        householdId,
        'pat_1',
        now: now.add(const Duration(days: 3)),
      );
      expect(isSuppressedNow, isTrue);

      final isSuppressedLater = await repository.isPatternSuppressed(
        householdId,
        'pat_1',
        now: now.add(const Duration(days: 8)),
      );
      expect(isSuppressedLater, isFalse);
    });

    test('ignoring a pattern suppresses it permanently', () async {
      await repository.ignorePattern(householdId, 'pat_2');

      final isSuppressed = await repository.isPatternSuppressed(
        householdId,
        'pat_2',
        now: DateTime(2030, 1, 1),
      );
      expect(isSuppressed, isTrue);

      final ignoredSet = await repository.getIgnoredPatternIds(householdId);
      expect(ignoredSet, contains('pat_2'));
    });

    test('unignoring a pattern removes permanent suppression', () async {
      await repository.ignorePattern(householdId, 'pat_3');
      expect(await repository.isPatternSuppressed(householdId, 'pat_3'), isTrue);

      await repository.unignorePattern(householdId, 'pat_3');
      expect(await repository.isPatternSuppressed(householdId, 'pat_3'), isFalse);
    });
  });
}
