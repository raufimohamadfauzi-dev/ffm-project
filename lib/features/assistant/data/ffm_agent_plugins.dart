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
import 'plugins/ffm_activity_live_sense_plugin.dart';
import 'plugins/ffm_activity_context_plugin.dart';
import 'plugins/ffm_activity_guard_plugin.dart';
import 'plugins/ffm_quick_note_actuator_plugin.dart';

export 'plugins/ffm_actuator_plugins.dart';
export 'plugins/ffm_logic_plugins.dart';
export 'plugins/ffm_sense_plugins.dart';
export 'plugins/ffm_activity_live_sense_plugin.dart';
export 'plugins/ffm_activity_context_plugin.dart';
export 'plugins/ffm_activity_guard_plugin.dart';
export 'plugins/ffm_quick_note_actuator_plugin.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FACTORY: Membuat harness yang sudah memuat semua built-in plugin.
// ─────────────────────────────────────────────────────────────────────────────

/// Membuat [FfmAgentHarness] yang sudah memuat 33 built-in plugin modular.
FfmAgentHarness createDefaultHarness(AppDatabase database) {
  final harness = FfmAgentHarness();
  harness.registerAll([
    // 👁️ Sense Plugins (16)
    FfmBalanceSensePlugin(database),
    FfmTransactionSensePlugin(database),
    FfmBudgetSensePlugin(database),
    FfmDebtSensePlugin(database),
    FfmAssetSensePlugin(database),
    FfmGoalSensePlugin(database),
    FfmUserHabitsAndProfilePlugin(database),
    FfmReceivableSensePlugin(database),
    FfmRecurringTransactionSensePlugin(database),
    FfmDailyNotesSensePlugin(database),
    FfmTaskSensePlugin(database),
    FfmScheduleSensePlugin(database),
    FfmRoutineSensePlugin(database),
    FfmTopMerchantSensePlugin(database),
    FfmWeeklyActivityReportPlugin(database),
    FfmLiveActivitySensePlugin(),

    // ✋ Actuator Plugins (6)
    FfmTransactionActuatorPlugin(),
    FfmGoalActuatorPlugin(),
    FfmReminderActuatorPlugin(),
    FfmReportActuatorPlugin(),
    FfmJsonGeneratorPlugin(database),
    FfmQuickNoteActuatorPlugin(),

    // 🧮 Logic Plugins (11)
    FfmZakatLogicPlugin(database),
    FfmFinancialHealthLogicPlugin(database),
    FfmBudgetGuardLogicPlugin(database),
    FfmLoanAffordabilityLogicPlugin(database),
    FfmSpendingPaceLogicPlugin(database),
    FfmHolisticAwarenessPlugin(database),
    FfmEmergencyFundLogicPlugin(database),
    FfmDebtSnowballLogicPlugin(database),
    FfmSavingRateLogicPlugin(database),
    FfmActivityContextPlugin(),
    FfmActivityGuardPlugin(),
  ]);
  return harness;
}



