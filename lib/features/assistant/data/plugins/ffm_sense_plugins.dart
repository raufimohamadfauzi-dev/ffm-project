/// Plugin kategori Sense (Mata) — Membaca data database SQLite secara lokal.
/// Tidak melakukan penulisan ke database.

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

/// Plugin Mata: Membaca total saldo dari semua rekening aktif.
class FfmBalanceSensePlugin extends FfmAgentPlugin {
  FfmBalanceSensePlugin(this._db);
  final AppDatabase _db;

  @override
  String get name => 'balance_sense';
  @override
  FfmPluginCategory get category => FfmPluginCategory.sense;
  @override
  int get priority => 9;
  @override
  List<String> get triggers => [
    'saldo',
    'total uang',
    'total kas',
    'sisa uang',
    'uang saya',
    'rekening',
    'berapa uang',
    'cek saldo',
    'isi rekening',
  ];

  @override
  bool canHandle(String normalizedText) {
    final lower = normalizedText.toLowerCase();
    // Jangan rebut perintah pencatatan/mutasi yang kebetulan menyebut
    // "rekening" (mis. "catat 1 juta ke rekening BRI baru").
    if (RegExp(
      r'^\s*(catat|simpan|tambah|transfer|pemasukan|pengeluaran|top ?up)\b',
    ).hasMatch(lower)) {
      return false;
    }
    return triggers.any(lower.contains);
  }

  @override
  Future<FfmHarnessResult?> execute(FfmHarnessContext context) async {
    final accounts =
        await (_db.select(_db.accounts)..where(
              (row) =>
                  row.householdId.equals(context.householdId) &
                  row.isActive.equals(true) &
                  row.isArchived.equals(false),
            ))
            .get();

    if (accounts.isEmpty) {
      return const FfmHarnessResult(
        pluginName: 'balance_sense',
        category: FfmPluginCategory.sense,
        text:
            '💳 Belum ada rekening aktif yang terdaftar di FFM. Buat rekening baru melalui menu **Data Utama**.',
      );
    }

    var grandTotal = 0;
    final lines = <String>[];

    for (final acc in accounts) {
      final txRows =
          await (_db.select(_db.transactions)..where(
                (row) =>
                    row.householdId.equals(context.householdId) &
                    row.accountId.equals(acc.id) &
                    row.isArchived.equals(false) &
                    row.isDeleted.equals(false),
              ))
              .get();

      final tfRows =
          await (_db.select(_db.transfers)..where(
                (row) =>
                    row.householdId.equals(context.householdId) &
                    (row.fromAccountId.equals(acc.id) |
                        row.toAccountId.equals(acc.id)) &
                    row.isDeleted.equals(false),
              ))
              .get();

      var balance = acc.openingBalance;
      for (final t in txRows) {
        if (t.type == 'income') balance += t.amount.abs();
        if (t.type == 'expense') balance -= t.amount.abs();
      }
      for (final tf in tfRows) {
        if (tf.fromAccountId == acc.id) balance -= tf.amount;
        if (tf.toAccountId == acc.id) balance += tf.amount;
      }

      grandTotal += balance;
      final typeLabel = acc.type == 'bank'
          ? '🏦'
          : acc.type == 'ewallet'
          ? '📱'
          : '💵';
      lines.add('- $typeLabel **${acc.name}**: ${_rupiah(balance)}');
    }

    return FfmHarnessResult(
      pluginName: name,
      category: category,
      text:
          '💳 **Posisi Kas & Saldo Rekening**\n\n${lines.join('\n')}\n\n**Total Keseluruhan: ${_rupiah(grandTotal)}**',
      metadata: {'grandTotal': grandTotal, 'accountCount': accounts.length},
    );
  }
}

/// Plugin Mata: Membaca ringkasan transaksi bulan ini.
class FfmTransactionSensePlugin extends FfmAgentPlugin {
  FfmTransactionSensePlugin(this._db);
  final AppDatabase _db;

  @override
  String get name => 'transaction_sense';
  @override
  FfmPluginCategory get category => FfmPluginCategory.sense;
  @override
  int get priority => 8;
  @override
  List<String> get triggers => [
    'ringkasan transaksi',
    'rekap transaksi',
    'ringkasan keuangan',
    'rekap keuangan',
    'laporan bulan ini',
    'pengeluaran bulan ini',
    'pemasukan bulan ini',
    'cashflow',
    'arus kas',
    'neraca bulan',
  ];

  @override
  Future<FfmHarnessResult?> execute(FfmHarnessContext context) async {
    final now = context.now;
    final start = DateTime(now.year, now.month);
    final nextMonth = DateTime(now.year, now.month + 1);

    final rows =
        await (_db.select(_db.transactions)..where(
              (row) =>
                  row.householdId.equals(context.householdId) &
                  row.isArchived.equals(false) &
                  row.isDeleted.equals(false),
            ))
            .get();

    var income = 0;
    var expense = 0;
    var txCount = 0;

    for (final row in rows) {
      if (row.date.isBefore(start) || !row.date.isBefore(nextMonth)) continue;
      txCount++;
      if (row.type == 'income') income += row.amount.abs();
      if (row.type == 'expense') expense += row.amount.abs();
    }

    final net = income - expense;
    final netSymbol = net >= 0 ? '🟢 +' : '🔴 -';

    return FfmHarnessResult(
      pluginName: name,
      category: category,
      text:
          '📊 **Rekap Arus Kas Bulan Ini (${now.month}/${now.year})**\n\n'
          '📈 **Total Pemasukan:** ${_rupiah(income)}\n'
          '📉 **Total Pengeluaran:** ${_rupiah(expense)}\n'
          '⚖️ **Selisih Bersih:** $netSymbol${_rupiah(net.abs())}\n\n'
          'Total transaksi tercatat: $txCount transaksi.',
      metadata: {
        'income': income,
        'expense': expense,
        'net': net,
        'txCount': txCount,
      },
    );
  }
}

