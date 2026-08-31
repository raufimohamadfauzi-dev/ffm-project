import '../../../core/database/app_database.dart';
import '../../../core/database/ffm_database_structure_service.dart';
import '../domain/ffm_assistant_models.dart';
import '../domain/ffm_assistant_financial_analysis.dart';
import '../domain/ffm_assistant_analysis_engine.dart';
import 'ffm_assistant_financial_snapshot_service.dart';

import 'package:drift/drift.dart';

/// Kontrak baca data Asisten. Tidak ada tool di berkas ini yang memiliki
/// akses insert, update, delete, atau side effect lain pada database FFM.
class FfmAssistantQueryRequest {
  const FfmAssistantQueryRequest({
    required this.householdId,
    required this.normalizedText,
    required this.parameters,
    required this.now,
  });

  final String householdId;
  final String normalizedText;
  final Map<String, Object?> parameters;
  final DateTime now;
}

class FfmAssistantQueryAnswer {
  const FfmAssistantQueryAnswer({required this.title, required this.message});

  final String title;
  final String message;
}

abstract interface class FfmAssistantQueryTool {
  bool canHandle(String normalizedText);

  Future<FfmAssistantQueryAnswer?> answer(FfmAssistantQueryRequest request);
}

/// Registry tool baca lokal. Query lebih spesifik dikembalikan lebih awal agar
/// tidak jatuh ke fallback penjelasan fitur atau parser draft transaksi.
class FfmAssistantQueryRegistry {
  FfmAssistantQueryRegistry(AppDatabase database, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now,
      _analysisEngine = FfmAssistantAnalysisEngine(database),
      _tools = <FfmAssistantQueryTool>[
        _DatabaseStructureQueryTool(FfmDatabaseStructureService(database)),
        _AccountBalanceQueryTool(database),
        _TransactionSummaryQueryTool(database),
        _ActiveActivityQueryTool(database),
        _GoalStatusQueryTool(database),
        _DebtStatusQueryTool(database),
        _AssetSummaryQueryTool(database),
        _LoanAffordabilityQueryTool(database),
        _DataCompletenessQueryTool(database),
        _PersonalProfileQueryTool(database),
      ] {
        // Initialize analysis tools after _analysisEngine is set
        _tools.addAll([
          _FrequencyAnalysisQueryTool(_analysisEngine),
          _TrendAnalysisQueryTool(_analysisEngine),
          _PatternAnalysisQueryTool(_analysisEngine),
          _PeriodAnalysisQueryTool(_analysisEngine),
        ]);
      }
  final DateTime Function() _clock;
  final FfmAssistantAnalysisEngine _analysisEngine;
  final List<FfmAssistantQueryTool> _tools;

  Future<FfmAssistantQueryAnswer?> tryAnswer(
    String normalizedText, {
    required String householdId,
  }) async {
    // Kalimat aksi harus selalu diteruskan ke parser draft. Tanpa pagar ini,
    // kata seperti "senilai" pada "tambah aset ... senilai ..." dapat keliru
    // terbaca sebagai pertanyaan nilai aset.
    if (RegExp(
      r'\b(tambah|buat|catat|mulai|selesai|ubah|hapus)\b',
      caseSensitive: false,
    ).hasMatch(normalizedText)) {
      return null;
    }
    final request = FfmAssistantQueryRequest(
      householdId: householdId,
      normalizedText: normalizedText,
      parameters: const <String, Object?>{},
      now: _clock(),
    );
    for (final tool in _tools) {
      if (!tool.canHandle(normalizedText)) continue;
      final answer = await tool.answer(request);
      if (answer != null) return answer;
    }
    return null;
  }
}

class _DatabaseStructureQueryTool implements FfmAssistantQueryTool {
  const _DatabaseStructureQueryTool(this._structureService);

  final FfmDatabaseStructureService _structureService;

  @override
  bool canHandle(String normalizedText) {
    final namesDatabase = RegExp(
      r'\b(database|basis data|struktur database|struktur data|tabel)\b',
    ).hasMatch(normalizedText);
    final asksAppData =
        normalizedText.contains('ada data apa saja') &&
        (normalizedText.contains('aplikasi') || normalizedText.contains('ffm'));
    return namesDatabase || asksAppData;
  }

  @override
  Future<FfmAssistantQueryAnswer?> answer(
    FfmAssistantQueryRequest request,
  ) async {
    final structure = await _structureService.read();
    final categories = structure.categoryCounts.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    final categoryText = categories
        .map((item) => '${item.key} (${item.value})')
        .join(', ');
    final examples = structure.tables
        .take(5)
        .map((table) => table.label)
        .join(', ');
    return FfmAssistantQueryAnswer(
      title: 'Struktur database FFM',
      message:
          'FFM memakai ${structure.tableCount} tabel lokal dalam kelompok: $categoryText. Contohnya: $examples. Aku hanya membaca metadata nama tabel, kategori, dan jumlah kolom—bukan isi transaksi, saldo, nama rekening, atau data keluarga. Untuk daftar lengkap, buka Lainnya > Struktur database.',
    );
  }
}

class _AccountBalanceQueryTool implements FfmAssistantQueryTool {
  const _AccountBalanceQueryTool(this._database);

  final AppDatabase _database;

  @override
  bool canHandle(String normalizedText) =>
      normalizedText.contains('saldo') &&
      !normalizedText.contains('saldo target') &&
      !normalizedText.contains('saldo tujuan');

