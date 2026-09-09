import 'dart:async';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/di/injection.dart';
import '../../advisor/data/cash_flow_profile_repository.dart';
import '../../reminder/data/services/reminder_notification_service.dart';
import '../data/ffm_assistant_insight_repository.dart';
import 'detectors/anomaly_spike_detector.dart';
import 'detectors/debt_payoff_acceleration_detector.dart';
import 'detectors/debt_service_ratio_detector.dart';
import 'detectors/goal_progress_risk_detector.dart';
import 'detectors/intelligent_envelope_rebalance_detector.dart';
import 'detectors/micro_expense_leak_detector.dart';
import 'detectors/predictive_runway_detector.dart';
import 'ffm_assistant_insight.dart';
import 'ffm_proactive_delivery_policy.dart';
import '../data/telegram_bot_service.dart';
import '../data/telegram_config_repository.dart';
import '../data/telegram_delivery_processor.dart';
import '../data/telegram_delivery_repository.dart';
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
    this.telegramDeliveryRepository,
    this.telegramDeliveryProcessor,
    CashFlowProfileRepository? cashFlowProfileRepository,
  }) : _db = database,
       _repo = insightRepository,
       _clock = clock ?? DateTime.now,
       _runwayDetector = PredictiveRunwayDetector(
         database,
         cashFlowRepo:
             cashFlowProfileRepository ??
             (getIt.isRegistered<CashFlowProfileRepository>()
                 ? getIt<CashFlowProfileRepository>()
                 : null),
       ),
       _rebalanceDetector = IntelligentEnvelopeRebalanceDetector(database),
       _spikeDetector = AnomalySpikeDetector(database),
       _latteDetector = MicroExpenseLeakDetector(database),
       _dsrDetector = DebtServiceRatioDetector(database),
       _goalDetector = GoalProgressRiskDetector(database),
       _debtPayoffDetector = DebtPayoffAccelerationDetector(database);

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
  final TelegramDeliveryRepository? telegramDeliveryRepository;
  final TelegramDeliveryProcessor? telegramDeliveryProcessor;

  final PredictiveRunwayDetector _runwayDetector;
  final IntelligentEnvelopeRebalanceDetector _rebalanceDetector;
  final AnomalySpikeDetector _spikeDetector;
  final MicroExpenseLeakDetector _latteDetector;
  final DebtServiceRatioDetector _dsrDetector;
  final GoalProgressRiskDetector _goalDetector;
  final DebtPayoffAccelerationDetector _debtPayoffDetector;

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
      final runway = await _runwayDetector.detect(
        householdId: householdId,
        now: now,
      );
      if (runway != null) candidates.add(runway);
    } catch (_) {}

    try {
      final rebalance = await _rebalanceDetector.detect(
        householdId: householdId,
        now: now,
      );
      if (rebalance != null) candidates.add(rebalance);
    } catch (_) {}

    try {
      final spike = await _spikeDetector.detect(
        householdId: householdId,
        now: now,
      );
      if (spike != null) candidates.add(spike);
    } catch (_) {}

    try {
      final latte = await _latteDetector.detect(
        householdId: householdId,
        now: now,
      );
      if (latte != null) candidates.add(latte);
    } catch (_) {}

    try {
      final dsr = await _dsrDetector.detect(householdId: householdId, now: now);
      if (dsr != null) candidates.add(dsr);
    } catch (_) {}

    try {
      final goal = await _goalDetector.detect(
        householdId: householdId,
        now: now,
      );
      if (goal != null) candidates.add(goal);
    } catch (_) {}

    try {
      final payoff = await _debtPayoffDetector.detect(
        householdId: householdId,
        now: now,
      );
      if (payoff != null) candidates.add(payoff);
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

    // Jika ada insight baru dan integrasi Telegram Bot aktif, kirim salinan
    // peringatan radar. Saat outbox tersedia, peringatan diantrekan durabel
    // (deduplikasi per insight + retry otomatis + status aktual). Tanpa
    // outbox, dipakai jalur langsung lama untuk kompatibilitas.
    if (savedInsights.isNotEmpty &&
        telegramBotService != null &&
        telegramConfigRepository != null) {
      // ignore: avoid_catches_without_on_clauses
      try {
        final teleConfig = await telegramConfigRepository!.loadConfig();
        if (teleConfig.isReady && teleConfig.alertsEnabled) {
          final highPriority = savedInsights
              .where((s) => s.priority >= 70)
              .toList(growable: false);
          if (highPriority.isNotEmpty) {
            if (telegramDeliveryRepository != null &&
                telegramDeliveryProcessor != null) {
              final deliveryNow = _clock();
              for (final insight in highPriority) {
                await telegramDeliveryRepository!.enqueue(
                  deliveryId: 'telegram:alert:${insight.id}',
                  householdId: householdId,
                  operation: 'alert',
                  messageText: TelegramMessageFormatter.formatAlertMessage(
                    title: insight.title,
                    summary: insight.summary,
                  ),
                  entityId: insight.id,
                  dedupeKey: 'telegram:alert:${insight.id}',
                  credentialFingerprint:
                      TelegramConfigRepository.credentialFingerprintFor(
                        teleConfig.botToken,
                        teleConfig.chatId,
                      ),
                  createdAt: deliveryNow,
                );
              }
              // Proses segera agar alarm tidak menunggu siklus background;
              // bila gagal di tengah jalan, antrean diproses ulang nanti.
              await telegramDeliveryProcessor!.processPending(
                householdId: householdId,
              );
            } else {
              for (final insight in highPriority) {
                // ignore: avoid_catches_without_on_clauses
                try {
                  if (await telegramConfigRepository!.isAlertDelivered(
                    insight.id,
                  )) {
                    continue;
                  }
                  final alertMsg = TelegramMessageFormatter.formatAlertMessage(
                    title: insight.title,
                    summary: insight.summary,
                  );
                  final alertResult = await telegramBotService!.sendMessage(
                    botToken: teleConfig.botToken,
                    chatId: teleConfig.chatId,
                    text: alertMsg,
                  );
                  if (alertResult.success) {
                    await telegramConfigRepository!.markAlertDelivered(
                      insight.id,
                    );
                    await telegramConfigRepository!.recordDeliveryStatus(
                      status: TelegramDeliveryStatus.sent,
                      message: 'Peringatan radar terkirim.',
                    );
                  } else {
                    await telegramConfigRepository!.markAlertFailed(insight.id);
                    await telegramConfigRepository!.recordDeliveryStatus(
                      status: TelegramDeliveryStatus.failed,
                      message: alertResult.message,
                    );
                  }
                } catch (_) {
                  await telegramConfigRepository!.markAlertFailed(insight.id);
                }
              }
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
        // Klaim atomik: hanya satu pemicu (background/manual) yang boleh mengirim.
        final claimed = await telegramConfigRepository!.claimWeeklyReport(
          periodKey: householdId,
          now: now,
        );
        if (!claimed) return false;
      }
      final claimKey = householdId;

      // Kumpulkan data transaksi 7 hari terakhir secara deterministik
      final sevenDaysAgo = now.subtract(const Duration(days: 7));
      final allTxs =
          await (_db.select(_db.transactions)..where(
                (row) =>
                    row.householdId.equals(householdId) &
                    row.isArchived.equals(false) &
                    row.isDeleted.equals(false),
              ))
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
          final cat = await (_db.select(
            _db.categories,
          )..where((c) => c.id.equals(topEntry.key))).getSingleOrNull();
          topCatName = cat?.name;
        } else {
          topCatName = 'Lain-lain';
        }
      }

      // Hitung total saldo kas likuid dari rekening aktif
      final accounts =
          await (_db.select(_db.accounts)..where(
                (row) =>
                    row.householdId.equals(householdId) &
                    row.isActive.equals(true) &
                    row.isArchived.equals(false),
              ))
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
      final household = await (_db.select(
        _db.households,
      )..where((h) => h.id.equals(householdId))).getSingleOrNull();

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

      if (telegramDeliveryRepository != null &&
          telegramDeliveryProcessor != null) {
        final deliveryNow = _clock();
        final periodKey = _weeklyPeriodKey(householdId, deliveryNow);
        final deliveryId = force
            ? 'telegram:weekly:$householdId:manual:${deliveryNow.microsecondsSinceEpoch}'
            : periodKey;
        final enqueued = await telegramDeliveryRepository!.enqueue(
          deliveryId: deliveryId,
          householdId: householdId,
          operation: 'weekly.report',
          messageText: reportMsg,
          entityId: periodKey,
          dedupeKey: force ? null : periodKey,
          credentialFingerprint:
              TelegramConfigRepository.credentialFingerprintFor(
                config.botToken,
                config.chatId,
              ),
          createdAt: deliveryNow,
        );
        // Proses segera agar "Kirim Sekarang" dan catch-up tetap responsif;
        // bila gagal di tengah jalan, siklus background mencoba lagi.
        if (force || enqueued) {
          await telegramDeliveryProcessor!.processPending(
            householdId: householdId,
          );
        }
        final row = await telegramDeliveryRepository!.deliveryById(deliveryId);
        if (row != null && row.status == 'sent') {
          await telegramConfigRepository!.recordDeliveryStatus(
            status: TelegramDeliveryStatus.sent,
            message: 'Laporan mingguan terkirim.',
          );
          return true;
        }
        await telegramConfigRepository!.recordDeliveryStatus(
          status: TelegramDeliveryStatus.failed,
          message:
              row?.lastError ?? 'Laporan mingguan masih menunggu pengiriman.',
        );
        return false;
      }

      final result = await telegramBotService!.sendMessage(
        botToken: config.botToken,
        chatId: config.chatId,
        text: reportMsg,
      );

      if (result.success) {
        await telegramConfigRepository!.saveLastWeeklyReportSent(now);
        await telegramConfigRepository!.completeWeeklyReport(
          periodKey: claimKey,
          now: now,
        );
        await telegramConfigRepository!.recordDeliveryStatus(
          status: TelegramDeliveryStatus.sent,
          message: 'Laporan mingguan terkirim.',
        );
        return true;
      }
      await telegramConfigRepository!.failWeeklyReport(
        periodKey: claimKey,
        now: now,
      );
      await telegramConfigRepository!.recordDeliveryStatus(
        status: TelegramDeliveryStatus.failed,
        message: result.message,
      );
      return false;
    } catch (_) {
      await telegramConfigRepository?.failWeeklyReport(
        periodKey: householdId,
        now: _clock(),
      );
      return false;
    }
  }

  /// Kunci periode mingguan (tahun + nomor minggu ISO) untuk deduplikasi
  /// laporan di seluruh siklus evaluasi.
  String _weeklyPeriodKey(String householdId, DateTime time) {
    final day = DateTime(time.year, time.month, time.day);
    final thursday = day.add(Duration(days: DateTime.thursday - day.weekday));
    final jan1 = DateTime(thursday.year, 1, 1);
    final week = (thursday.difference(jan1).inDays / 7).floor() + 1;
    return '$householdId:${thursday.year}-W${week.toString().padLeft(2, '0')}';
  }
}
