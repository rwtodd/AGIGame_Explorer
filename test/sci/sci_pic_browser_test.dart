import 'dart:ui';
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

    // Verify that Vector Replay is available for SCI
    final replayFinder = find.text('Vector Replay');
    expect(replayFinder, findsOneWidget);

    // Toggle Vector Replay on
    await tester.ensureVisible(replayFinder);
    await tester.pumpAndSettle();
    await tester.tap(replayFinder);
    await tester.pumpAndSettle();

    // Verify Replay Bar is displayed
    expect(find.byIcon(Icons.first_page), findsOneWidget);
    expect(find.byIcon(Icons.skip_previous), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.byIcon(Icons.skip_next), findsOneWidget);
    expect(find.byIcon(Icons.last_page), findsOneWidget);
    expect(find.textContaining('Step '), findsOneWidget);
    expect(find.textContaining('Opcode 0x'), findsOneWidget);

    // Reset to beginning (Step 0)
    await tester.tap(find.byIcon(Icons.first_page));
    await tester.pumpAndSettle();
    expect(find.textContaining('Step 0 /'), findsOneWidget);

    // Step forward one command
    await tester.tap(find.byIcon(Icons.skip_next));
    await tester.pumpAndSettle();
    expect(find.textContaining('Step 1 /'), findsOneWidget);

    // Jump to end
    await tester.tap(find.byIcon(Icons.last_page));
    await tester.pumpAndSettle();

    // Toggle Vector Replay off
    await tester.ensureVisible(replayFinder);
    await tester.pumpAndSettle();
    await tester.tap(replayFinder);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.first_page), findsNothing);

    // Verify view mode segments
    final unditheredFinder = find.text('Undithered (40-Color)');
    await tester.ensureVisible(unditheredFinder);
    await tester.pumpAndSettle();

    expect(find.text('Visual'), findsOneWidget);
    expect(unditheredFinder, findsOneWidget);
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
    await tester.tap(unditheredFinder);
    await tester.pumpAndSettle();

    expect(sciPic.isUndithered, isTrue);

    // Toggle to Composited mode to inspect Slices sidebar
    final compositedFinder = find.text('Composited');
    await tester.ensureVisible(compositedFinder);
    await tester.pumpAndSettle();
    await tester.tap(compositedFinder);
    await tester.pumpAndSettle();

    expect(find.text('PRIORITY SLICES'), findsOneWidget);
    expect(find.text('Priority 15 (Foreground)'), findsOneWidget);

    // Switch to Priority Map
    final priorityFinder = find.text('Priority');
    await tester.ensureVisible(priorityFinder);
    await tester.pumpAndSettle();
    await tester.tap(priorityFinder);
    await tester.pumpAndSettle();

    // Switch to Control Map
    final controlFinder = find.text('Control');
    await tester.ensureVisible(controlFinder);
    await tester.pumpAndSettle();
    await tester.tap(controlFinder);
    await tester.pumpAndSettle();
  });

  testWidgets('PicBrowserScreen hover inspector accurately samples 320x200 coordinates and formats color labels', (tester) async {
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

    // Switch to Visual mode
    await tester.tap(find.text('Visual'));
    await tester.pumpAndSettle();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);

    // Find the picture widget canvas
    final picFinder = find.byType(AgiPictureWidget);
    final picRect = tester.getRect(picFinder);

    // Hover at 75% across the width (x ≈ 240)
    final hoverTarget = Offset(picRect.left + picRect.width * 0.75, picRect.top + picRect.height * 0.5);
    await mouse.moveTo(hoverTarget);
    await tester.pumpAndSettle();

    // With 320x200 resolution, X must be >= 200 (proves 320 scaling, not clamped to 160)
    final hudFinder = find.textContaining('X:');
    expect(hudFinder, findsOneWidget);
    final hudTextWidget = tester.widget<Text>(hudFinder);
    final hudText = hudTextWidget.data!;
    final match = RegExp(r'X:\s*(\d+)').firstMatch(hudText);
    expect(match, isNotNull);
    final xVal = int.parse(match!.group(1)!);
    expect(xVal, greaterThan(200));

    // Verify visual color label is present and not empty or "Border"
    expect(find.textContaining('Color '), findsWidgets);

    // Now switch to Undithered (40-Color) mode and verify HUD label format
    await tester.tap(find.text('Undithered (40-Color)'));
    await tester.pumpAndSettle();

    await mouse.moveTo(hoverTarget);
    await tester.pumpAndSettle();

    // In undithered mode, the label must either show "Color X" or "Blended:" with color names
    final hasColor = find.textContaining('Color ').evaluate().isNotEmpty;
    final hasBlended = find.textContaining('Blended: ').evaluate().isNotEmpty;
    expect(hasColor || hasBlended, isTrue);

    await mouse.removePointer();
  });
}

