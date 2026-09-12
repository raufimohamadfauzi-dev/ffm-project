import 'dart:convert';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import 'ffm_assistant_agent_work.dart';

enum FfmAssistantMonitoringPreset {
  weeklyEvaluation,
  budgetMonitor,
  dueCheck;

  String get label => switch (this) {
        weeklyEvaluation => 'Evaluasi Mingguan',
        budgetMonitor => 'Pemantauan Anggaran Kategori',
        dueCheck => 'Pemeriksaan Tagihan & Target',
      };

  String get description => switch (this) {
        weeklyEvaluation =>
          'Rangkuman berkala arus kas mingguan, pengeluaran terbesar, dan burn rate.',
        budgetMonitor =>
          'Memantau kepatuhan batas anggaran belanja kategori dan laju belanja harian.',
        dueCheck =>
          'Memeriksa jatuh tempo cicilan kewajiban terdekat dan progres target finansial.',
      };
}

enum FfmAssistantJobCadence {
  daily,
  weekly,
  monthly,
  once;

  String get label => switch (this) {
        daily => 'Setiap Hari',
        weekly => 'Setiap Minggu',
        monthly => 'Setiap Bulan',
        once => 'Sekali',
      };
}

enum FfmAssistantDeliveryChannel {
  inApp,
  systemNotification,
  telegram;

  String get label => switch (this) {
        inApp => 'Di Dalam Aplikasi (In-App)',
        systemNotification => 'Notifikasi Sistem Perangkat',
        telegram => 'Telegram Bot',
      };
}

enum FfmAssistantJobStatus {
  active,
  paused,
  cancelled,
  completed;

  String get label => switch (this) {
        active => 'Aktif',
        paused => 'Dijeda',
        cancelled => 'Dibatalkan',
        completed => 'Selesai',
      };
}

/// Model data versioned untuk job otomatisasi monitoring (F3.1).
class FfmAssistantMonitoringJob {
  const FfmAssistantMonitoringJob({
    required this.id,
    required this.householdId,
    required this.preset,
    required this.title,
    required this.cadence,
    required this.targetTimeMinutes,
    this.targetDay,
    this.categoryFilter,
    this.deliveryChannel = FfmAssistantDeliveryChannel.inApp,
    this.status = FfmAssistantJobStatus.active,
    required this.createdAt,
    required this.updatedAt,
    this.lastRunAt,
    this.nextRunAt,
    this.costLimitUsd = 0.0,
  });

  final String id;
  final String householdId;
  final FfmAssistantMonitoringPreset preset;
  final String title;
  final FfmAssistantJobCadence cadence;

  /// Menit dari tengah malam (0..1439), misal 540 = 09:00 pagi.
  final int targetTimeMinutes;

  /// Hari dalam seminggu (1=Senin..7=Minggu) jika weekly,
  /// atau tanggal (1..31) jika monthly.
  final int? targetDay;

  final String? categoryFilter;
  final FfmAssistantDeliveryChannel deliveryChannel;
  final FfmAssistantJobStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastRunAt;
  final DateTime? nextRunAt;
  final double costLimitUsd;

  /// Menghitung jadwal eksekusi berikutnya secara deterministik.
  DateTime calculateNextRun(DateTime from) {
    final hour = targetTimeMinutes ~/ 60;
    final minute = targetTimeMinutes % 60;

    switch (cadence) {
      case FfmAssistantJobCadence.daily:
        var candidate = DateTime(from.year, from.month, from.day, hour, minute);
        if (!candidate.isAfter(from)) {
          candidate = candidate.add(const Duration(days: 1));
        }
        return candidate;

      case FfmAssistantJobCadence.weekly:
        final desiredWeekday = targetDay ?? DateTime.sunday;
        var candidate = DateTime(from.year, from.month, from.day, hour, minute);
        var daysDiff = (desiredWeekday - candidate.weekday) % 7;
        if (daysDiff == 0 && !candidate.isAfter(from)) {
          daysDiff = 7;
        }
        return candidate.add(Duration(days: daysDiff));

      case FfmAssistantJobCadence.monthly:
        final desiredDay = (targetDay ?? 1).clamp(1, 28);
        var candidate =
            DateTime(from.year, from.month, desiredDay, hour, minute);
        if (!candidate.isAfter(from)) {
          candidate =
              DateTime(from.year, from.month + 1, desiredDay, hour, minute);
        }
        return candidate;

      case FfmAssistantJobCadence.once:
        var candidate = DateTime(from.year, from.month, from.day, hour, minute);
        if (!candidate.isAfter(from)) {
          candidate = candidate.add(const Duration(days: 1));
        }
        return candidate;
    }
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'householdId': householdId,
        'preset': preset.name,
        'title': title,
        'cadence': cadence.name,
        'targetTimeMinutes': targetTimeMinutes,
        'targetDay': targetDay,
        'categoryFilter': categoryFilter,
        'deliveryChannel': deliveryChannel.name,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'lastRunAt': lastRunAt?.toIso8601String(),
        'nextRunAt': nextRunAt?.toIso8601String(),
        'costLimitUsd': costLimitUsd,
      };

