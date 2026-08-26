/// Plugin kategori Logic (Logika) — Menjalankan kalkulasi cerdas, rasio, simulasi,
/// serta evaluasi kondisi finansial keluarga secara 100% deterministik dan offline.
library;

import 'package:drift/drift.dart';

import '../../../../core/database/app_context.dart';
import '../../../../core/database/app_database.dart';
import '../../domain/ffm_agent_harness.dart';

String _rupiah(int amount) {
  final abs = amount.abs();
  final str = abs.toString().split('').reversed.join();
  final chunks = RegExp(r'.{1,3}').allMatches(str).map((m) => m.group(0)!);
  final formatted = chunks.join('.').split('').reversed.join();
  return '${amount < 0 ? '-' : ''}Rp $formatted';
}

String _householdId() => AppContext.householdId;

/// Plugin Logika: Menghitung zakat mal dan zakat fitrah berdasarkan total saldo kas.
class FfmZakatLogicPlugin extends FfmAgentPlugin {
  FfmZakatLogicPlugin(this._db);
  final AppDatabase _db;

  static const int defaultGoldPricePerGram = 1350000;
  static const int nisabGrams = 85;
  static const int defaultRicePricePerKg = 15000;
  static const double fitrahKgPerPerson = 2.5;

  @override
  String get name => 'zakat_logic';
  @override
  FfmPluginCategory get category => FfmPluginCategory.logic;
  @override
  int get priority => 9;
  @override
  List<String> get triggers => [
    'hitung zakat',
    'zakat mal',
    'zakat fitrah',
    'kewajiban zakat',
    'nisab zakat',
    'kalkulator zakat',
    'zakat penghasilan',
    'zakat harta',
    'apakah saya wajib zakat',
  ];

  @override
  Future<FfmHarnessResult?> execute(FfmHarnessContext context) async {
    final householdId = _householdId();

    final accounts =
        await (_db.select(_db.accounts)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isActive.equals(true) &
                  row.isArchived.equals(false),
            ))
            .get();

    var totalCash = 0;
    for (final acc in accounts) {
      final txs =
          await (_db.select(_db.transactions)..where(
                (row) =>
                    row.householdId.equals(householdId) &
                    row.accountId.equals(acc.id) &
                    row.isArchived.equals(false) &
                    row.isDeleted.equals(false),
              ))
              .get();
      final tfs =
          await (_db.select(_db.transfers)..where(
                (row) =>
                    row.householdId.equals(householdId) &
                    (row.fromAccountId.equals(acc.id) |
                        row.toAccountId.equals(acc.id)) &
                    row.isDeleted.equals(false),
              ))
              .get();
      var b = acc.openingBalance;
      for (final t in txs) {
        if (t.type == 'income') b += t.amount.abs();
        if (t.type == 'expense') b -= t.amount.abs();
      }
      for (final tf in tfs) {
        if (tf.fromAccountId == acc.id) b -= tf.amount;
        if (tf.toAccountId == acc.id) b += tf.amount;
      }
      totalCash += b;
    }

    final assets =
        await (_db.select(_db.assets)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isArchived.equals(false),
            ))
            .get();
    var liquidAssetValue = 0;
    for (final a in assets) {
      final lower = a.name.toLowerCase();
      if (lower.contains('emas') ||
          lower.contains('tabungan') ||
          lower.contains('deposito') ||
          lower.contains('reksadana') ||
          lower.contains('saham')) {
        liquidAssetValue += a.value;
      }
    }

    final totalWealth = totalCash + liquidAssetValue;
    final nisabNominal = defaultGoldPricePerGram * nisabGrams;
    final wajibZakatMal = totalWealth >= nisabNominal;
    final zakatMalAmount = wajibZakatMal ? (totalWealth * 0.025).round() : 0;
    final zakatFitrahPerPerson = (defaultRicePricePerKg * fitrahKgPerPerson).round();

    final lines = <String>[
      '🕋 **Kalkulator Zakat Mal & Fitrah**\n',
      '💰 **Harta Terhitung (Kas + Aset Likuid):** ${_rupiah(totalWealth)}',
      '   • Saldo Kas Rekening: ${_rupiah(totalCash)}',
      if (liquidAssetValue > 0)
        '   • Aset Likuid (Emas/Investasi): ${_rupiah(liquidAssetValue)}',
      '⚖️ **Nisab Emas 85 gram (asumsi ${_rupiah(defaultGoldPricePerGram)}/g):** ${_rupiah(nisabNominal)}\n',
      wajibZakatMal
          ? '✅ **Status: WAJIB Zakat Mal** (Harta melampaui nisab)\n'
                '👉 **Kewajiban Zakat Mal (2,5%): ${_rupiah(zakatMalAmount)}** / haul (1 tahun)'
          : 'ℹ️ **Status: Belum Wajib Zakat Mal** (Harta belum mencapai nisab ${_rupiah(nisabNominal)}).\n'
                '   Kurang ${_rupiah(nisabNominal - totalWealth)} lagi untuk mencapai batas nisab.',
      '\n🌾 **Zakat Fitrah (estimasi beras 2,5 kg/jiwa):**',
      '   • Per Jiwa: ${_rupiah(zakatFitrahPerPerson)} (asumsi beras ${_rupiah(defaultRicePricePerKg)}/kg)',
      '   • Keluarga (4 jiwa): ${_rupiah(zakatFitrahPerPerson * 4)}',
      '\n⚠️ *Perhitungan ini bersifat estimasi. Silakan salurkan zakat melalui lembaga amil zakat resmi (BAZNAS / LAZ).*',
    ];

    return FfmHarnessResult(
      pluginName: name,
      category: category,
      text: lines.join('\n'),
      metadata: {
        'totalWealth': totalWealth,
        'nisabNominal': nisabNominal,
        'wajibZakatMal': wajibZakatMal,
        'zakatMalAmount': zakatMalAmount,
        'zakatFitrahPerPerson': zakatFitrahPerPerson,
      },
    );
  }
}

