import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/shared/widgets/app_components.dart';

void main() {
  testWidgets('menutup dropdown tanpa memilih tidak menghapus pilihan', (
    tester,
  ) async {
    var selected = 'beras';

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: SearchableDropdown<String>(
              items: const ['beras', 'sayur'],
              selectedItem: selected,
              itemLabel: (value) => value == 'beras' ? 'Beras' : 'Sayur',
              cacheKey: null,
              onChanged: (value) => setState(() => selected = value ?? ''),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Beras'), findsOneWidget);
    await tester.tap(find.text('Beras'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(selected, 'beras');
    expect(find.text('Beras'), findsOneWidget);
  });

  testWidgets('memilih item mengirim nilai ke form', (tester) async {
    String? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: SearchableDropdown<String>(
              items: const ['beras', 'sayur'],
              selectedItem: selected,
              itemLabel: (value) => value == 'beras' ? 'Beras' : 'Sayur',
              cacheKey: null,
              onChanged: (value) => setState(() => selected = value),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Pilih dari daftar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sayur'));
    await tester.pumpAndSettle();

    expect(selected, 'sayur');
  });

  testWidgets('opsi kosong mengirim null hanya saat dipilih', (tester) async {
    String? selected = 'beras';

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: SearchableDropdown<String>(
              items: const ['beras', 'sayur'],
              selectedItem: selected,
              itemLabel: (value) => value == 'beras' ? 'Beras' : 'Sayur',
              allowClear: true,
              cacheKey: null,
              onChanged: (value) => setState(() => selected = value),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Beras'));
    await tester.pumpAndSettle();
    expect(find.text('Belum dipilih'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.remove_circle_outline));
    await tester.pumpAndSettle();

    expect(selected, isNull);
  });
}

