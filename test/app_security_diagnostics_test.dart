import 'dart:math';
import 'dart:convert';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/diagnostics/app_diagnostics_service.dart';
import 'package:ffm_manager/core/security/app_pin_service.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:ffm_manager/features/settings/presentation/pages/app_diagnostics_page.dart';

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

    test(
      'mendeteksi startup yang sebelumnya terputus tanpa data sensitif',
      () async {
        await diagnostics.markStartupStarted(phase: 'database_bootstrap');
        await diagnostics.recordInterruptedStartupIfNeeded();

        final entry = await diagnostics.latestEntry();
        expect(entry, isNotNull);
        expect(entry!.code, 'STARTUP_INTERRUPTED');
        expect(entry.feature, 'Bootstrap aplikasi');
        expect(entry.summary, contains('database_bootstrap'));
        expect(await diagnostics.readStartupMarker(), isNotNull);
      },
    );

    test(
      'startup normal ditandai complete dan tidak dilaporkan sebagai crash',
      () async {
        await diagnostics.markStartupStarted(phase: 'bindings_ready');
        await diagnostics.markStartupComplete();
        await diagnostics.recordInterruptedStartupIfNeeded();

        expect(await diagnostics.latest(), isEmpty);
        expect((await diagnostics.readStartupMarker())!['status'], 'complete');
      },
    );

    test('menyimpan maksimal seratus error terbaru', () async {
      for (var index = 0; index < 104; index++) {
        await diagnostics.recordException(
          code: 'TEST_$index',
          feature: 'Uji',
          error: StateError('masalah $index'),
          impact: 'Tidak mengubah data.',
        );
      }

      final entries = await diagnostics.latest();
      expect(entries, hasLength(AppDiagnosticsService.maxEntries));
      expect(entries.first.code, 'TEST_103');
      expect(entries.last.code, 'TEST_4');
    });

    test(
      'update mempertahankan identitas kejadian dan mengenali log lama',
      () async {
        const oldBuild = FfmDiagnosticBuild(
          version: '1.0',
          number: '1',
          commit: 'abcdef0',
        );
        const newBuild = FfmDiagnosticBuild(
          version: '1.0',
          number: '2',
          commit: 'abcdef1',
        );
        AppDiagnosticsService service(FfmDiagnosticBuild build) =>
            AppDiagnosticsService(
              store: store,
              clock: () => DateTime.utc(2026, 9, 14),
              buildLoader: () async => build,
            );
        final old = service(oldBuild);
        await old.recordException(
          code: 'SQLITE_BUSY',
          feature: 'Insight',
          error: 'locked',
          impact: 'Ditunda',
        );
        final updated = service(newBuild);
        final historical = (await updated.latest()).single;
        expect(historical.build.matches(oldBuild), isTrue);
        expect(historical.build.matches(newBuild), isFalse);
        expect(
          await updated.buildSafeReport(),
          contains('Error build saat ini: 0'),
        );
        await updated.recordException(
          code: 'SQLITE_BUSY',
          feature: 'Insight',
          error: 'locked',
          impact: 'Ditunda',
        );
        final report = await updated.buildSafeReport();
        expect(report, contains('Error build saat ini: 1'));
        expect(report, contains(oldBuild.label));
        expect(report, contains(newBuild.label));
        expect(report, contains('2026-09-14T00:00:00.000Z'));
      },
    );

    test(
      'log tanpa metadata tetap unknown dan retensi dipersistenkan',
      () async {
        final now = DateTime.utc(2026, 8, 22, 10, 30);
        Map<String, String> entry(DateTime date) =>
            FfmDiagnosticEntry(
              code: 'LEGACY',
              feature: 'Uji',
              occurredAt: date,
              summary: 'locked',
              stackTrace: '',
              impact: 'Ditunda',
            ).toJson()..removeWhere(
              (key, _) => ['version', 'buildNumber', 'commit'].contains(key),
            );
        store.values['entries.v1'] = jsonEncode([
          entry(now),
          entry(now.subtract(const Duration(days: 30))),
          entry(now.subtract(const Duration(days: 31))),
        ]);
        final entries = await diagnostics.latest();
        expect(entries, hasLength(2));
        expect(entries.every((e) => !e.build.isKnown), isTrue);
        expect(jsonDecode(store.values['entries.v1']!), hasLength(2));
        expect(
          await diagnostics.buildSafeReport(),
          contains('Build tidak diketahui'),
        );
      },
    );

    test(
      'kegagalan metadata dan pencatatan bersamaan tidak kehilangan log',
      () async {
        final service = AppDiagnosticsService(
          store: store,
          buildLoader: () async => throw StateError('unavailable'),
        );
        await Future.wait(
          List.generate(
            12,
            (i) => service.recordException(
              code: 'TEST_$i',
              feature: 'Uji',
              error: 'locked',
              impact: 'Ditunda',
            ),
          ),
        );
        expect(await service.latest(), hasLength(12));
        expect((await service.currentBuild()).isKnown, isFalse);
        await service.clear();
        expect(await service.latest(), isEmpty);
      },
    );

    test('startup terputus tetap memakai build sebelum pembaruan', () async {
      const previous = FfmDiagnosticBuild(version: '1.0', number: '1');
      final old = AppDiagnosticsService(
        store: store,
        buildLoader: () async => previous,
      );
      await old.markStartupStarted(phase: 'database');
      final updated = AppDiagnosticsService(
        store: store,
        buildLoader: () async =>
            const FfmDiagnosticBuild(version: '1.0', number: '2'),
      );
      await updated.recordInterruptedStartupIfNeeded();
      expect((await updated.latestEntry())!.build.matches(previous), isTrue);
    });
  });

  testWidgets('halaman memisahkan riwayat build dan membukanya saat diminta', (
    tester,
  ) async {
    final store = _MemoryStore();
    final diagnostics = AppDiagnosticsService(
      store: store,
      buildLoader: () async =>
          const FfmDiagnosticBuild(version: '1.0', number: '2'),
    );
    await diagnostics.recordException(
      code: 'OLD_LOCK',
      feature: 'Insight',
      error: 'locked',
      impact: 'Ditunda',
      buildAtOccurrence: const FfmDiagnosticBuild(version: '1.0', number: '1'),
    );
    await tester.pumpWidget(
      MaterialApp(home: AppDiagnosticsPage(diagnostics: diagnostics)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Belum ada error pada build saat ini'), findsOneWidget);
    expect(find.text('Kode: OLD_LOCK'), findsNothing);
    final history = find.text('Riwayat build lain / tidak diketahui (1)');
    await tester.ensureVisible(history);
    await tester.tap(history);
    await tester.pumpAndSettle();
    expect(find.text('Kode: OLD_LOCK'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
          diagnostics: diagnostics,
        );

        final errorIntent = await interpreter.interpret('Ada error apa?');
        final pinIntent = await interpreter.interpret('Tolong ganti PIN');

        expect(errorIntent.type, FfmAssistantIntentType.diagnosticStatus);
        expect(errorIntent.destination, FfmAssistantDestination.diagnostics);
        expect(errorIntent.response, contains('PIN_GATE_VERIFY_FAILED'));
        expect(errorIntent.response, contains('Build saat kejadian:'));
        expect(errorIntent.response, isNot(contains('482913')));
        expect(pinIntent.type, FfmAssistantIntentType.openPage);
        expect(pinIntent.destination, FfmAssistantDestination.appSecurity);
        expect(pinIntent.response, contains('bukan di chat'));
      },
    );

    test('menjelaskan saat belum ada error tanpa mengarang masalah', () async {
      final interpreter = FfmAssistantInterpreter(
        database,
        diagnostics: AppDiagnosticsService(store: _MemoryStore()),
      );

      final intent = await interpreter.interpret('Cek error aplikasi');

      expect(intent.type, FfmAssistantIntentType.diagnosticStatus);
      expect(intent.response, contains('Belum ada error teknis'));
    });
  });
}