/// Plugin Logika: Menganalisis rasio kesehatan keuangan (Rasio Tabungan, Rasio Hutang).
class FfmFinancialHealthLogicPlugin extends FfmAgentPlugin {
  FfmFinancialHealthLogicPlugin(this._db);
  final AppDatabase _db;

  @override
  String get name => 'financial_health_logic';
  @override
  FfmPluginCategory get category => FfmPluginCategory.logic;
  @override
  int get priority => 8;
  @override
  List<String> get triggers => [
    'kesehatan keuangan',
    'skor keuangan',
    'kondisi keuangan',
    'evaluasi keuangan',
    'cek kesehatan finansial',
    'rasio tabungan',
    'analisis keuangan',
    'kondisi finansial',
  ];

  @override
  Future<FfmHarnessResult?> execute(FfmHarnessContext context) async {
    final now = context.now;
    final householdId = _householdId();
    final start = DateTime(now.year, now.month);
    final nextMonth = DateTime(now.year, now.month + 1);

    final rows =
        await (_db.select(_db.transactions)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isArchived.equals(false) &
                  row.isDeleted.equals(false),
            ))
            .get();

    var income = 0;
    var expense = 0;

    for (final row in rows) {
      if (row.date.isBefore(start) || !row.date.isBefore(nextMonth)) continue;
      if (row.type == 'income') income += row.amount.abs();
      if (row.type == 'expense') expense += row.amount.abs();
    }

    final liabilities =
        await (_db.select(_db.liabilities)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isActive.equals(true),
            ))
            .get();
    final monthlyDebt =
        liabilities.fold<int>(0, (sum, row) => sum + row.monthlyInstallment);

    if (income == 0) {
      return const FfmHarnessResult(
        pluginName: 'financial_health_logic',
        category: FfmPluginCategory.logic,
        text:
            '📊 **Analisis Kesehatan Keuangan**\n\n'
            'Belum ada data pemasukan bulan ini untuk menghitung rasio. Catat pemasukan bulan ini terlebih dahulu.',
      );
    }

    final savings = (income - expense).clamp(0, income);
    final savingsRate = (savings / income * 100).round();
    final debtToIncomeRate = (monthlyDebt / income * 100).round();

    final healthBadge = savingsRate >= 20 && debtToIncomeRate <= 30
        ? '🟢 **SEHAT PRIMA**'
        : savingsRate >= 10 && debtToIncomeRate <= 40
        ? '🟡 **CUKUP SEHAT**'
        : '🔴 **PERLU PERBAIKAN**';

    final lines = <String>[
      '🏥 **Rapor Kesehatan Finansial Keluarga**\n',
      'Status Keseluruhan: $healthBadge\n',
      '📈 **1. Rasio Tabungan (Savings Rate): $savingsRate%** (Ideal: ≥ 20%)',
      savingsRate >= 20
          ? '   ✅ Luar biasa! Kemampuan menabung Anda sangat baik.'
          : savingsRate >= 10
          ? '   ⚠️ Masih aman, namun usahakan tingkatkan ke 20%.'
          : '   🔴 Rendah. Pengeluaran menyerap hampir seluruh pemasukan.',
      '\n💳 **2. Rasio Beban Cicilan (Debt Service Ratio): $debtToIncomeRate%** (Maksimal Aman: ≤ 30%)',
      debtToIncomeRate == 0
          ? '   ✅ Bebas cicilan! Tidak ada beban hutang bulanan.'
          : debtToIncomeRate <= 30
          ? '   ✅ Porsi cicilan dalam batas aman (≤ 30% pemasukan).'
          : '   ⚠️ Peringatan: Beban cicilan melebihi batas aman 30% pemasukan!',
      '\n💡 **Rekomendasi Aksi:**',
      if (savingsRate < 20)
        '- Sisihkan minimal 10-20% di awal gajian ke amplop tabungan sebelum belanja.',
      if (debtToIncomeRate > 30)
        '- Tahan pengajuan pinjaman/kredit baru hingga rasio cicilan turun.',
      if (savingsRate >= 20 && debtToIncomeRate <= 30)
        '- Pertahankan pola ini dan alokasikan surplus ke dana darurat atau investasi.',
    ];

    return FfmHarnessResult(
      pluginName: name,
      category: category,
      text: lines.join('\n'),
      metadata: {
        'savingsRate': savingsRate,
        'debtToIncomeRate': debtToIncomeRate,
        'income': income,
        'expense': expense,
      },
    );
  }
}

/// Plugin Logika: Budget Guard mendeteksi kategori yang overbudget atau mendekati batas.
class FfmBudgetGuardLogicPlugin extends FfmAgentPlugin {
  FfmBudgetGuardLogicPlugin(this._db);
  final AppDatabase _db;

