import 'package:drift/drift.dart' show Value;
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_financial_snapshot_service.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_proposal_json_service.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FfmAssistantProposalJsonService Goal Proposals', () {
    test('parse goal_deposit proposal creates goalDeposit draft', () {
      final json = '''
      {
        "formatVersion": "ffm-assistant-proposal-v1",
        "proposal": {
          "type": "goal_deposit",
          "goal": "Liburan ke Bali",
          "amount": 500000,
          "fromAccount": "BCA",
          "note": "Setor tabungan bulanan"
        }
      }
      ''';

      final result = FfmAssistantProposalJsonService.parse(
        json,
        createdAt: DateTime(2026, 9, 1),
      );

      expect(result.error, isNull);
      expect(result.draft, isNotNull);
      expect(result.draft!.kind, FfmAssistantDraftKind.goalDeposit);
      expect(result.draft!.goalName, 'Liburan ke Bali');
      expect(result.draft!.amount, 500000);
      expect(result.draft!.fromAccountName, 'BCA');
      expect(result.draft!.note, 'Setor tabungan bulanan');
    });

    test('parse goal_usage proposal creates goalUsage draft', () {
      final json = '''
      {
        "formatVersion": "ffm-assistant-proposal-v1",
        "proposal": {
          "type": "goal_usage",
          "goal": "Dana Darurat",
          "amount": 250000,
          "toAccount": "Kas",
          "note": "Beli obat"
        }
      }
      ''';

      final result = FfmAssistantProposalJsonService.parse(
        json,
        createdAt: DateTime(2026, 9, 1),
      );

      expect(result.error, isNull);
      expect(result.draft, isNotNull);
      expect(result.draft!.kind, FfmAssistantDraftKind.goalUsage);
      expect(result.draft!.goalName, 'Dana Darurat');
      expect(result.draft!.amount, 250000);
      expect(result.draft!.toAccountName, 'Kas');
      expect(result.draft!.note, 'Beli obat');
    });

    test('parse goal with action deposit routes to goalDeposit', () {
      final json = '''
      {
        "formatVersion": "ffm-assistant-proposal-v1",
        "proposal": {
          "type": "goal",
          "action": "deposit",
          "goal": "Beli Laptop",
          "amount": 1000000
        }
      }
      ''';

      final result = FfmAssistantProposalJsonService.parse(
        json,
        createdAt: DateTime(2026, 9, 1),
      );

      expect(result.error, isNull);
      expect(result.draft, isNotNull);
      expect(result.draft!.kind, FfmAssistantDraftKind.goalDeposit);
      expect(result.draft!.goalName, 'Beli Laptop');
      expect(result.draft!.amount, 1000000);
    });

    test('parseMultiple supports goal_deposit in batch proposals', () {
      final json = '''
      {
        "formatVersion": "ffm-assistant-proposal-v1",
        "proposals": [
          {
            "type": "transaction",
            "kind": "income",
            "amount": 5000000,
            "title": "Gaji"
          },
          {
            "type": "goal_deposit",
            "goal": "Tabungan Rumah",
            "amount": 1000000
          }
        ]
      }
      ''';

      final result = FfmAssistantProposalJsonService.parseMultiple(
        json,
        createdAt: DateTime(2026, 9, 1),
      );

      expect(result.error, isNull);
      expect(result.drafts.length, 2);
      expect(result.drafts[0].kind, FfmAssistantDraftKind.income);
      expect(result.drafts[1].kind, FfmAssistantDraftKind.goalDeposit);
      expect(result.drafts[1].goalName, 'Tabungan Rumah');
      expect(result.drafts[1].amount, 1000000);
    });
  });

  group('FfmAssistantFinancialSnapshotService Master Data Context', () {
    test('buildMasterDataContext includes target_aktif', () async {
      final database = createInMemoryDatabaseForTests();
      final snapshotService = FfmAssistantFinancialSnapshotService(database);

      await database.into(database.goals).insert(
            GoalsCompanion.insert(
              id: 'g-1',
              householdId: 'test-household',
              name: 'Dana Darurat',
              targetAmount: 10000000,
              targetDate: Value(DateTime(2026, 12, 31)),
              createdAt: DateTime(2026, 8, 1),
            ),
          );

      final context = await snapshotService.buildMasterDataContext(
        householdId: 'test-household',
      );

      expect(context, contains('target_aktif=Dana Darurat'));
      await database.close();
    });
  });

  group('FfmAssistantInterpreter Deterministic Goal Intent', () {
    test('simpan uang untuk target creates goalDeposit draft', () async {
      final database = createInMemoryDatabaseForTests();
      final interpreter = FfmAssistantInterpreter(database);

      final intent = await interpreter.interpret(
        'simpan uang 500rb untuk target liburan',
        currentDestination: FfmAssistantDestination.goals,
      );

      expect(intent.type, FfmAssistantIntentType.createGoalDeposit);
      expect(intent.draft?.kind, FfmAssistantDraftKind.goalDeposit);
      expect(intent.draft?.amount, 500000);
      expect(intent.draft?.goalName?.toLowerCase(), contains('liburan'));
      await database.close();
    });
  });

  group('Gemini navigation JSON parsing', () {
    test('top-level navigation field (instruksi Gemini) creates navigation draft',
        () {
      final json =
          '{"formatVersion":"ffm-assistant-proposal-v1","navigation":"masterData"}';

      final result = FfmAssistantProposalJsonService.parseMultiple(
        json,
        createdAt: DateTime(2026, 9, 1),
      );

      expect(result.drafts, hasLength(1));
      expect(result.drafts.single.formValues['navigation'], 'true');
      expect(result.drafts.single.formValues['destination'], 'masterData');
    });

    test('nested proposal.type navigation tetap terdukung (regresi)', () {
      final json =
          '{"formatVersion":"ffm-assistant-proposal-v1","proposal":{"type":"navigation","navigation":"transactions"}}';

      final result = FfmAssistantProposalJsonService.parseMultiple(
        json,
        createdAt: DateTime(2026, 9, 1),
      );

      expect(result.drafts, hasLength(1));
      expect(result.drafts.single.formValues['navigation'], 'true');
      expect(result.drafts.single.formValues['destination'], 'transactions');
    });

    test('interpreter menerjemahkan navigation top-level jadi openPage intent',
        () async {
      final database = createInMemoryDatabaseForTests();
      final interpreter = FfmAssistantInterpreter(database);

      final intent = await interpreter.interpret(
        'pindah ke data utama',
        currentDestination: FfmAssistantDestination.summary,
      );

      expect(intent.type, FfmAssistantIntentType.openPage);
      expect(intent.destination, FfmAssistantDestination.masterData);
      await database.close();
    });
  });
}
