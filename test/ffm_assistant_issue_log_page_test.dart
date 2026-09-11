import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/di/injection.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_response_feedback_repository.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_unanswered_question_repository.dart';
import 'package:ffm_manager/features/assistant/presentation/pages/ffm_assistant_issue_log_page.dart';

void main() {
  late AppDatabase db;
  late FfmAssistantResponseFeedbackRepository feedbackRepo;
  late FfmAssistantUnansweredQuestionRepository unansweredRepo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = createInMemoryDatabaseForTests();
    if (getIt.isRegistered<AppDatabase>()) {
      getIt.unregister<AppDatabase>();
    }
    getIt.registerSingleton<AppDatabase>(db);

    feedbackRepo = FfmAssistantResponseFeedbackRepository(db);
    if (getIt.isRegistered<FfmAssistantResponseFeedbackRepository>()) {
      getIt.unregister<FfmAssistantResponseFeedbackRepository>();
    }
    getIt.registerSingleton<FfmAssistantResponseFeedbackRepository>(feedbackRepo);

    unansweredRepo = FfmAssistantUnansweredQuestionRepository(db);
    if (getIt.isRegistered<FfmAssistantUnansweredQuestionRepository>()) {
      getIt.unregister<FfmAssistantUnansweredQuestionRepository>();
    }
    getIt.registerSingleton<FfmAssistantUnansweredQuestionRepository>(unansweredRepo);
  });

  tearDown(() async {
    if (getIt.isRegistered<FfmAssistantResponseFeedbackRepository>()) {
      getIt.unregister<FfmAssistantResponseFeedbackRepository>();
    }
    if (getIt.isRegistered<FfmAssistantUnansweredQuestionRepository>()) {
      getIt.unregister<FfmAssistantUnansweredQuestionRepository>();
    }
    if (getIt.isRegistered<AppDatabase>()) {
      final database = getIt<AppDatabase>();
      await database.close();
      getIt.unregister<AppDatabase>();
    }
  });

  group('FfmAssistantIssueLogPage Widget Tests', () {
    testWidgets('Renders empty state when no issues or unanswered questions exist', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: FfmAssistantIssueLogPage(),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Asisten Log & Anomali'), findsOneWidget);
      expect(find.text('Asisten Bekerja Normal'), findsOneWidget);
      expect(find.text('Semua (0)'), findsOneWidget);
      expect(find.text('Jawaban Bermasalah (0)'), findsOneWidget);
      expect(find.text('Gagal Dijawab (0)'), findsOneWidget);
    });

    testWidgets('Renders reported issue and unanswered question with execution trace', (tester) async {
      // 1. Record a reported bad assistant response
      await feedbackRepo.record(
        questionText: 'Berapa sisa saldo kas bulan ini?',
        responseText: 'Saldo kas Anda adalah Rp 50.000.000 (salah angka halusinasi).',
        kind: FfmAssistantResponseFeedbackKind.incorrect,
        sourceMessageId: 'msg-test-trace-1',
        note: 'Saldo keliru dihitung 50jt padahal aslinya cuma 5jt',
        pageContext: 'summary',
        issueMetadata: {
          'problemKind': 'Jawaban keliru',
          'responseOrigin': 'geminiCloud',
          'model': 'gemini-2.5-flash',
          'usedReadCapability': 'read.summary',
          'pluginName': 'balance_sense',
          'processTrace': {
            'origin': 'geminiCloud',
            'elapsedMs': 245,
            'events': [
              {
                'label': 'Menyiapkan permintaan...',
                'elapsedMs': 0,
              },
              {
                'label': 'Membaca ringkasan transaksi bulan ini',
                'elapsedMs': 35,
                'detail': 'read.summary capability',
              },
              {
                'label': 'Gemini Cloud selesai',
                'elapsedMs': 240,
              },
            ],
          },
        },
      );

      // 2. Record an unanswered fallback question
      await unansweredRepo.record(
        rawQuestion: 'Bagaimana cara bayar zakat mal untuk ternak kambing?',
        pageContext: 'zakat_calculator',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: FfmAssistantIssueLogPage(),
        ),
      );

      await tester.pumpAndSettle();

      // Header tabs reflect total count
      expect(find.text('Semua (2)'), findsOneWidget);
      expect(find.text('Jawaban Bermasalah (1)'), findsOneWidget);
      expect(find.text('Gagal Dijawab (1)'), findsOneWidget);

      // Section titles
      expect(find.text('JAWABAN BERMASALAH (1)'), findsOneWidget);
      expect(find.text('PERTANYAAN GAGAL DIJAWAB (1)'), findsOneWidget);

      // Question texts
      expect(find.text('Berapa sisa saldo kas bulan ini?'), findsOneWidget);
      expect(find.text('Bagaimana cara bayar zakat mal untuk ternak kambing?'), findsOneWidget);

      // Origin badge & read capability pill
      expect(
        find.descendant(
          of: find.byType(ExpansionTile),
          matching: find.text('✨ Gemini Cloud'),
        ),
        findsOneWidget,
      );
      expect(find.text('read.summary'), findsOneWidget);

      // Expand the issue card to see execution trace details
      await tester.tap(find.text('Berapa sisa saldo kas bulan ini?'));
      await tester.pumpAndSettle();

      expect(find.text('Trace Eksekusi & Audit'), findsOneWidget);
      expect(find.text('Total: 245ms'), findsOneWidget);
      expect(find.text('Membaca ringkasan transaksi bulan ini'), findsOneWidget);
      expect(find.text('Salin Prompt LLM'), findsOneWidget);
    });

    testWidgets('Search query filters issues dynamically', (tester) async {
      await feedbackRepo.record(
        questionText: 'Saldo BCA berapa?',
        responseText: 'Saldo BCA Rp 10.000.000',
        kind: FfmAssistantResponseFeedbackKind.incorrect,
        sourceMessageId: 'msg-test-search-1',
        issueMetadata: {'responseOrigin': 'orchestrator'},
      );

      await feedbackRepo.record(
        questionText: 'Catat beli kopi susu',
        responseText: 'Draft pengeluaran dibuat',
        kind: FfmAssistantResponseFeedbackKind.unhelpful,
        sourceMessageId: 'msg-test-search-2',
        issueMetadata: {'responseOrigin': 'geminiCloud'},
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: FfmAssistantIssueLogPage(),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Saldo BCA berapa?'), findsOneWidget);
      expect(find.text('Catat beli kopi susu'), findsOneWidget);

      // Search for "kopi"
      await tester.enterText(find.byType(TextField), 'kopi');
      await tester.pumpAndSettle();

      expect(find.text('Catat beli kopi susu'), findsOneWidget);
      expect(find.text('Saldo BCA berapa?'), findsNothing);
    });

    testWidgets('Displays Coba di Chat button and filters by status chips', (tester) async {
      await feedbackRepo.record(
        questionText: 'Berapa total belanja?',
        responseText: 'Total belanja adalah Rp 100.000',
        kind: FfmAssistantResponseFeedbackKind.incorrect,
        sourceMessageId: 'msg-test-status-1',
        issueMetadata: {'responseOrigin': 'orchestrator'},
      );

      final issue2 = await feedbackRepo.record(
        questionText: 'Berapa saldo dompet?',
        responseText: 'Saldo dompet Rp 50.000',
        kind: FfmAssistantResponseFeedbackKind.incorrect,
        sourceMessageId: 'msg-test-status-2',
        issueMetadata: {'responseOrigin': 'geminiCloud'},
      );
      if (issue2 != null) {
        await feedbackRepo.setReviewStatus(
          issue2.id,
          FfmAssistantResponseFeedbackReviewStatus.fixed,
        );
      }

      await unansweredRepo.record(
        rawQuestion: 'Bagaimana cara transfer uang?',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: FfmAssistantIssueLogPage(),
        ),
      );

      await tester.pumpAndSettle();

      // Verify "Tanyakan ke Asisten" button exists for unanswered question
      expect(find.text('Tanyakan ke Asisten'), findsOneWidget);

      // Expand first issue
      await tester.tap(find.text('Berapa total belanja?'));
      await tester.pumpAndSettle();

      // Verify "Coba di Chat" button exists
      expect(find.text('Coba di Chat'), findsOneWidget);

      // Collapse first issue back
      await tester.tap(find.text('Berapa total belanja?').first);
      await tester.pumpAndSettle();

      // Scroll to make status filter chip visible
      await tester.ensureVisible(find.text('⏳ Perlu Review'));
      await tester.tap(find.text('⏳ Perlu Review'));
      await tester.pumpAndSettle();

      expect(find.text('Berapa total belanja?'), findsOneWidget);
      expect(find.text('Berapa saldo dompet?'), findsNothing);

      // Tap status filter chip: "✅ Selesai"
      await tester.ensureVisible(find.text('✅ Selesai'));
      await tester.tap(find.text('✅ Selesai'));
      await tester.pumpAndSettle();

      expect(find.text('Berapa total belanja?'), findsNothing);
      expect(find.text('Berapa saldo dompet?'), findsOneWidget);
    });
  });
}

