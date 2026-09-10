import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/shared/ffm_date_period.dart';

void main() {
  final now = DateTime(2026, 9, 10, 8);

  test('tahun lalu memakai tahun kalender sebelumnya', () {
    final period = FfmDatePeriod.fromPreset(
      FfmDatePeriodPreset.previousYear,
      now: now,
    );

    expect(period.start, DateTime(2025));
    expect(period.endExclusive, DateTime(2026));
    expect(period.contains(DateTime(2025, 1, 1)), isTrue);
    expect(period.contains(DateTime(2025, 12, 31, 23, 59)), isTrue);
    expect(period.contains(DateTime(2026, 1, 1)), isFalse);
  });

  test('1 tahun terakhir memakai rolling period sampai hari ini', () {
    final period = FfmDatePeriod.fromPreset(
      FfmDatePeriodPreset.lastYear,
      now: now,
    );

    expect(period.start, DateTime(2025, 9, 10));
    expect(period.endExclusive, DateTime(2026, 9, 11));
    expect(period.contains(DateTime(2025, 9, 9, 23, 59)), isFalse);
    expect(period.contains(DateTime(2026, 9, 10, 23, 59)), isTrue);
  });

  test('custom range menyertakan seluruh hari terakhir', () {
    final period = FfmDatePeriod.custom(
      start: DateTime(2024, 2, 1),
      end: DateTime(2024, 2, 29),
    );

    expect(period.contains(DateTime(2024, 2, 29, 23, 59)), isTrue);
    expect(period.contains(DateTime(2024, 3, 1)), isFalse);
  });

  test('allTime has null start/endExclusive', () {
    final period = FfmDatePeriod.fromPreset(
      FfmDatePeriodPreset.allTime,
      now: now,
    );
    expect(period.isAllTime, isTrue);
    expect(period.start, isNull);
    expect(period.endExclusive, isNull);
  });

  test('startOrEpoch returns epoch when start is null', () {
    final period = FfmDatePeriod.fromPreset(
      FfmDatePeriodPreset.allTime,
      now: now,
    );
    expect(
      period.startOrEpoch,
      DateTime.fromMicrosecondsSinceEpoch(0),
    );
  });

  test('endOrMax returns max when endExclusive is null', () {
    final period = FfmDatePeriod.fromPreset(
      FfmDatePeriodPreset.allTime,
      now: now,
    );
    expect(period.endOrMax, DateTime(9999, 12, 31));
  });

  test('fromText parses "hari ini"', () {
    final period = FfmDatePeriod.fromText('cek pengeluaran hari ini', now: now);
    expect(period, isNotNull);
    expect(period!.label, 'Hari ini');
    expect(period.contains(now), isTrue);
  });

  test('fromText parses "3 bulan"', () {
    final period = FfmDatePeriod.fromText('riwayat 3 bulan', now: now);
    expect(period, isNotNull);
    expect(period!.label, '3 bulan terakhir');
    expect(period.start, DateTime(2026, 6, 10));
  });

  test('fromText parses "tahun lalu"', () {
    final period = FfmDatePeriod.fromText('tahun lalu', now: now);
    expect(period, isNotNull);
    expect(period!.label, 'Tahun lalu');
    expect(period.start, DateTime(2025));
    expect(period.endExclusive, DateTime(2026));
  });

  test('fromText parses specific year', () {
    final period = FfmDatePeriod.fromText('aktivitas tahun 2023', now: now);
    expect(period, isNotNull);
    expect(period!.label, 'tahun 2023');
    expect(period.start, DateTime(2023));
    expect(period.endExclusive, DateTime(2024));
  });

  test('fromText returns null for unmatched text', () {
    final period = FfmDatePeriod.fromText('belanja minggu depan', now: now);
    expect(period, isNull);
  });

  test('endInclusive is one day before endExclusive', () {
    final period = FfmDatePeriod.custom(
      start: DateTime(2026, 9, 1),
      end: DateTime(2026, 9, 10),
    );
    expect(period.endInclusive, DateTime(2026, 9, 10));
  });
}
