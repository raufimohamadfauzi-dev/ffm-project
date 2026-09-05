import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/features/assistant/domain/services/executive_morning_briefing_service.dart';
import 'package:ffm_manager/features/assistant/presentation/widgets/morning_briefing_card.dart';

void main() {
  final briefing = ExecutiveMorningBriefing(
    greeting: 'Selamat Pagi, Keluarga Bahagia! 🌅',
    familyName: 'Keluarga Bahagia',
    totalCashBalance: 2500000,
    yesterdayExpense: 120000,
    monthExpenseSoFar: 450000,
    dueItems: const ['Pola rutin Belanja Sayur (Rp 50.000)', 'Pengingat: Bayar Wifi'],
    textSummary: 'Ringkasan pagi...',
    spokenScript: 'Selamat pagi keluarga bahagia...',
    generatedAt: DateTime(2026, 9, 5, 7, 0),
  );

  Widget createWidget({
    bool isPlaying = false,
    bool isPaused = false,
    VoidCallback? onPlayAudio,
    VoidCallback? onPauseAudio,
    VoidCallback? onStopAudio,
    VoidCallback? onClose,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: MorningBriefingCard(
          briefing: briefing,
          isPlaying: isPlaying,
          isPaused: isPaused,
          onPlayAudio: onPlayAudio ?? () {},
          onPauseAudio: onPauseAudio ?? () {},
          onStopAudio: onStopAudio ?? () {},
          onClose: onClose ?? () {},
        ),
      ),
    );
  }

  group('MorningBriefingCard Widget Tests', () {
    testWidgets('renders header, metrics, and due items properly', (tester) async {
      await tester.pumpWidget(createWidget());

      expect(find.text('Executive Morning Briefing'), findsOneWidget);
      expect(find.textContaining('Keluarga Bahagia'), findsWidgets);
      expect(find.text('Rp 2.500.000'), findsOneWidget);
      expect(find.text('Rp 120.000'), findsOneWidget);
      expect(find.text('Rp 450.000'), findsOneWidget);

      expect(find.text('Agenda & Pola Hari Ini'), findsOneWidget);
      expect(find.textContaining('Belanja Sayur'), findsOneWidget);
      expect(find.textContaining('Bayar Wifi'), findsOneWidget);
      expect(find.text('Putar Suara'), findsOneWidget);
    });

    testWidgets('triggers onPlayAudio when Putar Suara tapped', (tester) async {
      var played = false;
      await tester.pumpWidget(createWidget(onPlayAudio: () => played = true));

      await tester.tap(find.text('Putar Suara'));
      await tester.pump();

      expect(played, isTrue);
    });

    testWidgets('renders Jeda and Berhenti when isPlaying is true', (tester) async {
      var paused = false;
      var stopped = false;
      await tester.pumpWidget(createWidget(
        isPlaying: true,
        onPauseAudio: () => paused = true,
        onStopAudio: () => stopped = true,
      ));

      expect(find.text('Jeda'), findsOneWidget);
      expect(find.text('Berhenti'), findsOneWidget);

      await tester.tap(find.text('Jeda'));
      await tester.pump();
      expect(paused, isTrue);

      await tester.tap(find.text('Berhenti'));
      await tester.pump();
      expect(stopped, isTrue);
    });

    testWidgets('renders Lanjutkan when isPaused is true', (tester) async {
      var resumed = false;
      await tester.pumpWidget(createWidget(
        isPaused: true,
        onPlayAudio: () => resumed = true,
      ));

      expect(find.text('Lanjutkan'), findsOneWidget);
      await tester.tap(find.text('Lanjutkan'));
      await tester.pump();

      expect(resumed, isTrue);
    });

    testWidgets('triggers onClose when Tutup tapped', (tester) async {
      var closed = false;
      await tester.pumpWidget(createWidget(onClose: () => closed = true));

      await tester.tap(find.text('Tutup'));
      await tester.pump();

      expect(closed, isTrue);
    });
  });
}