  @override
  Future<FfmAssistantQueryAnswer?> answer(
    FfmAssistantQueryRequest request,
  ) async {
    final accounts =
        await (_database.select(_database.accounts)..where(
              (row) =>
                  row.householdId.equals(request.householdId) &
                  row.isActive.equals(true) &
                  row.isArchived.equals(false),
            ))
            .get();
    if (accounts.isEmpty) {
      return const FfmAssistantQueryAnswer(
        title: 'Saldo rekening',
        message: 'Belum ada rekening aktif. Tambah rekening dulu di Data Utama, lalu aku bisa cek saldo bukunya dari data lokal.',
      );
    }
    final matches = accounts
        .where(
          (account) => request.normalizedText.contains(_fold(account.name)),
        )
        .toList(growable: false);
    if (matches.length != 1) {
      final names = accounts.map((item) => item.name).join(', ');
      return FfmAssistantQueryAnswer(
        title: 'Saldo rekening',
        message:
            'Mau cek saldo rekening yang mana? Rekening aktif: $names. Sebutkan namanya supaya tidak salah.',
      );
    }
    final account = matches.single;
    final transactions =
        await (_database.select(_database.transactions)..where(
              (row) =>
                  row.householdId.equals(request.householdId) &
                  row.accountId.equals(account.id) &
                  row.isArchived.equals(false) &
                  row.isDeleted.equals(false),
            ))
            .get();
    final transfers =
        await (_database.select(_database.transfers)..where(
              (row) =>
                  row.householdId.equals(request.householdId) &
                  (row.fromAccountId.equals(account.id) |
                      row.toAccountId.equals(account.id)) &
                  row.isDeleted.equals(false),
            ))
            .get();
    var balance = account.openingBalance;
    for (final row in transactions) {
      if (row.type == 'income') balance += row.amount.abs();
      if (row.type == 'expense') balance -= row.amount.abs();
    }
    for (final transfer in transfers) {
      if (transfer.fromAccountId == account.id) balance -= transfer.amount;
      if (transfer.toAccountId == account.id) balance += transfer.amount;
    }
    return FfmAssistantQueryAnswer(
      title: 'Saldo ${account.name}',
      message:
          'Saldo buku ${account.name} saat ini ${_rupiah(balance)}. Ini dihitung dari saldo awal, transaksi yang tidak diarsipkan, dan perpindahan dana yang tercatat.',
    );
  }
}

class _TransactionSummaryQueryTool implements FfmAssistantQueryTool {
  const _TransactionSummaryQueryTool(this._database);

  final AppDatabase _database;

  @override
  bool canHandle(String normalizedText) =>
      (normalizedText.contains('pemasukan') ||
          normalizedText.contains('pengeluaran') ||
          normalizedText.contains('transaksi')) &&
      (normalizedText.contains('berapa') ||
          normalizedText.contains('total') ||
          normalizedText.contains('bulan') ||
          normalizedText.contains('minggu'));

  @override
  Future<FfmAssistantQueryAnswer?> answer(
    FfmAssistantQueryRequest request,
  ) async {
    final isWeek = request.normalizedText.contains('minggu');
    final start = isWeek
        ? DateTime(
            request.now.year,
            request.now.month,
            request.now.day,
          ).subtract(Duration(days: request.now.weekday - 1))
        : DateTime(request.now.year, request.now.month);
    final end = isWeek
        ? start.add(const Duration(days: 7))
        : DateTime(start.year, start.month + 1);
    final rows =
        await (_database.select(_database.transactions)..where(
              (row) =>
                  row.householdId.equals(request.householdId) &
                  row.isArchived.equals(false) &
                  row.isDeleted.equals(false),
            ))
            .get();
    var income = 0;
    var expense = 0;
    var count = 0;
    for (final row in rows) {
      if (row.date.isBefore(start) || !row.date.isBefore(end)) continue;
      if (row.type == 'income') {
        income += row.amount.abs();
        count++;
      } else if (row.type == 'expense') {
        expense += row.amount.abs();
        count++;
      }
    }
    final period = isWeek ? 'minggu ini' : 'bulan ini';
    return FfmAssistantQueryAnswer(
      title: 'Ringkasan $period',
      message:
          'Dari $count transaksi tercatat pada $period: pemasukan ${_rupiah(income)} dan pengeluaran ${_rupiah(expense)}. Transfer antar rekening tidak dihitung sebagai pemasukan atau pengeluaran.',
    );
  }
}

class _ActiveActivityQueryTool implements FfmAssistantQueryTool {
  const _ActiveActivityQueryTool(this._database);

  final AppDatabase _database;

  @override
  bool canHandle(String normalizedText) =>
      normalizedText.contains('aktivitas aktif') ||
      normalizedText.contains('lagi apa') ||
      normalizedText.contains('sedang apa') ||
      normalizedText.contains('aktivitas berjalan') ||
      normalizedText.contains('riwayat aktivitas') ||
      normalizedText.contains('kebiasaan kegiatan') ||
      normalizedText.contains('kegiatan saya');

