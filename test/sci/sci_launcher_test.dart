import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/ui/providers/game_launcher_provider.dart';
import 'package:flutter_agigame/ui/screens/browsers/pic_browser_screen.dart';
import 'package:flutter_agigame/ui/screens/launcher_screen.dart';

void main() {
  testWidgets('LauncherScreen recognizes SCI0 game, displays 9 resource counts, and navigates to PicBrowser', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final container = ProviderContainer();
    final notifier = container.read(launcherProvider.notifier);

    // Scan PQ2 reference game directory
    await notifier.scanDirectory('reference_games/police-quest-2');

    final state = container.read(launcherProvider);
    expect(state.status, LauncherStatus.loaded);
    expect(state.isSci, isTrue);
    expect(state.gameInfo?.versionString, 'SCI0 (v0.000.490)');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: LauncherScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify engine badge
    expect(find.text('SCI0 / SCI1 EGA'), findsOneWidget);
    expect(find.text('SCI0 (v0.000.490)'), findsOneWidget);

    // Verify all 9 resource categories are rendered
    expect(find.text('PICTURE Rooms'), findsOneWidget);
    expect(find.text('VIEW Sprites'), findsOneWidget);
    expect(find.text('SCRIPT Bytecode'), findsOneWidget);
    expect(find.text('TEXT Messages'), findsOneWidget);
    expect(find.text('SOUND Tracks'), findsOneWidget);
    expect(find.text('VOCAB Dictionary'), findsOneWidget);
    expect(find.text('FONT Typography'), findsOneWidget);
    expect(find.text('CURSOR Sprites'), findsOneWidget);
    expect(find.text('PATCH Driver Fixes'), findsOneWidget);

    // Verify PICTURE Rooms count is 78
    expect(find.text('78'), findsOneWidget);

    // Verify play button is disabled or marked in dev for SCI
    expect(find.text('PLAY GAME (SCI VM IN DEV)'), findsOneWidget);

    // Tap on PICTURE Rooms tile to navigate to PicBrowserScreen
    await tester.tap(find.text('PICTURE Rooms'));
    await tester.pumpAndSettle();

    // Verify PicBrowserScreen is now displayed with initial Picture 0
    expect(find.byType(PicBrowserScreen), findsOneWidget);
    expect(find.text('PIC BROWSER'), findsOneWidget);
    expect(find.text('PICTURE 0'), findsWidgets);
  });

  testWidgets('LauncherScreen navigates to FontBrowserScreen when FONT Typography is tapped', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final container = ProviderContainer();
    final notifier = container.read(launcherProvider.notifier);

    await notifier.scanDirectory('reference_games/police-quest-2');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: LauncherScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Tap on FONT Typography tile
    await tester.tap(find.text('FONT Typography'));
    await tester.pumpAndSettle();

    // Verify FontBrowserScreen is displayed
    expect(find.text('FONT 0'), findsOneWidget);
    expect(find.text('SYSFONT / Chicago 12'), findsWidgets);
    expect(find.text('GLYPH INSPECTION #65 (0x41) \'A\''), findsOneWidget);
  });
}
