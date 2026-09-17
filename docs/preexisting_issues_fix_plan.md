# Pre-existing Issues Fix Plan

Audit date: 2026-09-17
Status: Ready for execution

---

## Issue 1: ID Collision Patterns (Medium Severity)

### 1A. `bill_reminder_repository.dart:290-302`

**Problem:** `_generateId()` uses `DateTime.now().millisecondsSinceEpoch` + `_randomId()` where `_randomId()` is seeded from the same timestamp. Two calls within the same millisecond produce identical IDs.

**Current code:**
```dart
String _generateId() {
  return 'bill-${DateTime.now().millisecondsSinceEpoch}-${_randomId()}';
}

String _randomId() {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final random = DateTime.now().millisecondsSinceEpoch; // BUG: same seed
  final buffer = StringBuffer();
  for (int i = 0; i < 8; i++) {
    buffer.write(chars[(random + i) % chars.length]);
  }
  return buffer.toString();
}
```

**Fix:** Replace with `Uuid().v4()` from the `uuid` package (already in project dependencies).

**Replacement:**
```dart
String _generateId() {
  return 'bill-${const Uuid().v4()}';
}
```

Delete `_randomId()` method entirely. Add `import 'package:uuid/uuid.dart';` if not present.

---

### 1B. `ffm_personal_context_engine_impl.dart:799`

**Problem:** Fallback ID `'personal-${DateTime.now().microsecondsSinceEpoch}'` has no random component. Rapid calls can collide.

**Current code:**
```dart
id: memory.id ?? 'personal-${DateTime.now().microsecondsSinceEpoch}',
```

**Fix:**
```dart
id: memory.id ?? 'personal-${const Uuid().v4()}',
```

Add `import 'package:uuid/uuid.dart';` if not present.

---

### 1C. `ffm_assistant_work_item_service.dart:59`

**Problem:** `'work_${DateTime.now().millisecondsSinceEpoch}_$index'` — `index` is a sequential counter that may reset per session.

**Current code:**
```dart
final id = 'work_${DateTime.now().millisecondsSinceEpoch}_$index';
```

**Fix:**
```dart
final id = 'work_${const Uuid().v4()}';
```

Add `import 'package:uuid/uuid.dart';` if not present.

---

## Issue 2: Empty Test Stubs (Low Severity)

### File: `test/features/assistant/domain/ffm_personal_context_engine_test.dart`

**Problem:** 15 test bodies contain only `// TODO: Implement test` with pseudocode comments. These provide zero test coverage for:
- Context retrieval (exact, paraphrase, typo, follow-up, goal relevance, unrelated memory, conflict, stale, correction, no-memory fallback)
- Relevance scoring (recency decay)
- Conflict resolution (newer wins, confidence difference)
- Deduplication
- Error handling (fallback behavior)

**Fix approach:**

1. Read the implementation: `lib/features/assistant/domain/ffm_personal_context_engine.dart` (interface) and `lib/features/assistant/data/ffm_personal_context_engine_impl.dart`
2. For each TODO test, implement using the existing models (`FfmMemoryCandidate`, `FfmMemoryType`, `FfmContextRelevanceScore`, `FfmContextBudget`)
3. Tests that require database or full engine instantiation should use `createInMemoryDatabaseForTests()` pattern (see existing test files for examples)
4. Tests that only test model behavior (relevance score calculation, budget config, enum existence) can be implemented without mocks
5. Priority order:
   - Relevance score calculation (already partially implemented at line 99-116)
   - Conflict resolution (newer wins, confidence difference)
   - Deduplication
   - Error handling fallback
   - Context retrieval tests (these may need integration-level setup)

**Skip if:** The context engine interface/implementation is too complex to unit-test without significant refactoring. In that case, convert TODO stubs to explicit `skip: 'requires integration setup'` with a tracking issue comment.

---

## Execution Order

1. Fix 1A (bill_reminder_repository) — highest collision risk
2. Fix 1B (personal_context_engine fallback) — medium risk
3. Fix 1C (work_item_service) — medium risk
4. Fix 2 (test stubs) — lowest priority, optional

## Verification

After each fix:
```bash
flutter analyze lib test
flutter test test/budget_habit_analyzer_test.dart test/ffm_assistant_budget_mutation_test.dart
```

After all fixes:
```bash
flutter test
```
