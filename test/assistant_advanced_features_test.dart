import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_forex_parser.dart';
import 'package:ffm_manager/features/asset/domain/entities/market_news_models.dart';
import 'package:ffm_manager/features/reminder/domain/entities/reminder_entity.dart';
import 'package:ffm_manager/features/reminder/domain/usecases/reminder_usecases.dart';

void main() {
  group('FfmForexParser', () {
    final customSnapshot = MarketPriceSnapshot(
      goldPrice24K: 1400000,
      goldBuybackPrice: 1250000,
      usdRate: 16000.0,
      sgdRate: 12000.0,
      eurRate: 17000.0,
      sarRate: 4200.0,
      chfRate: 18000.0,
      btcPrice: 1000000000.0,
      ethPrice: 50000000.0,
      usdtPrice: 16000.0,
      lastUpdated: DateTime(2026, 9, 17),
    );

    test('detects USD amounts with dollar sign or usd keyword', () {
      final res1 = FfmForexParser.detectAndConvert(
        'beli hosting \$15 dari bca',
        marketSnapshot: customSnapshot,
      );
      expect(res1, isNotNull);
      expect(res1!.foreignAmount, 15.0);
      expect(res1.currencyCode, 'USD');
      expect(res1.idrAmount, 240000);
      expect(res1.noteAnnotation, contains('15 USD @ Rp 16.000'));

      final res2 = FfmForexParser.detectAndConvert(
        'bayar domain 20.5 usd',
        marketSnapshot: customSnapshot,
      );
      expect(res2, isNotNull);
      expect(res2!.foreignAmount, 20.5);
      expect(res2.idrAmount, 328000);
    });

    test('detects SGD amounts', () {
      final res = FfmForexParser.detectAndConvert(
        'beli oleh-oleh 50 sgd',
        marketSnapshot: customSnapshot,
      );
      expect(res, isNotNull);
      expect(res!.currencyCode, 'SGD');
      expect(res.foreignAmount, 50.0);
      expect(res.idrAmount, 600000);
      expect(res.noteAnnotation, contains('50 SGD @ Rp 12.000'));
    });

    test('detects EUR amounts', () {
      final res = FfmForexParser.detectAndConvert(
        'tiket museum 30 euro',
        marketSnapshot: customSnapshot,
      );
      expect(res, isNotNull);
      expect(res!.currencyCode, 'EUR');
      expect(res.idrAmount, 510000);
    });

    test('detects SAR amounts (Riyal Saudi)', () {
      final res = FfmForexParser.detectAndConvert(
        'sedekah di mekkah 100 riyal',
        marketSnapshot: customSnapshot,
      );
      expect(res, isNotNull);
      expect(res!.currencyCode, 'SAR');
      expect(res.idrAmount, 420000);
    });

    test('returns null when no foreign currency is present', () {
      final res = FfmForexParser.detectAndConvert(
        'beli makan siang 25000 pakai gopay',
        marketSnapshot: customSnapshot,
      );
      expect(res, isNull);
    });
  });

  group('Reminder Recurrence - Hijri, Monthly, Yearly', () {
    const calculator = ReminderOccurrenceCalculator();

    test('nextMonthlyOccurrenceAt handles regular and clamped month-ends', () {
      final base = DateTime(2026, 1, 31, 10, 0);
      final now = DateTime(2026, 2, 1, 0, 0);
      final next = nextMonthlyOccurrenceAt(base, now);

      // February 2026 has 28 days -> clamped to 28
      expect(next.year, 2026);
      expect(next.month, 2);
      expect(next.day, 28);
      expect(next.hour, 10);
    });

    test('nextYearlyOccurrenceAt handles leap years to non-leap years', () {
      final base = DateTime(2024, 2, 29, 9, 30); // Leap year
      final now = DateTime(2025, 1, 1);
      final next = nextYearlyOccurrenceAt(base, now);

      // 2025 is not leap -> clamped to 28
      expect(next.year, 2025);
      expect(next.month, 2);
      expect(next.day, 28);
    });

    test('nextHijriMonthlyOccurrenceAt calculates next Hijri date', () {
      final base = DateTime(2026, 1, 1, 8, 0);
      final now = DateTime(2026, 1, 2, 0, 0);
      final next = nextHijriMonthlyOccurrenceAt(base, now);

      expect(next.isAfter(now), isTrue);
      expect(next.hour, 8);
      expect(next.minute, 0);
    });

    test('calculator produces valid occurrences for hijriMonthly reminder', () {
      final reminder = ReminderEntity(
        id: 'rem-hijri-1',
        householdId: 'hh-1',
        title: 'Puasa Ayyamul Bidh',
        scheduledAt: DateTime(2026, 1, 15, 5, 0),
        isActive: true,
        recurrenceType: ReminderRecurrenceType.hijriMonthly,
        weekdays: const [],
        notificationId: 101,
      );

      final occurrence = calculator.nextOccurrence(
        reminder,
        now: DateTime(2026, 1, 16),
      );
      expect(occurrence, isNotNull);
      expect(occurrence!.scheduledAt.isAfter(DateTime(2026, 1, 16)), isTrue);
    });
  });
}