  @override
  String get name => 'budget_guard_logic';
  @override
  FfmPluginCategory get category => FfmPluginCategory.logic;
  @override
  int get priority => 9;
  @override
  List<String> get triggers => [
    'budget guard',
    'peringatan anggaran',
    'overbudget',
    'anggaran jebol',
    'anggaran habis',
    'waspada pengeluaran',
  ];

  @override
  Future<FfmHarnessResult?> execute(FfmHarnessContext context) async {
    final now = context.now;
    final householdId = _householdId();
    final start = DateTime(now.year, now.month);
    final end = DateTime(now.year, now.month + 1);

    final budgets =
        await (_db.select(_db.envelopeBudgets)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isActive.equals(true),
            ))
            .get();

    if (budgets.isEmpty) {
      return const FfmHarnessResult(
        pluginName: 'budget_guard_logic',
        category: FfmPluginCategory.logic,
        text:
            '📋 Belum ada anggaran aktif untuk dipantau. Buat anggaran terlebih dahulu agar Budget Guard bisa bekerja.',
      );
    }

    final transactions =
        await (_db.select(_db.transactions)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isArchived.equals(false) &
                  row.isDeleted.equals(false),
            ))
            .get();

    final spendByCategory = <String, int>{};
    for (final t in transactions) {
      if (t.date.isBefore(start) || !t.date.isBefore(end)) continue;
      if (t.type != 'expense') continue;
      final cat = t.categoryId ?? 'unknown';
      spendByCategory[cat] = (spendByCategory[cat] ?? 0) + t.amount.abs();
    }

    final alerts = <String>[];
    final warnings = <String>[];

    for (final budget in budgets) {
      final spent = spendByCategory[budget.categoryId] ?? 0;
      final pct = budget.allocated > 0 ? (spent / budget.allocated * 100).round() : 0;
      if (spent > budget.allocated) {
        final over = spent - budget.allocated;
        alerts.add(
          '🔴 **$budget.name**: Melebihi ${_rupiah(over)} ($pct%)',
        );
      } else if (pct >= 80) {
        warnings.add(
          '🟡 **${budget.name}**: Sudah $pct% terpakai (sisa ${_rupiah(budget.allocated - spent)})',
        );
      }
    }

    if (alerts.isEmpty && warnings.isEmpty) {
      return const FfmHarnessResult(
        pluginName: 'budget_guard_logic',
        category: FfmPluginCategory.logic,
        text:
            '🛡️ **Budget Guard: Semua Anggaran Aman!**\n\n'
            'Semua pos anggaran masih berada di bawah 80% alokasi. Pengeluaran terkendali dengan baik.',
      );
    }

    final lines = <String>[
      '🛡️ **Budget Guard: Deteksi Pengeluaran Berisiko**\n',
      if (alerts.isNotEmpty) ...[
        '⚠️ **Pos Melebihi Anggaran (Overbudget):**',
        ...alerts,
        '',
      ],
      if (warnings.isNotEmpty) ...[
        '🔔 **Pos Mendekati Batas (≥ 80%):**',
        ...warnings,
        '',
      ],
      '💡 *Saran: Pertimbangkan memindahkan saldo dari pos anggaran lain melalui fitur Transfer Amplop.*',
    ];

    return FfmHarnessResult(
      pluginName: name,
      category: category,
      text: lines.join('\n'),
      metadata: {'alerts': alerts.length, 'warnings': warnings.length},
    );
  }
}

/// Plugin Logika: Simulasi batas aman kemampuan cicilan pinjaman.
class FfmLoanAffordabilityLogicPlugin extends FfmAgentPlugin {
  FfmLoanAffordabilityLogicPlugin(this._db);
  final AppDatabase _db;

  @override
  String get name => 'loan_affordability_logic';
  @override
  FfmPluginCategory get category => FfmPluginCategory.logic;
  @override
  int get priority => 8;
  @override
  List<String> get triggers => [
    'simulasi pinjaman',
    'bisa pinjam berapa',
    'kemampuan cicilan',
    'batas cicilan',
    'kalkulator pinjaman',
    'hitung pinjaman',
    'simulasi kredit',
  ];

  @override
  Future<FfmHarnessResult?> execute(FfmHarnessContext context) async {
    final now = context.now;
    final householdId = _householdId();
    final start = DateTime(now.year, now.month);
    final end = DateTime(now.year, now.month + 1);

    final rows =
        await (_db.select(_db.transactions)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isArchived.equals(false) &
                  row.isDeleted.equals(false),
            ))
            .get();

    var income = 0;
    for (final row in rows) {
      if (row.date.isBefore(start) || !row.date.isBefore(end)) continue;
      if (row.type == 'income') income += row.amount.abs();
    }

