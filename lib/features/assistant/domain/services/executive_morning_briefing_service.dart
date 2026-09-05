import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/database/app_database.dart';
import 'transaction_pattern_miner.dart';

/// Model representasi data Executive Morning Briefing.
class ExecutiveMorningBriefing {
  const ExecutiveMorningBriefing({
    required this.greeting,
    required this.familyName,
    required this.totalCashBalance,
    required this.yesterdayExpense,
    required this.monthExpenseSoFar,
    required this.dueItems,
    required this.textSummary,
    required this.spokenScript,
    required this.generatedAt,
  });

  /// Sapaan hangat pembuka (misal: "Selamat Pagi, Keluarga Kami! 🌅").
  final String greeting;

  /// Nama panggilan keluarga.
  final String familyName;

  /// Total saldo kas/rekening aktif yang tersedia saat ini (Rp).
  final int totalCashBalance;

  /// Total pengeluaran kemarin (H-1) (Rp).
  final int yesterdayExpense;

  /// Total pengeluaran bulan ini sampai hari ini (Rp).
  final int monthExpenseSoFar;

  /// Daftar pola pengeluaran atau agenda pengingat yang jatuh tempo hari ini.
  final List<String> dueItems;

  /// Rangkuman teks format markdown yang bersih dan rapi.
  final String textSummary;

  /// Naskah percakapan santun dalam Bahasa Indonesia untuk dibacakan oleh TTS.
  final String spokenScript;

  /// Waktu pembuatan briefing.
  final DateTime generatedAt;
}

/// Layanan Executive Morning Briefing yang tahan terhadap pembunuhan proses
/// oleh Android OS (anti-kill) dan hemat baterai (tanpa background polling liar).
class ExecutiveMorningBriefingService {
  ExecutiveMorningBriefingService({
    required this.database,
    this.patternMiner,
    SharedPreferences? preferences,
  }) : _prefs = preferences;

  final AppDatabase database;
  final TransactionPatternMiner? patternMiner;
  SharedPreferences? _prefs;

  Future<SharedPreferences> _getPrefs() async =>
      _prefs ??= await SharedPreferences.getInstance();

  /// Memeriksa apakah waktu saat ini berada pada rentang pagi (jam 05:00 - 09:59).
  bool isMorningTime({DateTime? now}) {
    final current = now ?? DateTime.now();
    return current.hour >= 5 && current.hour < 10;
  }

  /// Memeriksa apakah briefing pagi harus disajikan:
  /// 1. Berada dalam rentang waktu pagi (05:00 - 10:00).
  /// 2. Belum pernah disajikan hari ini untuk [householdId].
  Future<bool> shouldPresentBriefing(
    String householdId, {
    DateTime? now,
  }) async {
    final current = now ?? DateTime.now();
    if (!isMorningTime(now: current)) return false;

    final prefs = await _getPrefs();
    final key = 'ffm_last_morning_briefing_date_$householdId';
    final lastDate = prefs.getString(key);
    final todayStr = _formatDateKey(current);

    return lastDate != todayStr;
  }

  /// Menandai bahwa briefing pagi sudah disajikan hari ini agar tidak berulang.
  Future<void> markBriefingPresented(
    String householdId, {
    DateTime? now,
  }) async {
    final current = now ?? DateTime.now();
    final prefs = await _getPrefs();
    final key = 'ffm_last_morning_briefing_date_$householdId';
    final todayStr = _formatDateKey(current);
    await prefs.setString(key, todayStr);
  }

