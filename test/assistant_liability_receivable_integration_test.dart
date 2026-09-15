import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_capability_adapters.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_proposal_json_service.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_plan.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_planner.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_capability_executor.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_draft_validator.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = createInMemoryDatabaseForTests();
    // Seed an account
    await db
        .into(db.accounts)
        .insert(
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

    test(
      'parseMultiple proposal dari LLM mendukung liability dan receivable',
      () {
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
      },
    );
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
      final intent = await interpreter.interpret(
        'catat piutang ke Andi 300000',
      );

      expect(intent.draft, isNotNull);
      expect(intent.draft!.kind, FfmAssistantDraftKind.receivable);
      expect(intent.draft!.amount, 300000);
      expect(intent.draft!.partyName, contains('Andi'));
    });

    test('bayar hutang tidak salah dikira hutang baru, melainkan draft pengeluaran', () async {
      final interpreter = FfmAssistantInterpreter(db);
      final intent = await interpreter.interpret(
        'bayar hutang motor 200000 dari Tunai',
      );

      expect(intent.draft, isNotNull);
      // Menghasilkan draft pembayaran hutang (liabilityPayment), BUKAN liability baru
      expect(intent.draft!.kind, FfmAssistantDraftKind.liabilityPayment);
      expect(intent.draft!.amount, 200000);
      expect(intent.draft!.fromAccountName, 'Tunai');
    });

    test('terima pembayaran piutang tidak salah dikira piutang baru, melainkan draft pemasukan', () async {
      final interpreter = FfmAssistantInterpreter(db);
      final intent = await interpreter.interpret(
        'terima pembayaran piutang 300000 ke Tunai',
      );

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

  group('Acceptance canonical database boundary', () {
    Future<FfmAssistantActionPlan?> executePlan(
      FfmAssistantActionPlan plan,
    ) async {
      final controller =
          FfmAssistantActionPlanController(now: () => DateTime(2026, 9, 3))
            ..register(plan)
            ..markAwaitingConfirmation(plan.id)
            ..confirm(plan.id);
      return FfmAssistantCapabilityExecutor(
        controller: controller,
        handlers: FfmAssistantCapabilityAdapterRegistry(
          database: db,
          householdId: 'local-household',
          clock: () => DateTime(2026, 9, 3),
        ).handlers,
      ).execute(plan.id);
    }

    test(
      'JSON master data sumber pemasukan menyimpan row canonical dan verifier',
      () async {
        final parsed = FfmAssistantProposalJsonService.parse('''
        {"formatVersion":"ffm-assistant-proposal-v1","proposal":
        {"type":"master_data","target":"sumber_pemasukan","name":"Panen Sawah",
        "fields":{"details":"Musim 2026"}}}
      ''', createdAt: DateTime(2026, 9, 3));
        final draft = parsed.draft!;
        final plan = FfmAssistantActionPlanner(now: () => DateTime(2026, 9, 3))
            .planFor(
              FfmAssistantIntent(
                rawText: 'buat sumber pemasukan Panen Sawah',
                normalizedText: 'buat sumber pemasukan panen sawah',
                type: FfmAssistantIntentType.createMasterData,
                draft: draft,
              ),
            )!;
        expect(
          plan.steps.map((step) => step.capabilityId),
          contains('verify.saved_draft'),
        );
        final executed = await executePlan(plan);
        expect(
          executed?.status,
          FfmAssistantActionPlanStatus.completed,
          reason:
              executed?.blockedReason ??
              executed?.steps
                  .map((step) => '${step.id}:${step.error}')
                  .join(', '),
        );
        final rows =
            (await (db.select(db.transactionParties)..where(
                      (row) => row.householdId.equals('local-household'),
                    ))
                    .get())
                .where((row) => row.name == 'Panen Sawah')
                .toList();
        expect(rows, hasLength(1));
        expect(rows.single.kind, 'income_source');
        expect(rows.single.role, 'Sumber pemasukan');
        expect(
          (await db.select(db.categories).get()).where(
            (row) => row.name == 'Panen Sawah',
          ),
          isEmpty,
        );
      },
    );

    test('payment memakai relasi target dan retry idempotent, payload berbeda ditolak', () async {
      await db
          .into(db.liabilities)
          .insert(
            LiabilitiesCompanion.insert(
              id: 'liability-1',
              householdId: 'local-household',
              name: 'Hutang Budi',
              originalAmount: 1000,
              remainingBalance: 1000,
              startDate: DateTime(2026, 1, 1),
              createdAt: DateTime(2026, 1, 1),
            ),
          );
      final parameters = <String, Object?>{
        'kind': 'liabilityPayment',
        'entity': 'liability',
        'targetId': 'liability-1',
        'amount': 250,
        'date': '2026-09-03T00:00:00.000',
        'accountId': 'acc-tunai',
        '_idempotencyKey': 'payment-key',
      };
      final handler = FfmAssistantCapabilityAdapterRegistry(
        database: db,
        householdId: 'local-household',
        clock: () => DateTime(2026, 9, 3),
      ).handlers;
      final step = FfmAssistantActionStep(
        id: 'payment',
        capabilityId: 'mutate.debt_payment',
        parameters: parameters,
      );
      expect((await handler['mutate.debt_payment']!(step)).isSuccess, isTrue);
      expect((await handler['mutate.debt_payment']!(step)).isSuccess, isTrue);
      final liability = await (db.select(
        db.liabilities,
      )..where((r) => r.id.equals('liability-1'))).getSingle();
      expect(liability.remainingBalance, 750);
      expect(
        await (db.select(
          db.transactions,
        )..where((r) => r.source.equals('liability_payment'))).get(),
        hasLength(1),
      );
      final verified = await handler['verify.debt_payment']!(
        FfmAssistantActionStep(
          id: 'verify-payment',
          capabilityId: 'verify.debt_payment',
          parameters: parameters,
        ),
      );
      expect(verified.isSuccess, isTrue);
      final wrongDate = await handler['verify.debt_payment']!(
        FfmAssistantActionStep(
          id: 'verify-wrong-date',
          capabilityId: 'verify.debt_payment',
          parameters: {...parameters, 'date': '2026-09-04'},
        ),
      );
      expect(wrongDate.isSuccess, isFalse);
      final mismatch = await handler['mutate.debt_payment']!(
        FfmAssistantActionStep(
          id: 'payment-2',
          capabilityId: 'mutate.debt_payment',
          parameters: {...parameters, 'amount': 300},
        ),
      );
      expect(mismatch.isSuccess, isFalse);
    });

    test('payment menolak rekening dari household lain dan verifier menolak tanggal berbeda', () async {
      await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(
              id: 'other-account',
              householdId: 'other-household',
              name: 'Other',
              type: 'cash',
              createdAt: DateTime(2026, 1, 1),
            ),
          );
      await db
          .into(db.receivables)
          .insert(
            ReceivablesCompanion.insert(
              id: 'receivable-1',
              householdId: 'local-household',
              name: 'Piutang Andi',
              originalAmount: 500,
              remainingBalance: 500,
              startDate: DateTime(2026, 1, 1),
              createdAt: DateTime(2026, 1, 1),
            ),
          );
      final handler = FfmAssistantCapabilityAdapterRegistry(
        database: db,
        householdId: 'local-household',
        clock: () => DateTime(2026, 9, 3),
      ).handlers;
      final result = await handler['mutate.debt_payment']!(
        FfmAssistantActionStep(
          id: 'foreign',
          capabilityId: 'mutate.debt_payment',
          parameters: {
            'entity': 'receivable',
            'targetId': 'receivable-1',
            'amount': 100,
            'accountId': 'other-account',
            'date': '2026-09-03',
            '_idempotencyKey': 'foreign-key',
          },
        ),
      );
      expect(result.isSuccess, isFalse);
      expect(
        await (db.select(
          db.transactions,
        )..where((r) => r.householdId.equals('local-household'))).get(),
        isEmpty,
      );
    });
  });
}
