import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/features/assistant/presentation/widgets/gemini_typing_indicator.dart';

void main() {
  testWidgets('indikator proses dapat diketuk', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GeminiTypingIndicator(
            message: 'Memproses dengan SLM lokal...',
            onTap: () => tapped = true,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Memproses dengan SLM lokal...'));

    expect(tapped, isTrue);
  });
}