  @override
  Future<FfmAssistantQueryAnswer?> answer(
    FfmAssistantQueryRequest request,
  ) async {
    final isAskingHistory =
        request.normalizedText.contains('riwayat') ||
        request.normalizedText.contains('kebiasaan') ||
        request.normalizedText.contains('kegiatan saya');

    if (isAskingHistory) {
      final history =
          await (_database.select(_database.activityEntries)
                ..where(
                  (row) =>
                      row.householdId.equals(request.householdId) &
                      row.isArchived.equals(false),
                )
                ..orderBy([(row) => OrderingTerm.desc(row.startedAt)])
                ..limit(5))
              .get();
      if (history.isEmpty) {
        return const FfmAssistantQueryAnswer(
          title: 'Riwayat Aktivitas',
          message: 'Belum ada riwayat aktivitas atau jurnal yang tersimpan.',
        );
      }
      final buffer = StringBuffer();
      buffer.writeln('Ini 5 riwayat aktivitas terakhirmu:');
      for (final entry in history) {
        final date =
            '${entry.startedAt.day}/${entry.startedAt.month}/${entry.startedAt.year}';
        buffer.writeln('- $date: ${entry.title} (${entry.activityType})');
      }
      return FfmAssistantQueryAnswer(
        title: 'Riwayat Aktivitas',
        message: buffer.toString(),
      );
    }

    final rows =
        await (_database.select(_database.activitySessions)
              ..where(
                (row) =>
                    row.householdId.equals(request.householdId) &
                    row.status.equals('active') &
                    row.isArchived.equals(false),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.startedAt)]))
            .get();
    if (rows.isEmpty) {
      return const FfmAssistantQueryAnswer(
        title: 'Aktivitas aktif',
        message: 'Tidak ada aktivitas aktif sekarang. Kamu bisa bilang “mulai aktivitas [nama]” kalau mau menyiapkan catatan aktivitas.',
      );
    }
    final lines = rows
        .map((row) {
          final duration = request.now.difference(row.startedAt);
          return '• ${row.title} — ${_duration(duration)}';
        })
        .join('\n');
    return FfmAssistantQueryAnswer(
      title: 'Aktivitas aktif',
      message: 'Ada ${rows.length} aktivitas yang masih berjalan:\n$lines',
    );
  }
}

class _GoalStatusQueryTool implements FfmAssistantQueryTool {
  const _GoalStatusQueryTool(this._database);

  final AppDatabase _database;

  @override
  bool canHandle(String normalizedText) =>
      (normalizedText.contains('target') ||
          normalizedText.contains('tujuan')) &&
      (normalizedText.contains('status') ||
          normalizedText.contains('progres') ||
          normalizedText.contains('sisa') ||
          normalizedText.contains('berapa'));

  @override
  Future<FfmAssistantQueryAnswer?> answer(
    FfmAssistantQueryRequest request,
  ) async {
    final rows =
        await (_database.select(_database.goals)..where(
              (row) =>
                  row.householdId.equals(request.householdId) &
                  row.isActive.equals(true),
            ))
            .get();
    if (rows.isEmpty) {
      return const FfmAssistantQueryAnswer(
        title: 'Target keuangan',
        message: 'Belum ada target keuangan aktif. Kalau kamu mau, sebut nama target dan nominalnya supaya aku siapkan rancangan form.',
      );
    }
    final matched = rows
        .where((row) => request.normalizedText.contains(_fold(row.name)))
        .toList(growable: false);
    final goal = matched.length == 1 ? matched.single : rows.first;
    final remaining = (goal.targetAmount - goal.currentAmount).clamp(
      0,
      goal.targetAmount,
    );
    final percent = goal.targetAmount == 0
        ? 0
        : ((goal.currentAmount / goal.targetAmount) * 100).round();
    return FfmAssistantQueryAnswer(
      title: 'Target ${goal.name}',
      message:
          'Target ${goal.name}: terkumpul ${_rupiah(goal.currentAmount)} dari ${_rupiah(goal.targetAmount)} ($percent%). Sisa ${_rupiah(remaining)}. Ini hanya informasi, belum ada setoran atau perubahan data.',
    );
  }
}

class _DebtStatusQueryTool implements FfmAssistantQueryTool {
  const _DebtStatusQueryTool(this._database);

  final AppDatabase _database;

  @override
  bool canHandle(String normalizedText) =>
      (normalizedText.contains('hutang') ||
          normalizedText.contains('utang') ||
          normalizedText.contains('piutang')) &&
      (normalizedText.contains('status') ||
          normalizedText.contains('sisa') ||
          normalizedText.contains('total') ||
          normalizedText.contains('berapa'));

  @override
  Future<FfmAssistantQueryAnswer?> answer(
    FfmAssistantQueryRequest request,
  ) async {
    final asksReceivable = request.normalizedText.contains('piutang');
    if (asksReceivable) {
      final rows =
          await (_database.select(_database.receivables)..where(
                (row) =>
                    row.householdId.equals(request.householdId) &
                    row.isActive.equals(true),
              ))
              .get();
      final total = rows.fold<int>(0, (sum, row) => sum + row.remainingBalance);
      return FfmAssistantQueryAnswer(
        title: 'Piutang aktif',
        message: rows.isEmpty
            ? 'Belum ada piutang aktif yang tercatat.'
            : 'Ada ${rows.length} piutang aktif dengan sisa total ${_rupiah(total)}.',
      );
    }
    final rows =
        await (_database.select(_database.liabilities)..where(
              (row) =>
                  row.householdId.equals(request.householdId) &
                  row.isActive.equals(true),
            ))
            .get();
    final total = rows.fold<int>(0, (sum, row) => sum + row.remainingBalance);
    return FfmAssistantQueryAnswer(
      title: 'Hutang aktif',
      message: rows.isEmpty
          ? 'Belum ada hutang aktif yang tercatat.'
          : 'Ada ${rows.length} hutang aktif dengan sisa total ${_rupiah(total)}.',
    );
  }
}

