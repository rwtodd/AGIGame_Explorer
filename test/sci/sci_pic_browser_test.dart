import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/domain/game_info.dart';
import 'package:flutter_agigame/sci/loader/resource_type.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';
import 'package:flutter_agigame/sci/picture/sci_pic.dart';
import 'package:flutter_agigame/ui/providers/game_launcher_provider.dart';
import 'package:flutter_agigame/ui/screens/browsers/pic_browser_screen.dart';
import 'package:flutter_agigame/ui/widgets/agi_picture_canvas.dart';

void main() {
  testWidgets('PicBrowserScreen with SCI0 game loads, toggles 40-color undithered mode, and renders slices', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final vm = SciVolumeManager.fromDirectory('reference_games/police-quest-2');
    final map = vm.resourceMap;
    final picCount = map.entriesForType(SciResourceType.pic).length;

    final gameInfo = GameInfo(
      gamePath: 'reference_games/police-quest-2',
      versionString: 'SCI0 (v0.000.490)',
      version: 0.0,
      engineType: SierraEngineType.sci,
      picCount: picCount,
      viewCount: map.entriesForType(SciResourceType.view).length,
      resourceCounts: {
        'PICTURE Rooms': picCount,
      },
    );

    final container = ProviderContainer();
    final notifier = container.read(launcherProvider.notifier);
    notifier.state = notifier.state.copyWith(
      status: LauncherStatus.loaded,
      sciVolumeManager: vm,
      gameInfo: gameInfo,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: PicBrowserScreen(initialPicNumber: 1),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Title and basic badges
    expect(find.text('PIC BROWSER'), findsOneWidget);
    expect(find.text('PICTURE 1'), findsWidgets);

    // Verify that Vector Replay is hidden for SCI
    expect(find.text('Vector Replay'), findsNothing);

    // Verify view mode segments
    expect(find.text('Visual'), findsOneWidget);
    expect(find.text('Undithered (40-Color)'), findsOneWidget);
    expect(find.text('Priority'), findsOneWidget);
    expect(find.text('Control'), findsOneWidget);
    expect(find.text('Composited'), findsOneWidget);

    // Verify AgiPictureWidget is present with 320x200 SciPic
    final picWidgetFinder = find.byType(AgiPictureWidget);
    expect(picWidgetFinder, findsOneWidget);
    final picWidget = tester.widget<AgiPictureWidget>(picWidgetFinder);
    expect(picWidget.picture, isA<SciPic>());
    final sciPic = picWidget.picture as SciPic;
    expect(sciPic.width, 320);
    expect(sciPic.height, 200);
    expect(sciPic.isUndithered, isFalse);

    // Toggle to Undithered (40-Color)
    await tester.tap(find.text('Undithered (40-Color)'));
    await tester.pumpAndSettle();

    expect(sciPic.isUndithered, isTrue);

    // Toggle to Composited mode to inspect Slices sidebar
    await tester.tap(find.text('Composited'));
    await tester.pumpAndSettle();

    expect(find.text('PRIORITY SLICES'), findsOneWidget);
    expect(find.text('Priority 15 (Foreground)'), findsOneWidget);

    // Switch to Priority Map
    await tester.tap(find.text('Priority'));
    await tester.pumpAndSettle();

    // Switch to Control Map
    await tester.tap(find.text('Control'));
    await tester.pumpAndSettle();
  });
}
