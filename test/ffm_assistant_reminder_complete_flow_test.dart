import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_proposal_json_service.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_planner.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/reminder/domain/entities/reminder_entity.dart';

void main() {
  group(
    'FfmAssistantProposalJsonService - Super Complete Reminder Proposals',
    () {
      final now = DateTime(2026, 9, 13, 10, 0);

      test('parses reminder proposal with explicit time HH:mm', () {
        final json = jsonEncode({
          'formatVersion': 'ffm-assistant-proposal-v1',
          'proposal': {
            'type': 'reminder',
            'title': 'Bayar Listrik PLN',
            'targetDate': '2026-09-14',
            'time': '08:00',
            'note': 'Gunakan rekening BCA',
            'soundName': 'Gentle Bells',
          },
        });

        final result = FfmAssistantProposalJsonService.parse(
          json,
          createdAt: now,
        );
        expect(result.draft, isNotNull);

        final draft = result.draft!;
        expect(draft.kind, FfmAssistantDraftKind.reminder);
        expect(draft.title, 'Bayar Listrik PLN');
        expect(draft.note, 'Gunakan rekening BCA');
        expect(draft.soundName, 'Gentle Bells');
        expect(draft.date?.year, 2026);
        expect(draft.date?.month, 9);
        expect(draft.date?.day, 14);
        expect(draft.date?.hour, 8);
        expect(draft.date?.minute, 0);
        expect(draft.formValues['time'], '08:00');
        expect(draft.formValues['targetDate'], '2026-09-14');
        expect(draft.formValues['hasExplicitTime'], isTrue);
      });

      test(
        'parses reminder proposal with natural language time like "8 malam"',
        () {
          final json = jsonEncode({
            'formatVersion': 'ffm-assistant-proposal-v1',
            'proposal': {
              'type': 'reminder',
              'title': 'Minum Vitamin',
              'targetDate': '2026-09-15',
              'time': '8 malam',
            },
          });

          final result = FfmAssistantProposalJsonService.parse(
            json,
            createdAt: now,
          );
          expect(result.draft, isNotNull);

          final draft = result.draft!;
          expect(draft.date?.year, 2026);
          expect(draft.date?.month, 9);
          expect(draft.date?.day, 15);
          expect(draft.date?.hour, 20);
          expect(draft.date?.minute, 0);
          expect(draft.formValues['time'], '20:00');
        },
      );

      test('parses reminder proposal with dot time format like "14.30"', () {
        final json = jsonEncode({
          'formatVersion': 'ffm-assistant-proposal-v1',
          'proposal': {
            'type': 'reminder',
            'title': 'Rapat Kerja',
            'targetDate': '2026-09-16',
            'time': '14.30',
          },
        });

        final result = FfmAssistantProposalJsonService.parse(
          json,
          createdAt: now,
        );
        expect(result.draft, isNotNull);

        final draft = result.draft!;
        expect(draft.date?.hour, 14);
        expect(draft.date?.minute, 30);
        expect(draft.formValues['time'], '14:30');
      });

      test('rejects invalid weekly weekday values', () {
        final json = jsonEncode({
          'formatVersion': 'ffm-assistant-proposal-v1',
          'proposal': {
            'type': 'reminder',
            'title': 'Rapat',
            'targetDate': '2026-09-16',
            'time': '14:30',
            'recurrence': 'weekly',
            'weekdays': [0],
          },
        });

        final result = FfmAssistantProposalJsonService.parse(
          json,
          createdAt: now,
        );
        expect(result.draft, isNull);
        expect(result.error, contains('Hari pengulangan'));
      });
    },
  );

  group('FfmAssistantInterpreter - Reminder Time & Clarification Flow', () {
    late AppDatabase database;
    late FfmAssistantInterpreter interpreter;
    final fixedClock = DateTime(2026, 9, 13, 10, 0);

    setUp(() {
      database = createInMemoryDatabaseForTests();
      interpreter = FfmAssistantInterpreter(database, clock: () => fixedClock);
    });

    tearDown(() async {
      await database.close();
    });

    test('requests clarification when user creates reminder without specifying hour/time', () async {
      final intent = await interpreter.interpret(
        'ingatkan bayar tagihan listrik besok',
      );

      expect(intent.draft, isNotNull);
      expect(intent.draft?.kind, FfmAssistantDraftKind.reminder);
      expect(intent.draft?.title?.toLowerCase(), contains('listrik'));
      expect(intent.draft?.formValues['hasExplicitTime'], isFalse);

      // Clarification must be asked
      expect(intent.clarification, contains('Mau saya ingatkan jam berapa'));
      expect(intent.response, contains('Mau saya ingatkan jam berapa'));
      expect(intent.confidence, lessThan(0.9));
    });

    test(
      'creates super complete draft right away when time is provided',
      () async {
        final intent = await interpreter.interpret(
          'ingatkan bayar tagihan listrik besok jam 8 pagi',
        );

        expect(intent.draft, isNotNull);
        final draft = intent.draft!;
        expect(draft.kind, FfmAssistantDraftKind.reminder);
        expect(draft.formValues['hasExplicitTime'], isTrue);
        expect(draft.date?.day, 14); // besok dari 13 September
        expect(draft.date?.hour, 8);
        expect(draft.date?.minute, 0);
        expect(draft.formValues['time'], '08:00');

        // Super complete draft: no clarification needed, ready to confirm
        expect(intent.clarification, isNull);
        expect(intent.response, contains('Draft pengingat sudah siap'));
        expect(intent.confidence, 0.9);
      },
    );

    test('active reminder draft is updated with time when user replies in next turn', () async {
      // Turn 1: user asks for reminder without time
      final initialIntent = await interpreter.interpret(
        'ingatkan bayar pdam besok',
      );
      final activeDraft = initialIntent.draft!;
      expect(activeDraft.formValues['hasExplicitTime'], isFalse);

      // Turn 2: user replies "jam 8 pagi"
      final revisedIntent = await interpreter.interpret(
        'jam 8 pagi',
        activeDraft: activeDraft,
      );

      expect(revisedIntent.draft, isNotNull);
      final revisedDraft = revisedIntent.draft!;
      expect(revisedDraft.formValues['hasExplicitTime'], isTrue);
      expect(revisedDraft.date?.hour, 8);
      expect(revisedDraft.date?.minute, 0);
      expect(revisedDraft.formValues['time'], '08:00');
      expect(revisedIntent.response, contains('Jam diubah ke 08:00 WIB'));
    });

    test(
      'buat pengingat menghasilkan mode notification secara default',
      () async {
        final intent = await interpreter.interpret(
          'buat pengingat bayar air besok jam 9 pagi',
        );

        expect(intent.draft, isNotNull);
        final draft = intent.draft!;
        expect(draft.reminderMode, ReminderMode.notification);
        expect(draft.formValues['reminderMode'], 'notification');
        expect(draft.formValues['mode'], 'notification');
      },
    );

    test('buat alarm menghasilkan mode alarm eksplisit', () async {
      final intent = await interpreter.interpret(
        'buat alarm bangun pagi besok jam 5 pagi',
      );

      expect(intent.draft, isNotNull);
      final draft = intent.draft!;
      expect(draft.reminderMode, ReminderMode.alarm);
      expect(draft.formValues['reminderMode'], 'alarm');
      expect(draft.formValues['mode'], 'alarm');
    });

    test('action plan untuk reminder berisi read.reminders, draft.reminder, mutate.save_draft, dan verify.saved_draft', () {
      final draft = FfmAssistantDraft(
        kind: FfmAssistantDraftKind.reminder,
        createdAt: DateTime(2026, 9, 13),
        title: 'Beli Token',
        date: DateTime(2026, 9, 14, 8),
        reminderMode: ReminderMode.notification,
        formValues: const {
          'time': '08:00',
          'targetDate': '2026-09-14',
          'reminderMode': 'notification',
          'mode': 'notification',
        },
      );
      final intent = FfmAssistantIntent(
        rawText: 'buat pengingat beli token',
        normalizedText: 'buat pengingat beli token',
        type: FfmAssistantIntentType.createReminder,
        draft: draft,
      );
      final plan = const FfmAssistantActionPlanner().planFor(intent);
      expect(plan, isNotNull);
      expect(
        plan!.steps.any((s) => s.capabilityId == 'read.reminders'),
        isTrue,
      );
      expect(plan.steps.any((s) => s.capabilityId == 'draft.reminder'), isTrue);
      expect(
        plan.steps.any((s) => s.capabilityId == 'mutate.save_draft'),
        isTrue,
      );
      expect(
        plan.steps.any((s) => s.capabilityId == 'verify.saved_draft'),
        isTrue,
      );
      expect(plan.steps.last.capabilityId, 'verify.saved_draft');
    });
  });

  group('Reminder List - Smart Sorting', () {
    test('sorts active upcoming reminders first (closest time), past-due at bottom', () {
      final now = DateTime(2026, 9, 13, 12, 0);

      final upcomingSoon = ReminderEntity(
        id: 'r1',
        householdId: 'h1',
        title: 'Beli token listrik (sebentar lagi)',
        scheduledAt: now.add(const Duration(hours: 1)),
        recurrenceType: ReminderRecurrenceType.once,
        weekdays: const [],
        notificationId: 1,
        isActive: true,
      );

      final upcomingLater = ReminderEntity(
        id: 'r2',
        householdId: 'h1',
        title: 'Bayar internet besok',
        scheduledAt: now.add(const Duration(days: 1)),
        recurrenceType: ReminderRecurrenceType.once,
        weekdays: const [],
        notificationId: 2,
        isActive: true,
      );

      final pastDue = ReminderEntity(
        id: 'r3',
        householdId: 'h1',
        title: 'Alaram kemarin (sudah lewat)',
        scheduledAt: now.subtract(const Duration(hours: 3)),
        recurrenceType: ReminderRecurrenceType.once,
        weekdays: const [],
        notificationId: 3,
        isActive: true, // active switch on, but past-due
      );

      final inactive = ReminderEntity(
        id: 'r4',
        householdId: 'h1',
        title: 'Dimatikan user',
        scheduledAt: now.add(const Duration(hours: 4)),
        recurrenceType: ReminderRecurrenceType.once,
        weekdays: const [],
        notificationId: 4,
        isActive: false,
      );

      final list = [pastDue, upcomingLater, inactive, upcomingSoon];

      list.sort((a, b) {
        final aIsPastDue =
            a.recurrenceType == ReminderRecurrenceType.once &&
            a.scheduledAt.isBefore(now);
        final bIsPastDue =
            b.recurrenceType == ReminderRecurrenceType.once &&
            b.scheduledAt.isBefore(now);
        final aIsUpcoming = a.isActive && !aIsPastDue;
        final bIsUpcoming = b.isActive && !bIsPastDue;

        if (aIsUpcoming && !bIsUpcoming) return -1;
        if (!aIsUpcoming && bIsUpcoming) return 1;

        if (aIsUpcoming && bIsUpcoming) {
          return a.scheduledAt.compareTo(b.scheduledAt);
        } else {
          return b.scheduledAt.compareTo(a.scheduledAt);
        }
      });

      // Upcoming soon must be first
      expect(list[0].id, 'r1');
      // Upcoming later must be second
      expect(list[1].id, 'r2');
      // Inactive / past due at bottom
      expect(list.sublist(2).map((r) => r.id), containsAll(['r3', 'r4']));
    });
  });
}
