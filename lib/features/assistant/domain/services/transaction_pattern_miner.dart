import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';

/// Representasi pola transaksi berulang yang ditambang oleh sistem otonom.
class MinedTransactionPattern {
  const MinedTransactionPattern({
    required this.id,
    required this.title,
    this.merchant,
    this.merchantId,
    this.categoryName,
    this.categoryId,
    required this.amount,
    this.dayOfWeek,
    this.dayOfMonth,
    this.timeWindow,
    required this.occurrenceCount,
    required this.confidence,
    required this.isDueToday,
    this.sampleDates = const [],
  });

  /// Identifier hash unik dari pola (merchant/kategori/jadwal).
  final String id;

  /// Judul pola ramah pengguna (misal: "Jajan Anak di Indomaret" atau "Tagihan Internet").
  final String title;

  /// Nama toko/merchant (jika ada).
  final String? merchant;

  /// ID toko/merchant di database.
  final String? merchantId;

  /// Nama kategori (misal: "Makanan", "Pendidikan").
  final String? categoryName;

  /// ID kategori di database.
  final String? categoryId;

  /// Nominal acuan (median atau nilai rata-rata dibulatkan).
  final int amount;

  /// Hari dalam seminggu (1 = Senin ... 7 = Minggu).
  final int? dayOfWeek;

  /// Tanggal dalam sebulan (1 - 31).
  final int? dayOfMonth;

  /// Estimasi jendela waktu ("pagi", "siang", "sore", "malam").
  final String? timeWindow;

  /// Berapa kali transaksi ini muncul dalam rentang observasi.
  final int occurrenceCount;

  /// Skor keyakinan pola (0.0 – 1.0).
  final double confidence;

  /// Apakah pola ini bertepatan dengan hari ini.
  final bool isDueToday;

  /// Tanggal sampel kemunculan transaksi.
  final List<DateTime> sampleDates;

  /// Pesan santun rekomendasi untuk asisten.
  String get promptMessage {
    final dayLabel = dayOfWeek != null ? _dayName(dayOfWeek!) : 'tanggal $dayOfMonth';
    final windowLabel = timeWindow != null ? '$timeWindow ' : '';
    final merchantLabel = merchant != null && merchant!.isNotEmpty ? ' di $merchant' : '';
    final amountFormatted = _formatRupiah(amount);

    return 'Biasanya setiap $dayLabel ${windowLabel}ada pengeluaran $title$merchantLabel sebesar $amountFormatted. Mau dicatat sekarang?';
  }

  static String _dayName(int day) => switch (day) {
    DateTime.monday => 'Senin',
    DateTime.tuesday => 'Selasa',
    DateTime.wednesday => 'Rabu',
    DateTime.thursday => 'Kamis',
    DateTime.friday => 'Jumat',
    DateTime.saturday => 'Sabtu',
    DateTime.sunday => 'Minggu',
    _ => 'hari ini',
  };

  static String _formatRupiah(int val) {
    final s = val.toString();
    final buffer = StringBuffer('Rp ');
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write('.');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }
}

/// Mesin penambang pola (*Pattern Miner Engine*) berbasis riwayat transaksi 30–60 hari.
class TransactionPatternMiner {
  const TransactionPatternMiner(this._db);

  final AppDatabase _db;