class _AssetSummaryQueryTool implements FfmAssistantQueryTool {
  const _AssetSummaryQueryTool(this._database);

  final AppDatabase _database;

  @override
  bool canHandle(String normalizedText) =>
      normalizedText.contains('aset') &&
      (normalizedText.contains('total') ||
          normalizedText.contains('nilai') ||
          normalizedText.contains('berapa'));

  @override
  Future<FfmAssistantQueryAnswer?> answer(
    FfmAssistantQueryRequest request,
  ) async {
    final rows =
        await (_database.select(_database.assets)..where(
              (row) =>
                  row.householdId.equals(request.householdId) &
                  row.isArchived.equals(false),
            ))
            .get();
    final total = rows.fold<int>(0, (sum, row) => sum + row.value);
    return FfmAssistantQueryAnswer(
      title: 'Aset tercatat',
      message: rows.isEmpty
          ? 'Belum ada aset tercatat.'
          : 'Ada ${rows.length} aset aktif dengan nilai tercatat total ${_rupiah(total)}.',
    );
  }
}

String _fold(String value) =>
    value.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');

String _rupiah(int amount) {
  final digits = amount.abs().toString();
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) buffer.write('.');
    buffer.write(digits[index]);
  }
  return '${amount < 0 ? '-' : ''}Rp$buffer';
}

String _duration(Duration value) {
  if (value.inHours > 0) {
    return '${value.inHours} jam ${value.inMinutes.remainder(60)} menit';
  }
  return '${value.inMinutes} menit';
}

class _LoanAffordabilityQueryTool extends FfmAssistantQueryTool {
  _LoanAffordabilityQueryTool(this._database);

  final AppDatabase _database;

  @override
  bool canHandle(String normalizedText) {
    final asksDebt =
        normalizedText.contains('pinjam') ||
        normalizedText.contains('cicil') ||
        normalizedText.contains('kredit') ||
        normalizedText.contains('utang') ||
        normalizedText.contains('hutang');
    final asksAssessment =
        normalizedText.contains('kemampuan') ||
        normalizedText.contains('bisa') ||
        normalizedText.contains('aman') ||
        normalizedText.contains('maksimal') ||
        normalizedText.contains('layak') ||
        normalizedText.contains('sanggup') ||
        normalizedText.contains('berapa');
    return asksDebt && asksAssessment;
  }

  @override
  Future<FfmAssistantQueryAnswer?> answer(
    FfmAssistantQueryRequest request,
  ) async {
    final evidence = await FfmAssistantFinancialSnapshotService(_database)
        .readCurrentMonth(householdId: request.householdId, now: request.now);
    final analysis = FfmAssistantLoanAffordabilityAnalysis.calculate(
      evidence: evidence,
    );

    return FfmAssistantQueryAnswer(
      title: 'Analisis Kemampuan Pinjaman',
      message: _formatAnalysis(analysis),
    );
  }

  String _formatAnalysis(FfmAssistantLoanAffordabilityAnalysis analysis) {
    final evidence = analysis.evidence;
    final buffer = StringBuffer()
      ..writeln('Status: ${analysis.qualityLabel}.')
      ..writeln('Periode: ${evidence.periodLabel}.')
      ..writeln('Pemasukan tercatat: ${_rupiah(evidence.income)}.')
      ..writeln('Pengeluaran tercatat: ${_rupiah(evidence.expenses)}.')
      ..writeln(
        'Cicilan aktif: ${_rupiah(evidence.currentInstallments)} '
        '(${evidence.activeLiabilityCount} kewajiban).',
      );

    if (!analysis.hasEnoughData) {
      buffer
        ..writeln()
        ..writeln(
          'Belum ada dasar data yang cukup untuk menilai kemampuan pinjaman secara personal.',
        )
        ..writeln(analysis.reason)
        ..writeln(
          'Secara edukatif, total cicilan baru dan lama sebaiknya dijaga maksimal sekitar 30% dari pemasukan bulanan, tetapi angka ini bukan persetujuan kredit.',
        )
        ..writeln(
          'Saran: catat pemasukan dan pengeluaran rutin di FFM selama beberapa periode, lalu evaluasi kembali dari Ringkasan dan Analisis.',
        );
      return buffer.toString();
    }

    buffer
      ..writeln(
        'Cashflow sebelum cicilan: ${_rupiah(evidence.cashflowBeforeDebt)}.',
      )
      ..writeln(
        'Cashflow setelah cicilan aktif: ${_rupiah(evidence.cashflowAfterDebt)}.',
      )
      ..writeln(
        'Batas total cicilan konservatif (30% pemasukan): ${_rupiah(analysis.safeDebtServiceLimit)}.',
      )
      ..writeln(
        'Sisa ruang berdasarkan batas cicilan: ${_rupiah(analysis.remainingDebtServiceCapacity)}.',
      )
      ..writeln(
        'Sisa ruang berdasarkan cashflow: ${_rupiah(analysis.cashflowCapacity)}.',
      )
      ..writeln();

    if (analysis.shouldAvoidNewLoan) {
      buffer
        ..writeln('Saran utama: **jangan menambah pinjaman baru dulu**.')
        ..writeln(analysis.reason)
        ..writeln(
          'Prioritaskan menstabilkan cashflow, meninjau pengeluaran, dan mengecek kewajiban aktif di halaman Liabilities.',
        );
    } else {
      buffer
        ..writeln(
          'Estimasi cicilan baru konservatif: maksimal ${_rupiah(analysis.recommendedNewInstallment)} per bulan.',
        )
        ..writeln(
          'Angka ini adalah batas internal untuk simulasi, bukan nominal pinjaman pokok. Untuk menghitung pokok pinjaman diperlukan bunga, biaya, dan tenor nyata dari pemberi pinjaman.',
        )
        ..writeln(
          'Sebelum mengambil keputusan, sisakan dana kebutuhan rutin dan dana darurat; jangan menganggap piutang sebagai kas sampai benar-benar diterima.',
        );
    }

    buffer
      ..writeln()
      ..writeln('Asumsi: ${analysis.assumptions.join(' ')}')
      ..writeln(
        'Catatan: hasil ini adalah analisis berbasis data lokal FFM, bukan persetujuan kredit atau jaminan pinjaman aman.',
      );
    return buffer.toString();
  }
}