/// Plugin Mata: Membaca status anggaran (budget envelopes).
class FfmBudgetSensePlugin extends FfmAgentPlugin {
  FfmBudgetSensePlugin(this._db);
  final AppDatabase _db;

  @override
  String get name => 'budget_sense';
  @override
  FfmPluginCategory get category => FfmPluginCategory.sense;
  @override
  int get priority => 8;
  @override
  List<String> get triggers => [
    'sisa anggaran',
    'status anggaran',
    'cek anggaran',
    'pos anggaran',
    'anggaran bulan ini',
    'amplop anggaran',
    'budget amplop',
    'kondisi anggaran',
  ];

  @override
  Future<FfmHarnessResult?> execute(FfmHarnessContext context) async {
    final now = context.now;
    final budgets =
        await (_db.select(_db.envelopeBudgets)..where(
              (row) =>
                  row.householdId.equals(context.householdId) &
                  row.isActive.equals(true),
            ))
            .get();

    if (budgets.isEmpty) {
      return const FfmHarnessResult(
        pluginName: 'budget_sense',
        category: FfmPluginCategory.sense,
        text:
            '📋 Belum ada anggaran aktif yang dibuat. Atur anggaran kategori melalui menu **Anggaran**.',
      );
    }

    final start = DateTime(now.year, now.month);
    final end = DateTime(now.year, now.month + 1);

    final transactions =
        await (_db.select(_db.transactions)..where(
              (row) =>
                  row.householdId.equals(context.householdId) &
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

    final lines = <String>[];
    var overbudgetCount = 0;

    for (final budget in budgets.take(8)) {
      final spent = spendByCategory[budget.categoryId] ?? 0;
      final remaining = budget.allocated - spent;
      final pct = budget.allocated > 0
          ? ((spent / budget.allocated) * 100).round()
          : 0;
      final statusIcon = remaining < 0
          ? '🔴'
          : pct >= 80
          ? '🟡'
          : '🟢';
      if (remaining < 0) overbudgetCount++;
      lines.add(
        '$statusIcon ${budget.name}: ${_rupiah(spent)} / ${_rupiah(budget.allocated)} ($pct%)',
      );
    }

    final alert = overbudgetCount > 0
        ? '\n\n⚠️ Ada $overbudgetCount pos anggaran yang melebihi batas!'
        : '';

    return FfmHarnessResult(
      pluginName: name,
      category: category,
      text:
          '📋 **Status Anggaran Bulan Ini**\n\n${lines.join('\n')}$alert',
      metadata: {'budgetCount': budgets.length, 'overbudget': overbudgetCount},
    );
  }
}

/// Plugin Mata: Membaca daftar hutang dan piutang.
class FfmDebtSensePlugin extends FfmAgentPlugin {
  FfmDebtSensePlugin(this._db);
  final AppDatabase _db;

  @override
  String get name => 'debt_sense';
  @override
  FfmPluginCategory get category => FfmPluginCategory.sense;
  @override
  int get priority => 8;
  @override
  List<String> get triggers => [
    'daftar hutang',
    'sisa hutang',
    'tagihan hutang',
    'cicilan hutang',
    'total hutang',
    'rekap hutang',
    'piutang',
    'yang minjam',
  ];

  @override
  Future<FfmHarnessResult?> execute(FfmHarnessContext context) async {
    final liabilities =
        await (_db.select(_db.liabilities)..where(
              (row) =>
                  row.householdId.equals(context.householdId) &
                  row.isActive.equals(true),
            ))
            .get();

    if (liabilities.isEmpty) {
      return const FfmHarnessResult(
        pluginName: 'debt_sense',
        category: FfmPluginCategory.sense,
        text:
            '🎉 **Alhamdulillah!** Tidak ada catatan hutang aktif yang tercatat.',
      );
    }

    var totalRemaining = 0;
    var totalMonthly = 0;
    final lines = <String>[];

    for (final item in liabilities) {
      totalMonthly += item.monthlyInstallment;
      totalRemaining += item.remainingBalance;
      lines.add(
        '- **${item.name}**: Cicilan ${_rupiah(item.monthlyInstallment)}/bln | Sisa ${_rupiah(item.remainingBalance)}',
      );
    }

    return FfmHarnessResult(
      pluginName: name,
      category: category,
      text:
          '💳 **Daftar Kewajiban & Hutang Aktif**\n\n'
          '${lines.join('\n')}\n\n'
          '**Total Sisa Hutang: ${_rupiah(totalRemaining)}**\n'
          '**Total Cicilan Bulanan: ${_rupiah(totalMonthly)}/bulan**',
      metadata: {
        'totalRemaining': totalRemaining,
        'totalMonthly': totalMonthly,
        'count': liabilities.length,
      },
    );
  }
}

/// Plugin Mata: Membaca daftar aset keluarga.
class FfmAssetSensePlugin extends FfmAgentPlugin {
  FfmAssetSensePlugin(this._db);
  final AppDatabase _db;

  @override
  String get name => 'asset_sense';
  @override
  FfmPluginCategory get category => FfmPluginCategory.sense;
  @override
  int get priority => 8;
  @override
  List<String> get triggers => [
    'daftar aset',
    'total aset',
    'nilai aset',
    'aset keluarga',
    'kekayaan',
    'harta',
    'barang berharga',
  ];

  @override
  Future<FfmHarnessResult?> execute(FfmHarnessContext context) async {
    final assets =
        await (_db.select(_db.assets)..where(
              (row) =>
                  row.householdId.equals(context.householdId) &
                  row.isArchived.equals(false),
            ))
            .get();

    if (assets.isEmpty) {
      return const FfmHarnessResult(
        pluginName: 'asset_sense',
        category: FfmPluginCategory.sense,
        text:
            '📦 Belum ada aset yang dicatat. Tambah aset (rumah, kendaraan, emas, dll) melalui menu **Aset**.',
      );
    }

    var totalValue = 0;
    final lines = <String>[];

    for (final asset in assets) {
      totalValue += asset.value;
      lines.add('- **${asset.name}** (${asset.assetType}): ${_rupiah(asset.value)}');
    }

    return FfmHarnessResult(
      pluginName: name,
      category: category,
      text:
          '📦 **Daftar Aset & Harta Keluarga**\n\n'
          '${lines.join('\n')}\n\n'
          '**Total Nilai Aset: ${_rupiah(totalValue)}**',
      metadata: {'totalValue': totalValue, 'count': assets.length},
    );
  }
}

/// Plugin Mata: Membaca target tabungan / impian finansial.
class FfmGoalSensePlugin extends FfmAgentPlugin {
  FfmGoalSensePlugin(this._db);
  final AppDatabase _db;

  @override
  String get name => 'goal_sense';
  @override
  FfmPluginCategory get category => FfmPluginCategory.sense;
  @override
  int get priority => 8;
  @override
  List<String> get triggers => [
    'progres target',
    'target tabungan',
    'impian finansial',
    'celengan',
    'progres impian',
    'target keuangan',
    'daftar target',
    'capaian target',
  ];

  @override
  Future<FfmHarnessResult?> execute(FfmHarnessContext context) async {
    final goals =
        await (_db.select(_db.goals)..where(
              (row) =>
                  row.householdId.equals(context.householdId) &
                  row.isActive.equals(true),
            ))
            .get();

    if (goals.isEmpty) {
      return const FfmHarnessResult(
        pluginName: 'goal_sense',
        category: FfmPluginCategory.sense,
        text:
            '🎯 Belum ada target tabungan aktif. Buat target impianmu (beli rumah, dana darurat, kurban, dll) di menu **Target**.',
      );
    }

    final lines = <String>[];

    for (final g in goals) {
      final current = g.currentAmount;
      final target = g.targetAmount;
      final pct = target > 0 ? ((current / target) * 100).round() : 0;
      final bar = _progressBar(pct);
      lines.add(
        '🎯 **${g.name}**\n'
        '   $bar $pct%\n'
        '   ${_rupiah(current)} / ${_rupiah(target)} (Sisa: ${_rupiah((target - current).clamp(0, target))})',
      );
    }

    return FfmHarnessResult(
      pluginName: name,
      category: category,
      text: '🎯 **Progress Target Tabungan**\n\n${lines.join('\n\n')}',
      metadata: {'count': goals.length},
    );
  }

  String _progressBar(int percent) {
    final clamped = percent.clamp(0, 100);
    final filled = (clamped / 10).round().clamp(0, 10);
    return '${'🟩' * filled}${'⬜' * (10 - filled)}';
  }
}

/// Plugin Mata: Membaca potret profil pengguna, pola jam/hari transaksi,
/// merchant terfavorit, dan catatan jurnal keseharian.
class FfmUserHabitsAndProfilePlugin extends FfmAgentPlugin {
  FfmUserHabitsAndProfilePlugin(this._db);
  final AppDatabase _db;

  @override
  String get name => 'user_habits_and_profile';
  @override
  FfmPluginCategory get category => FfmPluginCategory.sense;
  @override
  int get priority => 9;
  @override
  List<String> get triggers => [
    'sejauh mana kamu mengenalku',
    'apa saja kebiasaanku',
    'pola keseharianku',
    'kebiasaan belanja saya',
    'profil keuangan saya',
    'kamu tahu apa tentang saya',
    'pola hidup saya',
    'rutinitas saya',
    'sering melakukan apa',
    'apa yang sering saya lakukan',
    'apa yang sering aku lakukan',
    'sering ngapain',
    'aktivitas paling sering',
    'kegiatan paling sering',
    'kebiasaan 1 bulan terakhir',
  ];

  @override
  Future<FfmHarnessResult?> execute(FfmHarnessContext context) async {
    final householdId = _householdId();
    final now = context.now;
    final thirtyDaysAgo = now.subtract(const Duration(days: 30));

    final households = await (_db.select(_db.households)
          ..where((row) => row.id.equals(householdId)))
        .get();
    final familyName = households.isNotEmpty ? households.first.name : 'Keluarga FFM';

    // 1. Ambil transaksi 30 hari terakhir
    final transactions = await (_db.select(_db.transactions)
          ..where((row) =>
              row.householdId.equals(householdId) &
              row.isArchived.equals(false) &
              row.isDeleted.equals(false) &
              row.date.isBiggerOrEqualValue(thirtyDaysAgo)))
        .get();

    final categories = await (_db.select(_db.categories)
          ..where((row) => row.householdId.equals(householdId)))
        .get();
    final catMap = {for (final c in categories) c.id: c.name};

    final hourCounts = <int, int>{};
    final catCounts = <String, int>{};

    for (final t in transactions) {
      final hour = t.date.hour;
      hourCounts[hour] = (hourCounts[hour] ?? 0) + 1;
      final catName = t.categoryId != null && catMap.containsKey(t.categoryId)
          ? catMap[t.categoryId]!
          : (t.type == 'expense' ? 'Pengeluaran Umum' : 'Pemasukan');
      catCounts[catName] = (catCounts[catName] ?? 0) + 1;
    }

    var peakHour = 19;
    var maxHourCount = 0;
    for (final entry in hourCounts.entries) {
      if (entry.value > maxHourCount) {
        maxHourCount = entry.value;
        peakHour = entry.key;
      }
    }

    // 2. Ambil sesi aktivitas 30 hari terakhir
    final activitySessions = await (_db.select(_db.activitySessions)
          ..where((row) =>
              row.householdId.equals(householdId) &
              row.isArchived.equals(false) &
              row.startedAt.isBiggerOrEqualValue(thirtyDaysAgo)))
        .get();

    final activityCounts = <String, int>{};
    final activityMinutes = <String, int>{};

    for (final s in activitySessions) {
      final title = s.title.trim();
      activityCounts[title] = (activityCounts[title] ?? 0) + 1;
      final duration = (s.endedAt ?? now).difference(s.startedAt).inMinutes;
      activityMinutes[title] = (activityMinutes[title] ?? 0) + duration;
    }

    // Top aktivitas
    final sortedActivities = activityCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topActivities = sortedActivities.take(3).toList();

    final activityLines = <String>[];
    for (final a in topActivities) {
      final totalMins = activityMinutes[a.key] ?? 0;
      final h = totalMins ~/ 60;
      final m = totalMins % 60;
      final timeStr = h > 0 ? '$h jam $m mnt' : '$m mnt';
      activityLines.add('- 🏃 **${a.key}**: ${a.value} kali tercatat (Total: $timeStr)');
    }

    // Top transaksi kategori
    final sortedCats = catCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topCats = sortedCats.take(3).toList();
    final catLines = <String>[];
    for (final c in topCats) {
      catLines.add('- 💳 **${c.key}**: ${c.value} transaksi');
    }

    final activitySummary = activityLines.isNotEmpty
        ? '🏃 **Aktivitas yang Paling Sering Dilakukan (30 Hari Terakhir):**\n${activityLines.join('\n')}\n\n'
        : '🏃 **Aktivitas:** Belum ada sesi aktivitas khusus dalam 30 hari terakhir.\n\n';

    final transactionSummary = catLines.isNotEmpty
        ? '🛒 **Pola Transaksi Paling Sering:**\n${catLines.join('\n')}\n\n'
        : '';

    return FfmHarnessResult(
      pluginName: name,
      category: category,
      text: '👤 **Potret Kebiasaan & Aktivitas Kamu (1 Bulan Terakhir)**\n\n'
          '🏠 **Profil:** $familyName\n'
          '📝 **Total Aktivitas:** ${activitySessions.length} sesi kegiatan & ${transactions.length} transaksi dalam 30 hari terakhir.\n\n'
          '$activitySummary'
          '$transactionSummary'
          '🕒 **Pola Waktu & Ritme Harian:**\n'
          '- **Jam Paling Aktif Mencatat:** Sekitar jam **${peakHour.toString().padLeft(2, '0')}:00 WIB**\n'
          '- **Privasi:** Semua kebiasaan dihitung 100% lokal dari database SQLite perangkatmu.\n\n'
          '💡 *Tip Asisten: Terus catat aktivitas dan transaksi harianmu agar asisten semakin presisi memahami ritme keseharianmu!*',
      metadata: {
        'totalSessions30d': activitySessions.length,
        'totalTransactions30d': transactions.length,
        'peakHour': peakHour,
      },
    );
  }
}


/// Plugin Mata: Membaca daftar piutang aktif (uang yang dipinjam orang ke keluarga).
class FfmReceivableSensePlugin extends FfmAgentPlugin {
  FfmReceivableSensePlugin(this._db);
  final AppDatabase _db;

  @override
  String get name => 'receivable_sense';
  @override
  FfmPluginCategory get category => FfmPluginCategory.sense;
  @override
  int get priority => 7;
  @override
  List<String> get triggers => [
    'piutang',
    'utang ke saya',
    'orang pinjam',
    'dipinjam',
    'tagihan piutang',
    'yang belum bayar ke saya',
    'siapa yang pinjam',
    'cek piutang',
    'daftar piutang',
  ];

  @override
  Future<FfmHarnessResult?> execute(FfmHarnessContext context) async {
    final householdId = _householdId();
    final receivables = await (_db.select(_db.receivables)
          ..where(
            (row) =>
                row.householdId.equals(householdId) &
                row.isActive.equals(true),
          )
          ..orderBy([(row) => OrderingTerm.desc(row.startDate)]))
        .get();

    if (receivables.isEmpty) {
      return const FfmHarnessResult(
        pluginName: 'receivable_sense',
        category: FfmPluginCategory.sense,
        text: '📋 Belum ada catatan piutang aktif di FFM. '
            'Catat piutang baru lewat chat dengan mengetik: '
            '*"catat piutang [nama] [nominal]"*.',
      );
    }

    var totalRemaining = 0;
    final lines = <String>[];
    for (final r in receivables) {
      totalRemaining += r.remainingBalance;
      final due = r.dueDate != null
          ? 'Jatuh tempo: ${r.dueDate!.day}/${r.dueDate!.month}/${r.dueDate!.year}'
          : 'Tanpa jatuh tempo';
      lines.add(
        '- **${r.name}**: ${_rupiah(r.remainingBalance)} (dari ${_rupiah(r.originalAmount)}) — $due',
      );
    }

    return FfmHarnessResult(
      pluginName: name,
      category: category,
      text: '📋 **Daftar Piutang Aktif** (${receivables.length} entri)\n\n'
          '${lines.join('\n')}\n\n'
          '**Total Piutang Belum Kembali: ${_rupiah(totalRemaining)}**',
      metadata: {'totalRemaining': totalRemaining, 'count': receivables.length},
    );
  }
}

/// Plugin Mata: Membaca daftar transaksi berulang / langganan aktif.
class FfmRecurringTransactionSensePlugin extends FfmAgentPlugin {
  FfmRecurringTransactionSensePlugin(this._db);
  final AppDatabase _db;

  @override
  String get name => 'recurring_transaction_sense';
  @override
  FfmPluginCategory get category => FfmPluginCategory.sense;
  @override
  int get priority => 7;
  @override
  List<String> get triggers => [
    'transaksi berulang',
    'langganan',
    'tagihan rutin',
    'rutin bulanan',
    'recurring',
    'cicilan rutin',
    'berlangganan',
    'tagihan otomatis',
    'pembayaran rutin',
    'daftar langganan',
  ];

  @override
  Future<FfmHarnessResult?> execute(FfmHarnessContext context) async {
    final householdId = _householdId();
    final recurring = await (_db.select(_db.recurringTransactions)
          ..where(
            (row) =>
                row.householdId.equals(householdId) &
                row.isActive.equals(true),
          )
          ..orderBy([(row) => OrderingTerm.asc(row.name)]))
        .get();

    if (recurring.isEmpty) {
      return const FfmHarnessResult(
        pluginName: 'recurring_transaction_sense',
        category: FfmPluginCategory.sense,
        text: '🔄 Belum ada transaksi berulang/langganan yang terdaftar. '
            'Tambahkan melalui menu **Transaksi Berulang** di halaman Lainnya.',
      );
    }

    var totalExpense = 0;
    var totalIncome = 0;
    final lines = <String>[];
    for (final r in recurring) {
      final icon = r.type == 'income' ? '📈' : '📉';
      final period = switch (r.periodType) {
        'weekly' => 'Mingguan',
        'biweekly' => 'Dua Mingguan',
        'monthly' => 'Bulanan',
        'quarterly' => 'Triwulan',
        'yearly' => 'Tahunan',
        _ => r.periodType,
      };
      lines.add('- $icon **${r.name}**: ${_rupiah(r.amount)} — $period');
      if (r.type == 'income') {
        totalIncome += r.amount;
      } else {
        totalExpense += r.amount;
      }
    }

    return FfmHarnessResult(
      pluginName: name,
      category: category,
      text: '🔄 **Transaksi Berulang Aktif** (${recurring.length} item)\n\n'
          '${lines.join('\n')}\n\n'
          '📊 **Ringkasan Per Periode:**\n'
          '- Pemasukan rutin: ${_rupiah(totalIncome)}\n'
          '- Pengeluaran rutin: ${_rupiah(totalExpense)}\n'
          '- **Net arus kas rutin: ${_rupiah(totalIncome - totalExpense)}**',
      metadata: {
        'totalExpense': totalExpense,
        'totalIncome': totalIncome,
        'count': recurring.length,
      },
    );
  }
}

/// Plugin Mata: Membaca catatan harian (Daily Notes) terkini.
class FfmDailyNotesSensePlugin extends FfmAgentPlugin {
  FfmDailyNotesSensePlugin(this._db);
  final AppDatabase _db;

  @override
  String get name => 'daily_notes_sense';
  @override
  FfmPluginCategory get category => FfmPluginCategory.sense;
  @override
  int get priority => 6;
  @override
  List<String> get triggers => [
    'catatan harian',
    'jurnal',
    'catatan hari ini',
    'daily note',
    'daily notes',
    'catatan terbaru',
    'jurnal harian',
    'apa yang aku catat',
    'notes hari ini',
    'catatan kemarin',
  ];

  @override
  bool canHandle(String normalizedText) {
    final lower = normalizedText.toLowerCase();
    // Jangan intercept perintah pembuatan/penulisan catatan harian
    // — kata 'catat' diikuti ':' atau konten = intent menulis, bukan membaca
    if (lower.startsWith('catat ') ||
        lower.startsWith('buat catatan') ||
        lower.startsWith('tulis catatan') ||
        lower.startsWith('tambah catatan') ||
        lower.contains('catat catatan harian') ||
        lower.contains('arsipkan catatan') ||
        lower.contains('arsip catatan')) {
      return false;
    }
    return triggers.any((t) => lower.contains(t));
  }

  @override
  Future<FfmHarnessResult?> execute(FfmHarnessContext context) async {
    final householdId = _householdId();
    final now = context.now;
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    // Ambil catatan hari ini terlebih dahulu
    var notes = await (_db.select(_db.dailyNotes)
          ..where(
            (row) =>
                row.householdId.equals(householdId) &
                row.isArchived.equals(false) &
                row.noteDate.isBiggerOrEqualValue(startOfDay) &
                row.noteDate.isSmallerThanValue(endOfDay),
          )
          ..orderBy([(row) => OrderingTerm.desc(row.noteDate)]))
        .get();

    // Jika hari ini kosong, ambil 5 catatan terbaru
    String periodLabel = 'Hari Ini';
    if (notes.isEmpty) {
      notes = await (_db.select(_db.dailyNotes)
            ..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isArchived.equals(false),
            )
            ..orderBy([(row) => OrderingTerm.desc(row.noteDate)])
            ..limit(5))
          .get();
      periodLabel = '5 Catatan Terbaru';
    }

    if (notes.isEmpty) {
      return const FfmHarnessResult(
        pluginName: 'daily_notes_sense',
        category: FfmPluginCategory.sense,
        text: '📓 Belum ada catatan harian. '
            'Tambahkan jurnal harianmu melalui menu **Catatan Harian** atau '
            'ketik: *"buat catatan harian [isi catatan]"*.',
      );
    }

    final lines = <String>[];
    for (final n in notes) {
      final tanggal =
          '${n.noteDate.day}/${n.noteDate.month}/${n.noteDate.year}';
      final title = n.title != null && n.title!.isNotEmpty ? '**${n.title}**: ' : '';
      final preview = n.body.length > 80
          ? '${n.body.substring(0, 80)}...'
          : n.body;
      lines.add('- **[$tanggal]** $title$preview');
    }

    return FfmHarnessResult(
      pluginName: name,
      category: category,
      text: '📓 **Catatan Harian — $periodLabel** (${notes.length} entri)\n\n'
          '${lines.join('\n')}',
      metadata: {'count': notes.length},
    );
  }
}

/// Plugin Mata: Membaca daftar tugas / to-do keluarga yang belum selesai.
class FfmTaskSensePlugin extends FfmAgentPlugin {
  FfmTaskSensePlugin(this._db);
  final AppDatabase _db;

