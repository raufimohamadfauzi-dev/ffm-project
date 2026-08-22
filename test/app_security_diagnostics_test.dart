import 'dart:math';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/diagnostics/app_diagnostics_service.dart';
import 'package:ffm_manager/core/security/app_pin_service.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStore implements FfmSecureKeyValueStore, FfmDiagnosticsStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

void main() {
  group('AppPinService', () {
    late _MemoryStore store;
    late AppPinService service;

    setUp(() {
      store = _MemoryStore();
      service = AppPinService(storage: store, random: Random(7), iterations: 8);
    });

    test(
      'menyimpan hash, bukan PIN mentah, lalu memverifikasi dengan benar',
      () async {
        expect(await service.createPin('4829'), FfmAppPinOperation.success);
        expect(await service.isEnabled(), isTrue);
        expect(await service.verifyPin('4829'), FfmAppPinOperation.success);
        expect(
          await service.verifyPin('4830'),
          FfmAppPinOperation.incorrectPin,
        );
        expect(await service.verifyPin('482'), FfmAppPinOperation.invalidPin);
        expect(await service.createPin('48291'), FfmAppPinOperation.invalidPin);
        expect(store.values.values, isNot(contains('4829')));
      },
    );

    test('ganti dan matikan PIN selalu perlu PIN lama yang cocok', () async {
      await service.createPin('4829');

      expect(
        await service.changePin(currentPin: '0000', nextPin: '9012'),
        FfmAppPinOperation.incorrectPin,
      );
      expect(
        await service.changePin(currentPin: '4829', nextPin: '9012'),
        FfmAppPinOperation.success,
      );
      expect(await service.verifyPin('4829'), FfmAppPinOperation.incorrectPin);
      expect(await service.verifyPin('9012'), FfmAppPinOperation.success);
      expect(await service.disablePin('0000'), FfmAppPinOperation.incorrectPin);
      expect(await service.disablePin('9012'), FfmAppPinOperation.success);
      expect(await service.isEnabled(), isFalse);
    });

    test(
      'PIN lama dimigrasi menjadi hash tanpa menghapus akses pengguna',
      () async {
        await store.write('ffm_pin', '4812');

        expect(await service.configuredPinLength(), 4);
        expect(await service.verifyPin('4812'), FfmAppPinOperation.success);
        expect(store.values.containsKey('ffm_pin'), isFalse);
        expect(store.values.values, isNot(contains('4812')));
      },
    );
  });

  group('AppDiagnosticsService', () {
    late _MemoryStore store;
    late AppDiagnosticsService diagnostics;

    setUp(() {
      store = _MemoryStore();
      diagnostics = AppDiagnosticsService(
        store: store,
        clock: () => DateTime.utc(2026, 8, 22, 10, 30),
      );
    });

    test('menyaring data sensitif dari ringkasan dan laporan salin', () async {
      await diagnostics.recordException(
        code: 'pin failed!',
        feature: 'Kunci aplikasi',
        error: StateError(
          'PIN=482913, account=SeaBank, amount=500000; orang@example.com',
        ),
        stackTrace: StackTrace.fromString('token=rahasia account=SeaBank'),
        impact: 'Coba ulangi setelah cek PIN.',
      );

      expect(store.values, isNotEmpty);
      final entry = await diagnostics.latestEntry();
      final report = await diagnostics.buildSafeReport();

      expect(entry, isNotNull);
      expect(entry!.code, 'PIN_FAILED');
      expect(entry.summary, isNot(contains('482913')));
      expect(entry.summary, isNot(contains('SeaBank')));
      expect(entry.summary, isNot(contains('orang@example.com')));
      expect(report, contains('PIN_FAILED'));
      expect(report, isNot(contains('482913')));
      expect(report, isNot(contains('SeaBank')));
      expect(report, isNot(contains('rahasia')));
    });

    test('menyimpan maksimal dua puluh error terbaru', () async {
      for (var index = 0; index < 24; index++) {
        await diagnostics.recordException(
          code: 'TEST_$index',
          feature: 'Uji',
          error: StateError('masalah $index'),
          impact: 'Tidak mengubah data.',
        );
      }

      final entries = await diagnostics.latest();
      expect(entries, hasLength(AppDiagnosticsService.maxEntries));
      expect(entries.first.code, 'TEST_23');
      expect(entries.last.code, 'TEST_4');
    });
  });

  group('Asisten dan diagnostik', () {
    late dynamic database;

    setUp(() => database = createInMemoryDatabaseForTests());
    tearDown(() async => database.close());

    test(
      'menjawab status error dari log nyata dan membuka layar aman PIN',
      () async {
        final diagnostics = AppDiagnosticsService(
          store: _MemoryStore(),
          clock: () => DateTime.utc(2026, 8, 22, 10, 30),
        );
        await diagnostics.recordException(
          code: 'PIN_GATE_VERIFY_FAILED',
          feature: 'Kunci aplikasi',
          error: StateError('PIN=482913'),
          impact: 'Aplikasi tetap terkunci.',
        );
        final interpreter = FfmAssistantInterpreter(
          database,
          null,
          null,
          diagnostics,
        );

        final errorIntent = await interpreter.interpret('Ada error apa?');
        final pinIntent = await interpreter.interpret('Tolong ganti PIN');

        expect(errorIntent.type, FfmAssistantIntentType.diagnosticStatus);
        expect(errorIntent.destination, FfmAssistantDestination.diagnostics);
        expect(errorIntent.response, contains('PIN_GATE_VERIFY_FAILED'));
        expect(errorIntent.response, isNot(contains('482913')));
        expect(pinIntent.type, FfmAssistantIntentType.openPage);
        expect(pinIntent.destination, FfmAssistantDestination.appSecurity);
        expect(pinIntent.response, contains('bukan di chat'));
      },
    );

    test('menjelaskan saat belum ada error tanpa mengarang masalah', () async {
      final interpreter = FfmAssistantInterpreter(
        database,
        null,
        null,
        AppDiagnosticsService(store: _MemoryStore()),
      );

      final intent = await interpreter.interpret('Cek error aplikasi');

      expect(intent.type, FfmAssistantIntentType.diagnosticStatus);
      expect(intent.response, contains('Belum ada error teknis'));
    });
  });
}
