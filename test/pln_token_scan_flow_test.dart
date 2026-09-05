import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ffm_manager/features/settings/data/utility_meter_repository.dart';
import 'package:ffm_manager/features/settings/domain/entities/utility_meter_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('PLN Electricity Token OCR Flow Tests', () {
    const householdId = 'hh_flow_test';

    test('Deteksi token 20-digit dan memperbarui meteran yang cocok di repository', () async {
      final repo = UtilityMeterRepository();
      final existingMeter = UtilityMeter(
        id: 'meter_pln_1',
        householdId: householdId,
        name: 'Listrik Rumah Utama',
        meterNumber: '14123456789',
        customerName: 'Budi Santoso',
        createdAt: DateTime(2026, 9, 1),
      );
      await repo.saveMeter(existingMeter);

      // Simulasi teks hasil scan struk token PLN
      const receiptText = 'PT PLN (PERSERO) STRUK PEMBELIAN TOKEN LISTRIK '
          'IDPEL/METER: 14123456789 NAMA: BUDI SANTOSO '
          'TOKEN: 1234-5678-9012-3456-7890 RP 100.000';

      final tokenRegex = RegExp(r'\b(\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4})\b');
      final tokenMatch = tokenRegex.firstMatch(receiptText);
      expect(tokenMatch, isNotNull);
      final cleanToken = tokenMatch!.group(1)!.replaceAll(RegExp(r'\D'), '');
      expect(cleanToken, '12345678901234567890');

      final meterRegex = RegExp(r'(?:idpel|meter|no\.?\s*meter|nomor\s*meteran?)[:\s]*(\d{11,12})', caseSensitive: false);
      final meterMatch = meterRegex.firstMatch(receiptText);
      expect(meterMatch, isNotNull);
      final cleanMeter = meterMatch!.group(1);
      expect(cleanMeter, '14123456789');

      final matched = await repo.findMeterByNumber(householdId, cleanMeter!);
      expect(matched, isNotNull);
      expect(matched!.name, 'Listrik Rumah Utama');

      await repo.updateLastToken(
        householdId: householdId,
        meterNumber: matched.meterNumber,
        tokenCode: cleanToken,
        amount: 100000,
        timestamp: DateTime(2026, 9, 5, 20, 0),
      );

      final updatedMeters = await repo.getAllMeters(householdId);
      final target = updatedMeters.firstWhere((m) => m.id == existingMeter.id);
      expect(target.lastTokenNumber, '12345678901234567890');
      expect(target.formattedTokenNumber, '1234-5678-9012-3456-7890');
      expect(target.lastAmount, 100000);
    });

    test('Auto-register meteran baru jika nomor meteran belum ada di Buku Saku', () async {
      final repo = UtilityMeterRepository();
      const newMeterNumber = '14987654321';
      const cleanToken = '98765432109876543210';

      final matched = await repo.findMeterByNumber(householdId, newMeterNumber);
      expect(matched, isNull);

      final newMeter = UtilityMeter(
        id: 'meter_${DateTime.now().millisecondsSinceEpoch}',
        householdId: householdId,
        name: 'Meteran PLN $newMeterNumber',
        meterNumber: newMeterNumber,
        createdAt: DateTime.now(),
        lastTokenNumber: cleanToken,
        lastAmount: 50000,
      );
      await repo.saveMeter(newMeter);

      final meters = await repo.getAllMeters(householdId);
      expect(meters, hasLength(1));
      expect(meters.first.meterNumber, newMeterNumber);
      expect(meters.first.formattedTokenNumber, '9876-5432-1098-7654-3210');
    });
  });
}
