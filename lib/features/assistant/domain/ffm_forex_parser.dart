import '../../asset/domain/entities/market_news_models.dart';

class FfmForexConversion {
  final int idrAmount;
  final double foreignAmount;
  final String currencyCode;
  final double exchangeRate;
  final String noteAnnotation;

  const FfmForexConversion({
    required this.idrAmount,
    required this.foreignAmount,
    required this.currencyCode,
    required this.exchangeRate,
    required this.noteAnnotation,
  });

  Map<String, dynamic> get metadata => {
    'forex': {
      'currency': currencyCode,
      'foreignAmount': foreignAmount,
      'rate': exchangeRate,
    },
  };
}

abstract final class FfmForexParser {
  /// Mendeteksi nominal valas dalam teks dan mengonversinya ke IDR secara deterministik.
  static FfmForexConversion? detectAndConvert(
    String text, {
    MarketPriceSnapshot? marketSnapshot,
  }) {
    final snapshot = marketSnapshot ?? MarketPriceSnapshot.initialFallback();
    final normalized = text.toLowerCase();

    // 1. USD: "$ 15", "15$", "15 usd", "15 dollar", "15 dolar", "15 us$"
    final usdMatch = RegExp(
      r'(?:\$|us\$)\s*(\d+(?:[.,]\d+)?)|(\d+(?:[.,]\d+)?)\s*(?:usd|dollar|dolar|us\$|\$)',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (usdMatch != null) {
      final rawNum = usdMatch.group(1) ?? usdMatch.group(2);
      final foreignAmount = _parseRawNumber(rawNum);
      if (foreignAmount != null && foreignAmount > 0) {
        final rate = snapshot.usdRate;
        final idrAmount = (foreignAmount * rate).round();
        return FfmForexConversion(
          idrAmount: idrAmount,
          foreignAmount: foreignAmount,
          currencyCode: 'USD',
          exchangeRate: rate,
          noteAnnotation:
              '(${_formatAmount(foreignAmount)} USD @ Rp ${_formatThousands(rate.round())})',
        );
      }
    }

    // 2. SGD: "15 sgd", "15 s$", "s$ 15", "15 dolar singapura"
    final sgdMatch = RegExp(
      r'(?:s\$)\s*(\d+(?:[.,]\d+)?)|(\d+(?:[.,]\d+)?)\s*(?:sgd|s\$|dolar singapura)',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (sgdMatch != null) {
      final rawNum = sgdMatch.group(1) ?? sgdMatch.group(2);
      final foreignAmount = _parseRawNumber(rawNum);
      if (foreignAmount != null && foreignAmount > 0) {
        final rate = snapshot.sgdRate;
        final idrAmount = (foreignAmount * rate).round();
        return FfmForexConversion(
          idrAmount: idrAmount,
          foreignAmount: foreignAmount,
          currencyCode: 'SGD',
          exchangeRate: rate,
          noteAnnotation:
              '(${_formatAmount(foreignAmount)} SGD @ Rp ${_formatThousands(rate.round())})',
        );
      }
    }

    // 3. EUR: "15 eur", "15 euro", "€ 15", "15 €"
    final eurMatch = RegExp(
      r'(?:€)\s*(\d+(?:[.,]\d+)?)|(\d+(?:[.,]\d+)?)\s*(?:eur|euro|€)',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (eurMatch != null) {
      final rawNum = eurMatch.group(1) ?? eurMatch.group(2);
      final foreignAmount = _parseRawNumber(rawNum);
      if (foreignAmount != null && foreignAmount > 0) {
        final rate = snapshot.eurRate;
        final idrAmount = (foreignAmount * rate).round();
        return FfmForexConversion(
          idrAmount: idrAmount,
          foreignAmount: foreignAmount,
          currencyCode: 'EUR',
          exchangeRate: rate,
          noteAnnotation:
              '(${_formatAmount(foreignAmount)} EUR @ Rp ${_formatThousands(rate.round())})',
        );
      }
    }

    // 4. SAR: "50 sar", "50 riyal", "50 riyal saudi", "sr 50", "50 sr"
    final sarMatch = RegExp(
      r'(?:sr)\s*(\d+(?:[.,]\d+)?)|(\d+(?:[.,]\d+)?)\s*(?:sar|riyal(?:\s+saudi)?|sr)',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (sarMatch != null) {
      final rawNum = sarMatch.group(1) ?? sarMatch.group(2);
      final foreignAmount = _parseRawNumber(rawNum);
      if (foreignAmount != null && foreignAmount > 0) {
        final rate = snapshot.sarRate;
        final idrAmount = (foreignAmount * rate).round();
        return FfmForexConversion(
          idrAmount: idrAmount,
          foreignAmount: foreignAmount,
          currencyCode: 'SAR',
          exchangeRate: rate,
          noteAnnotation:
              '(${_formatAmount(foreignAmount)} SAR @ Rp ${_formatThousands(rate.round())})',
        );
      }
    }

    // 5. CHF: "50 chf", "50 franc", "50 franc swiss"
    final chfMatch = RegExp(
      r'(\d+(?:[.,]\d+)?)\s*(?:chf|franc(?:\s+swiss)?)',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (chfMatch != null) {
      final rawNum = chfMatch.group(1);
      final foreignAmount = _parseRawNumber(rawNum);
      if (foreignAmount != null && foreignAmount > 0) {
        final rate = snapshot.chfRate;
        final idrAmount = (foreignAmount * rate).round();
        return FfmForexConversion(
          idrAmount: idrAmount,
          foreignAmount: foreignAmount,
          currencyCode: 'CHF',
          exchangeRate: rate,
          noteAnnotation:
              '(${_formatAmount(foreignAmount)} CHF @ Rp ${_formatThousands(rate.round())})',
        );
      }
    }

    // 6. MYR: "50 myr", "50 rm", "rm 50", "50 ringgit"
    final myrMatch = RegExp(
      r'(?:rm)\s*(\d+(?:[.,]\d+)?)|(\d+(?:[.,]\d+)?)\s*(?:myr|ringgit|rm)',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (myrMatch != null) {
      final rawNum = myrMatch.group(1) ?? myrMatch.group(2);
      final foreignAmount = _parseRawNumber(rawNum);
      if (foreignAmount != null && foreignAmount > 0) {
        const rate = 3500.0;
        final idrAmount = (foreignAmount * rate).round();
        return FfmForexConversion(
          idrAmount: idrAmount,
          foreignAmount: foreignAmount,
          currencyCode: 'MYR',
          exchangeRate: rate,
          noteAnnotation:
              '(${_formatAmount(foreignAmount)} MYR @ Rp ${_formatThousands(rate.round())})',
        );
      }
    }

    // 7. JPY: "3000 jpy", "3000 yen", "¥ 3000", "3000 ¥"
    final jpyMatch = RegExp(
      r'(?:¥)\s*(\d+(?:[.,]\d+)?)|(\d+(?:[.,]\d+)?)\s*(?:jpy|yen|¥)',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (jpyMatch != null) {
      final rawNum = jpyMatch.group(1) ?? jpyMatch.group(2);
      final foreignAmount = _parseRawNumber(rawNum);
      if (foreignAmount != null && foreignAmount > 0) {
        const rate = 105.0;
        final idrAmount = (foreignAmount * rate).round();
        return FfmForexConversion(
          idrAmount: idrAmount,
          foreignAmount: foreignAmount,
          currencyCode: 'JPY',
          exchangeRate: rate,
          noteAnnotation:
              '(${_formatAmount(foreignAmount)} JPY @ Rp ${_formatThousands(rate.round())})',
        );
      }
    }

    return null;
  }

  static double? _parseRawNumber(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final normalized = raw.replaceAll(',', '.');
    return double.tryParse(normalized);
  }

  static String _formatAmount(double amount) {
    if (amount == amount.truncateToDouble()) {
      return amount.toInt().toString();
    }
    return amount.toStringAsFixed(2);
  }

  static String _formatThousands(int value) {
    final str = value.toString();
    final buffer = StringBuffer();
    var count = 0;
    for (var i = str.length - 1; i >= 0; i--) {
      buffer.write(str[i]);
      count++;
      if (count % 3 == 0 && i != 0) {
        buffer.write('.');
      }
    }
    return buffer.toString().split('').reversed.join();
  }
}
