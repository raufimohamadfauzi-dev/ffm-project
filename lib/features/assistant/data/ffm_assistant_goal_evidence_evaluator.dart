import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';

/// Status kemajuan target finansial berdasarkan bukti arus kas dan saldo aktual.
enum FfmAssistantGoalProgressStatus {
  targetReached('Tercapai'),
  aheadOfSchedule('Melampaui Target Waktu'),
  onTrack('Sesuai Jadwal (On Track)'),
  behindSchedule('Tertinggal dari Jadwal'),
  insufficientCashflow('Arus Kas Kurang (Terkendala)'),
  noDeadline('Berjalan (Tanpa Batas Waktu)');

  const FfmAssistantGoalProgressStatus(this.label);
  final String label;
}

/// Laporan bukti evaluasi satu target finansial.
class FfmAssistantGoalEvidenceReport {
  const FfmAssistantGoalEvidenceReport({
    required this.goalId,
    required this.goalName,
    required this.targetAmount,
    required this.currentAmount,
    required this.remainingAmount,
    required this.progressPercent,
    required this.status,
    required this.isAchievableWithCurrentCashflow,
    required this.recommendation,
    this.targetDate,
    this.daysRemaining,
    this.requiredMonthlySaving,
    this.averageMonthlyCashflow,
  });

  final String goalId;
  final String goalName;
  final int targetAmount;
  final int currentAmount;
  final int remainingAmount;
  final double progressPercent;
  final DateTime? targetDate;
  final int? daysRemaining;
  final int? requiredMonthlySaving;
  final int? averageMonthlyCashflow;
  final FfmAssistantGoalProgressStatus status;
  final bool isAchievableWithCurrentCashflow;
  final String recommendation;

  String formattedRupiah(int amount) =>
      'Rp${amount.toString().replaceAllMapped(RegExp(r'(?=(\d{3})+(?!\d))'), (match) => '.')}';

  String toSummaryText() {
    final buffer = StringBuffer()
      ..writeln('🎯 **$goalName** (${progressPercent.toStringAsFixed(1)}%)')
      ..writeln(
        '• Terkumpul: ${formattedRupiah(currentAmount)} dari target ${formattedRupiah(targetAmount)}',
      )
      ..writeln('• Sisa kebutuhan: ${formattedRupiah(remainingAmount)}')
      ..writeln('• Status: **${status.label}**');

    if (targetDate != null && daysRemaining != null) {
      buffer.writeln(
        '• Tenggat: ${targetDate!.day}/${targetDate!.month}/${targetDate!.year} (sisa $daysRemaining hari)',
      );
      if (requiredMonthlySaving != null && requiredMonthlySaving! > 0) {
        buffer.writeln(
          '• Alokasi bulanan yang dibutuhkan: ${formattedRupiah(requiredMonthlySaving!)}/bulan',
        );
      }
    }

    if (averageMonthlyCashflow != null) {
      buffer.writeln(
        '• Rata-rata surplus arus kas bulanan: ${formattedRupiah(averageMonthlyCashflow!)}',
      );
    }

    buffer.writeln('• Rekomendasi: $recommendation');
    return buffer.toString().trim();
  }
}