  @override
  String get name => 'task_sense';
  @override
  FfmPluginCategory get category => FfmPluginCategory.sense;
  @override
  int get priority => 7;
  @override
  List<String> get triggers => [
    'tugas',
    'to-do',
    'todo',
    'daftar tugas',
    'tugas belum selesai',
    'tugas hari ini',
    'pekerjaan pending',
    'ada tugas apa',
    'cek tugas',
    'tugas terbuka',
  ];

  @override
  bool canHandle(String normalizedText) {
    final lower = normalizedText.toLowerCase();
    // Jangan intercept perintah pembuatan/penyelesaian/pengarsipan tugas
    if (lower.startsWith('buat tugas') ||
        lower.startsWith('tambah tugas') ||
        lower.startsWith('bikin tugas') ||
        lower.startsWith('selesaikan tugas') ||
        lower.startsWith('selesai tugas') ||
        lower.startsWith('arsipkan tugas') ||
        lower.startsWith('arsip tugas') ||
        lower.startsWith('update tugas') ||
        lower.startsWith('ubah tugas')) {
      return false;
    }
    return triggers.any((t) => lower.contains(t));
  }

  @override
  Future<FfmHarnessResult?> execute(FfmHarnessContext context) async {
    final householdId = _householdId();
    final tasks = await (_db.select(_db.tasks)
          ..where(
            (row) =>
                row.householdId.equals(householdId) &
                row.isArchived.equals(false) &
                row.status.equals('open'),
          )
          ..orderBy([(row) => OrderingTerm.asc(row.dueDate)]))
        .get();

    if (tasks.isEmpty) {
      return const FfmHarnessResult(
        pluginName: 'task_sense',
        category: FfmPluginCategory.sense,
        text: '✅ Hebat! Tidak ada tugas keluarga yang tertunda (semua selesai). '
            'Ketik: *"buat tugas [nama tugas]"* jika ada hal baru yang perlu dicatat.',
      );
    }

    final now = context.now;
    final lines = <String>[];
    for (final t in tasks) {
      String dueLabel = 'Tanpa batas waktu';
      if (t.dueDate != null) {
        final d = t.dueDate!;
        final isOverdue = d.isBefore(now) &&
            (d.year != now.year || d.month != now.month || d.day != now.day);
        final isToday =
            d.year == now.year && d.month == now.month && d.day == now.day;
        if (isOverdue) {
          dueLabel = '⚠️ **Terlambat (${d.day}/${d.month}/${d.year})**';
        } else if (isToday) {
          dueLabel = '⏰ **Hari ini**';
        } else {
          dueLabel = 'Tenggat: ${d.day}/${d.month}/${d.year}';
        }
      }
      final note = t.note != null && t.note!.isNotEmpty ? ' (${t.note})' : '';
      lines.add('- 🔲 **${t.title}**$note — $dueLabel');
    }

    return FfmHarnessResult(
      pluginName: name,
      category: category,
      text: '📋 **Daftar Tugas Keluarga Terbuka** (${tasks.length} tugas)\n\n'
          '${lines.join('\n')}\n\n'
          '💡 Ketik: *"selesaikan tugas [nama tugas]"* setelah tugas dikerjakan.',
      metadata: {'count': tasks.length},
    );
  }
}

/// Plugin Mata: Membaca agenda jadwal kalender keluarga hari ini dan minggu ini.
class FfmScheduleSensePlugin extends FfmAgentPlugin {
  FfmScheduleSensePlugin(this._db);
  final AppDatabase _db;