class _FrequencyAnalysisQueryTool implements FfmAssistantQueryTool {
  _FrequencyAnalysisQueryTool(this._analysisEngine);

  final FfmAssistantAnalysisEngine _analysisEngine;

  @override
  bool canHandle(String normalizedText) {
    return normalizedText.contains('frekuensi') ||
           normalizedText.contains('sering') ||
           normalizedText.contains('paling sering') ||
           (normalizedText.contains('berapa kali') && 
            (normalizedText.contains('bulan') || normalizedText.contains('minggu')));
  }

  @override
  Future<FfmAssistantQueryAnswer?> answer(
    FfmAssistantQueryRequest request,
  ) async {
    final now = request.now;
    final start = now.subtract(const Duration(days: 30));
    final end = now;

    final analysis = await _analysisEngine.analyzeFrequency(
      householdId: request.householdId,
      start: start,
      end: end,
    );

    if (analysis.totalTransactions == 0) {
      return const FfmAssistantQueryAnswer(
        title: 'Analisis Frekuensi',
        message: 'Belum ada transaksi dalam 30 hari terakhir untuk dianalisis frekuensinya.',
      );
    }

    final buffer = StringBuffer()
      ..writeln('Analisis frekuensi transaksi (30 hari terakhir):')
      ..writeln('Total transaksi: ${analysis.totalTransactions}')
      ..writeln();

    if (analysis.categoryFrequency.isNotEmpty) {
      buffer.writeln('Frekuensi per kategori:');
      final sortedCategories = analysis.categoryFrequency.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final entry in sortedCategories.take(5)) {
        buffer.writeln('- ${entry.key}: ${entry.value} kali');
      }
      buffer.writeln();
    }

    if (analysis.merchantFrequency.isNotEmpty) {
      buffer.writeln('Frekuensi per merchant:');
      final sortedMerchants = analysis.merchantFrequency.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final entry in sortedMerchants.take(5)) {
        buffer.writeln('- ${entry.key}: ${entry.value} kali');
      }
      buffer.writeln();
    }

    if (analysis.dayOfWeekFrequency.isNotEmpty) {
      final days = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
      final mostFrequentDay = analysis.mostFrequentDay;
      if (mostFrequentDay >= 1 && mostFrequentDay <= 7) {
        buffer.writeln('Hari paling aktif: ${days[mostFrequentDay - 1]}');
      }
    }

    return FfmAssistantQueryAnswer(
      title: 'Analisis Frekuensi',
      message: buffer.toString().trim(),
    );
  }
}

class _TrendAnalysisQueryTool implements FfmAssistantQueryTool {
  _TrendAnalysisQueryTool(this._analysisEngine);

  final FfmAssistantAnalysisEngine _analysisEngine;

  @override
  bool canHandle(String normalizedText) {
    return normalizedText.contains('trend') ||
           normalizedText.contains('tren') ||
           normalizedText.contains('naik') ||
           normalizedText.contains('turun') ||
           (normalizedText.contains('perubahan') && 
            (normalizedText.contains('bulan') || normalizedText.contains('bulan ke')));
  }

  @override
  Future<FfmAssistantQueryAnswer?> answer(
    FfmAssistantQueryRequest request,
  ) async {
    final now = request.now;
    final start = DateTime(now.year, now.month - 3, 1);
    final end = DateTime(now.year, now.month + 1, 1);

    // Determine trend type from request
    FfmTrendType trendType = FfmTrendType.both;
    if (request.normalizedText.contains('pemasukan') || 
        request.normalizedText.contains('income')) {
      trendType = FfmTrendType.income;
    } else if (request.normalizedText.contains('pengeluaran') || 
               request.normalizedText.contains('expense')) {
      trendType = FfmTrendType.expense;
    }

    final analysis = await _analysisEngine.analyzeTrend(
      householdId: request.householdId,
      start: start,
      end: end,
      type: trendType,
    );

    if (analysis.monthlyData.isEmpty) {
      return const FfmAssistantQueryAnswer(
        title: 'Analisis Trend',
        message: 'Belum ada data cukup untuk menganalisis trend dalam 3 bulan terakhir.',
      );
    }

    final buffer = StringBuffer()
      ..writeln('Analisis trend (3 bulan terakhir):')
      ..writeln('Arah trend: ${analysis.trendDirection}')
      ..writeln();

    buffer.writeln('Data bulanan:');
    for (final month in analysis.monthlyData) {
      buffer.writeln('- ${month.month}:');
      if (trendType == FfmTrendType.income || trendType == FfmTrendType.both) {
        buffer.writeln('  Pemasukan: ${_rupiah(month.income)}');
      }
      if (trendType == FfmTrendType.expense || trendType == FfmTrendType.both) {
        buffer.writeln('  Pengeluaran: ${_rupiah(month.expense)}');
      }
      buffer.writeln('  Jumlah transaksi: ${month.count}');
    }

    return FfmAssistantQueryAnswer(
      title: 'Analisis Trend',
      message: buffer.toString().trim(),
    );
  }
}

