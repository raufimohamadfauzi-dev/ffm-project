import 'dart:async';
import 'package:drift/drift.dart';
import '../../../core/database/app_database.dart';
import '../../reminder/data/services/reminder_notification_service.dart';
import '../data/ffm_assistant_insight_repository.dart';
import 'detectors/anomaly_spike_detector.dart';
import 'detectors/debt_service_ratio_detector.dart';
import 'detectors/goal_progress_risk_detector.dart';
import 'detectors/intelligent_envelope_rebalance_detector.dart';
import 'detectors/micro_expense_leak_detector.dart';
import 'detectors/predictive_runway_detector.dart';
import 'ffm_assistant_insight.dart';
import 'ffm_proactive_delivery_policy.dart';
import '../data/telegram_bot_service.dart';
import '../data/telegram_config_repository.dart';
import '../data/telegram_message_formatter.dart';

class AutonomousEvaluationCoordinator {
  AutonomousEvaluationCoordinator({
    required AppDatabase database,
    required FfmAssistantInsightRepository insightRepository,
    DateTime Function()? clock,
    this.notificationService,
    this.deliveryPolicy,
    this.telegramBotService,
    this.telegramConfigRepository,
  })  : _db = database,
        _repo = insightRepository,
        _clock = clock ?? DateTime.now,
        _runwayDetector = PredictiveRunwayDetector(database),
        _rebalanceDetector = IntelligentEnvelopeRebalanceDetector(database),
        _spikeDetector = AnomalySpikeDetector(database),
        _latteDetector = MicroExpenseLeakDetector(database),
        _dsrDetector = DebtServiceRatioDetector(database),
        _goalDetector = GoalProgressRiskDetector(database);

  static final Map<String, DateTime> _lastEvaluationTimes = {};
  static const Duration minimumEvaluationInterval = Duration(seconds: 15);

  /// Helper untuk reset debounce saat testing
  static void resetDebounce() => _lastEvaluationTimes.clear();

  final AppDatabase _db;

  final FfmAssistantInsightRepository _repo;
  final DateTime Function() _clock;
  final ReminderNotificationService? notificationService;
  final FfmProactiveDeliveryPolicy? deliveryPolicy;
  final TelegramBotService? telegramBotService;
  final TelegramConfigRepository? telegramConfigRepository;

  final PredictiveRunwayDetector _runwayDetector;
  final IntelligentEnvelopeRebalanceDetector _rebalanceDetector;
  final AnomalySpikeDetector _spikeDetector;
  final MicroExpenseLeakDetector _latteDetector;
  final DebtServiceRatioDetector _dsrDetector;
  final GoalProgressRiskDetector _goalDetector;

  /// Menjalankan seluruh detektor deterministik, melakukan deduplikasi,
  /// pemeringkatan prioritas, dan menyimpan insight baru ke SQLite repository.
  /// Parameter `force = true` dapat digunakan untuk melewati debounce (misal tombol manual refresh).
  Future<List<FfmAssistantInsight>> runEvaluation({
    required String householdId,
    bool force = false,
  }) async {
    final now = _clock();

    // Debounce/coalescing per household agar tidak membebani sistem
    if (!force) {
      final lastTime = _lastEvaluationTimes[householdId];
      if (lastTime != null &&
          now.difference(lastTime) < minimumEvaluationInterval) {
        return const [];
      }
    }
    _lastEvaluationTimes[householdId] = now;

    final candidates = <FfmAssistantInsight>[];

    // Jalankan setiap detektor secara independen dengan try/catch agar
    // kegagalan satu detektor tidak menghentikan detektor lainnya.
    try {
      final runway = await _runwayDetector.detect(householdId: householdId, now: now);
      if (runway != null) candidates.add(runway);
    } catch (_) {}

    try {
      final rebalance = await _rebalanceDetector.detect(householdId: householdId, now: now);
      if (rebalance != null) candidates.add(rebalance);
    } catch (_) {}

    try {
      final spike = await _spikeDetector.detect(householdId: householdId, now: now);
      if (spike != null) candidates.add(spike);
    } catch (_) {}

    try {
      final latte = await _latteDetector.detect(householdId: householdId, now: now);
      if (latte != null) candidates.add(latte);
    } catch (_) {}

    try {
      final dsr = await _dsrDetector.detect(householdId: householdId, now: now);
      if (dsr != null) candidates.add(dsr);
    } catch (_) {}

    try {
      final goal = await _goalDetector.detect(householdId: householdId, now: now);
      if (goal != null) candidates.add(goal);
    } catch (_) {}

    if (candidates.isEmpty) return const [];

    // Urutkan kandidat berdasarkan prioritas tertinggi
    candidates.sort((a, b) => b.priority.compareTo(a.priority));

    final savedInsights = <FfmAssistantInsight>[];

    // Simpan hanya insight yang belum aktif (deduplikasi dilakukan di repository)
    for (final candidate in candidates) {
      final existing = await _repo.findActiveByDedupeKey(
        householdId: householdId,
        dedupeKey: candidate.dedupeKey,
      );
      if (existing == null) {
        final saved = await _repo.saveInsight(candidate);
        savedInsights.add(saved);
      }
    }

    // Jika ada insight baru yang tersimpan, evaluasi kebijakan pengiriman notifikasi Android
    if (savedInsights.isNotEmpty &&
        notificationService != null &&
        deliveryPolicy != null) {
      for (final saved in savedInsights) {
        try {
          final shouldDeliver = await deliveryPolicy!.shouldDeliverNotification(
            saved,
            now: now,
          );
          if (shouldDeliver) {
            await notificationService!.showAssistantInsightNotification(
              insightId: saved.id,
              title: saved.title,
              summary: saved.summary,
            );
            await deliveryPolicy!.recordNotificationDelivered(now: now);
            // Batasi maksimal 1 notifikasi per siklus evaluasi agar tidak membanjiri user
            break;
          }
        } catch (_) {}
      }
    }

    // Jika ada insight baru dan integrasi Telegram Bot aktif, kirim salinan peringatan radar
    if (savedInsights.isNotEmpty &&
        telegramBotService != null &&
        telegramConfigRepository != null) {
      try {
        final teleConfig = await telegramConfigRepository!.loadConfig();
        if (teleConfig.isReady && teleConfig.alertsEnabled) {
          for (final saved in savedInsights) {
            // Teruskan wawasan prioritas tinggi (>= 70) ke Telegram
            if (saved.priority >= 70) {
              final alertMsg = TelegramMessageFormatter.formatAlertMessage(
                title: saved.title,
                summary: saved.summary,
              );
              await telegramBotService!.sendMessage(
                botToken: teleConfig.botToken,
                chatId: teleConfig.chatId,
                text: alertMsg,
              );
              break;
            }
          }
        }
      } catch (_) {}
    }

    // Catch-up: periksa apakah laporan mingguan tertunda perlu dikirimkan
    try {
      await checkAndSendWeeklyReport(householdId: householdId);
    } catch (_) {}

    return savedInsights;
  }