  @override
  String get name => 'schedule_sense';
  @override
  FfmPluginCategory get category => FfmPluginCategory.sense;
  @override
  int get priority => 7;
  @override
  List<String> get triggers => [
    'jadwal',
    'agenda',
    'jadwal hari ini',
    'agenda hari ini',
    'agenda besok',
    'jadwal minggu ini',
    'kalender',
    'ada acara apa',
    'rencana hari ini',
    'cek jadwal',
  ];

  @override
  Future<FfmHarnessResult?> execute(FfmHarnessContext context) async {
    final householdId = _householdId();
    final now = context.now;
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfWeek = startOfDay.add(const Duration(days: 7));

    final schedules = await (_db.select(_db.scheduleEntries)
          ..where(
            (row) =>
                row.householdId.equals(householdId) &
                row.isArchived.equals(false) &
                row.scheduledDate.isBiggerOrEqualValue(startOfDay) &
                row.scheduledDate.isSmallerThanValue(endOfWeek),
          )
          ..orderBy([(row) => OrderingTerm.asc(row.scheduledDate)]))
        .get();

    if (schedules.isEmpty) {
      return const FfmHarnessResult(
        pluginName: 'schedule_sense',
        category: FfmPluginCategory.sense,
        text: '📅 Tidak ada agenda atau jadwal terdaftar untuk 7 hari ke depan. '
            'Tambah jadwal lewat menu **Jadwal** atau ketik: *"buat jadwal [nama agenda]"*.',
      );
    }

    final lines = <String>[];
    for (final s in schedules) {
      final d = s.scheduledDate;
      final isToday =
          d.year == now.year && d.month == now.month && d.day == now.day;
      final dayPrefix = isToday ? '🔴 **Hari Ini**' : '${d.day}/${d.month}/${d.year}';
      String timeLabel = s.isAllDay ? 'Sepanjang hari' : '';
      if (!s.isAllDay && s.startMinutes != null) {
        final h = (s.startMinutes! ~/ 60).toString().padLeft(2, '0');
        final m = (s.startMinutes! % 60).toString().padLeft(2, '0');
        timeLabel = 'Jam $h:$m';
      }
      final note = s.note != null && s.note!.isNotEmpty ? ' — ${s.note}' : '';
      lines.add('- **[$dayPrefix]** ${s.title} ($timeLabel)$note');
    }

    return FfmHarnessResult(
      pluginName: name,
      category: category,
      text: '📅 **Agenda & Jadwal 7 Hari ke Depan** (${schedules.length} agenda)\n\n'
          '${lines.join('\n')}',
      metadata: {'count': schedules.length},
    );
  }
}

/// Plugin Mata: Membaca status rutinitas harian keluarga dan ceklis hari ini.
class FfmRoutineSensePlugin extends FfmAgentPlugin {
  FfmRoutineSensePlugin(this._db);
  final AppDatabase _db;

