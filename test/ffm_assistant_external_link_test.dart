import 'package:ffm_manager/features/assistant/presentation/widgets/ffm_assistant_external_link.dart';
import 'package:ffm_manager/features/assistant/presentation/widgets/ffm_assistant_markdown_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mendeteksi hanya URL http(s) dan Markdown link aman', () {
    final links = FfmAssistantExternalLinkParser.parse(
      'Baca [panduan](https://contoh.test/dokumen) atau www.contoh2.test. javascript:alert(1)',
    );

    expect(links, hasLength(2));
    expect(links.first.label, 'panduan');
    expect(links.first.uri.scheme, 'https');
    expect(links.last.uri.toString(), 'https://www.contoh2.test');
  });

  test('menolak skema lokal atau yang dapat dieksekusi', () {
    for (final text in const [
      '[jalan](javascript:alert)',
      '[data](data:text/plain,hi)',
      '[berkas](file:///storage/x)',
      'ftp://contoh.test/berkas',
    ]) {
      expect(FfmAssistantExternalLinkParser.parse(text), isEmpty);
    }
  });

  testWidgets(
    'tautan yang diketuk memakai callback eksplisit, tanpa membuka otomatis',
    (tester) async {
      Uri? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FfmAssistantMarkdownText(
              text: 'Baca [panduan](https://contoh.test/dokumen).',
              color: Colors.black,
              onOpenLink: (uri) async {
                opened = uri;
                return true;
              },
            ),
          ),
        ),
    );

    expect(opened, isNull);
    await tester.tap(find.byType(RichText));
    await tester.pump();
      expect(opened, Uri.parse('https://contoh.test/dokumen'));
    },
  );
}
