import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/features/assistant/data/ffm_background_download_service.dart';
import 'package:ffm_manager/features/assistant/data/ffm_local_model_service.dart';
import 'package:ffm_manager/features/assistant/presentation/pages/local_model_page.dart';

class _HangingModelService implements FfmLocalModelService {
  @override
  Future<FfmLocalModelInfo?> getInstalled() =>
      Completer<FfmLocalModelInfo?>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CountingHangingModelService extends _HangingModelService {
  var getInstalledCalls = 0;

  @override
  Future<FfmLocalModelInfo?> getInstalled() {
    getInstalledCalls++;
    return super.getInstalled();
  }
}

class _ErrorModelService implements FfmLocalModelService {
  @override
  Future<FfmLocalModelInfo?> getInstalled() async {
    throw StateError('platform status tidak tersedia');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _IdleBackgroundService implements FfmBackgroundDownloadService {
  @override
  Future<List<FfmBackgroundDownloadStatus>> status() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('timeout pemuatan mengganti spinner dengan tindakan pemulihan', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LocalModelPage(
          modelService: _HangingModelService(),
          backgroundService: _IdleBackgroundService(),
          statusLoadTimeout: const Duration(milliseconds: 20),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      find.textContaining('Gagal memuat status dalam 10 detik'),
      findsOneWidget,
    );
    expect(find.text('Unduh di halaman ini'), findsOneWidget);
  });

  testWidgets(
    'error non-Exception tetap mematikan spinner dan menampilkan refresh',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LocalModelPage(
            modelService: _ErrorModelService(),
            backgroundService: _IdleBackgroundService(),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.textContaining('Status model lokal belum dapat dibaca'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.refresh_outlined), findsOneWidget);
    },
  );

  testWidgets(
    'resume lifecycle tidak memulai load kedua saat load pertama aktif',
    (tester) async {
      final service = _CountingHangingModelService();
      await tester.pumpWidget(
        MaterialApp(
          home: LocalModelPage(
            modelService: service,
            backgroundService: _IdleBackgroundService(),
            statusLoadTimeout: const Duration(milliseconds: 20),
          ),
        ),
      );
      expect(service.getInstalledCalls, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(service.getInstalledCalls, 1);
      await tester.pump(const Duration(milliseconds: 30));
      await tester.pump();
    },
  );
}