  @override
  String get name => 'routine_sense';
  @override
  FfmPluginCategory get category => FfmPluginCategory.sense;
  @override
  int get priority => 7;
  @override
  List<String> get triggers => [
    'rutinitas',
    'kebiasaan',
    'rutinitas harian',
    'kebiasaan hari ini',
    'ceklis rutinitas',
    'cek rutinitas',
    'habits',
    'daily routine',
    'daftar rutinitas',
  ];

  @override
  bool canHandle(String normalizedText) {
    final lower = normalizedText.toLowerCase();
    // Jangan intercept perintah pembuatan profil yang menyebut rutinitas sebagai atribut diri
    if (lower.contains('buat profil') ||
        lower.contains('perkenalkan') ||
        lower.contains('nama saya') ||
        lower.contains('pekerjaan') ||
        lower.startsWith('profil') ||
        (lower.contains('profil') && lower.contains('nama'))) {
      return false;
    }
    return triggers.any((t) => lower.contains(t));
  }

  @override
  Future<FfmHarnessResult?> execute(FfmHarnessContext context) async {
    final householdId = _householdId();
    final now = context.now;
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final routines = await (_db.select(_db.dailyRoutines)
          ..where(
            (row) =>
                row.householdId.equals(householdId) &
                row.isActive.equals(true) &
                row.isArchived.equals(false),
          )
          ..orderBy([(row) => OrderingTerm.asc(row.title)]))
        .get();

    if (routines.isEmpty) {
      return const FfmHarnessResult(
        pluginName: 'routine_sense',
        category: FfmPluginCategory.sense,
        text: '🔁 Belum ada rutinitas harian yang aktif. '
            'Tambah rutinitas baru melalui menu **Rutinitas** di halaman Lainnya.',
      );
    }

    // Ambil penyelesaian rutinitas hari ini
    final completions = await (_db.select(_db.dailyRoutineCompletions)
          ..where(
            (row) =>
                row.householdId.equals(householdId) &
                row.routineDate.isBiggerOrEqualValue(startOfDay) &
                row.routineDate.isSmallerThanValue(endOfDay),
          ))
        .get();

    final completedIds = completions.map((c) => c.routineId).toSet();

    final lines = <String>[];
    var doneCount = 0;
    for (final r in routines) {
      final isDone = completedIds.contains(r.id);
      if (isDone) {
        doneCount++;
        lines.add('- 🟢 **${r.title}** *(Selesai)*');
      } else {
        lines.add('- ⚪ **${r.title}** *(Belum)*');
      }
    }

    final percent = ((doneCount / routines.length) * 100).round();

    return FfmHarnessResult(
      pluginName: name,
      category: category,
      text: '🔁 **Ceklis Rutinitas Harian Hari Ini**\n\n'
          '📊 **Progres:** $doneCount dari ${routines.length} selesai (**$percent%**)\n\n'
          '${lines.join('\n')}',
      metadata: {
        'total': routines.length,
        'done': doneCount,
        'percent': percent,
      },
    );
  }
}

/// Plugin Mata: Menganalisis tempat belanja / merchant yang paling sering dikunjungi.
class FfmTopMerchantSensePlugin extends FfmAgentPlugin {
  FfmTopMerchantSensePlugin(this._db);
  final AppDatabase _db;

