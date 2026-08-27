import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/features/assistant/presentation/widgets/gemini_header.dart';

Widget _host({required bool ready, String? model, String? error}) =>
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 400,
            height: 120,
            child: GeminiHeader(
              currentPage: null,
              isFullScreen: true,
              onToggleFullScreen: () {},
              onOpenVoicePicker: () {},
              onResetChat: () {},
              onClose: () {},
              cloudChecking: false,
              cloudReady: ready,
              cloudStatusError: error,
              onRefreshCloudStatus: () {},
              cloudModel: model,
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('header chatbot menampilkan model Gemini yang tersimpan', (
    tester,
  ) async {
    await tester.pumpWidget(_host(ready: true, model: 'gemini-2.5-pro'));

    expect(find.textContaining('Gemini Cloud siap'), findsOneWidget);
    expect(find.textContaining('gemini-2.5-pro'), findsOneWidget);
  });

  testWidgets('header chatbot tidak mengklaim siap ketika belum verified', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(ready: false, error: 'Gemini Cloud belum diuji di Pengaturan'),
    );

    expect(find.text('Gemini Cloud belum diuji di Pengaturan'), findsOneWidget);
    expect(find.textContaining('Gemini Cloud siap'), findsNothing);
  });
}
