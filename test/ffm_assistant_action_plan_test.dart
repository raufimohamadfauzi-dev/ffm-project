import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_plan.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_capabilities.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';

void main() {
  test(
    'registry mencakup seluruh destination dan capability mutation aman',
    () {
      for (final destination in FfmAssistantDestination.values) {
        expect(
          FfmAssistantCapabilityRegistry.find('navigate.${destination.name}'),
          isNotNull,
        );
      }

      final save = FfmAssistantCapabilityRegistry.find('mutate.save_draft');
      expect(save, isNotNull);
      expect(save!.requiresConfirmation, isTrue);
      expect(save.canRunWithoutConfirmation, isFalse);
    },
  );

  test('action plan menganggap mutation membutuhkan konfirmasi', () {
    final plan = FfmAssistantActionPlan(
      id: 'plan-1',
      summary: 'Simpan pengeluaran',
      createdAt: DateTime(2026, 8, 23),
      steps: const [
        FfmAssistantActionStep(
          capabilityId: 'navigate.transactions',
          id: 'step-1',
        ),
        FfmAssistantActionStep(capabilityId: 'mutate.save_draft', id: 'step-2'),
      ],
      requiresConfirmation: true,
    );

    expect(plan.hasMutation, isTrue);
    expect(plan.isTerminal, isFalse);
  });

  test(
    'controller menahan plan pada awaiting confirmation sebelum confirm',
    () {
      final controller = FfmAssistantActionPlanController();
      controller.register(
        FfmAssistantActionPlan(
          id: 'plan-awaiting',
          summary: 'Siapkan draft',
          createdAt: DateTime(2026, 8, 23),
          steps: const [
            FfmAssistantActionStep(
              capabilityId: 'mutate.save_draft',
              id: 'step-1',
            ),
          ],
          requiresConfirmation: true,
        ),
      );

      final awaiting = controller.markAwaitingConfirmation('plan-awaiting');
      expect(
        awaiting?.status,
        FfmAssistantActionPlanStatus.awaitingConfirmation,
      );
      final confirmed = controller.confirm('plan-awaiting');
      expect(confirmed?.status, FfmAssistantActionPlanStatus.executing);
      expect(controller.confirm('plan-awaiting'), isNull);
    },
  );

  test('controller menyelesaikan plan hanya sekali', () {
    final controller = FfmAssistantActionPlanController();
    controller.register(
      FfmAssistantActionPlan(
        id: 'plan-complete',
        summary: 'Buka halaman',
        createdAt: DateTime(2026, 8, 23),
        steps: const [
          FfmAssistantActionStep(
            capabilityId: 'navigate.transactions',
            id: 'step-1',
          ),
        ],
      ),
    );

    expect(
      controller.complete('plan-complete')?.status,
      FfmAssistantActionPlanStatus.completed,
    );
    expect(
      controller.complete('plan-complete')?.status,
      FfmAssistantActionPlanStatus.completed,
    );
  });
}
