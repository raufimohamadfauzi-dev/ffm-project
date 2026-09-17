import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/settings/data/utility_meter_repository.dart';
import 'package:ffm_manager/features/settings/domain/entities/utility_meter_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const householdId = AppContext.householdId;
  final at = DateTime(2026, 9, 17, 17, 22);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  UtilityMeter meter(String id, String name, String number) => UtilityMeter(
    id: id,
    householdId: householdId,
    name: name,
    meterNumber: number,
    createdAt: at,
  );

  test('IDPEL yang sudah ada selalu terikat ke meteran yang sama (tidak duplikat)', () async {
    final database = createInMemoryDatabaseForTests();
    addTearDown(database.close);
    final repository = UtilityMeterRepository(database);
    await repository.saveMeter(meter('m-utama', 'Rumah Utama', '14123456789'));

    final resolution = await repository.resolveMeterTarget(
      householdId: householdId,
      proposal: const {
        'meterNumber': '14123456789',
        'tokenCode': '12345678901234567890',
        'amount': 100660,
      },
    );
    expect(resolution.status, UtilityMeterTargetStatus.resolved);
    expect(resolution.isResolvable, isTrue);
    expect(resolution.meter?.id, 'm-utama');

    await repository.recordLinkedPurchase(
      householdId: householdId,
      transactionId: 'tx-1',
      proposal: const {
        'meterNumber': '14123456789',
        'tokenCode': '12345678901234567890',
        'amount': 100660,
        'adminFee': 1000,
        'creditedKwh': 63.7,
      },
    );
    await repository.recordLinkedPurchase(
      householdId: householdId,
      transactionId: 'tx-2',
      proposal: const {
        'meterNumber': '14123456789',
        'tokenCode': '12345678901234567890',
        'amount': 200000,
        'creditedKwh': 125.0,
      },
    );

    final meters = await repository.getAllMeters(householdId);
    final history = await repository.getPurchaseHistory(householdId);
    expect(meters, hasLength(1));
    expect(meters.single.id, 'm-utama');
    expect(history, hasLength(2));
    for (final purchase in history) {
      expect(purchase.meterId, 'm-utama');
    }
    expect(meters.single.lastAmount, 200000);
    expect(meters.single.lastTokenNumber, '12345678901234567890');
  });

  test('satu meteran otomatis jadi target tanpa membuat identitas baru', () async {
    final database = createInMemoryDatabaseForTests();
    addTearDown(database.close);
    final repository = UtilityMeterRepository(database);
    await repository.saveMeter(meter('m-kontrakan', 'Kontrakan', '15123456789'));

    final resolution = await repository.resolveMeterTarget(
      householdId: householdId,
      proposal: const {
        'tokenCode': '12345678901234567890',
        'amount': 50000,
      },
    );
    expect(resolution.status, UtilityMeterTargetStatus.resolved);
    expect(resolution.meter?.id, 'm-kontrakan');
    expect(resolution.meterNumber, '15123456789');

    await repository.recordLinkedPurchase(
      householdId: householdId,
      transactionId: 'tx-auto',
      proposal: const {
        'tokenCode': '12345678901234567890',
        'amount': 50000,
      },
    );
    expect(await repository.getPurchaseHistory(householdId), hasLength(1));
    expect(
      (await repository.getPurchaseHistory(householdId)).single.meterId,
      'm-kontrakan',
    );
  });

  test('lebih dari satu rumah + target tidak jelas WAJIB tanya balik tanpa write', () async {
    final database = createInMemoryDatabaseForTests();
    addTearDown(database.close);
    final repository = UtilityMeterRepository(database);
    await repository.saveMeter(meter('m-utama', 'Rumah Utama', '14123456789'));
    await repository.saveMeter(meter('m-ruko', 'Ruko Usaha', '15123456789'));

    final resolution = await repository.resolveMeterTarget(
      householdId: householdId,
      proposal: const {
        'tokenCode': '12345678901234567890',
        'amount': 100000,
      },
    );
    expect(resolution.status, UtilityMeterTargetStatus.missingTarget);
    expect(resolution.isResolvable, isFalse);
    expect(resolution.message, contains('Rumah Utama'));
    expect(resolution.message, contains('Ruko Usaha'));
    expect(resolution.message, contains('yang mana'));

    await expectLater(
      repository.recordLinkedPurchase(
        householdId: householdId,
        transactionId: 'tx-missing',
        proposal: const {
          'tokenCode': '12345678901234567890',
          'amount': 100000,
        },
      ),
      throwsStateError,
    );
    expect(await repository.getPurchaseHistory(householdId), isEmpty);
    expect(await repository.getAllMeters(householdId), hasLength(2));
  });

  test('referensi nama ambigu hanya meminta klarifikasi', () async {
    final database = createInMemoryDatabaseForTests();
    addTearDown(database.close);
    final repository = UtilityMeterRepository(database);
    await repository.saveMeter(meter('m-a', 'Rumah Utama', '14123456789'));
    await repository.saveMeter(meter('m-b', 'Rumah Utama', '15123456789'));

    final resolution = await repository.resolveMeterTarget(
      householdId: householdId,
      proposal: const {
        'meterReference': 'rumah utama',
        'amount': 100000,
      },
    );
    expect(resolution.status, UtilityMeterTargetStatus.ambiguous);
    expect(resolution.isResolvable, isFalse);
    expect(resolution.options, hasLength(2));
    expect(resolution.message, contains('14123456789'));
    expect(resolution.message, contains('15123456789'));
  });

  test('referensi nama tidak dikenal ditanya balik dengan daftar meteran', () async {
    final database = createInMemoryDatabaseForTests();
    addTearDown(database.close);
    final repository = UtilityMeterRepository(database);
    await repository.saveMeter(meter('m-utama', 'Rumah Utama', '14123456789'));

    final resolution = await repository.resolveMeterTarget(
      householdId: householdId,
      proposal: const {
        'meterReference': 'kantin',
        'amount': 100000,
      },
    );
    expect(resolution.status, UtilityMeterTargetStatus.unknownReference);
    expect(resolution.isResolvable, isFalse);
    expect(resolution.message, contains('kantin'));
    expect(resolution.message, contains('Rumah Utama'));
  });

  test('belum ada meteran + target hilang -> minta nomor meter/foto struk', () async {
    final database = createInMemoryDatabaseForTests();
    addTearDown(database.close);
    final repository = UtilityMeterRepository(database);

    final resolution = await repository.resolveMeterTarget(
      householdId: householdId,
      proposal: const {
        'tokenCode': '12345678901234567890',
        'amount': 100000,
      },
    );
    expect(resolution.status, UtilityMeterTargetStatus.noMeters);
    expect(resolution.isResolvable, isFalse);
    expect(resolution.message, contains('nomor meter'));
  });

  test('nomor meter baru ditandai sebagai meteran baru (didaftarkan saat konfirmasi)', () async {
    final database = createInMemoryDatabaseForTests();
    addTearDown(database.close);
    final repository = UtilityMeterRepository(database);
    await repository.saveMeter(meter('m-utama', 'Rumah Utama', '14123456789'));

    final resolution = await repository.resolveMeterTarget(
      householdId: householdId,
      proposal: const {
        'meterNumber': '16123456789',
        'amount': 100000,
      },
    );
    expect(resolution.status, UtilityMeterTargetStatus.newMeter);
    expect(resolution.isResolvable, isTrue);
    expect(resolution.meterNumber, '16123456789');
    expect(await repository.getAllMeters(householdId), hasLength(1));

    await repository.recordLinkedPurchase(
      householdId: householdId,
      transactionId: 'tx-new',
      proposal: const {
        'meterNumber': '16123456789',
        'proposedMeterName': 'Sawah',
        'amount': 100000,
        'creditedKwh': 66.0,
      },
    );
    final meters = await repository.getAllMeters(householdId);
    expect(meters, hasLength(2));
    expect(meters.map((m) => m.name), contains('Sawah'));
  });

  test('anomali kode token ganda dan tarif kWh tidak wajar terdeteksi', () async {
    final database = createInMemoryDatabaseForTests();
    addTearDown(database.close);
    final repository = UtilityMeterRepository(database);
    await repository.saveMeter(meter('m-utama', 'Rumah Utama', '14123456789'));

    await repository.recordLinkedPurchase(
      householdId: householdId,
      transactionId: 'tx-first',
      proposal: const {
        'meterNumber': '14123456789',
        'tokenCode': '12345678901234567890',
        'amount': 100660,
        'creditedKwh': 63.7,
      },
    );

    final warnings = await repository.scanPurchaseAnomalies(
      householdId: householdId,
      proposal: const {
        'meterNumber': '14123456789',
        'tokenCode': '12345678901234567890',
        'amount': 100660,
        'creditedKwh': 63.7,
        'adminFee': 1000,
      },
    );
    expect(warnings, isNotEmpty);
    final joined = warnings.join('\n');
    expect(joined, contains('sudah pernah dicatat'));

    final badRate = await repository.scanPurchaseAnomalies(
      householdId: householdId,
      proposal: const {
        'meterNumber': '14123456789',
        'tokenCode': '12345678901234567899',
        'amount': 20000000,
        'creditedKwh': 1.0,
      },
    );
    expect(badRate.join('\n'), contains('tidak wajar'));
  });

  test('duplikat token lama di riwayat >100 transaksi tetap terdeteksi', () async {
    final database = createInMemoryDatabaseForTests();
    addTearDown(database.close);
    final repository = UtilityMeterRepository(database);
    await repository.saveMeter(meter('m-utama', 'Rumah Utama', '14123456789'));

    const oldToken = '10000000000000000000';
    await repository.recordLinkedPurchase(
      householdId: householdId,
      transactionId: 'tx-old-token',
      proposal: {
        'meterNumber': '14123456789',
        'tokenCode': oldToken,
        'amount': 100000,
        'creditedKwh': 50.0,
        'timestamp': DateTime(2026, 9, 1, 10, 0).toIso8601String(),
      },
    );

    for (var i = 0; i < 150; i++) {
      final token = '10000000000000000${(i + 1).toString().padLeft(3, '0')}';
      await repository.recordLinkedPurchase(
        householdId: householdId,
        transactionId: 'tx-history-$i',
        proposal: {
          'meterNumber': '14123456789',
          'tokenCode': token,
          'amount': 100000 + i,
          'creditedKwh': 50.0,
          'timestamp': DateTime(2026, 9, 2 + (i % 5), 10, 0).toIso8601String(),
        },
      );
    }

    final warnings = await repository.scanPurchaseAnomalies(
      householdId: householdId,
      proposal: const {
        'meterNumber': '14123456789',
        'tokenCode': '10000000000000000000',
        'amount': 100000,
        'creditedKwh': 50.0,
        'timestamp': '2026-09-17T11:00:00.000',
      },
    );
    expect(warnings, isNotEmpty);
    expect(warnings.join('\n'), contains('sudah pernah dicatat'));
  });

  test('duplikat hari yang sama dan tarif yang tidak masuk akal terdeteksi', () async {
    final database = createInMemoryDatabaseForTests();
    addTearDown(database.close);
    final repository = UtilityMeterRepository(database);
    await repository.saveMeter(meter('m-utama', 'Rumah Utama', '14123456789'));

    await repository.recordLinkedPurchase(
      householdId: householdId,
      transactionId: 'tx-sameday-1',
      proposal: {
        'meterNumber': '14123456789',
        'tokenCode': '11111111111111111111',
        'amount': 50000,
        'creditedKwh': 50.0,
        'timestamp': DateTime(2026, 9, 17, 10, 0).toIso8601String(),
      },
    );

    final warnings = await repository.scanPurchaseAnomalies(
      householdId: householdId,
      proposal: {
        'meterNumber': '14123456789',
        'tokenCode': '22222222222222222222',
        'amount': 50000,
        'creditedKwh': 50.0,
        'timestamp': DateTime(2026, 9, 17, 14, 0).toIso8601String(),
      },
    );
    expect(warnings.join('\n'), contains('hari ini'));

    final badRate = await repository.scanPurchaseAnomalies(
      householdId: householdId,
      proposal: {
        'meterNumber': '14123456789',
        'tokenCode': '33333333333333333333',
        'amount': 200000,
        'creditedKwh': 50.0,
        'timestamp': DateTime(2026, 9, 17, 15, 0).toIso8601String(),
      },
    );
    expect(badRate.join('\n'), contains('tidak wajar'));
  });

  group('jalur interpreter (teks alami)', () {
    late AppDatabase database;
    late FfmAssistantInterpreter interpreter;
    late UtilityMeterRepository repository;

    setUp(() async {
      database = createInMemoryDatabaseForTests();
      interpreter = FfmAssistantInterpreter(database, clock: () => at);
      repository = UtilityMeterRepository(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('2 rumah tanpa target -> klarifikasi, tanpa draft, tanpa write', () async {
      await repository.saveMeter(meter('m-utama', 'Rumah Utama', '14123456789'));
      await repository.saveMeter(meter('m-ruko', 'Ruko Usaha', '15123456789'));

      final intent = await interpreter.interpret(
        'catat pembelian token listrik 100 ribu',
      );

      expect(intent.type, FfmAssistantIntentType.unknown);
      expect(intent.clarification, contains('Rumah Utama'));
      expect(intent.clarification, contains('Ruko Usaha'));
      expect(intent.draft, isNull);
      expect(await repository.getPurchaseHistory(householdId), isEmpty);
    });

    test('1 rumah tanpa target -> draft tertaut ke meteran itu', () async {
      await repository.saveMeter(meter('m-utama', 'Rumah Utama', '14123456789'));

      final intent = await interpreter.interpret(
        'beli token listrik 100 ribu',
      );

      expect(intent.draft, isNotNull);
      final proposal = intent.draft!.metadata?['utilityProposal'] as Map?;
      expect(proposal, isNotNull);
      expect(proposal!['meterId'], 'm-utama');
      expect(proposal['isNewMeter'], isFalse);
      expect(proposal['amount'], 100000);
      expect(intent.response, contains('Rumah Utama'));
      expect(await repository.getPurchaseHistory(householdId), isEmpty);
    });

    test('menyebut nama rumah -> draft tertaut ke rumah yang benar', () async {
      await repository.saveMeter(meter('m-utama', 'Rumah Utama', '14123456789'));
      await repository.saveMeter(meter('m-ruko', 'Ruko Usaha', '15123456789'));

      final intent = await interpreter.interpret(
        'beli token listrik 100 ribu untuk rumah utama',
      );

      expect(intent.draft, isNotNull);
      final proposal = intent.draft!.metadata?['utilityProposal'] as Map?;
      expect(proposal!['meterId'], 'm-utama');
      expect(proposal['isNewMeter'], isFalse);
    });

    test('IDPEL baru via teks -> draft isNewMeter=true', () async {
      await repository.saveMeter(meter('m-utama', 'Rumah Utama', '14123456789'));

      final intent = await interpreter.interpret(
        'catat beli token listrik 100 ribu idpel 16123456789',
      );

      expect(intent.draft, isNotNull);
      final proposal = intent.draft!.metadata?['utilityProposal'] as Map?;
      expect(proposal!['meterNumber'], '16123456789');
      expect(proposal['isNewMeter'], isTrue);
    });

    test('meter 13 digit terdeteksi dari teks natural language', () async {
      final intent = await interpreter.interpret(
        'beli token listrik 50rb meteran 1401234567890',
      );

      expect(intent.draft, isNotNull);
      final proposal = intent.draft!.metadata?['utilityProposal'] as Map?;
      expect(proposal, isNotNull);
      expect(proposal!['meterNumber'], '1401234567890');
      expect(intent.response, contains('meteran'));
    });

    test('kWh dari teks alami diekstrak dan warning muncul bila token atau kWh belum lengkap', () async {
      await repository.saveMeter(meter('m-utama', 'Rumah Utama', '14123456789'));

      final intent = await interpreter.interpret(
        'beli token listrik 200rb kwh 50 untuk rumah utama',
      );

      expect(intent.draft, isNotNull);
      final proposal = intent.draft!.metadata?['utilityProposal'] as Map?;
      expect(proposal, isNotNull);
      expect(proposal!['creditedKwh'], 50);
      expect(intent.response, contains('kWh'));

      final missingIntent = await interpreter.interpret(
        'beli token listrik 200 ribu untuk rumah utama',
      );
      expect(missingIntent.response, contains('token'));
      expect(missingIntent.response, contains('kWh'));
    });

    test('perintah cek/hapus meter tidak dibajak menjadi draft pembelian', () async {
      await repository.saveMeter(meter('m-utama', 'Rumah Utama', '14123456789'));

      final intent = await interpreter.interpret(
        'cek data meteran 14123456789',
      );
      expect(intent.type, isNot(FfmAssistantIntentType.createExpense));

      final hapus = await interpreter.interpret(
        'hapus meteran 14123456789',
      );
      expect(hapus.type, isNot(FfmAssistantIntentType.createExpense));
    });

    test('pembacaan meter membuat draft meterReading untuk meter yang jelas', () async {
      await repository.saveMeter(meter('m-utama', 'Rumah Utama', '14123456789'));

      final intent = await interpreter.interpret(
        'pembacaan meter 10112 kWh untuk rumah utama',
      );

      expect(intent.draft, isNotNull);
      expect(intent.draft!.kind.name, 'meterReading');
      expect(intent.draft!.metadata?['meterReadingProposal'], isNotNull);
      expect(intent.draft!.metadata!['meterReadingProposal']['readingKwh'], 10112);
      expect(intent.draft!.metadata!['meterReadingProposal']['meterId'], 'm-utama');
      expect(intent.response, contains('Rumah Utama'));
    });

    test('pembacaan meter tanpa target pada banyak rumah meminta klarifikasi', () async {
      await repository.saveMeter(meter('m-utama', 'Rumah Utama', '14123456789'));
      await repository.saveMeter(meter('m-ruko', 'Ruko Usaha', '15123456789'));

      final intent = await interpreter.interpret('pembacaan meter 10112 kWh');

      expect(intent.draft, isNull);
      expect(intent.clarification, contains('Rumah Utama'));
      expect(intent.clarification, contains('Ruko Usaha'));
    });

    test('pembacaan meter tidak dibajak menjadi pembelian token listrik', () async {
      await repository.saveMeter(meter('m-utama', 'Rumah Utama', '14123456789'));

      final intent = await interpreter.interpret(
        'catat pembacaan meter 10112 kWh untuk rumah utama',
      );

      expect(intent.draft?.kind.name, 'meterReading');
      expect(intent.draft?.metadata?['utilityProposal'], isNull);
    });
  });
}