/// Service deterministik untuk mengevaluasi progres target keuangan (Goals)
/// dengan memeriksa bukti riil saldo dan arus kas tanpa halusinasi model.
class FfmAssistantGoalEvidenceEvaluator {
  FfmAssistantGoalEvidenceEvaluator({
    required this.database,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase database;
  final DateTime Function() _clock;

  /// Mengevaluasi seluruh target aktif untuk household tertentu.
  Future<List<FfmAssistantGoalEvidenceReport>> evaluateAllGoals(
    String householdId, {
    DateTime? now,
  }) async {
    final effectiveNow = now ?? _clock();
    final goals = await (database.select(database.goals)
          ..where(
            (row) =>
                row.householdId.equals(householdId) &
                row.isActive.equals(true),
          )
          ..orderBy([(row) => OrderingTerm.asc(row.targetDate)]))
        .get();

    final avgCashflow = await _calculateAverageMonthlyCashflow(
      householdId,
      effectiveNow,
    );

    final reports = <FfmAssistantGoalEvidenceReport>[];
    for (final goal in goals) {
      reports.add(
        _evaluateSingle(goal, effectiveNow, avgCashflow: avgCashflow),
      );
    }
    return reports;
  }

  /// Mengevaluasi satu target spesifik berdasarkan ID.
  Future<FfmAssistantGoalEvidenceReport?> evaluateGoal(
    String goalId, {
    DateTime? now,
  }) async {
    final effectiveNow = now ?? _clock();
    final goal = await (database.select(database.goals)
          ..where((row) => row.id.equals(goalId)))
        .getSingleOrNull();
    if (goal == null) return null;

    final avgCashflow = await _calculateAverageMonthlyCashflow(
      goal.householdId,
      effectiveNow,
    );
    return _evaluateSingle(goal, effectiveNow, avgCashflow: avgCashflow);
  }

  FfmAssistantGoalEvidenceReport _evaluateSingle(
    Goal goal,
    DateTime now, {
    required int avgCashflow,
  }) {
    final targetAmount = goal.targetAmount;
    final currentAmount = goal.currentAmount;
    final remainingAmount = (targetAmount - currentAmount).clamp(0, targetAmount);
    final progressPercent =
        targetAmount > 0 ? (currentAmount / targetAmount * 100).clamp(0.0, 100.0) : 100.0;

    if (currentAmount >= targetAmount) {
      return FfmAssistantGoalEvidenceReport(
        goalId: goal.id,
        goalName: goal.name,
        targetAmount: targetAmount,
        currentAmount: currentAmount,
        remainingAmount: 0,
        progressPercent: 100.0,
        status: FfmAssistantGoalProgressStatus.targetReached,
        isAchievableWithCurrentCashflow: true,
        recommendation:
            'Target telah tercapai penuh! Dana siap dialokasikan atau target dapat ditandai selesai.',
        targetDate: goal.targetDate,
      );
    }

    if (goal.targetDate == null) {
      return FfmAssistantGoalEvidenceReport(
        goalId: goal.id,
        goalName: goal.name,
        targetAmount: targetAmount,
        currentAmount: currentAmount,
        remainingAmount: remainingAmount,
        progressPercent: progressPercent,
        status: FfmAssistantGoalProgressStatus.noDeadline,
        isAchievableWithCurrentCashflow: avgCashflow > 0,
        averageMonthlyCashflow: avgCashflow,
        recommendation: avgCashflow > 0
            ? 'Terus sisihkan surplus kas bulanan untuk mempercepat penyelesaian target.'
            : 'Perbaiki arus kas operasional agar dapat mulai menyisihkan tabungan untuk target ini.',
      );
    }

    final targetDate = goal.targetDate!;
    final daysRemaining = targetDate.difference(now).inDays;
    final monthsRemaining = (daysRemaining / 30.4).ceil().clamp(1, 120);
    final requiredMonthlySaving =
        daysRemaining > 0 ? (remainingAmount / monthsRemaining).ceil() : remainingAmount;

    FfmAssistantGoalProgressStatus status;
    String recommendation;
    bool achievable;

    if (daysRemaining <= 0) {
      status = FfmAssistantGoalProgressStatus.behindSchedule;
      achievable = false;
      recommendation =
          'Tenggat waktu target telah terlewati. Pertimbangkan memperpanjang tenggat atau menyuntikkan dana tambahan.';
    } else if (avgCashflow <= 0) {
      status = FfmAssistantGoalProgressStatus.insufficientCashflow;
      achievable = false;
      recommendation =
          'Arus kas bulanan defisit atau nol. Penuhi dulu kebutuhan operasional dasar sebelum menambah porsi target ini.';
    } else if (requiredMonthlySaving <= avgCashflow) {
      final coverage = avgCashflow / requiredMonthlySaving;
      if (coverage >= 1.5) {
        status = FfmAssistantGoalProgressStatus.aheadOfSchedule;
        achievable = true;
        recommendation =
            'Arus kas surplus sangat aman. Target berpotensi tercapai lebih awal dari jadwal yang direncanakan.';
      } else {
        status = FfmAssistantGoalProgressStatus.onTrack;
        achievable = true;
        recommendation =
            'Pertahankan alokasi tabungan minimal ${_formatRupiah(requiredMonthlySaving)} per bulan agar target selesai tepat waktu.';
      }
    } else {
      status = FfmAssistantGoalProgressStatus.behindSchedule;
      achievable = false;
      recommendation =
          'Kebutuhan tabungan (${_formatRupiah(requiredMonthlySaving)}/bln) melebihi surplus kas rata-rata (${_formatRupiah(avgCashflow)}/bln). Disarankan sesuaikan tenggat tanggal atau efisiensikan pengeluaran.';
    }

    return FfmAssistantGoalEvidenceReport(
      goalId: goal.id,
      goalName: goal.name,
      targetAmount: targetAmount,
      currentAmount: currentAmount,
      remainingAmount: remainingAmount,
      progressPercent: progressPercent,
      targetDate: targetDate,
      daysRemaining: daysRemaining,
      requiredMonthlySaving: requiredMonthlySaving,
      averageMonthlyCashflow: avgCashflow,
      status: status,
      isAchievableWithCurrentCashflow: achievable,
      recommendation: recommendation,
    );
  }

  /// Menghitung rata-rata surplus arus kas bulanan berdasarkan 90 hari terakhir.
  Future<int> _calculateAverageMonthlyCashflow(
    String householdId,
    DateTime now,
  ) async {
    final ninetyDaysAgo = now.subtract(const Duration(days: 90));
    final txs = await (database.select(database.transactions)
          ..where(
            (row) =>
                row.householdId.equals(householdId) &
                row.date.isBiggerOrEqualValue(ninetyDaysAgo) &
                row.date.isSmallerOrEqualValue(now),
          ))
        .get();

    final validTxs =
        txs.where((t) => !t.isArchived && !t.isDeleted && t.type != 'transfer').toList();

    var netCashflow = 0;
    for (final tx in validTxs) {
      if (tx.type == 'income') {
        netCashflow += tx.amount.abs();
      } else if (tx.type == 'expense') {
        netCashflow -= tx.amount.abs();
      }
    }

    // 90 hari ~ 3 bulan
    final monthlyAverage = (netCashflow / 3).round();
    return monthlyAverage;
  }

  String _formatRupiah(int amount) =>
      'Rp${amount.toString().replaceAllMapped(RegExp(r'(?=(\d{3})+(?!\d))'), (match) => '.')}';
}
