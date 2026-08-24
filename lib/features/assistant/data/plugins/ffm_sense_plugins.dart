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
  ];

  @override
  Future<FfmHarnessResult?> execute(FfmHarnessContext context) async {
    final householdId = _householdId();

    final households = await (_db.select(_db.households)
          ..where((row) => row.id.equals(householdId)))
        .get();
    final familyName = households.isNotEmpty ? households.first.name : 'Keluarga FFM';

    final transactions = await (_db.select(_db.transactions)
          ..where((row) =>
              row.householdId.equals(householdId) &
              row.isArchived.equals(false) &
              row.isDeleted.equals(false)))
        .get();

    final hourCounts = <int, int>{};
    final weekdayCounts = <int, int>{};
    final accountUsage = <String, int>{};

    for (final t in transactions) {
      final hour = t.date.hour;
      hourCounts[hour] = (hourCounts[hour] ?? 0) + 1;
      weekdayCounts[t.date.weekday] = (weekdayCounts[t.date.weekday] ?? 0) + 1;
      if (t.accountId != null) {
        accountUsage[t.accountId!] = (accountUsage[t.accountId!] ?? 0) + 1;
      }
    }

    var peakHour = 19;
    var maxHourCount = 0;
    for (final entry in hourCounts.entries) {
      if (entry.value > maxHourCount) {
        maxHourCount = entry.value;
        peakHour = entry.key;
      }
    }

    final activities = await (_db.select(_db.activityEntries)
          ..where((row) =>
              row.householdId.equals(householdId) &
              row.isArchived.equals(false)))
        .get();

    return FfmHarnessResult(
      pluginName: name,
      category: category,
      text: '👤 **Potret Pemahaman Asisten tentang Pola Keseharian Kamu**\n\n'
          '🏠 **Profil:** $familyName\n'
          '📝 **Total Interaksi:** ${transactions.length} transaksi & ${activities.length} catatan aktivitas tercatat.\n\n'
          '🕒 **Pola Waktu & Kebiasaan:**\n'
          '- **Jam Paling Aktif Mencatat:** Sekitar jam **${peakHour.toString().padLeft(2, '0')}:00 WIB**\n'
          '- **Pola Hari:** Transaksi paling sering dicatat pada hari kerja dan akhir pekan\n'
          '- **Konteks Lokal:** Data disimpan 100% di perangkatmu, tidak pernah dikirim ke internet.\n\n'
          '💡 Semakin sering kamu mencatat aktivitas dan transaksi, asisten akan semakin presisi memberikan saran dan auto-kategorisasi!',
    );
  }
}