  @override
  String get name => 'top_merchant_sense';
  @override
  FfmPluginCategory get category => FfmPluginCategory.sense;
  @override
  int get priority => 7;
  @override
  List<String> get triggers => [
    'tempat belanja',
    'toko favorit',
    'sering belanja di mana',
    'merchant',
    'toko paling sering',
    'analisis merchant',
    'belanja ke mana aja',
    'toko pengeluaran terbesar',
  ];

  @override
  Future<FfmHarnessResult?> execute(FfmHarnessContext context) async {
    final householdId = _householdId();
    final now = context.now;
    final threeMonthsAgo = DateTime(now.year, now.month - 3, 1);

    final transactions = await (_db.select(_db.transactions)
          ..where(
            (row) =>
                row.householdId.equals(householdId) &
                row.type.equals('expense') &
                row.isArchived.equals(false) &
                row.isDeleted.equals(false) &
                row.date.isBiggerOrEqualValue(threeMonthsAgo),
          ))
        .get();

    final merchants = await (_db.select(_db.merchants)
          ..where((row) => row.householdId.equals(householdId)))
        .get();
    final merchantMap = {for (final m in merchants) m.id: m.name};

    final merchantSpend = <String, int>{};
    final merchantCount = <String, int>{};

    for (final t in transactions) {
      final name = t.merchantId != null && merchantMap.containsKey(t.merchantId)
          ? merchantMap[t.merchantId]!
          : (t.partyName != null && t.partyName!.isNotEmpty
              ? t.partyName!
              : 'Lainnya / Tanpa Nama Toko');
      merchantSpend[name] = (merchantSpend[name] ?? 0) + t.amount.abs();
      merchantCount[name] = (merchantCount[name] ?? 0) + 1;
    }

    if (merchantSpend.isEmpty) {
      return const FfmHarnessResult(
        pluginName: 'top_merchant_sense',
        category: FfmPluginCategory.sense,
        text: '🏪 Belum ada data transaksi belanja dalam 3 bulan terakhir.',
      );
    }

    final sorted = merchantSpend.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final top5 = sorted.take(5).toList();
    final lines = <String>[];
    for (var i = 0; i < top5.length; i++) {
      final entry = top5[i];
      final count = merchantCount[entry.key] ?? 1;
      lines.add(
        '${i + 1}. 🏪 **${entry.key}**: ${_rupiah(entry.value)} ($count transaksi)',
      );
    }

    return FfmHarnessResult(
      pluginName: name,
      category: category,
      text: '🏪 **5 Tempat Belanja Terbesar (3 Bulan Terakhir)**\n\n'
          '${lines.join('\n')}\n\n'
          '💡 *Tip: Mengetahui tempat belanja favorit membantumu mengontrol frekuensi jajan dan menemukan peluang hemat.*',
      metadata: {'count': top5.length},
    );
  }
}

/// Plugin Mata: Merangkum laporan aktivitas mingguan dan bulanan keluarga.
class FfmWeeklyActivityReportPlugin extends FfmAgentPlugin {
  FfmWeeklyActivityReportPlugin(this._db);
  final AppDatabase _db;

