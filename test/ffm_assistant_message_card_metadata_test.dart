import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/assistant/presentation/widgets/chat/ffm_assistant_message_card.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets(
    'metadata waktu dan model tersembunyi dan muncul saat bubble ditekan',
    (tester) async {
      final entry = FfmAssistantChatEntry(
        isUser: false,
        text: 'Jawaban asisten.',
        sentAt: DateTime(2026, 9, 5, 9, 12, 5),
        receivedAt: DateTime(2026, 9, 5, 9, 12, 9),
        modelUsed: 'gemini-cloud',
      );

      await tester.pumpWidget(
        _wrap(
          FfmAssistantMessageCard(
            entry: entry,
            isSpeaking: false,
            teachingSaved: false,
            activityConfirmed: false
          ),
        ),
      );

      expect(find.textContaining('Kirim 09:12:05'), findsNothing);
      expect(find.textContaining('Terima 09:12:09'), findsNothing);
      expect(find.textContaining('gemini-cloud'), findsNothing);

await tester.tap(find.text('Jawaban asisten.'));
      await tester.pump();

      expect(find.textContaining('Kirim 09:12:05'), findsOneWidget);
      expect(find.textContaining('Terima 09:12:09'), findsOneWidget);
      expect(find.textContaining('gemini-cloud'), findsOneWidget);
    },
  );

  testWidgets(
    'metadata bubble user menampilkan waktu kirim tanpa waktu terima',
    (tester) async {
      final entry = FfmAssistantChatEntry(
        isUser: true,
        text: 'Cek saldo',
        sentAt: DateTime(2026, 9, 5, 9, 12, 5),
        modelUsed: 'user',
      );

      await tester.pumpWidget(
        _wrap(
          FfmAssistantMessageCard(
            entry: entry,
            isSpeaking: false,
            teachingSaved: false,
            activityConfirmed: false
          ),
        ),
      );

      await tester.tap(find.text('Cek saldo'));
      await tester.pump();

      expect(find.textContaining('Kirim 09:12:05'), findsOneWidget);
      expect(find.textContaining('Terima'), findsNothing);
      expect(find.textContaining('user'), findsOneWidget);
    },
  );

  testWidgets(
    'user bubble 1 baris menampilkan tombol salin & 3 titik di luar sebelah kiri bubble',
    (tester) async {
      final entry = FfmAssistantChatEntry(
        isUser: true,
        text: 'kenapa gk biaa pindah halaman?',
      );

      await tester.pumpWidget(
        _wrap(
          FfmAssistantMessageCard(
            entry: entry,
            isSpeaking: false,
            teachingSaved: false,
            activityConfirmed: false,
            onCopyText: () {},
            onCorrectMessage: () {},
          ),
        ),
      );

      expect(find.byIcon(Icons.copy_outlined), findsOneWidget);
      expect(find.byIcon(Icons.more_horiz), findsOneWidget);
      expect(find.text('kenapa gk biaa pindah halaman?'), findsOneWidget);

      final copyBox = tester.getRect(find.byIcon(Icons.copy_outlined));
      final textBox = tester.getRect(find.text('kenapa gk biaa pindah halaman?'));

      // Tombol copy berada di sebelah KIRI luar bubble teks (copyBox.left < textBox.left)
      expect(copyBox.left, lessThan(textBox.left));
    },
  );

  testWidgets(
    'user bubble multi-line (2 baris+) tetap menampilkan tombol di sebelah kiri luar bubble, bukan di bawah',
    (tester) async {
      final entry = FfmAssistantChatEntry(
        isUser: true,
        text: 'kenapa gk biaa pindah halaman?\ntolong bantu jelaskan',
      );

      await tester.pumpWidget(
        _wrap(
          FfmAssistantMessageCard(
            entry: entry,
            isSpeaking: false,
            teachingSaved: false,
            activityConfirmed: false,
            onCopyText: () {},
            onCorrectMessage: () {},
          ),
        ),
      );

      expect(find.byIcon(Icons.copy_outlined), findsOneWidget);
      expect(find.textContaining('kenapa gk biaa pindah halaman?'), findsOneWidget);

      final copyBox = tester.getRect(find.byIcon(Icons.copy_outlined));
      final textBox = tester.getRect(find.textContaining('kenapa gk biaa pindah halaman?'));

      // Tombol copy tetap di sebelah KIRI luar bubble teks (copyBox.left < textBox.left)
      expect(copyBox.left, lessThan(textBox.left));
    },
  );

  testWidgets(
    'menampilkan token badge pada header balasan asisten saat tokenUsage tersedia',
    (tester) async {
      final entry = FfmAssistantChatEntry(
        isUser: false,
        text: 'Ini jawaban asisten.',
        processTrace: const FfmAssistantProcessTrace(
          origin: FfmAssistantResponseOrigin.geminiCloud,
          elapsed: Duration(milliseconds: 300),
          events: [],
          tokenUsage: {
            'promptTokenCount': 1240,
            'candidatesTokenCount': 300,
            'totalTokenCount': 1540,
          },
        ),
      );

      await tester.pumpWidget(
        _wrap(
          FfmAssistantMessageCard(
            entry: entry,
            isSpeaking: false,
            teachingSaved: false,
            activityConfirmed: false,
          ),
        ),
      );

      expect(find.textContaining('1.540 token'), findsOneWidget);
    },
  );

  testWidgets(
    'menampilkan pill saran pertanyaan/tag dan memanggil onSelectSuggestion saat diklik',
    (tester) async {
      String? selected;
      final entry = FfmAssistantChatEntry(
        isUser: false,
        text: 'Silakan pilih tag untuk transaksi ini:',
        suggestedQuestions: const ['#makan-siang', '#proyek', '#liburan'],
      );

      await tester.pumpWidget(
        _wrap(
          FfmAssistantMessageCard(
            entry: entry,
            isSpeaking: false,
            teachingSaved: false,
            activityConfirmed: false,
            onSelectSuggestion: (s) => selected = s,
          ),
        ),
      );

      expect(find.text('#makan-siang'), findsOneWidget);
      expect(find.text('#proyek'), findsOneWidget);
      expect(find.text('#liburan'), findsOneWidget);

      await tester.tap(find.text('#makan-siang'));
      await tester.pump();

      expect(selected, '#makan-siang');
    },
  );
}
