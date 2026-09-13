import 'package:drift/drift.dart' hide Column;
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../advisor/domain/services/smart_budget_engine.dart';
import '../../transaction/domain/usecases/transaction_crud_usecases.dart';
import '../domain/ffm_assistant_agent_work.dart';
import '../domain/ffm_assistant_monitoring_job.dart';
import 'ffm_assistant_autonomy_repository.dart';

class FfmAssistantMonitoringReport {
  const FfmAssistantMonitoringReport({
    required this.jobId,
    required this.preset,
    required this.title,
    required this.generatedAt,
    required this.summary,
    required this.content,
    required this.isActionRequired,
  });

  final String jobId;
  final FfmAssistantMonitoringPreset preset;
  final String title;
  final DateTime generatedAt;
  final String summary;
  final String content;
  final bool isActionRequired;
}

class FfmAssistantMonitoringJobService {
  FfmAssistantMonitoringJobService({
    required this.database,
    required this.autonomyRepository,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase database;
  final FfmAssistantAutonomyRepository autonomyRepository;
  final DateTime Function() _clock;

  /// Menyimpan job pemantauan baru secara durable ke repository otonom.
  Future<FfmAssistantMonitoringJob?> createJob(
    FfmAssistantMonitoringJob job,
  ) async {
    final agentGoal = job.toAgentGoal();
    final savedGoal = await autonomyRepository.createGoal(agentGoal);
    if (savedGoal == null) return null;

    // Buat satu initial task durable untuk jadwal first run
    final firstRun = job.nextRunAt ?? job.calculateNextRun(_clock());
    final task = FfmAssistantAgentTask(
      id: const Uuid().v4(),
      goalId: job.id,
      householdId: job.householdId,
      title: 'Jalankan ${job.title}',
      objective: job.preset.description,
      priority: 5,
      createdAt: _clock(),
      updatedAt: _clock(),
      nextRunAt: firstRun,
      status: FfmAssistantAgentTaskStatus.pending,
      capabilityId: 'read.monitoring_evaluation',
      parameters: <String, Object?>{
        'jobId': job.id,
        'preset': job.preset.name,
      },
    );
    await autonomyRepository.createTask(task);

    return job.copyWith(nextRunAt: firstRun);
  }

  /// Membaca semua job pemantauan untuk satu household.
  Future<List<FfmAssistantMonitoringJob>> listJobs(String householdId) async {
    final goals = await autonomyRepository.goalsForHousehold(householdId);
    final jobs = <FfmAssistantMonitoringJob>[];
    for (final goal in goals) {
      if (goal.domain != 'monitoring_job') continue;
      final job = FfmAssistantMonitoringJob.fromAgentGoal(goal);
      if (job != null) jobs.add(job);
    }
    return jobs;
  }

  /// Menemukan satu job berdasarkan ID.
  Future<FfmAssistantMonitoringJob?> jobById(String jobId) async {
    final goal = await autonomyRepository.goalById(jobId);
    if (goal == null || goal.domain != 'monitoring_job') return null;
    return FfmAssistantMonitoringJob.fromAgentGoal(goal);
  }

  /// Menjeda job pemantauan.
  Future<bool> pauseJob(String jobId) async {
    final success = await autonomyRepository.setGoalStatus(
      jobId,
      FfmAssistantAgentGoalStatus.paused,
    );
    return success;
  }

  /// Melanjutkan job pemantauan yang dijeda.
  Future<bool> resumeJob(String jobId) async {
    final job = await jobById(jobId);
    if (job == null) return false;
    final now = _clock();
    final nextRun = job.calculateNextRun(now);

    final success = await autonomyRepository.setGoalStatus(
      jobId,
      FfmAssistantAgentGoalStatus.active,
    );
    if (success) {
      await (database.update(database.assistantAgentGoals)
            ..where((row) => row.id.equals(jobId)))
          .write(
        AssistantAgentGoalsCompanion(
          nextRunAt: Value(nextRun),
          updatedAt: Value(now),
        ),
      );
    }
    return success;
  }

  /// Membatalkan / menghapus jadwal job pemantauan.
  Future<bool> cancelJob(String jobId) async {
    final success = await autonomyRepository.setGoalStatus(
      jobId,
      FfmAssistantAgentGoalStatus.cancelled,
    );
    return success;
  }

  /// Menjalankan evaluasi langsung untuk satu job.
  Future<FfmAssistantMonitoringReport> runJobNow(String jobId) async {
    final job = await jobById(jobId);
    if (job == null) {
      throw StateError('Job monitoring dengan id $jobId tidak ditemukan.');
    }
    return executeEvaluation(job);
  }

  /// Mengeksekusi evaluasi deterministik untuk job monitoring.
  Future<FfmAssistantMonitoringReport> executeEvaluation(
    FfmAssistantMonitoringJob job, {
    DateTime? now,
  }) async {
    final effectiveNow = now ?? _clock();

    final report = switch (job.preset) {
      FfmAssistantMonitoringPreset.weeklyEvaluation =>
        await _evaluateWeekly(job, effectiveNow),
      FfmAssistantMonitoringPreset.budgetMonitor =>
        await _evaluateBudget(job, effectiveNow),
      FfmAssistantMonitoringPreset.dueCheck =>
        await _evaluateDueCheck(job, effectiveNow),
    };

    // Update checkpoint waktu lastRun dan nextRun
    final nextRun = job.calculateNextRun(effectiveNow);
    await (database.update(database.assistantAgentGoals)
          ..where((row) => row.id.equals(job.id)))
        .write(
      AssistantAgentGoalsCompanion(
        lastRunAt: Value(effectiveNow),
        nextRunAt: Value(nextRun),
        updatedAt: Value(effectiveNow),
      ),
    );

    // Simpan riwayat evaluasi ke executions agar dapat dirujuk percakapan (F3.8)
    try {
      final tasks = await autonomyRepository.tasksForGoal(job.id);
      if (tasks.isNotEmpty) {
        await autonomyRepository.recordTaskExecution(
          FfmAssistantAgentTaskExecution(
            id: const Uuid().v4(),
            taskId: tasks.first.id,
            goalId: job.id,
            householdId: job.householdId,
            runId: 'monitoring:${job.preset.name}:${job.id}',
            status: FfmAssistantAgentTaskExecutionStatus.completed,
            startedAt: effectiveNow,
            finishedAt: effectiveNow,
            summary: report.summary,
          ),
        );
      }
    } catch (_) {
      // Perekaman ringkasan eksekusi bersifat non-blocking
    }

    return report;
  }

  /// Mengevaluasi seluruh job monitoring aktif yang sudah jatuh tempo (due).
  Future<List<FfmAssistantMonitoringReport>> evaluateDueJobs(
    String householdId, {
    DateTime? now,
  }) async {
    final effectiveNow = now ?? _clock();
    final jobs = await listJobs(householdId);
    final reports = <FfmAssistantMonitoringReport>[];

    for (final job in jobs) {
      if (job.status != FfmAssistantJobStatus.active) continue;
      if (job.nextRunAt != null && job.nextRunAt!.isAfter(effectiveNow)) {
        continue;
      }

      try {
        final report = await executeEvaluation(job, now: effectiveNow);
        reports.add(report);
      } catch (_) {
        // Jangan hentikan evaluasi job lain jika satu job mengalami kendala data
      }
    }
    return reports;
  }

  /// Membangun ringkasan jadwal dan laporan evaluasi terakhir untuk konteks percakapan (F3.8).
  Future<String> buildMonitoringDigest({
    required String householdId,
    DateTime? now,
  }) async {
    final jobs = await listJobs(householdId);
    if (jobs.isEmpty) {
      return 'JADWAL PEMANTAUAN OTOMATIS (MONITORING JOBS):\nBelum ada jadwal pemantauan aktif.';
    }

    final buffer = StringBuffer('JADWAL PEMANTAUAN OTOMATIS (MONITORING JOBS):\n');
    for (final job in jobs) {
      final statusLabel = switch (job.status) {
        FfmAssistantJobStatus.active => 'Aktif',
        FfmAssistantJobStatus.paused => 'Dijeda',
        FfmAssistantJobStatus.cancelled => 'Dibatalkan',
        FfmAssistantJobStatus.completed => 'Selesai',
      };
      final nextRunStr =
          job.nextRunAt != null ? _formatDate(job.nextRunAt!) : 'Belum dijadwalkan';
      buffer.writeln(
        '• [Job ID: ${job.id}] ${job.title} (${job.preset.name}): Status $statusLabel, Waktu run berikutnya: $nextRunStr',
      );

      final executions = await autonomyRepository.executionsForGoal(job.id);
      if (executions.isNotEmpty) {
        final latest = executions.first;
        final runTime = _formatDate(latest.startedAt);
        buffer.writeln(
          '  - Evaluasi terakhir ($runTime): ${latest.summary ?? "Selesai tanpa catatan"}',
        );
      }
    }
    return buffer.toString().trim();
  }

  // 1. Evaluasi Mingguan (Weekly Evaluation)
  Future<FfmAssistantMonitoringReport> _evaluateWeekly(
    FfmAssistantMonitoringJob job,
    DateTime now,
  ) async {
    final sevenDaysAgo = now.subtract(const Duration(days: 7));
    final txs = await (database.select(database.transactions)
          ..where(
            (row) =>
                row.householdId.equals(job.householdId) &
                row.isArchived.equals(false) &
                row.isDeleted.equals(false),
          ))
        .get();

    final recentTxs = txs.where((t) => !t.date.isBefore(sevenDaysAgo)).toList();

    var income = 0;
    var expense = 0;
    final expenseTxs = <Transaction>[];

    for (final t in recentTxs) {
      if (t.type == 'income') {
        income += t.amount.abs();
      } else if (t.type == 'expense') {
        expense += t.amount.abs();
        expenseTxs.add(t);
      }
    }

    expenseTxs.sort((a, b) => b.amount.abs().compareTo(a.amount.abs()));
    final topExpenses = expenseTxs.take(3).toList();

    final netCashflow = income - expense;
    final isDeficit = netCashflow < 0;

    final buffer = StringBuffer()
      ..writeln('📊 **Laporan Evaluasi Mingguan FFM**')
      ..writeln(
        'Periode: 7 hari terakhir (${_formatDate(sevenDaysAgo)} - ${_formatDate(now)})',
      )
      ..writeln('• Total Pemasukan: ${_rupiah(income)}')
      ..writeln('• Total Pengeluaran: ${_rupiah(expense)}')
      ..writeln(
        '• Arus Kas Bersih: ${_rupiah(netCashflow)} (${isDeficit ? 'Defisit' : 'Surplus'})',
      );

    if (topExpenses.isNotEmpty) {
      buffer.writeln('\n🔍 **3 Pengeluaran Terbesar Mingguan**:');
      for (final t in topExpenses) {
        final note =
            t.note?.trim().isNotEmpty == true ? t.note : 'Tanpa catatan';
        buffer.writeln(
          '• ${_rupiah(t.amount.abs())} - $note (${_formatDate(t.date)})',
        );
      }
    }

    // Burn rate bulan berjalan
    final currentMonthTxs = txs
        .where((t) => t.date.year == now.year && t.date.month == now.month)
        .map(
          (t) => TransactionEntity(
            id: t.id,
            householdId: t.householdId,
            date: t.date,
            amount: t.amount,
            owner: t.owner ?? '',
            categoryId: t.categoryId,
            note: t.note,
            source: t.source ?? 'manual',
            recordedAt: t.recordedAt,
          ),
        )
        .toList();

    final engine = SmartBudgetEngine();
    final burnRate = engine.calculateBurnRate(
      currentMonthExpenses: currentMonthTxs,
      monthlyBudgetLimit: 5000000.0,
      now: now,
    );

    buffer.writeln('\n📈 **Laju Belanja Bulan Berjalan**:');
    buffer.writeln('• Status: ${burnRate.statusLabel}');
    buffer.writeln(
      '• Batas Belanja Harian Aman: Rp ${_formatNum(burnRate.safeDailySpendingLimit)}/hari',
    );

    final summary = isDeficit
        ? 'Evaluasi Mingguan: Pengeluaran melebihi pemasukan (defisit ${_rupiah(netCashflow.abs())}).'
        : 'Evaluasi Mingguan: Arus kas aman dengan surplus ${_rupiah(netCashflow)}.';

    return FfmAssistantMonitoringReport(
      jobId: job.id,
      preset: job.preset,
      title: 'Laporan Evaluasi Mingguan',
      generatedAt: now,
      summary: summary,
      content: buffer.toString(),
      isActionRequired: isDeficit,
    );
  }

  // 2. Pemantauan Anggaran Kategori (Budget Monitor)
  Future<FfmAssistantMonitoringReport> _evaluateBudget(
    FfmAssistantMonitoringJob job,
    DateTime now,
  ) async {
    final budgets = await (database.select(database.envelopeBudgets)
          ..where(
            (row) =>
                row.householdId.equals(job.householdId) &
                row.isActive.equals(true),
          ))
        .get();

    final currentMonthTxs = await (database.select(database.transactions)
          ..where(
            (row) =>
                row.householdId.equals(job.householdId) &
                row.isArchived.equals(false) &
                row.isDeleted.equals(false),
          ))
        .get();

    final thisMonthExpenses = currentMonthTxs
        .where(
          (t) =>
              t.type == 'expense' &&
              t.date.year == now.year &&
              t.date.month == now.month,
        )
        .toList();

    final buffer = StringBuffer()
      ..writeln('🎯 **Pemantauan Kategori Anggaran**')
      ..writeln('Waktu Pemantauan: ${_formatDate(now)}');

    var hasOverBudget = false;

    if (budgets.isEmpty) {
      buffer.writeln('Belum ada pos anggaran aktif yang diatur.');
    } else {
      buffer.writeln('Daftar Pos Anggaran Aktif:');
      for (final b in budgets) {
        if (job.categoryFilter != null &&
            !b.name.toLowerCase().contains(job.categoryFilter!.toLowerCase())) {
          continue;
        }
        final spent = thisMonthExpenses
            .where((t) => t.categoryId == b.categoryId)
            .fold<int>(0, (sum, t) => sum + t.amount.abs());
        final limit = b.allocated;
        final percent = limit > 0 ? ((spent / limit) * 100).round() : 0;
        final isOver = limit > 0 && spent > limit;
        if (isOver) hasOverBudget = true;

        buffer.writeln(
          '• ${b.name}: Terpakai ${_rupiah(spent)} dari ${_rupiah(limit)} ($percent%) ${isOver ? '⚠️ [MELEBIHI BATAS]' : '✅'}',
        );
      }
    }

    final summary = hasOverBudget
        ? 'Peringatan Anggaran: Terdapat kategori belanja yang telah melampaui batas!'
        : 'Pemantauan Anggaran: Seluruh kategori belanja masih berada dalam batas aman.';

    return FfmAssistantMonitoringReport(
      jobId: job.id,
      preset: job.preset,
      title: 'Laporan Pemantauan Anggaran',
      generatedAt: now,
      summary: summary,
      content: buffer.toString(),
      isActionRequired: hasOverBudget,
    );
  }

  // 3. Pemeriksaan Tagihan & Target (Due Check)
  Future<FfmAssistantMonitoringReport> _evaluateDueCheck(
    FfmAssistantMonitoringJob job,
    DateTime now,
  ) async {
    final liabilities = await (database.select(database.liabilities)
          ..where((row) => row.householdId.equals(job.householdId)))
        .get();

    final goals = await (database.select(database.goals)
          ..where(
            (row) =>
                row.householdId.equals(job.householdId) &
                row.isActive.equals(true),
          ))
        .get();

    final buffer = StringBuffer()
      ..writeln('🗓️ **Pemeriksaan Tagihan & Target Finansial**')
      ..writeln('Periksa per: ${_formatDate(now)}');

    var isActionRequired = false;

    // Cek cicilan/kewajiban
    final activeLiabilities =
        liabilities.where((l) => l.remainingBalance > 0).toList();
    buffer.writeln(
      '\n💳 **Kewajiban & Cicilan Aktif (${activeLiabilities.length})**:',
    );
    if (activeLiabilities.isEmpty) {
      buffer.writeln('• Tidak ada kewajiban cicilan aktif.');
    } else {
      for (final l in activeLiabilities) {
        final installment = l.monthlyInstallment;
        final due =
            l.dueDate != null ? _formatDate(l.dueDate!) : 'Belum ditentukan';
        final isNear = l.dueDate != null &&
            l.dueDate!.difference(now).inDays <= 7 &&
            !l.dueDate!.isBefore(now);
        if (isNear) isActionRequired = true;

        buffer.writeln(
          '• ${l.name}: Sisa ${_rupiah(l.remainingBalance)}, Cicilan/bln: ${_rupiah(installment)} (Jatuh tempo: $due)${isNear ? ' ⚠️ SEGERA' : ''}',
        );
      }
    }

    // Cek target
    buffer.writeln('\n🎯 **Target Finansial Aktif (${goals.length})**:');
    if (goals.isEmpty) {
      buffer.writeln('• Belum ada target keuangan aktif.');
    } else {
      for (final g in goals) {
        final remaining =
            (g.targetAmount - g.currentAmount).clamp(0, g.targetAmount);
        final percent = g.targetAmount > 0
            ? ((g.currentAmount / g.targetAmount) * 100).round()
            : 0;
        buffer.writeln(
          '• ${g.name}: Terkumpul ${_rupiah(g.currentAmount)} / ${_rupiah(g.targetAmount)} ($percent%, Sisa ${_rupiah(remaining)})',
        );
      }
    }

    final summary = isActionRequired
        ? 'Pemeriksaan Tagihan: Terdapat cicilan yang mendekati tanggal jatuh tempo dalam 7 hari.'
        : 'Pemeriksaan Tagihan & Target: Semua cicilan dan progres target terpantau tertib.';

    return FfmAssistantMonitoringReport(
      jobId: job.id,
      preset: job.preset,
      title: 'Pemeriksaan Tagihan & Target',
      generatedAt: now,
      summary: summary,
      content: buffer.toString(),
      isActionRequired: isActionRequired,
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _rupiah(int amount) {
    final digits = amount.abs().toString();
    final buffer = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) buffer.write('.');
      buffer.write(digits[index]);
    }
    return '${amount < 0 ? '-' : ''}Rp$buffer';
  }

  String _formatNum(double n) {
    final str = n.toStringAsFixed(0);
    final buf = StringBuffer();
    int count = 0;
    for (int i = str.length - 1; i >= 0; i--) {
      if (count > 0 && count % 3 == 0) buf.write('.');
      buf.write(str[i]);
      count++;
    }
    return buf.toString().split('').reversed.join();
  }
}