  static FfmAssistantMonitoringJob? fromJson(Map<String, Object?> json) {
    try {
      final id = json['id'] as String?;
      final householdId = json['householdId'] as String?;
      final presetName = json['preset'] as String?;
      final title = json['title'] as String?;
      final cadenceName = json['cadence'] as String?;
      final targetTimeMinutes = json['targetTimeMinutes'] as int? ?? 540;
      final targetDay = json['targetDay'] as int?;
      final categoryFilter = json['categoryFilter'] as String?;
      final channelName = json['deliveryChannel'] as String?;
      final statusName = json['status'] as String?;
      final createdAtStr = json['createdAt'] as String?;
      final updatedAtStr = json['updatedAt'] as String?;
      final lastRunAtStr = json['lastRunAt'] as String?;
      final nextRunAtStr = json['nextRunAt'] as String?;
      final costLimitUsd = (json['costLimitUsd'] as num?)?.toDouble() ?? 0.0;

      if (id == null ||
          householdId == null ||
          presetName == null ||
          title == null ||
          cadenceName == null ||
          createdAtStr == null ||
          updatedAtStr == null) {
        return null;
      }

      final preset = FfmAssistantMonitoringPreset.values.firstWhere(
        (p) => p.name == presetName,
        orElse: () => FfmAssistantMonitoringPreset.weeklyEvaluation,
      );
      final cadence = FfmAssistantJobCadence.values.firstWhere(
        (c) => c.name == cadenceName,
        orElse: () => FfmAssistantJobCadence.weekly,
      );
      final deliveryChannel = FfmAssistantDeliveryChannel.values.firstWhere(
        (d) => d.name == channelName,
        orElse: () => FfmAssistantDeliveryChannel.inApp,
      );
      final status = FfmAssistantJobStatus.values.firstWhere(
        (s) => s.name == statusName,
        orElse: () => FfmAssistantJobStatus.active,
      );

      return FfmAssistantMonitoringJob(
        id: id,
        householdId: householdId,
        preset: preset,
        title: title,
        cadence: cadence,
        targetTimeMinutes: targetTimeMinutes,
        targetDay: targetDay,
        categoryFilter: categoryFilter,
        deliveryChannel: deliveryChannel,
        status: status,
        createdAt: DateTime.parse(createdAtStr),
        updatedAt: DateTime.parse(updatedAtStr),
        lastRunAt: lastRunAtStr != null ? DateTime.parse(lastRunAtStr) : null,
        nextRunAt: nextRunAtStr != null ? DateTime.parse(nextRunAtStr) : null,
        costLimitUsd: costLimitUsd,
      );
    } catch (_) {
      return null;
    }
  }

  /// Mengonversi job ke model durable FfmAssistantAgentGoal.
  FfmAssistantAgentGoal toAgentGoal() {
    final metadata = <String, Object?>{
      'preset': preset.name,
      'cadence': cadence.name,
      'targetTimeMinutes': targetTimeMinutes,
      'targetDay': targetDay,
      'categoryFilter': categoryFilter,
      'deliveryChannel': deliveryChannel.name,
      'costLimitUsd': costLimitUsd,
    };

    final goalStatus = switch (status) {
      FfmAssistantJobStatus.active => FfmAssistantAgentGoalStatus.active,
      FfmAssistantJobStatus.paused => FfmAssistantAgentGoalStatus.paused,
      FfmAssistantJobStatus.cancelled => FfmAssistantAgentGoalStatus.cancelled,
      FfmAssistantJobStatus.completed => FfmAssistantAgentGoalStatus.completed,
    };

    return FfmAssistantAgentGoal(
      id: id,
      householdId: householdId,
      domain: 'monitoring_job',
      title: title,
      objective: '${preset.label} (${cadence.label})',
      status: goalStatus,
      createdAt: createdAt,
      updatedAt: updatedAt,
      lastRunAt: lastRunAt,
      nextRunAt: nextRunAt,
      completionCondition: jsonEncode(metadata),
    );
  }

