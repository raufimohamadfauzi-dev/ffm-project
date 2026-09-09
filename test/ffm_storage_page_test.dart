import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/features/settings/presentation/pages/ffm_storage_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('ffm/privacy');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  testWidgets('menampilkan pengelolaan penyimpanan dan dialog reset', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: FfmStoragePage()));

    expect(find.text('Penyimpanan FFM'), findsOneWidget);
    expect(find.text('Setel ulang FFM'), findsOneWidget);
    expect(find.text('Buka Setelan penyimpanan aplikasi'), findsOneWidget);

    await tester.tap(find.text('Setel ulang FFM'));
    await tester.pumpAndSettle();

    expect(find.text('Setel ulang sekarang'), findsOneWidget);
    expect(find.textContaining('akan dihapus secara permanen'), findsOneWidget);
  });

  testWidgets('membatalkan reset tidak membuka Settings Android', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });

    await tester.pumpWidget(const MaterialApp(home: FfmStoragePage()));
    await tester.tap(find.text('Setel ulang FFM'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();

    expect(calls, isEmpty);
    expect(find.text('Setel ulang sekarang'), findsNothing);
  });

  testWidgets('konfirmasi reset membuka halaman Settings Android', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });

    await tester.pumpWidget(const MaterialApp(home: FfmStoragePage()));
    await tester.tap(find.text('Setel ulang FFM'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Setel ulang sekarang'));
    await tester.pumpAndSettle();

    expect(calls.map((call) => call.method), ['openAppSettings']);
  });
}