  /// Menghasilkan briefing pagi eksekutif dari data deterministik database lokal.
  Future<ExecutiveMorningBriefing> generateBriefing(
    String householdId, {
    DateTime? now,
  }) async {
    final current = now ?? DateTime.now();

    // 1. Ambil nama keluarga
    final household = await (database.select(database.households)
          ..where((h) => h.id.equals(householdId)))
        .getSingleOrNull();
    final familyName =
        (household?.name != null && household!.name.trim().isNotEmpty)
            ? household.name.trim()
            : 'Keluarga Kami';

    // 2. Hitung total saldo kas dari semua akun aktif
    final accounts = await (database.select(database.accounts)
          ..where((a) =>
              a.householdId.equals(householdId) &
              a.isActive.equals(true) &
              a.isArchived.equals(false)))
        .get();

    final txAll = await (database.select(database.transactions)
          ..where((t) =>
              t.householdId.equals(householdId) &
              t.isDeleted.equals(false) &
              t.isArchived.equals(false)))
        .get();

    final tfAll = await (database.select(database.transfers)
          ..where((tf) =>
              tf.householdId.equals(householdId) & tf.isDeleted.equals(false)))
        .get();

    var grandTotal = 0;
    for (final acc in accounts) {
      var balance = acc.openingBalance;
      for (final t in txAll) {
        if (t.accountId == acc.id) {
          if (t.type == 'income') balance += t.amount.abs();
          if (t.type == 'expense') balance -= t.amount.abs();
        }
      }
      for (final tf in tfAll) {
        if (tf.fromAccountId == acc.id) balance -= tf.amount;
        if (tf.toAccountId == acc.id) balance += tf.amount;
      }
      grandTotal += balance;
    }

    // 3. Pengeluaran kemarin (H-1)
    final yesterdayDate = current.subtract(const Duration(days: 1));
    final yesterdayStart =
        DateTime(yesterdayDate.year, yesterdayDate.month, yesterdayDate.day);
    final yesterdayEnd = DateTime(current.year, current.month, current.day);
    var yesterdayExpense = 0;
    for (final t in txAll) {
      if (t.type == 'expense' &&
          !t.date.isBefore(yesterdayStart) &&
          t.date.isBefore(yesterdayEnd)) {
        yesterdayExpense += t.amount.abs();
      }
    }

    // 4. Pengeluaran bulan ini
    final monthStart = DateTime(current.year, current.month, 1);
    var monthExpense = 0;
    for (final t in txAll) {
      if (t.type == 'expense' &&
          !t.date.isBefore(monthStart) &&
          !t.date.isAfter(current)) {
        monthExpense += t.amount.abs();
      }
    }

    // 5. Pola pengeluaran atau pengingat yang jatuh tempo hari ini
    final dueItems = <String>[];
    if (patternMiner != null) {
      try {
        final patterns = await patternMiner!.minePatterns(
          householdId: householdId,
          referenceDate: current,
        );
        for (final p in patterns) {
          if (p.isDueToday) {
            dueItems.add('Pola rutin ${p.title} (${_formatRupiah(p.amount)})');
          }
        }
      } catch (_) {}
    }

    // Cek reminders hari ini
    try {
      final todayStart = DateTime(current.year, current.month, current.day);
      final todayEnd =
          DateTime(current.year, current.month, current.day, 23, 59, 59);
      final reminders = await (database.select(database.reminders)
            ..where((r) =>
                r.householdId.equals(householdId) &
                r.isActive.equals(true) &
                r.scheduledAt.isBiggerOrEqualValue(todayStart) &
                r.scheduledAt.isSmallerOrEqualValue(todayEnd)))
          .get();
      for (final r in reminders) {
        dueItems.add('Pengingat: ${r.title}');
      }
    } catch (_) {}

    // Sapaan dan Teks Ringkasan Eksekutif
    final greeting = 'Selamat Pagi, $familyName! 🌅';
    final balanceText = _formatRupiah(grandTotal);
    final yesterdayText = yesterdayExpense > 0
        ? _formatRupiah(yesterdayExpense)
        : 'Tidak ada pengeluaran';
    final monthText = _formatRupiah(monthExpense);

    final textSummaryBuffer = StringBuffer();
    textSummaryBuffer.writeln('🌅 **Executive Morning Briefing**');
    textSummaryBuffer
        .writeln('Halo **$familyName**, berikut rangkuman keuangan pagi ini:');
    textSummaryBuffer.writeln('• 💳 **Saldo Kas Tersedia**: $balanceText');
    textSummaryBuffer.writeln('• 📉 **Pengeluaran Kemarin**: $yesterdayText');
    textSummaryBuffer.writeln('• 📊 **Total Belanja Bulan Ini**: $monthText');
    if (dueItems.isNotEmpty) {
      textSummaryBuffer.writeln('• 🔔 **Agenda & Pola Hari Ini**:');
      for (final item in dueItems) {
        textSummaryBuffer.writeln('  - $item');
      }
    } else {
      textSummaryBuffer.writeln(
          '• ✨ **Agenda / Tagihan**: Tidak ada tagihan jatuh tempo hari ini.');
    }
    textSummaryBuffer.writeln(
        '\nSemoga hari ini penuh berkah dan pengeluaran tetap terkendali!');

    // Skrip Audio Natural Bahasa Indonesia untuk Text-To-Speech
    final scriptBuffer = StringBuffer();
    scriptBuffer.write('Selamat pagi, $familyName. ');
    scriptBuffer.write('Total saldo kas keluarga saat ini sebesar $balanceText. ');
    if (yesterdayExpense > 0) {
      scriptBuffer.write('Pengeluaran kemarin tercatat sebesar $yesterdayText. ');
    } else {
      scriptBuffer.write('Kemarin tidak ada catatan pengeluaran. ');
    }
    if (dueItems.isNotEmpty) {
      scriptBuffer.write(
          'Untuk hari ini, ada ${dueItems.length} agenda atau pola rutin yang perlu diperhatikan, yaitu: ');
      scriptBuffer.write(dueItems.join(', '));
      scriptBuffer.write('. ');
    } else {
      scriptBuffer.write(
          'Hari ini tidak ada tagihan atau pengeluaran rutin yang jatuh tempo. ');
    }
    scriptBuffer.write(
        'Semoga hari ini penuh keberkahan dan keuangan keluarga tetap terjaga.');

    return ExecutiveMorningBriefing(
      greeting: greeting,
      familyName: familyName,
      totalCashBalance: grandTotal,
      yesterdayExpense: yesterdayExpense,
      monthExpenseSoFar: monthExpense,
      dueItems: dueItems,
      textSummary: textSummaryBuffer.toString(),
      spokenScript: scriptBuffer.toString(),
      generatedAt: current,
    );
  }

  static String _formatDateKey(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  static String _formatRupiah(int val) {
    final s = val.abs().toString();
    final buffer = StringBuffer(val < 0 ? '-Rp ' : 'Rp ');
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write('.');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }
}
