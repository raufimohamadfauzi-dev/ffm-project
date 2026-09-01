import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/activity/domain/activity_category_resolution.dart';

Category _category(String id, String name) => Category(
  id: id,
  householdId: 'home-a',
  name: name,
  type: 'activity',
  defaultBudgetPeriod: 'monthly',
  isActive: true,
  createdAt: DateTime(2026, 9, 1),
);

void main() {
  final categories = [
    _category('c-farm', 'Pertanian'),
    _category('c-care', 'Perawatan Tanaman'),
    _category('c-shopping', 'Belanja'),
  ];

  group('resolveActivityCategoryName', () {
    test('nama persis (case-insensitive) menghasilkan resolve tunggal', () {
      final result = resolveActivityCategoryName(categories, 'pertanian');

      expect(result.kind, ActivityCategoryResolutionKind.resolved);
      expect(result.category!.id, 'c-farm');
    });

    test('typo ringan lolos lewat fuzzy unique', () {
      final result = resolveActivityCategoryName(categories, 'pertanain');

      expect(result.kind, ActivityCategoryResolutionKind.resolved);
      expect(result.category!.id, 'c-farm');
    });

    test('satu kandidat fuzzy terbaik di-resolve', () {
      final result = resolveActivityCategoryName(categories, 'tanaman');

      expect(result.kind, ActivityCategoryResolutionKind.resolved);
      expect(result.category!.id, 'c-care');
    });

    test('dua kandidat mirip menghasilkan ambiguous untuk klarifikasi', () {
      final close = [
        _category('c-panen-pagi', 'Panen Pagi'),
        _category('c-panen-sore', 'Panen Sore'),
        _category('c-farm', 'Pertanian'),
      ];
      final result = resolveActivityCategoryName(close, 'panen');

      expect(result.isAmbiguous, isTrue);
      expect(result.candidates, hasLength(greaterThan(1)));
    });

    test('nama tidak dikenal menghasilkan notFound', () {
      final result = resolveActivityCategoryName(categories, 'hobi');

      expect(result.kind, ActivityCategoryResolutionKind.notFound);
      expect(result.category, isNull);
    });

    test('nama kosong atau null menghasilkan notFound', () {
      expect(
        resolveActivityCategoryName(categories, '  ').kind,
        ActivityCategoryResolutionKind.notFound,
      );
      expect(
        resolveActivityCategoryName(categories, null).kind,
        ActivityCategoryResolutionKind.notFound,
      );
    });
  });
}
