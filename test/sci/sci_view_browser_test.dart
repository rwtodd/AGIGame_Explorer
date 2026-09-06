import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/domain/game_info.dart';
import 'package:flutter_agigame/sci/loader/resource_type.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';
import 'package:flutter_agigame/ui/providers/game_launcher_provider.dart';
import 'package:flutter_agigame/ui/screens/browsers/view_browser_screen.dart';
import 'package:flutter_agigame/ui/screens/launcher_screen.dart';

void main() {
  testWidgets('ViewBrowserScreen loads SCI0 PQ2 view 0 with native scale', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final vm = SciVolumeManager.fromDirectory('reference_games/police-quest-2');
    final map = vm.resourceMap;
    final viewCount = map.entriesForType(SciResourceType.view).length;

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(launcherProvider.notifier);
    notifier.state = notifier.state.copyWith(
      status: LauncherStatus.loaded,
      sciVolumeManager: vm,
      gameInfo: GameInfo(
        gamePath: 'reference_games/police-quest-2',
        versionString: 'SCI0 (v0.000.490)',
        version: 0.0,
        engineType: SierraEngineType.sci,
        viewCount: viewCount,
        resourceCounts: {'VIEW Sprites': viewCount},
      ),
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: ViewBrowserScreen(initialViewNumber: 0),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('VIEW BROWSER'), findsOneWidget);
    expect(find.text('VIEW 0'), findsWidgets);
    expect(find.textContaining('Loops'), findsOneWidget);
    expect(find.textContaining('Cels'), findsOneWidget);
    expect(find.text('Loop: '), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    // Native 320-space: 19×43 scaled by 1, not doubled.
    expect(find.textContaining('19 × 43 (scaled to 19 × 43)'), findsOneWidget);
  });

  testWidgets('LauncherScreen VIEW Sprites tile opens the View browser for SCI0', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(launcherProvider.notifier).scanDirectory('reference_games/police-quest-2');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: LauncherScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('VIEW Sprites'));
    await tester.pumpAndSettle();

    expect(find.byType(ViewBrowserScreen), findsOneWidget);
    expect(find.text('VIEW BROWSER'), findsOneWidget);
  });
}