  /// Memeriksa dan mengirimkan Laporan Mingguan ke Telegram jika belum terkirim pekan ini (*Catch-Up*).
  /// Parameter `force = true` dapat digunakan untuk pengiriman manual langsung (*Kirim Sekarang*).
  Future<bool> checkAndSendWeeklyReport({
    required String householdId,
    bool force = false,
  }) async {
    if (telegramBotService == null || telegramConfigRepository == null) {
      return false;
    }
    try {
      final config = await telegramConfigRepository!.loadConfig();
      if (!config.isReady) return false;
      if (!force && !config.weeklyReportEnabled) return false;

      final now = _clock();
      if (!force) {
        final lastSent =
            await telegramConfigRepository!.loadLastWeeklyReportSent();
        if (lastSent != null) {
          final diffDays = now.difference(lastSent).inDays;
          // Jangan kirim ulang otomatis jika belum ada 6 hari sejak pengiriman terakhir
          if (diffDays < 6) return false;
        }
      }

      // Kumpulkan data transaksi 7 hari terakhir secara deterministik
      final sevenDaysAgo = now.subtract(const Duration(days: 7));
      final allTxs = await (_db.select(_db.transactions)
            ..where((row) =>
                row.householdId.equals(householdId) &
                row.isArchived.equals(false) &
                row.isDeleted.equals(false)))
          .get();

      var totalExpense = 0;
      var totalIncome = 0;
      final categoryExpenses = <String, int>{};

      for (final tx in allTxs) {
        if (tx.date.isBefore(sevenDaysAgo) || tx.date.isAfter(now)) continue;
        if (tx.type == 'expense' || tx.amount < 0) {
          final amt = tx.amount.abs();
          totalExpense += amt;
          final catId = tx.categoryId ?? 'uncategorized';
          categoryExpenses[catId] = (categoryExpenses[catId] ?? 0) + amt;
        } else if (tx.type == 'income' || tx.amount > 0) {
          totalIncome += tx.amount.abs();
        }
      }

      // Cari kategori terbesar
      String? topCatName;
      int topCatAmount = 0;
      if (categoryExpenses.isNotEmpty) {
        final sortedCats = categoryExpenses.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final topEntry = sortedCats.first;
        topCatAmount = topEntry.value;

        if (topEntry.key != 'uncategorized') {
          final cat = await (_db.select(_db.categories)
                ..where((c) => c.id.equals(topEntry.key)))
              .getSingleOrNull();
          topCatName = cat?.name;
        } else {
          topCatName = 'Lain-lain';
        }
      }

      // Hitung total saldo kas likuid dari rekening aktif
      final accounts = await (_db.select(_db.accounts)
            ..where((row) =>
                row.householdId.equals(householdId) &
                row.isActive.equals(true) &
                row.isArchived.equals(false)))
          .get();

      int liquidCash = 0;
      for (final acc in accounts) {
        int balance = acc.openingBalance;
        for (final tx in allTxs) {
          if (tx.accountId == acc.id) {
            balance += tx.amount;
          }
        }
        liquidCash += balance;
      }

      // Ambil profil keluarga
      final household = await (_db.select(_db.households)
            ..where((h) => h.id.equals(householdId)))
          .getSingleOrNull();

      final reportMsg = TelegramMessageFormatter.formatWeeklyReport(
        familyName: household?.name,
        husbandName: household?.husbandName,
        wifeName: household?.wifeName,
        totalExpense: totalExpense,
        totalIncome: totalIncome,
        topExpenseCategory: topCatName,
        topExpenseAmount: topCatAmount,
        cashBalance: liquidCash,
        headline: totalExpense > 0 && liquidCash > totalExpense * 4
            ? 'Cadangan kas keluarga sehat dan aman untuk operasional.'
            : null,
      );

      final result = await telegramBotService!.sendMessage(
        botToken: config.botToken,
        chatId: config.chatId,
        text: reportMsg,
      );

      if (result.success) {
        await telegramConfigRepository!.saveLastWeeklyReportSent(now);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