class _PatternAnalysisQueryTool implements FfmAssistantQueryTool {
  _PatternAnalysisQueryTool(this._analysisEngine);

  final FfmAssistantAnalysisEngine _analysisEngine;

  @override
  bool canHandle(String normalizedText) {
    return normalizedText.contains('pola') ||
           normalizedText.contains('pattern') ||
           normalizedText.contains('rata-rata') ||
           normalizedText.contains('biasanya') ||
           (normalizedText.contains('kategori') && 
            (normalizedText.contains('terbanyak') || normalizedText.contains('terbesar')));
  }

  @override
  Future<FfmAssistantQueryAnswer?> answer(
    FfmAssistantQueryRequest request,
  ) async {
    final now = request.now;
    final start = now.subtract(const Duration(days: 30));
    final end = now;

    final analysis = await _analysisEngine.analyzePatterns(
      householdId: request.householdId,
      start: start,
      end: end,
    );

    if (analysis.categoryPatterns.isEmpty) {
      return const FfmAssistantQueryAnswer(
        title: 'Analisis Pola',
        message: 'Belum ada transaksi dalam 30 hari terakhir untuk dianalisis polanya.',
      );
    }

    final buffer = StringBuffer()
      ..writeln('Analisis pola pengeluaran (30 hari terakhir):')
      ..writeln();

    final sortedPatterns = analysis.categoryPatterns.entries.toList()
      ..sort((a, b) => b.value.total.compareTo(a.value.total));

    for (final entry in sortedPatterns.take(5)) {
      final pattern = entry.value;
      buffer.writeln('Kategori: ${pattern.category}');
      buffer.writeln('- Jumlah: ${pattern.count} kali');
      buffer.writeln('- Total: ${_rupiah(pattern.total)}');
      buffer.writeln('- Rata-rata: ${_rupiah(pattern.average)}');
      buffer.writeln('- Median: ${_rupiah(pattern.median)}');
      buffer.writeln('- Rentang: ${_rupiah(pattern.min)} - ${_rupiah(pattern.max)}');
      buffer.writeln();
    }

    return FfmAssistantQueryAnswer(
      title: 'Analisis Pola',
      message: buffer.toString().trim(),
    );
  }
}

class _PeriodAnalysisQueryTool implements FfmAssistantQueryTool {
  _PeriodAnalysisQueryTool(this._analysisEngine);

  final FfmAssistantAnalysisEngine _analysisEngine;

  @override
  bool canHandle(String normalizedText) {
    return (normalizedText.contains('30 hari') || 
            normalizedText.contains('90 hari') ||
            normalizedText.contains('3 bulan') ||
            normalizedText.contains('bulan ini') ||
            normalizedText.contains('bulan lalu')) &&
           (normalizedText.contains('berapa') ||
            normalizedText.contains('total') ||
            normalizedText.contains('ringkasan'));
  }

  @override
  Future<FfmAssistantQueryAnswer?> answer(
    FfmAssistantQueryRequest request,
  ) async {
    FfmAnalysisPeriod period = FfmAnalysisPeriod.last30Days;
    
    if (request.normalizedText.contains('90 hari') || 
        request.normalizedText.contains('3 bulan')) {
      period = FfmAnalysisPeriod.last90Days;
    } else if (request.normalizedText.contains('bulan ini')) {
      period = FfmAnalysisPeriod.thisMonth;
    } else if (request.normalizedText.contains('bulan lalu')) {
      period = FfmAnalysisPeriod.lastMonth;
    }

    final analysis = await _analysisEngine.analyzePeriod(
      householdId: request.householdId,
      period: period,
      referenceDate: request.now,
    );

    if (analysis.transactionCount == 0) {
      return FfmAssistantQueryAnswer(
        title: 'Analisis Periode',
        message: 'Belum ada transaksi dalam ${analysis.periodLabel}.',
      );
    }

    final buffer = StringBuffer()
      ..writeln('Ringkasan ${analysis.periodLabel}:')
      ..writeln('Pemasukan: ${_rupiah(analysis.income)}')
      ..writeln('Pengeluaran: ${_rupiah(analysis.expense)}')
      ..writeln('Net cashflow: ${_rupiah(analysis.netCashflow)}')
      ..writeln('Jumlah transaksi: ${analysis.transactionCount}')
      ..writeln();

    if (analysis.expenseRatio != null) {
      buffer.writeln('Rasio pengeluaran: ${(analysis.expenseRatio! * 100).toStringAsFixed(1)}%');
    }

    if (analysis.categoryBreakdown.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Breakdown kategori terbesar:');
      final sortedCategories = analysis.categoryBreakdown.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final entry in sortedCategories.take(5)) {
        buffer.writeln('- ${entry.key}: ${_rupiah(entry.value)}');
      }
    }

