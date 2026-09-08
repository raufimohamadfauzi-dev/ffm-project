import 'dart:io';

import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/assistant/presentation/widgets/ffm_assistant_page_context.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('semua destination Asisten punya halaman akar dengan page context', () {
    const roots = <FfmAssistantDestination, String>{
      FfmAssistantDestination.summary:
          'lib/features/advisor/presentation/pages/summary_page.dart',
      FfmAssistantDestination.transactions:
          'lib/features/transaction/presentation/pages/transaction_pages.dart',
      FfmAssistantDestination.budget:
          'lib/features/budget/presentation/pages/budget_page.dart',
      FfmAssistantDestination.analysis:
          'lib/features/advisor/presentation/pages/analysis_page.dart',
      FfmAssistantDestination.otherMenu:
          'lib/features/settings/presentation/pages/other_menu_page.dart',
      FfmAssistantDestination.masterData:
          'lib/features/settings/presentation/pages/master_data_page.dart',
      FfmAssistantDestination.assets:
          'lib/features/asset/presentation/pages/asset_pages.dart',
      FfmAssistantDestination.goals:
          'lib/features/goal/presentation/pages/goal_pages.dart',
      FfmAssistantDestination.liabilities:
          'lib/features/liability/presentation/pages/liability_pages.dart',
      FfmAssistantDestination.activity:
          'lib/features/activity/presentation/pages/activity_page.dart',
      FfmAssistantDestination.reminders:
          'lib/features/reminder/presentation/pages/reminder_page.dart',
      FfmAssistantDestination.backup:
          'lib/features/backup/presentation/pages/backup_page.dart',
      FfmAssistantDestination.monthlyReport:
          'lib/features/backup/presentation/pages/monthly_report_page.dart',
      FfmAssistantDestination.reconciliation: 'lib/features/recurring_transaction/presentation/pages/account_reconciliation_page.dart',
      FfmAssistantDestination.appSecurity:
          'lib/features/settings/presentation/pages/pin_security_page.dart',
      FfmAssistantDestination.diagnostics:
          'lib/features/settings/presentation/pages/app_diagnostics_page.dart',
      FfmAssistantDestination.activityLog:
          'lib/features/audit/presentation/pages/activity_log_page.dart',

      FfmAssistantDestination.recurringTransaction: 'lib/features/recurring_transaction/presentation/pages/recurring_transaction_page.dart',

      FfmAssistantDestination.privacyCenter:
          'lib/features/settings/presentation/pages/privacy_center_page.dart',
      FfmAssistantDestination.databaseStructure: 'lib/features/settings/presentation/pages/database_structure_page.dart',

      FfmAssistantDestination.familyProfile:
          'lib/features/settings/presentation/pages/family_profile_page.dart',
      FfmAssistantDestination.intelligenceDashboard:
          'lib/features/settings/presentation/pages/supabase_setup_page.dart',
      FfmAssistantDestination.paymentDetector:
          'lib/features/assistant/presentation/pages/payment_detector_settings_page.dart',
      FfmAssistantDestination.telegramSetup:
          'lib/features/assistant/presentation/pages/telegram_setup_page.dart',
      FfmAssistantDestination.agentInbox:
          'lib/features/assistant/presentation/pages/agent_inbox_page.dart',
      FfmAssistantDestination.autonomyMonitor:
          'lib/features/assistant/presentation/pages/ffm_assistant_autonomy_monitor_page.dart',
      FfmAssistantDestination.hijriSettings:
          'lib/features/hijri/presentation/pages/hijri_settings_page.dart',
      FfmAssistantDestination.calendarSettings:
          'lib/features/settings/presentation/pages/calendar_settings_page.dart',
      FfmAssistantDestination.marketNewsRadar:
          'lib/features/asset/presentation/pages/market_news_radar_page.dart',
      FfmAssistantDestination.utilityMeter:
          'lib/features/settings/presentation/pages/utility_meter_page.dart',
    };

    expect(
      roots.keys.toSet(),
      FfmAssistantDestination.values.map((value) => value.canonical).toSet(),
    );
    for (final entry in roots.entries) {
      final source = File(entry.value).readAsStringSync();
      expect(source, contains('FfmAssistantPageContext('));
      expect(source, contains('FfmAssistantDestination.${entry.key.name}'));
    }
  });

  test('FfmAssistantPageContextController mengisolasi tab shell dari pembaruan latar belakang', () {
    final controller = FfmAssistantPageContextController(
      defaultDestination: FfmAssistantDestination.summary,
    );
    expect(controller.currentDestination, FfmAssistantDestination.summary);

    // Pengguna berpindah ke tab Aktivitas
    controller.setShellTab(FfmAssistantDestination.activity);
    expect(controller.currentDestination, FfmAssistantDestination.activity);
    expect(controller.value, FfmAssistantDestination.activity);

    // SummaryPage di latar belakang melakukan pembaruan asinkron (isTab: true)
    final summaryToken = Object();
    controller.activate(
      summaryToken,
      FfmAssistantDestination.summary,
      isTab: true,
      dataSummary: 'Kekayaan Bersih: 50 Juta. Bulan ini: Masuk 10 Juta, Keluar 5 Juta.',
    );

    // Konteks aktif HARUS tetap Aktivitas, tidak boleh dibajak oleh SummaryPage!
    expect(controller.currentDestination, FfmAssistantDestination.activity);
    expect(controller.value, FfmAssistantDestination.activity);

    // Pushed route (misal pengguna membuka Data Utama dari dialog / aksi)
    final pushedToken = Object();
    controller.activate(
      pushedToken,
      FfmAssistantDestination.masterData,
      isTab: false,
      dataSummary: 'Sedang mengelola Data Utama',
    );
    expect(controller.currentDestination, FfmAssistantDestination.masterData);
    expect(controller.value, FfmAssistantDestination.masterData);
    expect(controller.currentSnapshot?.destination, FfmAssistantDestination.masterData);

    // Ketika pushed route ditutup, konteks kembali ke tab Aktivitas yang sedang aktif
    controller.deactivate(pushedToken);
    expect(controller.currentDestination, FfmAssistantDestination.activity);
    expect(controller.value, FfmAssistantDestination.activity);

    // Berpindah kembali ke tab Beranda / Summary
    controller.setShellTab(FfmAssistantDestination.summary);
    expect(controller.currentDestination, FfmAssistantDestination.summary);
    expect(
      controller.currentSnapshot?.dataSummary,
      contains('Kekayaan Bersih: 50 Juta'),
    );

    controller.dispose();
  });
}