  @override
  String get name => 'activity_report_sense';
  @override
  FfmPluginCategory get category => FfmPluginCategory.sense;
  @override
  int get priority => 7;
  @override
  List<String> get triggers => [
    'laporan aktivitas',
    'rekap aktivitas',
    'laporan kegiatan',
    'rekap kegiatan',
    'aktivitas mingguan',
    'kegiatan minggu ini',
    'rekap aktivitas mingguan',
    'laporan aktivitas bulanan',
    'rekap kegiatan bulanan',
    'ringkasan aktivitas',
  ];

  @override
  Future<FfmHarnessResult?> execute(FfmHarnessContext context) async {
    final householdId = _householdId();
    final now = context.now;
    final isMonthly = context.normalizedText.contains('bulan');
    final startDate = isMonthly
        ? DateTime(now.year, now.month, 1)
        : DateTime(now.year, now.month, now.day - 7);
    final periodLabel = isMonthly ? 'Bulan Ini' : '7 Hari Terakhir';

    final sessions = await (_db.select(_db.activitySessions)
          ..where(
            (row) =>
                row.householdId.equals(householdId) &
                row.isArchived.equals(false) &
                row.startedAt.isBiggerOrEqualValue(startDate),
          )
          ..orderBy([(row) => OrderingTerm.desc(row.startedAt)]))
        .get();

    if (sessions.isEmpty) {
      return FfmHarnessResult(
        pluginName: name,
        category: category,
        text: '⏱️ Belum ada sesi aktivitas yang tercatat untuk periode **$periodLabel**. '
            'Mulai sesi aktivitas baru dengan mengetik: *"mulai aktivitas [nama]"*.',
      );
    }

    final rootSessions = sessions.where((s) => s.parentSessionId == null).toList();
    final childSessions = sessions.where((s) => s.parentSessionId != null).toList();

    var rootTotalMinutes = 0;
    var completedCount = 0;
    var activeCount = 0;
    final categoryMinutes = <String, int>{};
    final dailyMinutes = <String, int>{};

    for (final s in (rootSessions.isNotEmpty ? rootSessions : sessions)) {
      final isCompleted = s.status == 'completed' && s.endedAt != null;
      final duration = isCompleted
          ? s.endedAt!.difference(s.startedAt).inMinutes
          : now.difference(s.startedAt).inMinutes;

      if (isCompleted) {
        completedCount++;
      } else {
        activeCount++;
      }

      rootTotalMinutes += duration;
      categoryMinutes[s.category] = (categoryMinutes[s.category] ?? 0) + duration;

      final dayKey = '${s.startedAt.year}-${s.startedAt.month.toString().padLeft(2, "0")}-${s.startedAt.day.toString().padLeft(2, "0")}';
      dailyMinutes[dayKey] = (dailyMinutes[dayKey] ?? 0) + duration;
    }

    // Breakdown child activities
    final childCategoryMinutes = <String, int>{};
    for (final c in childSessions) {
      final isCompleted = c.status == 'completed' && c.endedAt != null;
      final duration = isCompleted
          ? c.endedAt!.difference(c.startedAt).inMinutes
          : now.difference(c.startedAt).inMinutes;
      childCategoryMinutes[c.category] = (childCategoryMinutes[c.category] ?? 0) + duration;
    }

    final hours = rootTotalMinutes ~/ 60;
    final mins = rootTotalMinutes % 60;
    final timeStr = hours > 0 ? '$hours jam $mins menit' : '$mins menit';

    final catLines = <String>[];
    final sortedCats = categoryMinutes.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final c in sortedCats) {
      final ch = c.value ~/ 60;
      final cm = c.value % 60;
      final cStr = ch > 0 ? '$ch j $cm m' : '$cm m';
      catLines.add('- **${c.key.toUpperCase()}**: $cStr');
    }

