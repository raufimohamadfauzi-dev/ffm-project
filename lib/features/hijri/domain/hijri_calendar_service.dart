import 'package:drift/drift.dart';
import 'package:hijri_plus/hijri_plus.dart';

import '../../../core/database/app_database.dart';

class HijriSettingsEntity {
  const HijriSettingsEntity({
    required this.id,
    required this.householdId,
    required this.method,
    required this.region,
    required this.dayAdjustment,
    required this.timezone,
    required this.updatedAt,
  });

  final String id;
  final String householdId;
  final String method;
  final String region;
  final int dayAdjustment;
  final String timezone;
  final DateTime updatedAt;
}

class HijriMonthOverrideEntity {
  const HijriMonthOverrideEntity({
    required this.id,
    required this.householdId,
    required this.hijriYear,
    required this.hijriMonth,
    required this.gregorianStartDate,
    required this.note,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String householdId;
  final int hijriYear;
  final int hijriMonth;
  final DateTime gregorianStartDate;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class HijriCorrectionLogEntity {
  const HijriCorrectionLogEntity({
    required this.id,
    required this.householdId,
    required this.action,
    required this.settingKey,
    required this.oldValue,
    required this.newValue,
    required this.timestamp,
  });

  final String id;
  final String householdId;
  final String action;
  final String settingKey;
  final String? oldValue;
  final String? newValue;
  final DateTime timestamp;
}

class HijriDisplayDate {
  const HijriDisplayDate({
    required this.gregorian,
    required this.hijri,
    required this.source,
    required this.manualOffsetDays,
  });

  final DateTime gregorian;
  final HijriDate hijri;
  final CalendarSource source;
  final int manualOffsetDays;
}

class HijriCalendarService {
  HijriCalendarService(this._database);

  final AppDatabase _database;

  String _settingsId(String householdId) => 'hijri-settings-$householdId';

  Future<HijriSettingsEntity> getSettings(String householdId) async {
    final id = _settingsId(householdId);
    final row = await (_database.select(
      _database.hijriSettings,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    if (row != null) return _settingsFromRow(row);

    final now = DateTime.now();
    await _database
        .into(_database.hijriSettings)
        .insert(
          HijriSettingsCompanion.insert(
            id: id,
            householdId: householdId,
            updatedAt: now,
          ),
        );
    return HijriSettingsEntity(
      id: id,
      householdId: householdId,
      method: 'umm_al_qura',
      region: 'global',
      dayAdjustment: 0,
      timezone: 'local',
      updatedAt: now,
    );
  }

  Future<List<HijriMonthOverrideEntity>> listOverrides(
    String householdId,
  ) async {
    final rows =
        await (_database.select(_database.hijriMonthOverrides)
              ..where((table) => table.householdId.equals(householdId))
              ..orderBy([
                (table) => OrderingTerm.asc(table.hijriYear),
                (table) => OrderingTerm.asc(table.hijriMonth),
              ]))
            .get();
    return rows.map(_overrideFromRow).toList(growable: false);
  }

  Future<List<HijriCorrectionLogEntity>> listLogs(String householdId) async {
    final rows =
        await (_database.select(_database.hijriCorrectionLogs)
              ..where((table) => table.householdId.equals(householdId))
              ..orderBy([(table) => OrderingTerm.desc(table.timestamp)]))
            .get();
    return rows.map(_logFromRow).toList(growable: false);
  }

  Future<HijriDisplayDate> convert(
    String householdId,
    DateTime gregorian,
  ) async {
    final settings = await getSettings(householdId);
    final overrides = await listOverrides(householdId);
    final calendar = _calendar(settings, overrides);
    final conversion = calendar.toHijriDateTime(gregorian);
    return HijriDisplayDate(
      gregorian: gregorian,
      hijri: conversion.date,
      source: conversion.source,
      manualOffsetDays: conversion.manualOffsetDays,
    );
  }

  Future<void> saveSettings({
    required String householdId,
    required String method,
    required String region,
    required int dayAdjustment,
    required String timezone,
  }) async {
    if (dayAdjustment < -2 || dayAdjustment > 2) {
      throw ArgumentError.value(dayAdjustment, 'dayAdjustment');
    }
    final old = await getSettings(householdId);
    final now = DateTime.now();
    await _database
        .into(_database.hijriSettings)
        .insertOnConflictUpdate(
          HijriSettingsCompanion.insert(
            id: _settingsId(householdId),
            householdId: householdId,
            method: Value(method),
            region: Value(region),
            dayAdjustment: Value(dayAdjustment),
            timezone: Value(timezone),
            updatedAt: now,
          ),
        );
    await _log(
      householdId: householdId,
      action: 'update_settings',
      settingKey: 'calendar',
      oldValue:
          '${old.method}|${old.region}|${old.dayAdjustment}|${old.timezone}',
      newValue: '$method|$region|$dayAdjustment|$timezone',
    );
  }

  Future<void> saveOverride({
    required String householdId,
    required int hijriYear,
    required int hijriMonth,
    required DateTime gregorianStartDate,
    String? note,
  }) async {
    final settings = await getSettings(householdId);
    final existing =
        await (_database.select(_database.hijriMonthOverrides)..where(
              (table) =>
                  table.householdId.equals(householdId) &
                  table.hijriYear.equals(hijriYear) &
                  table.hijriMonth.equals(hijriMonth),
            ))
            .getSingleOrNull();
    final overrides = await listOverrides(householdId);
    final calendar = _calendar(settings, [
      ...overrides.where(
        (item) => item.hijriYear != hijriYear || item.hijriMonth != hijriMonth,
      ),
      HijriMonthOverrideEntity(
        id:
            existing?.id ??
            'hijri-override-$householdId-$hijriYear-$hijriMonth',
        householdId: householdId,
        hijriYear: hijriYear,
        hijriMonth: hijriMonth,
        gregorianStartDate: gregorianStartDate,
        note: note,
        createdAt: existing?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    ]);
    calendar.toHijriDateTime(gregorianStartDate);

    final now = DateTime.now();
    await _database
        .into(_database.hijriMonthOverrides)
        .insertOnConflictUpdate(
          HijriMonthOverridesCompanion.insert(
            id:
                existing?.id ??
                'hijri-override-$householdId-$hijriYear-$hijriMonth',
            householdId: householdId,
            hijriYear: hijriYear,
            hijriMonth: hijriMonth,
            gregorianStartDate: gregorianStartDate,
            note: Value(note),
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
          ),
        );
    await _log(
      householdId: householdId,
      action: existing == null ? 'create_override' : 'update_override',
      settingKey: '$hijriYear-$hijriMonth',
      oldValue: existing?.gregorianStartDate.toIso8601String(),
      newValue: gregorianStartDate.toIso8601String(),
    );
  }

  Future<void> deleteOverride(String householdId, String id) async {
    final row = await (_database.select(
      _database.hijriMonthOverrides,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    if (row == null) return;
    await (_database.delete(
      _database.hijriMonthOverrides,
    )..where((table) => table.id.equals(id))).go();
    await _log(
      householdId: householdId,
      action: 'delete_override',
      settingKey: '${row.hijriYear}-${row.hijriMonth}',
      oldValue: row.gregorianStartDate.toIso8601String(),
      newValue: null,
    );
  }

  UmmAlQuraCalendar _calendar(
    HijriSettingsEntity settings,
    List<HijriMonthOverrideEntity> overrides,
  ) {
    return UmmAlQuraCalendar(
      dayAdjustment: DayAdjustment.fromDays(settings.dayAdjustment),
      manualMonthOverrides: overrides
          .map(
            (item) => ManualMonthOverride(
              month: HijriMonth(item.hijriYear, item.hijriMonth),
              startsOn: GregorianDate.fromDateTime(item.gregorianStartDate),
            ),
          )
          .toList(growable: false),
    );
  }

  Future<void> _log({
    required String householdId,
    required String action,
    required String settingKey,
    required String? oldValue,
    required String? newValue,
  }) async {
    await _database
        .into(_database.hijriCorrectionLogs)
        .insert(
          HijriCorrectionLogsCompanion.insert(
            id: 'hijri-log-${DateTime.now().microsecondsSinceEpoch}',
            householdId: householdId,
            action: action,
            settingKey: settingKey,
            oldValue: Value(oldValue),
            newValue: Value(newValue),
            timestamp: DateTime.now(),
          ),
        );
  }

  HijriSettingsEntity _settingsFromRow(HijriSetting row) => HijriSettingsEntity(
    id: row.id,
    householdId: row.householdId,
    method: row.method,
    region: row.region,
    dayAdjustment: row.dayAdjustment,
    timezone: row.timezone,
    updatedAt: row.updatedAt,
  );

  HijriMonthOverrideEntity _overrideFromRow(HijriMonthOverride row) =>
      HijriMonthOverrideEntity(
        id: row.id,
        householdId: row.householdId,
        hijriYear: row.hijriYear,
        hijriMonth: row.hijriMonth,
        gregorianStartDate: row.gregorianStartDate,
        note: row.note,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
      );

  HijriCorrectionLogEntity _logFromRow(HijriCorrectionLog row) =>
      HijriCorrectionLogEntity(
        id: row.id,
        householdId: row.householdId,
        action: row.action,
        settingKey: row.settingKey,
        oldValue: row.oldValue,
        newValue: row.newValue,
        timestamp: row.timestamp,
      );
}
