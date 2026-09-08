import 'package:ffm_manager/features/assistant/presentation/widgets/ffm_assistant_global_launcher.dart';
import 'package:ffm_manager/features/settings/presentation/widgets/app_pin_entry_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('keypad PIN mengosongkan input ketika tahap verifikasi berubah', (
    tester,
  ) async {
    var title = 'Buat PIN';
    late void Function(void Function()) updateStage;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            updateStage = setState;
            return AppPinEntryPanel(
              title: title,
              message: 'Masukkan 4 angka.',
              onCompleted: (_) async => null,
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('1'));
    await tester.tap(find.text('2'));
    await tester.pump();
    expect(find.byKey(const ValueKey('pin-progress-2')), findsOneWidget);

    updateStage(() => title = 'Ulangi PIN');
    await tester.pump();
    expect(find.byKey(const ValueKey('pin-progress-0')), findsOneWidget);
  });

  testWidgets('launcher Asisten menyimpan posisi setelah digeser', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final launcherState = ValueNotifier(
      const FfmAssistantLauncherState(isSheetOpen: false),
    );
    addTearDown(launcherState.dispose);

    Future<void> pumpLauncher() => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              FfmAssistantGlobalLauncher(
                state: launcherState,
                onOpen: () async {},
              ),
            ],
          ),
        ),
      ),
    );

    await pumpLauncher();
    await tester.pumpAndSettle();
    final launcher = find.byType(FloatingActionButton);
    final before = tester.getTopLeft(launcher);

    await tester.drag(launcher, const Offset(-48, -64));
    await tester.pumpAndSettle();
    final saved = await SharedPreferences.getInstance();
    final savedX = saved.getDouble('assistant_launcher_x');
    final savedY = saved.getDouble('assistant_launcher_y');

    expect(savedX, isNotNull);
    expect(savedY, isNotNull);
    expect(savedX, lessThan(before.dx));
    expect(savedY, lessThan(before.dy));

    await pumpLauncher();
    await tester.pumpAndSettle();
    final restored = tester.getTopLeft(launcher);
    expect(restored.dx, closeTo(savedX!, 1));
    expect(restored.dy, closeTo(savedY!, 1));
  });

  testWidgets('launcher Asisten memicu onOpen pada tap dan pergeseran mikro', (tester) async {
    SharedPreferences.setMockInitialValues({});
    var openCount = 0;
    final launcherState = ValueNotifier<FfmAssistantLauncherState>(
      const FfmAssistantLauncherState(isSheetOpen: false),
    );
    addTearDown(launcherState.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              FfmAssistantGlobalLauncher(
                state: launcherState,
                onOpen: () async => openCount++,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final launcher = find.byType(FloatingActionButton);
    expect(launcher, findsOneWidget);

    // 1. Ketukan biasa
    await tester.tap(launcher);
    await tester.pumpAndSettle();
    expect(openCount, 1);

    // 2. Pergeseran mikro (micro-drag < 10px, jari bergerak sedikit di touchscreen)
    await tester.drag(launcher, const Offset(2, 2));
    await tester.pumpAndSettle();
    expect(openCount, 2);

    // 3. Sembunyikan saat sheet terbuka dan munculkan kembali saat sheet ditutup
    launcherState.value = const FfmAssistantLauncherState(isSheetOpen: true);
    await tester.pumpAndSettle();
    expect(find.byType(FloatingActionButton), findsNothing);

    launcherState.value = const FfmAssistantLauncherState(isSheetOpen: false);
    await tester.pumpAndSettle();
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });
}

