import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ffm_manager/shared/widgets/recent_selection_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('RecentSelectionCache stores, reads from memory and prunes correctly', () async {
    final cache = RecentSelectionCache();

    // Read on empty returns empty list
    final initial = await cache.read('category');
    expect(initial, isEmpty);

    // Remember 3 items
    await cache.remember('category', 'cat-1');
    await cache.remember('category', 'cat-2');
    await cache.remember('category', 'cat-3');

    final stored = await cache.read('category');
    expect(stored, ['cat-3', 'cat-2', 'cat-1']);

    // Prune invalid values
    final pruned = await cache.prune('category', ['cat-1', 'cat-3']);
    expect(pruned, ['cat-3', 'cat-1']);

    // Clear
    await cache.clear('category');
    final cleared = await cache.read('category');
    expect(cleared, isEmpty);
  });
}
