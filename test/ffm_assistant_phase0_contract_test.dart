import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_capability_adapters.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_database_reference_resolver.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_proposal_json_service.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_plan.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_planner.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_capability_executor.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_reference_resolver.dart';

Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  test(
    'seluruh fixture parser memiliki matrix dan parameter planner lengkap',
    () {
      final proposalFixture = _fixture('assistant_phase0_all_llm_drafts.json');
      final expectedFixture = _fixture(
        'assistant_phase0_all_expected_rows.json',
      );
      final matrixFixture = _fixture('assistant_phase0_field_matrix.json');
      final result = FfmAssistantProposalJsonService.parseMultiple(
        jsonEncode(proposalFixture),
        createdAt: DateTime(2026, 9, 13),
      );
      final expectedRows = (expectedFixture['rows'] as List)
          .cast<Map<String, dynamic>>();
      final canonical = (matrixFixture['canonical'] as Map)
          .cast<String, dynamic>();

      expect(result.error, isNull);
      expect(result.drafts, hasLength(expectedRows.length));
      for (var index = 0; index < result.drafts.length; index++) {
        final draft = result.drafts[index];
        final expected = expectedRows[index];
        expect(draft.kind.name, expected['kind']);
        expect(canonical, contains(draft.kind.name));
        final plan = const FfmAssistantActionPlanner().planFor(
          FfmAssistantIntent(
            rawText: 'fixture ${draft.kind.name}',
            normalizedText: 'fixture ${draft.kind.name}',
            type: FfmAssistantIntentType.createExpense,
            draft: draft,
          ),
        );
        expect(plan, isNotNull, reason: draft.kind.name);
        final parameters = plan!.steps
            .singleWhere((step) => step.id == 'save')
            .parameters;
        expect(
          FfmAssistantActionPlanner.missingRequiredParameters(
            draft,
            parameters,
          ),
          isEmpty,
          reason: draft.kind.name,
        );
        for (final key in (expected['canonical'] as List).cast<String>()) {
          expect(parameters, contains(key), reason: '${draft.kind.name}: $key');
          expect(
            parameters[key],
            isNotNull,
            reason: '${draft.kind.name}: $key',
          );
        }
      }
    },
  );

  test('fixture LLM mempertahankan field penting sampai plan save', () {
    final fixture = _fixture('assistant_phase0_llm_drafts.json');
    final result = FfmAssistantProposalJsonService.parseMultiple(
      jsonEncode(fixture),
      createdAt: DateTime(2026, 9, 13),
    );

    expect(result.drafts, hasLength(3));
    final expense = result.drafts.singleWhere(
      (draft) => draft.kind == FfmAssistantDraftKind.expense,
    );
    final plan = const FfmAssistantActionPlanner().planFor(
      FfmAssistantIntent(
        rawText: 'catat belanja',
        normalizedText: 'catat belanja',
        type: FfmAssistantIntentType.createExpense,
        draft: expense,
      ),
    )!;
    final parameters = plan.steps
        .singleWhere((step) => step.id == 'save')
        .parameters;

    expect(parameters['amount'], 75000);
    expect(parameters['fromAccount'], 'BCA');
    expect(parameters['category'], 'Belanja');
    expect(parameters['merchant'], 'Supermarket');
    expect(parameters['assistantMerchantName'], 'Supermarket');
    expect(parameters['tags'], 'bulanan');
    expect(parameters['note'], 'Belanja dapur');
    expect(parameters['date'], '2026-09-13T08:30:00.000');
  });

  test(
    'database resolver mengembalikan resolved, missing, dan ambiguous',
    () async {
      final database = createInMemoryDatabaseForTests();
      addTearDown(database.close);
      const householdId = 'phase0-household';
      final now = DateTime(2026, 9, 13);
      await database
          .into(database.accounts)
          .insert(
            AccountsCompanion.insert(
              id: 'account-bca',
              householdId: householdId,
              name: 'BCA',
              type: 'bank',
              createdAt: now,
            ),
          );
      await database
          .into(database.categories)
          .insert(
            CategoriesCompanion.insert(
              id: 'category-belanja',
              householdId: householdId,
              name: 'Belanja',
              type: 'expense',
              createdAt: now,
            ),
          );
      await database
          .into(database.merchants)
          .insert(
            MerchantsCompanion.insert(
              id: 'merchant-supermarket',
              householdId: householdId,
              name: 'Supermarket',
              createdAt: now,
            ),
          );
      await database
          .into(database.tags)
          .insert(
            TagsCompanion.insert(
              id: 'tag-bulanan',
              householdId: householdId,
              name: 'Bulanan',
              createdAt: now,
            ),
          );
      await database
          .into(database.goals)
          .insert(
            GoalsCompanion.insert(
              id: 'goal-darurat',
              householdId: householdId,
              name: 'Dana Darurat',
              targetAmount: 1000000,
              createdAt: now,
            ),
          );
      await database
          .into(database.activitySessions)
          .insert(
            ActivitySessionsCompanion.insert(
              id: 'activity-parent-1',
              householdId: householdId,
              title: 'Pekerjaan Rumah',
              startedAt: now,
              createdAt: now,
            ),
          );

      final resolver = FfmAssistantDatabaseReferenceResolver(
        database: database,
        householdId: householdId,
      );
      expect(
        (await resolver.account('bca')).status,
        FfmAssistantReferenceStatus.resolved,
      );
      expect(
        (await resolver.category('Belanja', type: 'expense')).value?.id,
        'category-belanja',
      );
      expect(
        (await resolver.merchant('supermarket')).status,
        FfmAssistantReferenceStatus.resolved,
      );
      expect(
        (await resolver.tag('bulanan')).status,
        FfmAssistantReferenceStatus.resolved,
      );
      expect(
        (await resolver.goal('dana darurat')).status,
        FfmAssistantReferenceStatus.resolved,
      );
      expect(
        (await resolver.activity('activity-parent-1')).status,
        FfmAssistantReferenceStatus.resolved,
      );
      expect(
        (await resolver.account('Jago')).status,
        FfmAssistantReferenceStatus.missing,
      );

      final fixture = _fixture('assistant_phase0_llm_drafts.json');
      final parsed = FfmAssistantProposalJsonService.parseMultiple(
        jsonEncode(fixture),
        createdAt: now,
      );
      final expense = parsed.drafts.singleWhere(
        (draft) => draft.kind == FfmAssistantDraftKind.expense,
      );
      final plan = const FfmAssistantActionPlanner().planFor(
        FfmAssistantIntent(
          rawText: 'catat belanja',
          normalizedText: 'catat belanja',
          type: FfmAssistantIntentType.createExpense,
          draft: expense,
        ),
      )!;
      final controller = FfmAssistantActionPlanController()
        ..register(plan)
        ..markAwaitingConfirmation(plan.id)
        ..confirm(plan.id);
      final adapters = FfmAssistantCapabilityAdapterRegistry(
        database: database,
        householdId: householdId,
        clock: () => now,
      );
      final completed = await FfmAssistantCapabilityExecutor(
        controller: controller,
        handlers: adapters.handlers,
      ).execute(plan.id);
      expect(completed?.status, FfmAssistantActionPlanStatus.completed);
      final expected = _fixture('assistant_phase0_expected_rows.json');
      final expectedRow = (expected['transactions'] as List).single;
      final rows = await (database.select(
        database.transactions,
      )..where((row) => row.householdId.equals(householdId))).get();
      expect(rows, hasLength(1));
      expect(rows.single.amount, expectedRow['amount']);
      expect(rows.single.accountId, expectedRow['accountId']);
      expect(rows.single.categoryId, expectedRow['categoryId']);
      expect(rows.single.merchantId, expectedRow['merchantId']);
      expect(rows.single.note, expectedRow['note']);

      await database
          .into(database.accounts)
          .insert(
            AccountsCompanion.insert(
              id: 'account-bca-2',
              householdId: householdId,
              name: 'bCa',
              type: 'cash',
              createdAt: now,
            ),
          );
      expect(
        (await resolver.account('BCA')).status,
        FfmAssistantReferenceStatus.ambiguous,
      );
    },
  );
}
