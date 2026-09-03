import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_capability_adapters.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_proposal_json_service.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_plan.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_draft_validator.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = createInMemoryDatabaseForTests();
    // Seed an account
    await db.into(db.accounts).insert(
          AccountsCompanion.insert(
            id: 'acc-tunai',
            householdId: 'local-household',
            name: 'Tunai',
            type: 'cash',
            createdAt: DateTime(2026, 1, 1),
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  group('FfmAssistantProposalJsonService - LLM Proposal Parsing', () {
    test('parse single proposal type liability dari LLM', () {
      const rawJson = '''
      {
        "formatVersion": "ffm-assistant-proposal-v1",
        "proposal": {
          "type": "liability",
          "title": "Hutang Bank BRI",
          "party": "Bank BRI",
          "amount": 5000000,
          "dueDate": "2026-12-31",
          "note": "Cicilan usaha"
        }
      }
      ''';

      final result = FfmAssistantProposalJsonService.parse(
        rawJson,
        createdAt: DateTime(2026, 9, 3),
      );

      expect(result.isProposal, isTrue);
      expect(result.draft, isNotNull);
      expect(result.draft!.kind, FfmAssistantDraftKind.liability);
      expect(result.draft!.amount, 5000000);
      expect(result.draft!.title, 'Hutang Bank BRI');
      expect(result.draft!.partyName, 'Bank BRI');
      expect(result.draft!.note, 'Cicilan usaha');
      expect(result.draft!.formValues['dueDate'], '2026-12-31');

      final issues = FfmAssistantDraftValidator.validate(result.draft!);
      expect(issues.any((i) => i.blocksContinuation), isFalse);
    });

    test('parse single proposal type receivable dari LLM', () {
      const rawJson = '''
      {
        "formatVersion": "ffm-assistant-proposal-v1",
        "proposal": {
          "type": "receivable",
          "title": "Piutang Usaha",
          "party": "Pak Joko",
          "amount": 1500000,
          "dueDate": "2026-10-15",
          "note": "Pinjaman modal tani"
        }
      }
      ''';

      final result = FfmAssistantProposalJsonService.parse(
        rawJson,
        createdAt: DateTime(2026, 9, 3),
      );

      expect(result.isProposal, isTrue);
      expect(result.draft, isNotNull);
      expect(result.draft!.kind, FfmAssistantDraftKind.receivable);
      expect(result.draft!.amount, 1500000);
      expect(result.draft!.title, 'Piutang Usaha');
      expect(result.draft!.partyName, 'Pak Joko');
      expect(result.draft!.note, 'Pinjaman modal tani');
      expect(result.draft!.formValues['dueDate'], '2026-10-15');

      final issues = FfmAssistantDraftValidator.validate(result.draft!);
      expect(issues.any((i) => i.blocksContinuation), isFalse);
    });

    test('parseMultiple proposal dari LLM mendukung liability dan receivable', () {
      const rawJson = '''
      {
        "formatVersion": "ffm-assistant-proposal-v1",
        "proposals": [
          {
            "type": "liability",
            "title": "Hutang Motor",
            "party": "Dealer",
            "amount": 3000000
          },
          {
            "type": "receivable",
            "title": "Piutang Bibit",
            "party": "Budi",
            "amount": 750000
          }
        ]
      }
      ''';

      final result = FfmAssistantProposalJsonService.parseMultiple(
        rawJson,
        createdAt: DateTime(2026, 9, 3),
      );

      expect(result.drafts, hasLength(2));
      expect(result.drafts[0].kind, FfmAssistantDraftKind.liability);
      expect(result.drafts[0].amount, 3000000);
      expect(result.drafts[1].kind, FfmAssistantDraftKind.receivable);
      expect(result.drafts[1].amount, 750000);
    });
  });

  group('FfmAssistantInterpreter - Pemahaman Intent dan Draft', () {
    test('catat hutang baru menghasilkan draft liability', () async {
      final interpreter = FfmAssistantInterpreter(db);
      final intent = await interpreter.interpret('catat hutang ke Budi 500000');

      expect(intent.draft, isNotNull);
      expect(intent.draft!.kind, FfmAssistantDraftKind.liability);
      expect(intent.draft!.amount, 500000);
      expect(intent.draft!.partyName, contains('Budi'));
    });

    test('catat piutang baru menghasilkan draft receivable', () async {
      final interpreter = FfmAssistantInterpreter(db);
      final intent = await interpreter.interpret('catat piutang ke Andi 300000');

      expect(intent.draft, isNotNull);
      expect(intent.draft!.kind, FfmAssistantDraftKind.receivable);
      expect(intent.draft!.amount, 300000);
      expect(intent.draft!.partyName, contains('Andi'));
    });

    test('bayar hutang tidak salah dikira hutang baru, melainkan draft pengeluaran', () async {
      final interpreter = FfmAssistantInterpreter(db);
      final intent = await interpreter.interpret('bayar hutang motor 200000 dari Tunai');

      expect(intent.draft, isNotNull);
      // Menghasilkan draft pembayaran hutang (liabilityPayment), BUKAN liability baru
      expect(intent.draft!.kind, FfmAssistantDraftKind.liabilityPayment);
      expect(intent.draft!.amount, 200000);
      expect(intent.draft!.fromAccountName, 'Tunai');
    });

    test('terima pembayaran piutang tidak salah dikira piutang baru, melainkan draft pemasukan', () async {
      final interpreter = FfmAssistantInterpreter(db);
      final intent = await interpreter.interpret('terima pembayaran piutang 300000 ke Tunai');

      expect(intent.draft, isNotNull);
      // Menghasilkan draft penerimaan piutang (receivablePayment), BUKAN receivable baru
      expect(intent.draft!.kind, FfmAssistantDraftKind.receivablePayment);
      expect(intent.draft!.amount, 300000);
      expect(intent.draft!.toAccountName, 'Tunai');
    });
  });

  group('FfmAssistantCapabilityAdapterRegistry - Simpan Eksekusi', () {
    test('simpan draft liability mengeksekusi dan tersimpan di database dengan benar', () async {
      final registry = FfmAssistantCapabilityAdapterRegistry(
        database: db,
        householdId: 'local-household',
      );

      final handler = registry.handlers['mutate.save_draft']!;
      final result = await handler(
        const FfmAssistantActionStep(
          id: 'step-1',
          capabilityId: 'mutate.save_draft',
          parameters: {
            'kind': 'liability',
            'title': 'Kredit Motor',
            'party': 'FIF',
            'amount': 15000000,
            'dueDate': '2027-01-01',
            'note': 'Cicilan bulanan',
            '_idempotencyKey': 'test-save-liability',
          },
        ),
      );

      expect(result.isSuccess, isTrue);

      final liabilities = await db.select(db.liabilities).get();
      expect(liabilities, hasLength(1));
      expect(liabilities.first.name, 'Kredit Motor - FIF');
      expect(liabilities.first.originalAmount, 15000000);
      expect(liabilities.first.remainingBalance, 15000000);
      expect(liabilities.first.dueDate, DateTime(2027, 1, 1));
      expect(liabilities.first.note, 'Cicilan bulanan');
    });

    test('simpan draft receivable mengeksekusi dan tersimpan di database dengan benar', () async {
      final registry = FfmAssistantCapabilityAdapterRegistry(
        database: db,
        householdId: 'local-household',
      );

      final handler = registry.handlers['mutate.save_draft']!;
      final result = await handler(
        const FfmAssistantActionStep(
          id: 'step-2',
          capabilityId: 'mutate.save_draft',
          parameters: {
            'kind': 'receivable',
            'title': 'Piutang Pupuk',
            'party': 'Pak Tani',
            'amount': 2500000,
            'dueDate': '2026-11-30',
            'note': 'Jatuh tempo pasca panen',
            '_idempotencyKey': 'test-save-receivable',
          },
        ),
      );

      expect(result.isSuccess, isTrue);

      final receivables = await db.select(db.receivables).get();
      expect(receivables, hasLength(1));
      expect(receivables.first.name, 'Piutang Pupuk - Pak Tani');
      expect(receivables.first.originalAmount, 2500000);
      expect(receivables.first.remainingBalance, 2500000);
      expect(receivables.first.dueDate, DateTime(2026, 11, 30));
      expect(receivables.first.note, 'Jatuh tempo pasca panen');
    });
  });
}