    return FfmAssistantQueryAnswer(
      title: 'Analisis Periode',
      message: buffer.toString().trim(),
    );
  }
}

class _DataCompletenessQueryTool implements FfmAssistantQueryTool {
  const _DataCompletenessQueryTool(this._database);

  final AppDatabase _database;

  @override
  bool canHandle(String normalizedText) {
    final question = FfmAssistantCatalog.classifyBasicQuestion(normalizedText);
    return question?.kind == FfmAssistantBasicQuestionKind.completeness &&
        question?.page.dataSection != null;
  }

  @override
  Future<FfmAssistantQueryAnswer?> answer(
    FfmAssistantQueryRequest request,
  ) async {
    final section = FfmAssistantCatalog.classifyBasicQuestion(
      request.normalizedText,
    )?.page.dataSection;
    if (section == null) return null;
    return switch (section) {
      FfmAssistantDataSection.masterData => _masterData(request.householdId),
      FfmAssistantDataSection.profile => _profile(request.householdId),
      FfmAssistantDataSection.budget => _budget(request.householdId),
      FfmAssistantDataSection.goals => _goals(request.householdId),
      FfmAssistantDataSection.assets => _assets(request.householdId),
      FfmAssistantDataSection.liabilities => _liabilities(request.householdId),
      FfmAssistantDataSection.reminders => _reminders(request.householdId),
      FfmAssistantDataSection.activities => _activities(request.householdId),
      FfmAssistantDataSection.transactions => _transactions(
        request.householdId,
      ),
    };
  }

  Future<FfmAssistantQueryAnswer> _masterData(String householdId) async {
    final accounts =
        await (_database.select(_database.accounts)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isActive.equals(true) &
                  row.isArchived.equals(false),
            ))
            .get();
    final categories =
        await (_database.select(_database.categories)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isActive.equals(true),
            ))
            .get();
    final merchants =
        await (_database.select(_database.merchants)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isActive.equals(true),
            ))
            .get();
    final tags =
        await (_database.select(_database.tags)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isArchived.equals(false),
            ))
            .get();
    final missing = <String>[
      if (accounts.isEmpty) 'minimal satu rekening aktif',
      if (categories.isEmpty) 'minimal satu kategori aktif',
    ];
    final message = missing.isEmpty
        ? 'Data Utama sudah siap untuk pencatatan: ${accounts.length} rekening aktif dan ${categories.length} kategori aktif. Merchant (${merchants.length}) dan tag (${tags.length}) bersifat opsional.'
        : 'Data Utama belum lengkap untuk pencatatan. Yang masih kosong: ${missing.join(', ')}. Saat ini ada ${accounts.length} rekening aktif dan ${categories.length} kategori aktif. Merchant dan tag tetap opsional.';
    return FfmAssistantQueryAnswer(
      title: 'Kelengkapan Data Utama',
      message: message,
    );
  }

  Future<FfmAssistantQueryAnswer> _profile(String householdId) async {
    final rows = await (_database.select(
      _database.userPreferences,
    )..where((row) => row.householdId.equals(householdId))).get();
    final values = <String, String>{
      for (final row in rows) row.preferenceKey: row.preferenceValue.trim(),
    };
    const labels = <String, String>{
      'profile_name': 'nama/panggilan',
      'profile_occupation': 'pekerjaan/peran',
      'profile_routine': 'rutinitas penting',
      'profile_goals': 'tujuan/prioritas',
    };
    final missing = labels.entries
        .where((entry) => (values[entry.key] ?? '').isEmpty)
        .map((entry) => entry.value)
        .toList(growable: false);
    return FfmAssistantQueryAnswer(
      title: 'Kelengkapan Profil Asisten',
      message: missing.isEmpty
          ? 'Profil personalisasi sudah lengkap: nama/panggilan, pekerjaan/peran, rutinitas penting, dan tujuan/prioritas sudah terisi.'
          : 'Profil personalisasi belum lengkap. Yang masih kosong: ${missing.join(', ')}. Ini opsional dan tidak menghalangi pencatatan keuangan; isi di Lainnya > Profil Personalisasi Asisten > Kenalkan Diri bila kamu ingin jawaban lebih sesuai konteksmu.',
    );
  }

  Future<FfmAssistantQueryAnswer> _budget(String householdId) async {
    final rows =
        await (_database.select(_database.envelopeBudgets)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isActive.equals(true),
            ))
            .get();
    return _optionalSection(
      title: 'Kelengkapan Anggaran',
      count: rows.length,
      configured: 'Ada ${rows.length} pos anggaran aktif yang dapat dipantau.',
      empty: 'Belum ada pos anggaran aktif. Ini bukan kesalahan bila kamu belum ingin memakai anggaran; kamu dapat menambahkannya di halaman Anggaran.',
    );
  }

  Future<FfmAssistantQueryAnswer> _goals(String householdId) async {
    final rows =
        await (_database.select(_database.goals)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isActive.equals(true),
            ))
            .get();
    return _optionalSection(
      title: 'Kelengkapan Target Keuangan',
      count: rows.length,
      configured: 'Ada ${rows.length} target keuangan aktif.',
      empty: 'Belum ada target keuangan aktif. Ini opsional; buat target hanya bila ada tujuan dana yang ingin dilacak.',
    );
  }

  Future<FfmAssistantQueryAnswer> _assets(String householdId) async {
    final rows =
        await (_database.select(_database.assets)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isArchived.equals(false),
            ))
            .get();
    return _optionalSection(
      title: 'Kelengkapan Aset',
      count: rows.length,
      configured: 'Ada ${rows.length} aset yang masih dicatat.',
      empty: 'Belum ada aset yang dicatat. Ini opsional dan tidak menghalangi transaksi atau laporan arus kas.',
    );
  }

  Future<FfmAssistantQueryAnswer> _liabilities(String householdId) async {
    final liabilities =
        await (_database.select(_database.liabilities)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isActive.equals(true),
            ))
            .get();
    final receivables =
        await (_database.select(_database.receivables)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isActive.equals(true),
            ))
            .get();
    final total = liabilities.length + receivables.length;
    return FfmAssistantQueryAnswer(
      title: 'Kelengkapan Hutang & Piutang',
      message: total == 0
          ? 'Belum ada hutang atau piutang aktif yang dicatat. Ini bukan data yang wajib diisi bila memang tidak ada kewajiban atau tagihan.'
          : 'Ada ${liabilities.length} hutang aktif dan ${receivables.length} piutang aktif yang dicatat.',
    );
  }

  Future<FfmAssistantQueryAnswer> _reminders(String householdId) async {
    final rows =
        await (_database.select(_database.reminders)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isActive.equals(true),
            ))
            .get();
    return _optionalSection(
      title: 'Kelengkapan Pengingat',
      count: rows.length,
      configured: 'Ada ${rows.length} pengingat aktif.',
      empty: 'Belum ada pengingat aktif. Ini opsional; tambahkan bila ada jadwal yang ingin diingatkan di perangkat ini.',
    );
  }

  Future<FfmAssistantQueryAnswer> _activities(String householdId) async {
    final rows =
        await (_database.select(_database.activityEntries)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isArchived.equals(false),
            ))
            .get();
    return _optionalSection(
      title: 'Kelengkapan Aktivitas',
      count: rows.length,
      configured: 'Ada ${rows.length} catatan aktivitas yang tersimpan.',
      empty: 'Belum ada catatan aktivitas. Ini opsional; mulai aktivitas saat kamu ingin melacak durasi kegiatan.',
    );
  }

  Future<FfmAssistantQueryAnswer> _transactions(String householdId) async {
    final rows =
        await (_database.select(_database.transactions)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isArchived.equals(false) &
                  row.isDeleted.equals(false),
            ))
            .get();
    return FfmAssistantQueryAnswer(
      title: 'Kelengkapan Transaksi',
      message: rows.isEmpty
          ? 'Belum ada transaksi aktif yang dicatat. Data Utama tetap dapat disiapkan lebih dulu, lalu catat transaksi pertama ketika ada pemasukan, pengeluaran, atau transfer nyata.'
          : 'Ada ${rows.length} transaksi aktif yang tersimpan. Angka ini hanya menghitung catatan aktif dan tidak membuat perubahan apa pun.',
    );
  }

  FfmAssistantQueryAnswer _optionalSection({
    required String title,
    required int count,
    required String configured,
    required String empty,
  }) => FfmAssistantQueryAnswer(
    title: title,
    message: count > 0 ? configured : empty,
  );
}