  /// Menemukan pola transaksi berulang dalam kurun waktu [lookbackDays] (default 60 hari).
  Future<List<MinedTransactionPattern>> minePatterns({
    required String householdId,
    DateTime? referenceDate,
    int lookbackDays = 60,
  }) async {
    final now = referenceDate ?? DateTime.now();
    final cutoff = now.subtract(Duration(days: lookbackDays));

    // 1. Ambil transaksi pengeluaran non-hapus dalam rentang waktu observasi
    final txQuery = _db.select(_db.transactions)
      ..where((t) =>
          t.householdId.equals(householdId) &
          t.isDeleted.equals(false) &
          t.isArchived.equals(false) &
          t.type.equals('expense') &
          t.date.isBiggerOrEqualValue(cutoff));

    final txList = await txQuery.get();
    if (txList.length < 2) return const [];

    // 2. Ambil peta kategori & merchant untuk pelabelan manusiawi
    final categories = await _db.select(_db.categories).get();
    final categoryMap = {for (final c in categories) c.id: c.name};

    final merchants = await _db.select(_db.merchants).get();
    final merchantMap = {for (final m in merchants) m.id: m.name};

    // 3. Ambil transaksi berulang resmi yang sudah aktif agar tidak menduplikasi saran
    final activeRecurring = await (_db.select(_db.recurringTransactions)
          ..where((r) => r.householdId.equals(householdId) & r.isActive.equals(true)))
        .get();
    final recurringCategoryIds = activeRecurring.map((r) => r.categoryId).toSet();
    final recurringNames = activeRecurring.map((r) => r.name.toLowerCase().trim()).toSet();

    // 4. Kelompokkan transaksi berdasarkan identitas (Merchant atau Kategori + Note)
    final clusterMap = <String, List<Transaction>>{};

    for (final tx in txList) {
      // Abaikan jika sudah tercatat di recurring transactions resmi
      if (tx.recurringTransactionId != null) continue;
      if (tx.categoryId != null && recurringCategoryIds.contains(tx.categoryId)) {
        continue;
      }
      final rawNote = tx.note?.toLowerCase().trim() ?? '';
      if (recurringNames.contains(rawNote)) continue;

      // Kunci klaster preferensi: merchantId jika ada, jika tidak categoryId + note pendek
      final clusterKey = tx.merchantId != null && tx.merchantId!.isNotEmpty
          ? 'm_${tx.merchantId}'
          : (tx.categoryId != null ? 'c_${tx.categoryId}_${rawNote.take(12)}' : 'n_$rawNote');

      if (clusterKey.isEmpty || clusterKey == 'n_') continue;
      clusterMap.putIfAbsent(clusterKey, () => []).add(tx);
    }

    final discoveredPatterns = <MinedTransactionPattern>[];

    // 5. Analisis pola berulang untuk tiap klaster
    for (final entry in clusterMap.entries) {
      final items = entry.value;
      if (items.length < 2) continue;

      // Evaluasi Pola Mingguan (Day of Week)
      final weekdayGroups = <int, List<Transaction>>{};
      for (final tx in items) {
        weekdayGroups.putIfAbsent(tx.date.weekday, () => []).add(tx);
      }

      for (final wg in weekdayGroups.entries) {
        final day = wg.key;
        final dayTxs = wg.value;
        if (dayTxs.length >= 2) {
          final pattern = _evaluateCluster(
            txs: dayTxs,
            dayOfWeek: day,
            dayOfMonth: null,
            now: now,
            categoryMap: categoryMap,
            merchantMap: merchantMap,
          );
          if (pattern != null) {
            discoveredPatterns.add(pattern);
          }
        }
      }

      // Evaluasi Pola Bulanan (Tanggal tertentu +/- 1 hari)
      final monthDayGroups = <int, List<Transaction>>{};
      for (final tx in items) {
        monthDayGroups.putIfAbsent(tx.date.day, () => []).add(tx);
      }

      for (final mg in monthDayGroups.entries) {
        final d = mg.key;
        final monthTxs = mg.value;
        if (monthTxs.length >= 2) {
          final pattern = _evaluateCluster(
            txs: monthTxs,
            dayOfWeek: null,
            dayOfMonth: d,
            now: now,
            categoryMap: categoryMap,
            merchantMap: merchantMap,
          );
          if (pattern != null) {
            // Hindari duplikasi jika sudah terdeteksi di pola mingguan
            if (!discoveredPatterns.any((p) => p.id == pattern.id)) {
              discoveredPatterns.add(pattern);
            }
          }
        }
      }
    }

    // Urutkan pola berdasarkan keyakinan dan jumlah kemunculan
    discoveredPatterns.sort((a, b) {
      if (a.isDueToday && !b.isDueToday) return -1;
      if (!a.isDueToday && b.isDueToday) return 1;
      return b.confidence.compareTo(a.confidence);
    });

    return discoveredPatterns;
  }

  /// Mengambil pola yang sedang jatuh tempo hari ini dan relevan untuk disarankan.
  Future<List<MinedTransactionPattern>> getDuePatterns({
    required String householdId,
    DateTime? referenceDate,
  }) async {
    final patterns = await minePatterns(
      householdId: householdId,
      referenceDate: referenceDate,
    );
    return patterns.where((p) => p.isDueToday).toList();
  }

  MinedTransactionPattern? _evaluateCluster({
    required List<Transaction> txs,
    required int? dayOfWeek,
    required int? dayOfMonth,
    required DateTime now,
    required Map<String, String> categoryMap,
    required Map<String, String> merchantMap,
  }) {
    if (txs.length < 2) return null;

    // Hitung rata-rata dan deviasi nominal
    final amounts = txs.map((t) => t.amount).toList()..sort();
    final medianAmount = amounts[amounts.length ~/ 2];

    // Pastikan variasi nominal tidak terlalu liar (maksimal selisih 35% dari median)
    final isAmountConsistent = amounts.every((a) =>
        (a - medianAmount).abs() <= (medianAmount * 0.35) ||
        (a - medianAmount).abs() <= 15000);

    if (!isAmountConsistent) return null;

    // Ekstrak waktu/jam rata-rata
    final avgHour = txs.map((t) => t.date.hour).reduce((a, b) => a + b) / txs.length;
    final timeWindow = avgHour < 11.5
        ? 'pagi'
        : (avgHour < 15.0
            ? 'siang'
            : (avgHour < 18.5 ? 'sore' : 'malam'));

    final representative = txs.last;
    final merchantName = representative.merchantId != null
        ? merchantMap[representative.merchantId]
        : null;
    final catName = representative.categoryId != null
        ? categoryMap[representative.categoryId]
        : null;

    final baseTitle = (representative.note != null && representative.note!.trim().isNotEmpty)
        ? representative.note!.trim()
        : (merchantName ?? catName ?? 'Pengeluaran Rutin');

    // Cek apakah hari ini bertepatan dengan pola
    final isDueToday = dayOfWeek != null
        ? now.weekday == dayOfWeek
        : (dayOfMonth != null ? (now.day - dayOfMonth).abs() <= 1 : false);

    // Hitung skor keyakinan
    var score = 0.6 + (txs.length * 0.1);
    if (score > 0.95) score = 0.95;

    final patternId = 'pat_${dayOfWeek ?? 0}_${dayOfMonth ?? 0}_${representative.merchantId ?? ''}_${representative.categoryId ?? ''}_${representative.amount ~/ 1000}';

    return MinedTransactionPattern(
      id: patternId,
      title: baseTitle,
      merchant: merchantName,
      merchantId: representative.merchantId,
      categoryName: catName,
      categoryId: representative.categoryId,
      amount: medianAmount,
      dayOfWeek: dayOfWeek,
      dayOfMonth: dayOfMonth,
      timeWindow: timeWindow,
      occurrenceCount: txs.length,
      confidence: score,
      isDueToday: isDueToday,
      sampleDates: txs.map((t) => t.date).toList(),
    );
  }
}

extension _StringExt on String {
  String take(int n) => length <= n ? this : substring(0, n);
}