  /// Membaca job dari AssistantAgentGoal database Drift.
  static FfmAssistantMonitoringJob? fromAgentGoal(AssistantAgentGoal goal) {
    if (goal.domain != 'monitoring_job') return null;
    try {
      final condition = goal.completionCondition;
      if (condition == null || condition.trim().isEmpty) return null;
      final metadata = jsonDecode(condition) as Map<String, Object?>;

      final presetName = metadata['preset'] as String?;
      final cadenceName = metadata['cadence'] as String?;
      final targetTimeMinutes = metadata['targetTimeMinutes'] as int? ?? 540;
      final targetDay = metadata['targetDay'] as int?;
      final categoryFilter = metadata['categoryFilter'] as String?;
      final channelName = metadata['deliveryChannel'] as String?;
      final costLimit = (metadata['costLimitUsd'] as num?)?.toDouble() ?? 0.0;

      final preset = FfmAssistantMonitoringPreset.values.firstWhere(
        (p) => p.name == presetName,
        orElse: () => FfmAssistantMonitoringPreset.weeklyEvaluation,
      );
      final cadence = FfmAssistantJobCadence.values.firstWhere(
        (c) => c.name == cadenceName,
        orElse: () => FfmAssistantJobCadence.weekly,
      );
      final deliveryChannel = FfmAssistantDeliveryChannel.values.firstWhere(
        (d) => d.name == channelName,
        orElse: () => FfmAssistantDeliveryChannel.inApp,
      );

      final status = switch (goal.status) {
        'active' => FfmAssistantJobStatus.active,
        'paused' || 'blocked' => FfmAssistantJobStatus.paused,
        'cancelled' => FfmAssistantJobStatus.cancelled,
        'completed' => FfmAssistantJobStatus.completed,
        _ => FfmAssistantJobStatus.active,
      };

      return FfmAssistantMonitoringJob(
        id: goal.id,
        householdId: goal.householdId,
        preset: preset,
        title: goal.title,
        cadence: cadence,
        targetTimeMinutes: targetTimeMinutes,
        targetDay: targetDay,
        categoryFilter: categoryFilter,
        deliveryChannel: deliveryChannel,
        status: status,
        createdAt: goal.createdAt,
        updatedAt: goal.updatedAt,
        lastRunAt: goal.lastRunAt,
        nextRunAt: goal.nextRunAt,
        costLimitUsd: costLimit,
      );
    } catch (_) {
      return null;
    }
  }

  FfmAssistantMonitoringJob copyWith({
    String? title,
    FfmAssistantJobStatus? status,
    DateTime? updatedAt,
    DateTime? lastRunAt,
    DateTime? nextRunAt,
  }) {
    return FfmAssistantMonitoringJob(
      id: id,
      householdId: householdId,
      preset: preset,
      title: title ?? this.title,
      cadence: cadence,
      targetTimeMinutes: targetTimeMinutes,
      targetDay: targetDay,
      categoryFilter: categoryFilter,
      deliveryChannel: deliveryChannel,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastRunAt: lastRunAt ?? this.lastRunAt,
      nextRunAt: nextRunAt ?? this.nextRunAt,
      costLimitUsd: costLimitUsd,
    );
  }

  /// Membuat instance baru dengan ID collision-safe (UUID).
  static FfmAssistantMonitoringJob create({
    required String householdId,
    required FfmAssistantMonitoringPreset preset,
    String? title,
    FfmAssistantJobCadence cadence = FfmAssistantJobCadence.weekly,
    int targetTimeMinutes = 540,
    int? targetDay,
    String? categoryFilter,
    FfmAssistantDeliveryChannel deliveryChannel =
        FfmAssistantDeliveryChannel.inApp,
    DateTime? now,
  }) {
    final effectiveNow = now ?? DateTime.now();
    final defaultTitle = title ??
        switch (preset) {
          FfmAssistantMonitoringPreset.weeklyEvaluation => 'Evaluasi Mingguan Otomatis',
          FfmAssistantMonitoringPreset.budgetMonitor =>
            categoryFilter != null
                ? 'Pantau Anggaran $categoryFilter'
                : 'Pantau Anggaran Operasional',
          FfmAssistantMonitoringPreset.dueCheck => 'Pemeriksaan Tagihan & Target',
        };

    final tempJob = FfmAssistantMonitoringJob(
      id: const Uuid().v4(),
      householdId: householdId,
      preset: preset,
      title: defaultTitle,
      cadence: cadence,
      targetTimeMinutes: targetTimeMinutes,
      targetDay: targetDay,
      categoryFilter: categoryFilter,
      deliveryChannel: deliveryChannel,
      status: FfmAssistantJobStatus.active,
      createdAt: effectiveNow,
      updatedAt: effectiveNow,
    );

    return tempJob.copyWith(
      nextRunAt: tempJob.calculateNextRun(effectiveNow),
    );
  }
}