    final liabilities =
        await (_db.select(_db.liabilities)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isActive.equals(true),
            ))
            .get();
    final existingInstallments = liabilities.fold<int>(
      0,
      (sum, row) => sum + row.monthlyInstallment,
    );

    if (income == 0) {
      return const FfmHarnessResult(
        pluginName: 'loan_affordability_logic',
        category: FfmPluginCategory.logic,
        text:
            '🏦 **Simulasi Cicilan**\n\n'
            'Belum ada data pemasukan bulan ini. Catat pemasukan agar aku bisa menghitung kemampuan cicilan yang aman.',
      );
    }

    final maxSafeInstallment = (income * 0.30).round();
    final remainingCapacity = maxSafeInstallment - existingInstallments;

    final examplePrincipal = remainingCapacity > 0
        ? (remainingCapacity * 12 / 1.12).toInt()
        : 0;

    return FfmHarnessResult(
      pluginName: name,
      category: category,
      text:
          '🏦 **Simulasi Kemampuan Cicilan**\n\n'
          '💰 Pemasukan bulan ini: ${_rupiah(income)}\n'
          '🏦 Cicilan berjalan: ${_rupiah(existingInstallments)}\n'
          '📊 Batas aman cicilan (30%): ${_rupiah(maxSafeInstallment)}\n\n'
          '**Kapasitas cicilan tambahan: ${_rupiah(remainingCapacity > 0 ? remainingCapacity : 0)}**\n\n'
          '${remainingCapacity > 0 ? '📋 *Estimasi pinjaman maksimal (12 bulan, bunga 12%/thn flat):*\n**~${_rupiah(examplePrincipal)}**\n\n' : '⚠️ Cicilan berjalan sudah melebihi batas aman 30%. Tidak disarankan menambah pinjaman baru.\n\n'}'
          '⚠️ *Ini simulasi kasar. Konsultasikan dengan lembaga keuangan terpercaya sebelum mengambil keputusan.*',
      metadata: {
        'income': income,
        'existingInstallments': existingInstallments,
        'maxSafeInstallment': maxSafeInstallment,
        'remainingCapacity': remainingCapacity,
      },
    );
  }
}

/// Plugin Logika: Menghitung laju pengeluaran (Burn Rate), evaluasi Boros vs Hemat,
/// proyeksi akhir bulan, serta batas belanja harian aman.
class FfmSpendingPaceLogicPlugin extends FfmAgentPlugin {
  FfmSpendingPaceLogicPlugin(this._db);
  final AppDatabase _db;

  @override
  String get name => 'spending_pace_logic';
  @override
  FfmPluginCategory get category => FfmPluginCategory.logic;
  @override
  int get priority => 9;
  @override
  List<String> get triggers => [
    'boros',
    'hemat',
    'apakah saya boros',
    'apakah saya hemat',
    'laju pengeluaran',
    'burn rate',
    'pola belanja saya',
    'evaluasi belanja',
    'proyeksi pengeluaran',
    'kuota belanja harian',
    'batas belanja harian',
  ];

  @override
  Future<FfmHarnessResult?> execute(FfmHarnessContext context) async {
    final now = context.now;
    final householdId = _householdId();
    final start = DateTime(now.year, now.month);
    final nextMonth = DateTime(now.year, now.month + 1);
    final daysInMonth = nextMonth.difference(start).inDays;
    final dayPassed = now.day;
    final remainingDays = (daysInMonth - dayPassed).clamp(1, 31);

    final rows = await (_db.select(_db.transactions)
          ..where((row) =>
              row.householdId.equals(householdId) &
              row.isArchived.equals(false) &
              row.isDeleted.equals(false)))
        .get();

    var income = 0;
    var expense = 0;
    final categoryTotals = <String, int>{};

    for (final row in rows) {
      if (row.date.isBefore(start) || !row.date.isBefore(nextMonth)) continue;
      if (row.type == 'income') {
        income += row.amount.abs();
      } else if (row.type == 'expense') {
        final amt = row.amount.abs();
        expense += amt;
        final catId = row.categoryId ?? 'Lain-lain';
        categoryTotals[catId] = (categoryTotals[catId] ?? 0) + amt;
      }
    }

    if (expense == 0 && income == 0) {
      return const FfmHarnessResult(
        pluginName: 'spending_pace_logic',
        category: FfmPluginCategory.logic,
        text: '📊 **Evaluasi Pengeluaran**\n\n'
            'Belum ada transaksi pengeluaran atau pemasukan yang dicatat bulan ini.',
      );
    }

    final timePercent = ((dayPassed / daysInMonth) * 100).round();
    final expensePercent = income > 0 ? ((expense / income) * 100).round() : 100;
    final dailyAverage = (expense / dayPassed).round();
    final projectedMonthEndExpense = (dailyAverage * daysInMonth).round();

    final remainingBudget = (income - expense).clamp(0, 999999999999);
    final safeDailyQuota = (remainingBudget / remainingDays).round();

    String statusTitle;
    String statusExplanation;
    if (income > 0 && expensePercent > (timePercent + 20)) {
      statusTitle = '🔴 **Status: Cenderung Boros (Laju Terlalu Cepat)**';
      statusExplanation =
          'Baru berjalan $timePercent% bulan (hari ke-$dayPassed dari $daysInMonth), tetapi Anda sudah menghabiskan $expensePercent% dari total pemasukan.';
    } else if (income > 0 && expensePercent <= timePercent) {
      statusTitle = '🟢 **Status: Terkendali & Hemat**';
      statusExplanation =
          'Laju belanja Anda sangat sehat! Sudah $timePercent% bulan berjalan, dan pengeluaran baru mencapai $expensePercent% dari pemasukan.';
    } else {
      statusTitle = '🟡 **Status: Cukup Waspada**';
      statusExplanation =
          'Pengeluaran Anda seimbang dengan perjalanan bulan ($expensePercent% pengeluaran di $timePercent% bulan berjalan).';
    }

    final categories = await (_db.select(_db.categories)
          ..where((row) => row.householdId.equals(householdId)))
        .get();
    final categoryNameMap = {for (final c in categories) c.id: c.name};

    final sortedCategories = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topLines = <String>[];
    for (final entry in sortedCategories.take(3)) {
      final name = categoryNameMap[entry.key] ?? entry.key;
      final pct = expense > 0 ? ((entry.value / expense) * 100).round() : 0;
      topLines.add('- **$name**: ${_rupiah(entry.value)} ($pct%)');
    }

    final projectionText = income > 0
        ? (projectedMonthEndExpense > income
            ? '⚠️ **Proyeksi Akhir Bulan:** Diprediksi tembus **${_rupiah(projectedMonthEndExpense)}** (Potensi Defisit ${_rupiah(projectedMonthEndExpense - income)})'
            : '✅ **Proyeksi Akhir Bulan:** Diprediksi **${_rupiah(projectedMonthEndExpense)}** (Surplus Sisa Tabungan ${_rupiah(income - projectedMonthEndExpense)})')
        : '⚠️ Belum ada data pemasukan untuk memproyeksikan surplus/defisit.';

    return FfmHarnessResult(
      pluginName: name,
      category: category,
      text: '📊 **Evaluasi Pola Pengeluaran & Laju Belanja**\n\n'
          '$statusTitle\n$statusExplanation\n\n'
          '📈 **Statistik Pengeluaran:**\n'
          '- Rata-rata per hari: ${_rupiah(dailyAverage)}/hari\n'
          '- Total pengeluaran saat ini: ${_rupiah(expense)}\n'
          '${income > 0 ? '- Total pemasukan: ${_rupiah(income)}\n' : ''}\n'
          '${topLines.isNotEmpty ? '🛍️ **Pos Pengeluaran Terbesar:**\n${topLines.join('\n')}\n\n' : ''}'
          '🔮 $projectionText\n\n'
          '💡 **Rekomendasi Kuota Aman:**\n'
          'Batas belanja harian maksimal Anda untuk **$remainingDays hari tersisa** adalah **${_rupiah(safeDailyQuota)}/hari** agar keuangan tetap aman dan tidak defisit.',
      metadata: {
        'expensePercent': expensePercent,
        'timePercent': timePercent,
        'safeDailyQuota': safeDailyQuota,
      },
    );
  }
}

