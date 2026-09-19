import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/assistant/presentation/widgets/chat/ffm_assistant_message_card.dart';
import 'package:ffm_manager/features/reminder/domain/entities/reminder_entity.dart';
import 'package:ffm_manager/features/reminder/presentation/widgets/alarm_ringing_dialog.dart';
import 'package:ffm_manager/core/di/injection.dart';
import 'package:ffm_manager/features/reminder/data/services/reminder_tts_service.dart';

class _MockTtsService implements ReminderTtsService {
  String? lastSpokenText;
  bool stopCalled = false;
  VoidCallback? _onCompletion;

  @override
  void setOnCompletionHandler(VoidCallback? callback) {
    _onCompletion = callback;
  }

  @override
  Future<void> speak(String text) async {
    lastSpokenText = text;
    _onCompletion?.call();
  }

  @override
  Future<void> speakReminder({
    required String title,
    String? note,
    bool isUrgentAlarm = false,
  }) async {
    final prefix = isUrgentAlarm ? 'Alarm:' : 'Pengingat:';
    lastSpokenText = note != null && note.trim().isNotEmpty
        ? '$prefix $title. Catatan: $note'
        : '$prefix $title';
    _onCompletion?.call();
  }

  @override
  Future<void> stop() async {
    stopCalled = true;
  }
}

