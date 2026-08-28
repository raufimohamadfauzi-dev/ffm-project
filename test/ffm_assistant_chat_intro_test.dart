import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/features/assistant/presentation/widgets/chat/ffm_assistant_chat_intro.dart';

const List<FfmAssistantQuickPrompt> _defaultExamples = [
  (
    label: 'Draft transaksi',
    text: 'Catat pengeluaran makan Rp50.000 hari ini',
    icon: Icons.receipt_long_outlined,
  ),
  (
    label: 'Draft anggaran',
    text: 'Buatkan draft anggaran makan bulan ini',
    icon: Icons.pie_chart_outline,
  ),
];

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('FfmAssistantChatIntro', () {
    testWidgets(
      'menampilkan pengantar singkat dan contoh yang dapat diketuk',
      (tester) async {
        String? filled;
        await tester.pumpWidget(
          _wrap(
            FfmAssistantChatIntro(
              examples: _defaultExamples,
              onFillExample: (text) => filled = text,
            ),
          ),
        );

        expect(
          find.textContaining('satu permintaan atau beberapa sekaligus'),
          findsOneWidget,
        );
        expect(find.text('Draft transaksi'), findsOneWidget);
        expect(find.text('Draft anggaran'), findsOneWidget);

        await tester.tap(find.text('Draft transaksi'));
        expect(
          filled,
          'Catat pengeluaran makan Rp50.000 hari ini',
        );
      },
    );

    testWidgets('contoh menghasilkan teks asli tanpa menambahkan data',
        (tester) async {
      String? filled;
      await tester.pumpWidget(
        _wrap(
          FfmAssistantChatIntro(
            examples: _defaultExamples,
            onFillExample: (text) => filled = text,
          ),
        ),
      );

      await tester.tap(find.text('Draft anggaran'));
      expect(filled, 'Buatkan draft anggaran makan bulan ini');
      expect(find.text('Draft anggaran'), findsOneWidget);
    });

    testWidgets(
      'mode compact mengecil menjadi satu aksi "Contoh"',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            FfmAssistantChatIntro(
              examples: _defaultExamples,
              onFillExample: (_) {},
              compact: true,
            ),
          ),
        );

        expect(find.text('Contoh'), findsOneWidget);
        expect(find.text('Draft transaksi'), findsNothing);

        await tester.tap(find.text('Contoh'));
        await tester.pumpAndSettle();
        expect(find.text('Contoh permintaan'), findsOneWidget);
      },
    );

    testWidgets('contoh cepat memiliki label aksesibilitas', (tester) async {
      await tester.pumpWidget(
        _wrap(
          FfmAssistantChatIntro(
            examples: _defaultExamples,
            onFillExample: (_) {},
          ),
        ),
      );

      expect(
        find.bySemanticsLabel(RegExp(r'Contoh: Draft transaksi')),
        findsOneWidget,
      );
    });

    testWidgets('tidak overflow pada layar kecil', (tester) async {
      tester.view.physicalSize = const Size(320 * 2, 480 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _wrap(
          FfmAssistantChatIntro(
            examples: _defaultExamples,
            onFillExample: (_) {},
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('Draft anggaran'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Draft anggaran'), findsOneWidget);
    });
  });

  group('FfmAssistantContextualSuggestions', () {
    testWidgets('menampilkan saran dan mengisi input lewat callback',
        (tester) async {
      String? filled;
      await tester.pumpWidget(
        _wrap(
          FfmAssistantContextualSuggestions(
            suggestions: const [
              (
                label: 'Buat draft transaksi',
                text: 'Catat pengeluaran hari ini',
                icon: Icons.add,
              ),
            ],
            onFillExample: (text) => filled = text,
          ),
        ),
      );

      expect(find.textContaining('Lanjutkan'), findsOneWidget);
      await tester.tap(find.text('Buat draft transaksi'));
      expect(filled, 'Catat pengeluaran hari ini');
    });
  });

  group('FfmAssistantAmbiguousClarification', () {
    testWidgets('menampilkan pertanyaan dan pilihan aman', (tester) async {
      String? selected;
      await tester.pumpWidget(
        _wrap(
          FfmAssistantAmbiguousClarification(
            question: 'Dari rekening mana pembayarannya?',
            safeChoices: const ['Tunai', 'SeaBank'],
            onSelectChoice: (choice) => selected = choice,
          ),
        ),
      );

      expect(
        find.text('Dari rekening mana pembayarannya?'),
        findsOneWidget,
      );
      await tester.tap(find.text('SeaBank'));
      expect(selected, 'SeaBank');
    });

    testWidgets('tidak menampilkan pilihan saat tidak ada pilihan aman',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          FfmAssistantAmbiguousClarification(
            question: 'Nominalnya berapa?',
            safeChoices: const [],
            onSelectChoice: (_) {},
          ),
        ),
      );

      expect(find.text('Nominalnya berapa?'), findsOneWidget);
      expect(find.byType(OutlinedButton), findsNothing);
    });
  });
}