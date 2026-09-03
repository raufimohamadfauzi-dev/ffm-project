import 'package:uuid/uuid.dart';
import '../../../../core/database/app_database.dart';
import '../ffm_assistant_insight.dart';
import '../ffm_assistant_models.dart';

class AnomalySpikeDetector {
  const AnomalySpikeDetector(this._db);

  final AppDatabase _db;

  /// Mendeteksi transaksi kembar (kemungkinan double input 15 menit)
  /// atau lonjakan belanja drastis (>3x median kategori dalam 90 hari).
  Future<FfmAssistantInsight?> detect({
    required String householdId,
    required DateTime now,
  }) async {
    final ninetyDaysAgo = now.subtract(const Duration(days: 90));
    final allTxs = await (_db.select(_db.transactions)
          ..where((row) => row.householdId.equals(householdId)))
        .get();

    final txs = allTxs.where((row) {
      return !row.isArchived &&
          !row.isDeleted &&
          !row.date.isBefore(ninetyDaysAgo);
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    if (txs.isEmpty) return null;

    // 1. Cek duplikasi transaksi dalam rentang 15 menit (hanya transaksi 24 jam terakhir)
    final oneDayAgo = now.subtract(const Duration(hours: 24));
    final recentTxs = txs.where((t) => t.date.isAfter(oneDayAgo)).toList();

    for (int i = 0; i < recentTxs.length; i++) {
      for (int j = i + 1; j < recentTxs.length; j++) {
        final tx1 = recentTxs[i];
        final tx2 = recentTxs[j];

        if (tx1.amount == tx2.amount &&
            tx1.amount != 0 &&
            tx1.id != tx2.id &&
            tx1.accountId == tx2.accountId &&
            (tx1.merchantId == tx2.merchantId ||
                (tx1.note != null && tx1.note == tx2.note))) {
          final diffMinutes = tx1.date.difference(tx2.date).inMinutes.abs();
          if (diffMinutes <= 15) {
            final dedupeKey = 'dup_${tx1.id}_${tx2.id}';
            final nominalStr = tx1.amount.abs().toString();

            return FfmAssistantInsight(
              id: const Uuid().v4(),
              householdId: householdId,
              type: FfmAssistantInsightType.anomalySpike,
              severity: FfmAssistantInsightSeverity.caution,
              priority: 90,
              confidence: 0.95,
              title: 'Kemungkinan Transaksi Ganda (Duplikat)',
              summary:
                  'Terdeteksi dua transaksi bernominal sama persis (Rp $nominalStr) dalam selisih waktu $diffMinutes menit. '
                  'Periksa riwayat transaksi untuk memastikan apakah ini ketidaksengajaan double input.',
              evidence: {
                'tx1Id': tx1.id,
                'tx2Id': tx2.id,
                'amount': tx1.amount.abs(),
                'diffMinutes': diffMinutes,
              },
              suggestedAction: 'Buka Riwayat Transaksi untuk memeriksa atau menghapus salah satu',
              destination: FfmAssistantDestination.transactions,
              createdAt: now,
              expiresAt: now.add(const Duration(days: 2)),
              dedupeKey: dedupeKey,
              cooldownKey: 'duplicate_tx',
              status: FfmAssistantInsightStatus.newInsight,
            );
          }
        }
      }
    }

    // 2. Cek lonjakan nominal (Spike) transaksi terbaru terhadap median 90 hari kategori
    final latestTx = recentTxs.where((t) => t.amount < 0 && t.categoryId != null).firstOrNull;
    if (latestTx != null) {
      final categoryHistory = txs
          .where((t) =>
              t.categoryId == latestTx.categoryId &&
              t.amount < 0 &&
              t.id != latestTx.id)
          .map((t) => t.amount.abs())
          .toList()
        ..sort();

      if (categoryHistory.length >= 5) {
        final median = categoryHistory[categoryHistory.length ~/ 2];
        final latestAmount = latestTx.amount.abs();

        if (median >= 10000 && latestAmount > (median * 3.5)) {
          final category = await (_db.select(_db.categories)
                ..where((row) => row.id.equals(latestTx.categoryId!)))
              .getSingleOrNull();
          final categoryName = category?.name ?? 'Kategori';

          final dedupeKey = 'spike_${latestTx.id}';

          return FfmAssistantInsight(
            id: const Uuid().v4(),
            householdId: householdId,
            type: FfmAssistantInsightType.anomalySpike,
            severity: FfmAssistantInsightSeverity.info,
            priority: 60,
            confidence: 0.85,
            title: 'Lonjakan Pengeluaran Tak Biasa di "$categoryName"',
            summary:
                'Transaksi Rp ${latestAmount.toString()} di kategori "$categoryName" '
                'jauh lebih tinggi dari kebiasaan belanja Anda (median Rp ${median.toString()}). '
                'Pastikan pencatatan sudah sesuai.',
            evidence: {
              'transactionId': latestTx.id,
              'amount': latestAmount,
              'median': median,
              'category': categoryName,
              'ratio': (latestAmount / median).toStringAsFixed(1),
            },
            suggestedAction: 'Tinjau rincian transaksi',
            destination: FfmAssistantDestination.transactions,
            createdAt: now,
            expiresAt: now.add(const Duration(days: 3)),
            dedupeKey: dedupeKey,
            cooldownKey: 'spike_${latestTx.categoryId}',
            status: FfmAssistantInsightStatus.newInsight,
          );
        }
      }
    }

    return null;
  }
}
