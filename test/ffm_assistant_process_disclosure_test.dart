import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/assistant/presentation/widgets/chat/ffm_assistant_process_disclosure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ringkasan provenance dapat membuka dropdown proses aktual', (
    tester,
  ) async {
    const trace = FfmAssistantProcessTrace(
      origin: FfmAssistantResponseOrigin.geminiCloud,
      elapsed: Duration(milliseconds: 420),
      events: [
        FfmAssistantProcessEvent(
          label: 'Lampiran diterima untuk dianalisis',
          elapsed: Duration.zero,
        ),
        FfmAssistantProcessEvent(
          label: 'Gemini Cloud mengembalikan jawaban',
          elapsed: Duration(milliseconds: 420),
          detail: 'Proposal tetap divalidasi FFM sebelum ditampilkan.',
        ),
      ],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: FfmAssistantProcessDisclosure(trace: trace)),
      ),
    );

    expect(find.textContaining('Gemini Cloud'), findsOneWidget);
    expect(find.text('Lampiran diterima untuk dianalisis'), findsNothing);

    await tester.tap(find.textContaining('Gemini Cloud'));
    await tester.pumpAndSettle();

    expect(find.text('Lampiran diterima untuk dianalisis'), findsOneWidget);
    expect(find.text('Gemini Cloud mengembalikan jawaban'), findsOneWidget);
  });
}