/// Plugin Logika: Ringkasan menyeluruh (Holistic Awareness) menggabungkan
/// Kas, Hutang, Anggaran, Target, dan Rasio Finansial.
class FfmHolisticAwarenessPlugin extends FfmAgentPlugin {
  FfmHolisticAwarenessPlugin(this._db);
  final AppDatabase _db;

  @override
  String get name => 'holistic_awareness';
  @override
  FfmPluginCategory get category => FfmPluginCategory.logic;
  @override
  int get priority => 8;
  @override
  List<String> get triggers => [
    'kondisi keuangan keseluruhan',
    'potret keuangan',
    'kesehatan keuangan lengkap',
    'ringkasan menyeluruh',
    'kondisi finansial saya',
    'dashboard keuangan',
    'keuangan saya secara umum',
    'situasi keuangan',
  ];

  @override
  Future<FfmHarnessResult?> execute(FfmHarnessContext context) async {
    final householdId = _householdId();
    final now = context.now;
    final start = DateTime(now.year, now.month);
    final nextMonth = DateTime(now.year, now.month + 1);

    // 1. Total Kas
    final accounts = await (_db.select(_db.accounts)
          ..where((row) =>
              row.householdId.equals(householdId) &
              row.isActive.equals(true) &
              row.isArchived.equals(false)))
        .get();
    var totalCash = 0;
    for (final acc in accounts) {
      final txs = await (_db.select(_db.transactions)
            ..where((row) =>
                row.householdId.equals(householdId) &
                row.accountId.equals(acc.id) &
                row.isArchived.equals(false) &
                row.isDeleted.equals(false)))
          .get();
      final tfs = await (_db.select(_db.transfers)
            ..where((row) =>
                row.householdId.equals(householdId) &
                (row.fromAccountId.equals(acc.id) |
                    row.toAccountId.equals(acc.id)) &
                row.isDeleted.equals(false)))
          .get();
      var b = acc.openingBalance;
      for (final t in txs) {
        if (t.type == 'income') b += t.amount.abs();
        if (t.type == 'expense') b -= t.amount.abs();
      }
      for (final tf in tfs) {
        if (tf.fromAccountId == acc.id) b -= tf.amount;
        if (tf.toAccountId == acc.id) b += tf.amount;
      }
      totalCash += b;
    }

    // 2. Transaksi Bulan Ini
    final txRows = await (_db.select(_db.transactions)
          ..where((row) =>
              row.householdId.equals(householdId) &
              row.isArchived.equals(false) &
              row.isDeleted.equals(false)))
        .get();
    var income = 0;
    var expense = 0;
    for (final row in txRows) {
      if (row.date.isBefore(start) || !row.date.isBefore(nextMonth)) continue;
      if (row.type == 'income') income += row.amount.abs();
      if (row.type == 'expense') expense += row.amount.abs();
    }

    // 3. Total Hutang
    final liabilities = await (_db.select(_db.liabilities)
          ..where((row) =>
              row.householdId.equals(householdId) & row.isActive.equals(true)))
        .get();
    final totalRemainingDebt =
        liabilities.fold<int>(0, (sum, row) => sum + row.remainingBalance);
    final monthlyDebt =
        liabilities.fold<int>(0, (sum, row) => sum + row.monthlyInstallment);

    // 4. Aset
    final assets = await (_db.select(_db.assets)
          ..where((row) =>
              row.householdId.equals(householdId) &
              row.isArchived.equals(false)))
        .get();
    final totalAssets = assets.fold<int>(0, (sum, row) => sum + row.value);

    // 5. Target
    final goals = await (_db.select(_db.goals)
          ..where((row) =>
              row.householdId.equals(householdId) & row.isActive.equals(true)))
        .get();

    final netWorth = totalCash + totalAssets - totalRemainingDebt;

    return FfmHarnessResult(
      pluginName: name,
      category: category,
      text: '🌐 **Potret Kondisi Keuangan Menyeluruh (360° View)**\n\n'
          '💰 **Likuiditas & Arus Kas:**\n'
          '- Total Saldo Kas di Rekening: **${_rupiah(totalCash)}**\n'
          '- Pemasukan Bulan Ini: ${_rupiah(income)}\n'
          '- Pengeluaran Bulan Ini: ${_rupiah(expense)}\n'
          '- Arus Kas Bersih (Cashflow): ${income - expense >= 0 ? "🟢 +" : "🔴 -"}${_rupiah((income - expense).abs())}\n\n'
          '📦 **Kekayaan & Kewajiban:**\n'
          '- Total Nilai Aset: ${_rupiah(totalAssets)} (${assets.length} aset)\n'
          '- Sisa Kewajiban Hutang: ${_rupiah(totalRemainingDebt)} (Cicilan ${_rupiah(monthlyDebt)}/bln)\n'
          '- **Kekayaan Bersih (Net Worth): ${_rupiah(netWorth)}**\n\n'
          '🎯 **Target Finansial:**\n'
          '- ${goals.length} target tabungan aktif sedang berjalan\n\n'
          '💡 *Tip Asisten: Selalu prioritaskan cicilan hutang dan pertahankan dana darurat minimal 3 bulan pengeluaran.*',
    );
  }
}