void main() {
  setUpAll(() {
    if (!getIt.isRegistered<ReminderTtsService>()) {
      getIt.registerSingleton<ReminderTtsService>(_MockTtsService());
    }
  });

  group('Personal Memory Chips in Assistant UI', () {
    testWidgets('Renders memory chip when usedMemories is not empty and triggers onOpenMemoryViewer', (tester) async {
      bool memoryViewerOpened = false;

      final entry = const FfmAssistantChatEntry(
        isUser: false,
        text: 'Berdasarkan catatan memori kamu, komoditas panen utama adalah pepaya.',
        usedMemories: ['Komoditas tani/usaha: pepaya'],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FfmAssistantMessageCard(
              entry: entry,
              isSpeaking: false,
              teachingSaved: false,
              activityConfirmed: false,
              onOpenMemoryViewer: () {
                memoryViewerOpened = true;
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify the chip text is displayed
      expect(find.text('🧠 Memori: Komoditas tani/usaha: pepaya'), findsOneWidget);

      // Tap on the chip
      await tester.tap(find.text('🧠 Memori: Komoditas tani/usaha: pepaya'));
      await tester.pumpAndSettle();

      expect(memoryViewerOpened, isTrue);
    });
  });

  group('Talking Voice Alarm Ringing Dialog', () {
    testWidgets('Displays alarm details, destination button, and completes', (tester) async {
      bool completed = false;
      bool navigated = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  AlarmRingingDialog.show(
                    context,
                    title: 'Panen Pepaya California',
                    note: 'Cek kondisi buah dan timbang hasil panen',
                    destinationRoute: 'reminders',
                    onComplete: () {
                      completed = true;
                    },
                    onSnooze: () {},
                    onNavigateDestination: (route) {
                      navigated = true;
                    },
                  );
                },
                child: const Text('Buka Alarm'),
              ),
            ),
          ),
        ),
      );

      // Open dialog
      await tester.tap(find.text('Buka Alarm'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Check title and note
      expect(find.text('Panen Pepaya California'), findsOneWidget);
      expect(find.text('Cek kondisi buah dan timbang hasil panen'), findsOneWidget);
      expect(find.text('Buka Halaman Pengingat'), findsOneWidget);

      // Tap destination button
      await tester.tap(find.text('Buka Halaman Pengingat'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(navigated, isTrue);

      // Re-open dialog to test complete
      await tester.tap(find.text('Buka Alarm'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Selesai'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(completed, isTrue);
    });

    testWidgets('Defaults destination button to Halaman Pengingat when destinationRoute is null', (tester) async {
      String? routedTo;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  AlarmRingingDialog.show(
                    context,
                    title: 'Bangun Tengah Malam',
                    note: 'Waktunya cek pembukuan',
                    destinationRoute: null,
                    onComplete: () {},
                    onSnooze: () {},
                    onNavigateDestination: (route) {
                      routedTo = route;
                    },
                  );
                },
                child: const Text('Buka Alarm'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Buka Alarm'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Buka Halaman Pengingat'), findsOneWidget);

      await tester.tap(find.text('Buka Halaman Pengingat'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(routedTo, equals('reminders'));
    });

    testWidgets('Auto-Silence automatically triggers onSnooze when snoozeCount < 3', (tester) async {
      bool autoSnoozed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  AlarmRingingDialog.show(
                    context,
                    title: 'Bangun Pagi',
                    note: 'Waktunya olahraga',
                    snoozeCount: 1,
                    autoSilenceDuration: const Duration(milliseconds: 500),
                    onComplete: () {},
                    onSnooze: () {
                      autoSnoozed = true;
                    },
                  );
                },
                child: const Text('Buka Alarm'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Buka Alarm'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verifikasi indikator tunda ke-1 dan tombol tunda muncul
      expect(find.text('Tunda ke-1 (maks 3)'), findsOneWidget);
      expect(find.text('Tunda 10 Menit'), findsOneWidget);

      // Lewatkan waktu melebihi batas auto-silence (500ms)
      await tester.pump(const Duration(milliseconds: 600));

      expect(autoSnoozed, isTrue);
    });

    testWidgets('Auto-Silence terminates with onComplete and hides snooze button when snoozeCount >= 3', (tester) async {
      bool autoCompleted = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  AlarmRingingDialog.show(
                    context,
                    title: 'Bangun Pagi Terakhir',
                    snoozeCount: 3,
                    autoSilenceDuration: const Duration(milliseconds: 500),
                    onComplete: () {
                      autoCompleted = true;
                    },
                    onSnooze: () {},
                  );
                },
                child: const Text('Buka Alarm'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Buka Alarm'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verifikasi indikator tunda ke-3 muncul dan tombol tunda disembunyikan
      expect(find.text('Tunda ke-3 (maks 3)'), findsOneWidget);
      expect(find.text('Tunda 10 Menit'), findsNothing);

      // Lewatkan waktu melebihi batas auto-silence (500ms)
      await tester.pump(const Duration(milliseconds: 600));

      expect(autoCompleted, isTrue);
    });
  });

  group('Assistant Reminder Intent & Title Extraction', () {
    late AppDatabase database;
    late FfmAssistantInterpreter interpreter;
    final fixedClock = DateTime(2026, 9, 19, 10, 0);

    setUp(() {
      database = createInMemoryDatabaseForTests();
      interpreter = FfmAssistantInterpreter(
        database,
        clock: () => fixedClock,
      );
    });

    tearDown(() async {
      await database.close();
    });

    test('ingatkan saya besok jam 6 pagi mau ke kebun -> mode notifikasi, judul bersih Ke Kebun, route activity', () async {
      final intent = await interpreter.interpret('ingatkan saya besok jam 6 pagi mau ke kebun');
      expect(intent.type, FfmAssistantIntentType.createReminder);
      final draft = intent.draft;
      expect(draft, isNotNull);
      expect(draft!.kind, FfmAssistantDraftKind.reminder);
      expect(draft.reminderMode, ReminderMode.notification);
      expect(draft.date?.day, 20); // besok
      expect(draft.date?.hour, 6);
      expect(draft.date?.minute, 0);
      expect(draft.title, 'Ke Kebun');
      expect(draft.destinationRoute, 'activity');
      expect(draft.formValues['destinationRoute'], 'activity');
    });

    test('bangunkan saya besok jam 6 pagi mau ke kebun -> mode alarm otomatis, judul Ke Kebun, route activity', () async {
      final intent = await interpreter.interpret('bangunkan saya besok jam 6 pagi mau ke kebun');
      expect(intent.type, FfmAssistantIntentType.createReminder);
      final draft = intent.draft;
      expect(draft, isNotNull);
      expect(draft!.kind, FfmAssistantDraftKind.reminder);
      expect(draft.reminderMode, ReminderMode.alarm);
      expect(draft.date?.day, 20);
      expect(draft.date?.hour, 6);
      expect(draft.title, 'Ke Kebun');
      expect(draft.destinationRoute, 'activity');
    });

    test('buat alarm besok jam 5 subuh -> mode alarm, judul Alarm, default route reminders', () async {
      final intent = await interpreter.interpret('buat alarm besok jam 5 subuh');
      expect(intent.type, FfmAssistantIntentType.createReminder);
      final draft = intent.draft;
      expect(draft, isNotNull);
      expect(draft!.kind, FfmAssistantDraftKind.reminder);
      expect(draft.reminderMode, ReminderMode.alarm);
      expect(draft.date?.day, 20);
      expect(draft.date?.hour, 5);
      expect(draft.title, 'Alarm');
      expect(draft.destinationRoute, 'reminders');
    });

    test('ingatkan bayar tagihan listrik besok jam 7 malam -> route liabilities', () async {
      final intent = await interpreter.interpret('ingatkan bayar tagihan listrik besok jam 7 malam');
      expect(intent.type, FfmAssistantIntentType.createReminder);
      final draft = intent.draft;
      expect(draft, isNotNull);
      expect(draft!.destinationRoute, 'liabilities');
    });

    test('ingatkan saya target beli emas besok jam 9 pagi -> route goals', () async {
      final intent = await interpreter.interpret('ingatkan saya target beli emas besok jam 9 pagi');
      expect(intent.type, FfmAssistantIntentType.createReminder);
      final draft = intent.draft;
      expect(draft, isNotNull);
      expect(draft!.destinationRoute, 'goals');
    });
  });
}