class _PersonalProfileQueryTool implements FfmAssistantQueryTool {
  const _PersonalProfileQueryTool(this.database);
  final AppDatabase database;

  @override
  bool canHandle(String normalizedText) {
    return RegExp(
      r'\b(profil|pekerjaan|rutinitas|tujuan|kebiasaan|identitas|siapa saya|saya siapa|saya itu siapa|tentang saya|mengenal saya)\b',
    ).hasMatch(normalizedText);
  }

  @override
  Future<FfmAssistantQueryAnswer?> answer(
    FfmAssistantQueryRequest request,
  ) async {
    final prefs = await (database.select(
      database.userPreferences,
    )..where((row) => row.householdId.equals(request.householdId))).get();
    if (prefs.isEmpty) {
      return const FfmAssistantQueryAnswer(
        title: 'Profil Pribadi',
        message: 'Aku belum punya catatan tentang profil, rutinitas, atau kebiasaanmu. Kamu bisa mengisinya di menu Lainnya > Profil Personalisasi Asisten > Kenalkan Diri.',
      );
    }

    final values = <String, String>{
      for (final p in prefs) p.preferenceKey: p.preferenceValue,
    };
    final name = values['profile_name'] ?? 'Belum diisi';
    final occupation = values['profile_occupation'] ?? 'Belum diisi';
    final routine = values['profile_routine'] ?? 'Belum diisi';
    final goals = values['profile_goals'] ?? 'Belum diisi';

    final buffer = StringBuffer();
    buffer.writeln('Berdasarkan catatan perkenalan dirimu:');
    buffer.writeln('- Nama/Panggilan: $name');
    buffer.writeln('- Pekerjaan/Peran: $occupation');
    buffer.writeln('- Rutinitas Penting: $routine');
    buffer.writeln('- Tujuan/Prioritas: $goals');
    buffer.writeln();
    buffer.write(
      'Informasi ini aku pakai untuk menyesuaikan jawaban dan saran, tanpa melatih ulang model AI.',
    );

    return FfmAssistantQueryAnswer(
      title: 'Profil & Kebiasaan',
      message: buffer.toString(),
    );
  }
}