/// Plugin Logika: Menghitung kebutuhan dan kecukupan dana darurat keluarga.
class FfmEmergencyFundLogicPlugin extends FfmAgentPlugin {
  FfmEmergencyFundLogicPlugin(this._db);
  final AppDatabase _db;

  @override
  String get name => 'emergency_fund_logic';
  @override
  FfmPluginCategory get category => FfmPluginCategory.logic;
  @override
  int get priority => 8;
  @override
  List<String> get triggers => [
    'dana darurat',
    'hitung dana darurat',
    'kebutuhan darurat',
    'emergency fund',
    'dana cadangan',
    'tabungan darurat',
    'berapa dana darurat',
    'cukup dana darurat',
    'simpanan darurat',
  ];

  @override
  Future<FfmHarnessResult?> execute(FfmHarnessContext context) async {
    final householdId = _householdId();
    final now = context.now;

    // Hitung rata-rata pengeluaran 3 bulan terakhir
    final threeMonthsAgo = DateTime(now.year, now.month - 3, 1);
    final expenseRows = await (_db.select(_db.transactions)
          ..where(
            (row) =>
                row.householdId.equals(householdId) &
                row.type.equals('expense') &
                row.isArchived.equals(false) &
                row.isDeleted.equals(false) &
                row.date.isBiggerOrEqualValue(threeMonthsAgo),
          ))
        .get();

    var totalExpense3Mo = 0;
    for (final t in expenseRows) {
      totalExpense3Mo += t.amount.abs();
    }
    final avgMonthlyExpense =
        expenseRows.isEmpty ? 0 : (totalExpense3Mo / 3).round();

    // Hitung saldo kas saat ini
    final accounts = await (_db.select(_db.accounts)
          ..where(
            (row) =>
                row.householdId.equals(householdId) &
                row.isActive.equals(true) &
                row.isArchived.equals(false),
          ))
        .get();

    var currentCash = 0;
    for (final acc in accounts) {
      final txs = await (_db.select(_db.transactions)
            ..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.accountId.equals(acc.id) &
                  row.isArchived.equals(false) &
                  row.isDeleted.equals(false),
            ))
          .get();
      final tfs = await (_db.select(_db.transfers)
            ..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  (row.fromAccountId.equals(acc.id) |
                      row.toAccountId.equals(acc.id)) &
                  row.isDeleted.equals(false),
            ))
          .get();
      var b = acc.openingBalance;
      for (final t in txs) {
        if (t.type == 'income') b += t.amount.abs();
        if (t.type == 'expense') b -= t.amount.abs();
      }
      for (final tf in tfs) {
        if (tf.fromAccountId == acc.id) b -= tf.amount;
        if (tf.toAccountId == acc.id) b += tf.amount;
      }
      currentCash += b;
    }

    if (avgMonthlyExpense == 0) {
      return const FfmHarnessResult(
        pluginName: 'emergency_fund_logic',
        category: FfmPluginCategory.logic,
        text: '🛡️ **Kalkulator Dana Darurat**\n\n'
            'Belum ada data pengeluaran yang cukup untuk menghitung kebutuhan dana darurat. '
            'Catat minimal 1 bulan pengeluaran agar asisten bisa memberikan perhitungan akurat.',
      );
    }

    final needed3Mo = avgMonthlyExpense * 3;
    final needed6Mo = avgMonthlyExpense * 6;
    final needed12Mo = avgMonthlyExpense * 12;

    final coverageMonths =
        avgMonthlyExpense > 0 ? (currentCash / avgMonthlyExpense) : 0;
    final coverageLabel = coverageMonths >= 12
        ? '✅ Sangat Ideal (≥12 bulan)'
        : coverageMonths >= 6
        ? '🟢 Ideal (6–12 bulan)'
        : coverageMonths >= 3
        ? '🟡 Cukup (3–6 bulan) — tingkatkan ke 6 bulan'
        : coverageMonths >= 1
        ? '🔴 Kurang (< 3 bulan) — prioritaskan segera'
        : '⚠️ Sangat Kritis (< 1 bulan)';

    final gap3Mo = needed3Mo - currentCash;
    final gapText = gap3Mo > 0
        ? 'Masih butuh **${_rupiah(gap3Mo)}** lagi untuk mencapai target minimum 3 bulan.'
        : '**Dana darurat sudah melewati target minimum 3 bulan.** 🎉';

    return FfmHarnessResult(
      pluginName: name,
      category: category,
      text: '🛡️ **Kalkulator Dana Darurat Keluarga**\n\n'
          '📊 **Data Dasar (rata-rata 3 bulan terakhir):**\n'
          '- Pengeluaran bulanan rata-rata: **${_rupiah(avgMonthlyExpense)}**\n'
          '- Kas & saldo saat ini: **${_rupiah(currentCash)}**\n'
          '- Kemampuan bertahan: **${coverageMonths.toStringAsFixed(1)} bulan**\n\n'
          '🎯 **Kebutuhan Dana Darurat:**\n'
          '- Minimum (3 bulan): ${_rupiah(needed3Mo)}\n'
          '- Ideal (6 bulan): ${_rupiah(needed6Mo)}\n'
          '- Sangat Aman (12 bulan): ${_rupiah(needed12Mo)}\n\n'
          '📈 **Status Kecukupan: $coverageLabel**\n\n'
          '$gapText\n\n'
          '💡 *Tip: Pisahkan dana darurat ke rekening tabungan terpisah agar '
          'tidak terpakai untuk kebutuhan sehari-hari.*',
      metadata: {
        'avgMonthlyExpense': avgMonthlyExpense,
        'currentCash': currentCash,
        'needed3Mo': needed3Mo,
        'needed6Mo': needed6Mo,
        'coverageMonths': coverageMonths,
      },
    );
  }
}

