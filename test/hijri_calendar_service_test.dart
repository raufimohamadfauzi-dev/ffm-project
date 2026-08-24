import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/hijri/domain/hijri_calendar_service.dart';

void main() {
  late final database = createInMemoryDatabaseForTests();
  late final service = HijriCalendarService(database);
  const householdId = 'hijri-test-household';
  const overrideHouseholdId = 'hijri-override-household';

  setUpAll(() async {
    await database
        .into(database.households)
        .insert(
          HouseholdsCompanion.insert(
            id: householdId,
            name: 'Keluarga Test Hijriah',
            createdAt: DateTime(2026, 8, 17),
          ),
        );
    await database
        .into(database.households)
        .insert(
          HouseholdsCompanion.insert(
            id: overrideHouseholdId,
            name: 'Keluarga Test Override',
            createdAt: DateTime(2026, 8, 17),
          ),
        );
  });

  tearDownAll(() async {
    await database.close();
  });

  test('memakai default Umm al-Qura offline saat setting belum ada', () async {
    final settings = await service.getSettings(householdId);
    final display = await service.convert(
      householdId,
      DateTime(2026, 8, 17, 20, 58),
    );

    expect(settings.method, 'umm_al_qura');
    expect(settings.region, 'global');
    expect(settings.dayAdjustment, 0);
    expect(settings.timezone, 'local');
    expect(display.hijri.year, greaterThan(1400));
    expect(display.hijri.month, inInclusiveRange(1, 12));
    expect(display.hijri.day, inInclusiveRange(1, 30));
    expect(display.manualOffsetDays, 0);
  });

  test('menyimpan koreksi hari dan mencatat riwayat setting', () async {
    await service.saveSettings(
      householdId: householdId,
      method: 'umm_al_qura',
      region: 'indonesia',
      dayAdjustment: 1,
      timezone: 'WIB',
    );

    final settings = await service.getSettings(householdId);
    final display = await service.convert(
      householdId,
      DateTime(2026, 8, 17, 20, 58),
    );
    final logs = await service.listLogs(householdId);

    expect(settings.region, 'indonesia');
    expect(settings.dayAdjustment, 1);
    expect(settings.timezone, 'WIB');
    expect(display.manualOffsetDays, 1);
    expect(logs.any((log) => log.action == 'update_settings'), isTrue);
  });

  test(
    'menguji seluruh variasi koreksi Umm al-Qura pada tanggal berbeda',
    () async {
      const offsets = [-2, -1, 0, 1, 2];
      final dates = [
        DateTime(2026, 1, 1),
        DateTime(2026, 8, 17),
        DateTime(2026, 12, 31),
      ];

      for (final offset in offsets) {
        await service.saveSettings(
          householdId: householdId,
          method: 'umm_al_qura',
          region: 'global',
          dayAdjustment: offset,
          timezone: 'local',
        );
        final settings = await service.getSettings(householdId);
        expect(settings.method, 'umm_al_qura');
        expect(settings.dayAdjustment, offset);

        for (final date in dates) {
          final display = await service.convert(householdId, date);
          expect(display.gregorian, date);
          expect(display.manualOffsetDays, offset);
          expect(display.hijri.year, greaterThan(1400));
          expect(display.hijri.month, inInclusiveRange(1, 12));
          expect(display.hijri.day, inInclusiveRange(1, 30));
        }
      }
    },
  );

  test('menyimpan override awal bulan dan dapat dihapus kembali', () async {
    final display = await service.convert(
      overrideHouseholdId,
      DateTime(2026, 8, 14),
    );
    final id =
        'hijri-override-$overrideHouseholdId-${display.hijri.year}-${display.hijri.month}';

    await service.saveOverride(
      householdId: overrideHouseholdId,
      hijriYear: display.hijri.year,
      hijriMonth: display.hijri.month,
      gregorianStartDate: DateTime(2026, 8, 14),
      note: 'Koreksi rukyat lokal',
    );

    final overrides = await service.listOverrides(overrideHouseholdId);
    final logsAfterSave = await service.listLogs(overrideHouseholdId);
    expect(overrides, hasLength(1));
    expect(overrides.single.id, id);
    expect(overrides.single.note, 'Koreksi rukyat lokal');
    expect(logsAfterSave.any((log) => log.action == 'create_override'), isTrue);

    await service.deleteOverride(overrideHouseholdId, id);

    expect(await service.listOverrides(overrideHouseholdId), isEmpty);
    final logsAfterDelete = await service.listLogs(overrideHouseholdId);
    expect(
      logsAfterDelete.any((log) => log.action == 'delete_override'),
      isTrue,
    );
  });

  test('menolak koreksi hari di luar rentang aman', () async {
    expect(
      () => service.saveSettings(
        householdId: householdId,
        method: 'umm_al_qura',
        region: 'global',
        dayAdjustment: 3,
        timezone: 'local',
      ),
      throwsArgumentError,
    );
  });
}
