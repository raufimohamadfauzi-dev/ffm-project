import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../entities/market_news_models.dart';

/// Hasil revaluasi aset otomatis berdasarkan data pasar terkini.
class AssetAutoValuationResult {
  const AssetAutoValuationResult({
    required this.revaluedCount,
    required this.totalValueBefore,
    required this.totalValueAfter,
    required this.revaluedAssetNames,
  });

  final int revaluedCount;
  final int totalValueBefore;
  final int totalValueAfter;
  final List<String> revaluedAssetNames;

  int get difference => totalValueAfter - totalValueBefore;
}

/// Layanan evaluasi & pembaruan nilai aset fisik (Emas Karat, Valas, Kripto) secara otomatis.
class AssetAutoValuationService {
  const AssetAutoValuationService([this._db]);
  final AppDatabase? _db;

  /// Memindai dan memperbarui seluruh aset di householdId. Mengembalikan jumlah aset yang diperbarui.
  Future<int> revalueAllAssets(
    String householdId,
    MarketPriceSnapshot snapshot, {
    AppDatabase? database,
  }) async {
    final dbToUse = database ?? _db;
    if (dbToUse == null) return 0;
    final res = await revalueAssets(
      db: dbToUse,
      snapshot: snapshot,
      householdId: householdId,
    );
    return res.revaluedCount;
  }

  /// Memindai aset keluarga di database dan mengkalkulasi ulang nilainya
  /// berdasarkan snapshot harga pasar terkini secara deterministik.
  Future<AssetAutoValuationResult> revalueAssets({
    required AppDatabase db,
    required MarketPriceSnapshot snapshot,
    required String householdId,
  }) async {
    final assets = await (db.select(db.assets)
          ..where((a) =>
              a.householdId.equals(householdId) & a.isArchived.equals(false)))
        .get();

    var count = 0;
    var totalBefore = 0;
    var totalAfter = 0;
    final names = <String>[];

    for (final asset in assets) {
      totalBefore += asset.value;
      final textCombined = '${asset.name} ${asset.note ?? ''}'.toLowerCase();

      int? computedNewValue;

      // 1. Deteksi Emas (Gram & Karat)
      if (textCombined.contains('emas') ||
          textCombined.contains('gold') ||
          asset.assetType.toLowerCase() == 'gold') {
        final weight = _extractWeightGrams(textCombined);
        final karat = _extractKarat(textCombined);

        if (weight != null && weight > 0) {
          computedNewValue = GoldKarat.calculateValueStatic(
            weightGrams: weight,
            karat: karat,
            goldPrice24K: snapshot.goldPrice24K,
          );
        }
      }
      // 2. Deteksi Valas USD
      else if (textCombined.contains('usd') ||
          textCombined.contains('dollar') ||
          textCombined.contains('dolar')) {
        final nominal = _extractForeignNominal(textCombined, 'usd') ??
            _extractForeignNominal(textCombined, r'\$');
        if (nominal != null && nominal > 0) {
          computedNewValue = (nominal * snapshot.usdRate).round();
        }
      }
      // 3. Deteksi Valas SGD
      else if (textCombined.contains('sgd') ||
          textCombined.contains('dolar singapura')) {
        final nominal = _extractForeignNominal(textCombined, 'sgd');
        if (nominal != null && nominal > 0) {
          computedNewValue = (nominal * snapshot.sgdRate).round();
        }
      }
      // 4. Deteksi Valas SAR (Riyal Tabungan Haji/Umrah)
      else if (textCombined.contains('sar') ||
          textCombined.contains('riyal')) {
        final nominal = _extractForeignNominal(textCombined, 'sar') ??
            _extractForeignNominal(textCombined, 'riyal');
        if (nominal != null && nominal > 0) {
          computedNewValue = (nominal * snapshot.sarRate).round();
        }
      }

      if (computedNewValue != null && computedNewValue > 0) {
        totalAfter += computedNewValue;
        if (computedNewValue != asset.value) {
          count++;
          names.add(asset.name);

          // Update nilai aset di database secara langsung
          await (db.update(db.assets)..where((a) => a.id.equals(asset.id))).write(
            AssetsCompanion(
              value: Value(computedNewValue),
              updatedAt: Value(DateTime.now()),
            ),
          );
        }
      } else {
        totalAfter += asset.value;
      }
    }

    return AssetAutoValuationResult(
      revaluedCount: count,
      totalValueBefore: totalBefore,
      totalValueAfter: totalAfter,
      revaluedAssetNames: names,
    );
  }

  double? _extractWeightGrams(String text) {
    // Pola: "10 gram", "10.5 gr", "10g", "berat: 25 gr"
    final match = RegExp(r'(\d+([.,]\d+)?)\s*(gram|gr|g\b)').firstMatch(text);
    if (match != null) {
      final str = match.group(1)!.replaceAll(',', '.');
      return double.tryParse(str);
    }
    return null;
  }

  GoldKarat _extractKarat(String text) {
    if (text.contains('22k') || text.contains('22 karat') || text.contains('emas tua')) {
      return GoldKarat.k22;
    }
    if (text.contains('18k') || text.contains('18 karat') || text.contains('toko emas')) {
      return GoldKarat.k18;
    }
    if (text.contains('16k') || text.contains('16 karat')) {
      return GoldKarat.k16;
    }
    if (text.contains('10k') || text.contains('10 karat') || text.contains('emas muda')) {
      return GoldKarat.k10;
    }
    return GoldKarat.k24; // Default batangan / murni
  }

  double? _extractForeignNominal(String text, String currencyRegex) {
    // Pola: "500 usd", "$ 100", "nominal: 200 riyal"
    final match =
        RegExp('$currencyRegex\\s*(\\d+([.,]\\d+)?)').firstMatch(text) ??
            RegExp('(\\d+([.,]\\d+)?)\\s*$currencyRegex').firstMatch(text);
    if (match != null) {
      final numStr = (match.group(1) ?? match.group(2))!.replaceAll(',', '.');
      return double.tryParse(numStr);
    }
    return null;
  }
}
