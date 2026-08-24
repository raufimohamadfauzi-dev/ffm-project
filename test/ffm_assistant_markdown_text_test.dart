import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/features/assistant/presentation/widgets/ffm_assistant_markdown_text.dart';

void main() {
  testWidgets('renderer Markdown menampilkan struktur dasar chat', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FfmAssistantMarkdownText(
            text: '# Ringkasan\n\n**Pemasukan**\n- Gaji\n> Data lokal\n\n```json\n{"ok": true}\n```',
            color: Colors.black,
          ),
        ),
      ),
    );

    expect(find.text('Ringkasan'), findsOneWidget);
    expect(find.text('Pemasukan'), findsOneWidget);
    expect(find.text('•'), findsOneWidget);
    expect(find.text('Data lokal'), findsOneWidget);
    expect(find.text('{"ok": true}'), findsOneWidget);
  });
}