    final nestedLines = <String>[];
    if (childSessions.isNotEmpty) {
      nestedLines.add('\n📌 **Sub-Kegiatan (Nested Activities):**');
      for (final child in childSessions) {
        final isCompleted = child.status == 'completed' && child.endedAt != null;
        final duration = isCompleted
            ? child.endedAt!.difference(child.startedAt).inMinutes
            : now.difference(child.startedAt).inMinutes;
        final ch = duration ~/ 60;
        final cm = duration % 60;
        final cStr = ch > 0 ? '$ch j $cm m' : '$cm m';
        nestedLines.add('  └─ **${child.title}** (${child.category}): $cStr');
      }
    }

    return FfmHarnessResult(
      pluginName: name,
      category: category,
      text: '⏱️ **Rekap Laporan Aktivitas ($periodLabel)**\n\n'
          '📊 **Statistik Utama:**\n'
          '- Total Waktu Utama: **$timeStr** (tanpa double counting sub-kegiatan)\n'
          '- Total Sesi Kegiatan: **${sessions.length} sesi** ($completedCount sesi utama selesai, $activeCount aktif, ${childSessions.length} sub-kegiatan)\n\n'
          '🏷️ **Alokasi Waktu per Kategori Utama:**\n'
          '${catLines.isEmpty ? "- Belum ada breakdown kategori" : catLines.join('\n')}'
          '${nestedLines.isEmpty ? "" : "\n${nestedLines.join('\n')}"}\n\n'
          '💡 *Tip: Pelacakan bertingkat memisahkan perjalanan utama dengan kegiatan singgah seperti makan dan istirahat.*',
      metadata: {
        'totalSessions': sessions.length,
        'rootSessionsCount': rootSessions.length,
        'childSessionsCount': childSessions.length,
        'completedCount': completedCount,
        'activeCount': activeCount,
        'totalDurationMinutes': rootTotalMinutes,
      },
    );
  }
}



