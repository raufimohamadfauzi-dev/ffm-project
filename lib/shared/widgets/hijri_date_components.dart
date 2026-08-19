import 'package:flutter/material.dart';

import '../../core/database/app_context.dart';
import '../../core/di/injection.dart';
import '../../features/hijri/domain/hijri_calendar_service.dart';
import 'date_time_components.dart';

const _hijriMonths = <String>[
  'Muharam',
  'Safar',
  'Rabiulawal',
  'Rabiulakhir',
  'Jumadilawal',
  'Jumadilakhir',
  'Rajab',
  'Syakban',
  'Ramadan',
  'Syawal',
  'Zulkaidah',
  'Zulhijah',
];

String formatHijriDate(HijriDisplayDate date) {
  final month = date.hijri.month.clamp(1, _hijriMonths.length);
  return '${date.hijri.day} ${_hijriMonths[month - 1]} '
      '${date.hijri.year} H';
}

class HijriDateText extends StatelessWidget {
  const HijriDateText({
    required this.date,
    super.key,
    this.showGregorian = true,
    this.includeSeconds = false,
    this.compact = false,
    this.color,
  });

  final DateTime date;
  final bool showGregorian;
  final bool includeSeconds;
  final bool compact;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final textStyle = compact
        ? Theme.of(context).textTheme.bodySmall
        : Theme.of(context).textTheme.bodyMedium;
    return FutureBuilder<HijriDisplayDate>(
      future: getIt<HijriCalendarService>().convert(
        AppContext.householdId,
        date,
      ),
      builder: (context, snapshot) {
        final hijriText = snapshot.hasData
            ? formatHijriDate(snapshot.data!)
            : 'Kalender Hijriah sedang dimuat...';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showGregorian)
              Text(
                formatTanggalLengkap(date, includeSeconds: includeSeconds),
                style: textStyle?.copyWith(fontWeight: FontWeight.w700),
              ),
            Text(
              hijriText,
              style: textStyle?.copyWith(
                color: color ?? Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        );
      },
    );
  }
}

class HijriDateLabel extends StatelessWidget {
  const HijriDateLabel({required this.date, super.key, this.color});

  final DateTime date;
  final Color? color;

  @override
  Widget build(BuildContext context) => HijriDateText(
    date: date,
    showGregorian: false,
    compact: true,
    color: color,
  );
}

class HijriDateRangeLabel extends StatelessWidget {
  const HijriDateRangeLabel({
    required this.start,
    required this.end,
    super.key,
  });

  final DateTime start;
  final DateTime end;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.primary,
      fontWeight: FontWeight.w700,
    );
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      children: [
        Text('Hijriah:', style: style),
        HijriDateText(date: start, showGregorian: false, compact: true),
        Text('sampai', style: style),
        HijriDateText(date: end, showGregorian: false, compact: true),
      ],
    );
  }
}
