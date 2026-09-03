import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/features/budget/presentation/pages/budget_page.dart';

void main() {
  group('budgetProgressFor dihitung dari dana tersedia', () {
    test('tanpa transfer: spent / batas', () {
      expect(
        budgetProgressFor(
          allocated: 1000000,
          rollover: 0,
          transferredIn: 0,
          transferredOut: 0,
          spent: 400000,
        ),
        closeTo(0.4, 1e-9),
      );
    });

    test('transfer keluar mengurangi penyebut (bukan batas kotor)', () {
      // Alokasi 1 jt, transfer keluar 500 rb, belanja 400 rb.
      // Perilaku lama: 400/1000 = 0.4 ("Aman" padahal sisa tinggal 100 rb).
      // Perilaku benar: 400/500 = 0.8.
      expect(
        budgetProgressFor(
          allocated: 1000000,
          rollover: 0,
          transferredIn: 0,
          transferredOut: 500000,
          spent: 400000,
        ),
        closeTo(0.8, 1e-9),
      );
    });

    test('transfer masuk menambah penyebut', () {
      expect(
        budgetProgressFor(
          allocated: 1000000,
          rollover: 0,
          transferredIn: 200000,
          transferredOut: 0,
          spent: 600000,
        ),
        closeTo(0.5, 1e-9),
      );
    });

    test('rollover ikut menjadi dana tersedia', () {
      expect(
        budgetProgressFor(
          allocated: 1000000,
          rollover: 200000,
          transferredIn: 0,
          transferredOut: 0,
          spent: 600000,
        ),
        closeTo(0.5, 1e-9),
      );
    });

    test('basis habis dan ada belanja → 1 (melewati batas)', () {
      expect(
        budgetProgressFor(
          allocated: 500000,
          rollover: 0,
          transferredIn: 0,
          transferredOut: 500000,
          spent: 100000,
        ),
        1,
      );
    });

    test('basis habis tanpa belanja → 0', () {
      expect(
        budgetProgressFor(
          allocated: 500000,
          rollover: 0,
          transferredIn: 0,
          transferredOut: 500000,
          spent: 0,
        ),
        0,
      );
    });

    test('konsisten dengan sisa dana: progress = spent / (sisa + spent)', () {
      const allocated = 1000000;
      const transferredOut = 300000;
      const spent = 350000;
      final remaining = allocated - transferredOut - spent;
      expect(
        budgetProgressFor(
          allocated: allocated,
          rollover: 0,
          transferredIn: 0,
          transferredOut: transferredOut,
          spent: spent,
        ),
        closeTo(spent / (remaining + spent), 1e-9),
      );
    });
  });
}