/// Plugin Logika: Menghitung strategi pelunasan hutang (Debt Snowball vs Debt Avalanche).
class FfmDebtSnowballLogicPlugin extends FfmAgentPlugin {
  FfmDebtSnowballLogicPlugin(this._db);
  final AppDatabase _db;

  @override
  String get name => 'debt_snowball_logic';
  @override
  FfmPluginCategory get category => FfmPluginCategory.logic;
  @override
  int get priority => 8;
  @override
  List<String> get triggers => [
    'strategi lunas hutang',
    'debt snowball',
    'debt avalanche',
    'cara cepat lunas hutang',
    'urutan bayar hutang',
    'strategi hutang',
    'bebas hutang',
    'lunasi hutang',
    'cara melunasi hutang',
  ];

  @override
  Future<FfmHarnessResult?> execute(FfmHarnessContext context) async {
    final householdId = _householdId();
    final debts = await (_db.select(_db.liabilities)
          ..where(
            (row) =>
                row.householdId.equals(householdId) &
                row.isActive.equals(true),
          ))
        .get();

    if (debts.isEmpty) {
      return const FfmHarnessResult(
        pluginName: 'debt_snowball_logic',
        category: FfmPluginCategory.logic,
        text: '🎉 **Alhamdulillah!** Tidak ada catatan hutang/kewajiban aktif di FFM. '
            'Pertahankan kondisi bebas hutang ini dan fokus alokasikan dana ke tabungan & investasi.',
      );
    }

    var totalDebt = 0;
    var totalMonthlyInstallment = 0;
    for (final d in debts) {
      totalDebt += d.remainingBalance;
      totalMonthlyInstallment += d.monthlyInstallment;
    }

    // Urutan 1: Snowball (Saldo terkecil ke terbesar)
    final snowballList = List.of(debts)
      ..sort((a, b) => a.remainingBalance.compareTo(b.remainingBalance));

    // Urutan 2: Avalanche (Bunga tertinggi ke terendah)
    final avalancheList = List.of(debts)
      ..sort((a, b) => b.interestRate.compareTo(a.interestRate));

    final snowballLines = <String>[];
    for (var i = 0; i < snowballList.length; i++) {
      final d = snowballList[i];
      snowballLines.add(
        '${i + 1}. **${d.name}**: ${_rupiah(d.remainingBalance)} (Cicilan: ${_rupiah(d.monthlyInstallment)}/bln)',
      );
    }

    final avalancheLines = <String>[];
    for (var i = 0; i < avalancheList.length; i++) {
      final d = avalancheList[i];
      final rateStr = d.interestRate > 0 ? ' (Bunga: ${d.interestRate}%)' : '';
      avalancheLines.add(
        '${i + 1}. **${d.name}**: ${_rupiah(d.remainingBalance)}$rateStr',
      );
    }

    return FfmHarnessResult(
      pluginName: name,
      category: category,
      text: '🎯 **Strategi Percepatan Pelunasan Hutang Keluarga**\n\n'
          '📊 **Total Sisa Pokok Hutang:** **${_rupiah(totalDebt)}** (${debts.length} kewajiban)\n'
          '💳 **Total Cicilan Wajib:** ${_rupiah(totalMonthlyInstallment)}/bulan\n\n'
          '━━━━━━━━━━━━━━━━━━━━\n'
          '🏔️ **Metode 1: Debt Snowball (Sangat Direkomendasikan)**\n'
          '*Fokus lunasi dari nominal saldo TERKECIL dulu untuk kemenangan cepat & motivasi psikologis:*\n\n'
          '${snowballLines.join('\n')}\n\n'
          '━━━━━━━━━━━━━━━━━━━━\n'
          '⚡ **Metode 2: Debt Avalanche**\n'
          '*Fokus lunasi dari bunga TERTINGGI dulu untuk menghemat total biaya bunga:*\n\n'
          '${avalancheLines.join('\n')}\n\n'
          '💡 **Langkah Aksi:** Bayar cicilan minimum untuk semua hutang, lalu arahkan semua kelebihan dana bulanan ke **Prioritas #1** sampai lunas, lalu beralih ke #2!',
      metadata: {
        'totalDebt': totalDebt,
        'totalMonthlyInstallment': totalMonthlyInstallment,
        'count': debts.length,
      },
    );
  }
}

