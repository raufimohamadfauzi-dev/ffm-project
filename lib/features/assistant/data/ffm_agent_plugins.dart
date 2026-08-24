/// FFM Built-in Agent Plugins — Barrel export & factory harness.
///
/// File ini mengekspor semua plugin yang telah dipecah modular ke folder `plugins/`:
/// - 👁️ Sense Plugins: `plugins/ffm_sense_plugins.dart`
/// - ✋ Actuator Plugins: `plugins/ffm_actuator_plugins.dart`
/// - 🧮 Logic Plugins: `plugins/ffm_logic_plugins.dart`

import '../../../core/database/app_database.dart';
import '../domain/ffm_agent_harness.dart';
import 'plugins/ffm_actuator_plugins.dart';
import 'plugins/ffm_logic_plugins.dart';
import 'plugins/ffm_sense_plugins.dart';

export 'plugins/ffm_actuator_plugins.dart';
export 'plugins/ffm_logic_plugins.dart';
export 'plugins/ffm_sense_plugins.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FACTORY: Membuat harness yang sudah memuat semua built-in plugin.
// ─────────────────────────────────────────────────────────────────────────────

/// Membuat [FfmAgentHarness] yang sudah memuat 18 built-in plugin modular.
FfmAgentHarness createDefaultHarness(AppDatabase database) {
  final harness = FfmAgentHarness();
  harness.registerAll([
    // 👁️ Sense Plugins (7)
    FfmBalanceSensePlugin(database),
    FfmTransactionSensePlugin(database),
    FfmBudgetSensePlugin(database),
    FfmDebtSensePlugin(database),
    FfmAssetSensePlugin(database),
    FfmGoalSensePlugin(database),
    FfmUserHabitsAndProfilePlugin(database),

    // ✋ Actuator Plugins (5)
    FfmTransactionActuatorPlugin(),
    FfmGoalActuatorPlugin(),
    FfmReminderActuatorPlugin(),
    FfmReportActuatorPlugin(),
    FfmJsonGeneratorPlugin(),

    // 🧮 Logic Plugins (6)
    FfmZakatLogicPlugin(database),
    FfmFinancialHealthLogicPlugin(database),
    FfmBudgetGuardLogicPlugin(database),
    FfmLoanAffordabilityLogicPlugin(database),
    FfmSpendingPaceLogicPlugin(database),
    FfmHolisticAwarenessPlugin(database),
  ]);
  return harness;
}