/// Plugin Logika: Menghitung rasio menabung bulanan (Saving Rate).
class FfmSavingRateLogicPlugin extends FfmAgentPlugin {
  FfmSavingRateLogicPlugin(this._db);
  final AppDatabase _db;

  @override
  String get name => 'saving_rate_logic';
  @override
  FfmPluginCategory get category => FfmPluginCategory.logic;
  @override
  int get priority => 8;
  @override
  List<String> get triggers => [
    'saving rate',
    'rasio menabung',
    'persentase tabungan',
    'berapa persen yang kutabung',
    'kemampuan menabung',
    'apakah tabungan cukup',
    'rasio tabungan',
  ];

  @override
  Future<FfmHarnessResult?> execute(FfmHarnessContext context) async {
    final householdId = _householdId();
    final now = context.now;
    final startOfMonth = DateTime(now.year, now.month, 1);

    final transactions = await (_db.select(_db.transactions)
          ..where(
            (row) =>
                row.householdId.equals(householdId) &
                row.isArchived.equals(false) &
                row.isDeleted.equals(false) &
                row.date.isBiggerOrEqualValue(startOfMonth),
          ))
        .get();

    var income = 0;
    var expense = 0;
    for (final t in transactions) {
      if (t.type == 'income') income += t.amount.abs();
      if (t.type == 'expense') expense += t.amount.abs();
    }

    if (income == 0) {
      return const FfmHarnessResult(
        pluginName: 'saving_rate_logic',
        category: FfmPluginCategory.logic,
        text: '📈 **Kalkulator Saving Rate Bulan Ini**\n\n'
            'Belum ada pemasukan yang tercatat di bulan ini. '
            'Catat pemasukan bulananmu agar asisten bisa menghitung rasio menabung dengan akurat.',
      );
    }

    final netSaved = income - expense;
    final savingRatePercent = (netSaved / income) * 100;

    final (label, icon, advice) = savingRatePercent >= 30
        ? (
            'Sangat Sehat (≥30%)',
            '⭐',
            'Luar biasa! Kapasitas menabungmu sangat kuat. Alokasikan sebagian ke instrumen investasi jangka panjang.',
          )
        : savingRatePercent >= 20
        ? (
            'Ideal (20–30%)',
            '🟢',
            'Bagus sekali! Kamu sudah memenuhi standar ideal perencanaan keuangan keluarga (minimal 20%).',
          )
        : savingRatePercent >= 10
        ? (
            'Cukup (10–20%)',
            '🟡',
            'Cukup baik, tetapi coba telusuri pos pengeluaran sekunder untuk meningkatkan tabungan ke minimal 20%.',
          )
        : savingRatePercent > 0
        ? (
            'Rendah (<10%)',
            '🔴',
            'Peringatan: Selisih tabungan sangat tipis. Prioritaskan menabung di awal bulan (pay yourself first).',
          )
        : (
            'Defisit (Pengeluaran > Pemasukan)',
            '⚠️',
            'Kritis: Pengeluaran bulan ini melebihi pemasukan. Segera rem belanja non-esensial!',
          );

    return FfmHarnessResult(
      pluginName: name,
      category: category,
      text: '📈 **Potret Rasio Menabung Bulan Ini (Saving Rate)**\n\n'
          '💰 **Arus Kas Bulan Ini:**\n'
          '- Total Pemasukan: **${_rupiah(income)}**\n'
          '- Total Pengeluaran: ${_rupiah(expense)}\n'
          '- Dana Tersimpan Bersih: **${netSaved >= 0 ? "+" : "-"}${_rupiah(netSaved.abs())}**\n\n'
          '📊 **Saving Rate:** $icon **${savingRatePercent.toStringAsFixed(1)}%** — *$label*\n\n'
          '💡 **Evaluasi Finansial:**\n$advice',
      metadata: {
        'income': income,
        'expense': expense,
        'netSaved': netSaved,
        'savingRatePercent': savingRatePercent,
      },
    );
  }
}


