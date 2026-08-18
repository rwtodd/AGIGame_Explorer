import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/domain/picture.dart';
import 'package:flutter_agigame/domain/priority_buffer.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/picture/picture_slicer.dart';
import 'package:flutter_agigame/ui/screens/browsers/logic_browser_screen.dart';
import 'package:flutter_agigame/ui/screens/game/game_screen.dart';
import 'package:flutter_agigame/ui/widgets/debug_inspector_dialog.dart';
import 'package:flutter_agigame/ui/widgets/snapshot_thumbnail_widget.dart';

void main() {
  group('DebugInspectorDialog Widget Tests', () {
    late AgiGameEngine engine;

    setUp(() {
      engine = AgiGameEngine(speedHz: 20.0, randomSeed: 123);
      final priBuf = PriorityBuffer();
      engine.currentPic = AgiPic(
        visualPixels: Uint8List(160 * 168),
        priorityBuffer: priBuf,
        slices: PictureSlicer.slice(
          visualPixels: Uint8List(160 * 168),
          priorityBuffer: priBuf,
        ),
      );
      engine.memory.setVar(0, 3);
      engine.memory.setVar(3, 10);
      engine.memory.setFlag(9);
      engine.ego.x = 80;
      engine.ego.y = 100;

      final obj2 = engine.animatedObjects[2];
      obj2.isAnimated = true;
      obj2.isDrawn = true;
      obj2.x = 144;
      obj2.y = 145;
      obj2.motionType = 3;
      obj2.targetX = 159;
      obj2.targetY = 145;
      obj2.targetFlag = 34;
    });

    tearDown(() {
      engine.dispose();
    });

    testWidgets('renders 1x live screen, pauses engine, steps frame, and toggles pause/resume', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => DebugInspectorDialog.show(context, engine),
                child: const Text('Open Debugger'),
              ),
            ),
          ),
        ),
      );

      // Open Dialog (must pause engine automatically)
      await tester.tap(find.text('Open Debugger'));
      await tester.pumpAndSettle();

      // Check dialog header and title
      expect(find.text('AGI DEBUG WORKBENCH'), findsOneWidget);
      expect(find.text('LIVE 1X VIEWPORT'), findsOneWidget);
      expect(find.text('PAUSED'), findsWidgets);
      expect(find.text('Resume'), findsOneWidget);
      expect(find.text('Step Frame'), findsOneWidget);
      expect(engine.isPaused, isTrue, reason: 'Opening debug inspector automatically pauses game engine');

      // Click Single Step Frame
      await tester.tap(find.text('Step Frame'));
      await tester.pumpAndSettle();

      expect(engine.cycleCount, 1);

      // Click Resume
      await tester.tap(find.text('Resume'));
      await tester.pumpAndSettle();

      expect(engine.isPaused, isFalse);
      expect(find.text('RUNNING'), findsWidgets);

      // Click Pause again
      await tester.tap(find.text('Pause'));
      await tester.pumpAndSettle();

      expect(engine.isPaused, isTrue);

      // Capture Snapshot
      await tester.tap(find.text('Capture'));
      await tester.pumpAndSettle();

      expect(engine.checkpointHistory.length, 2, reason: '1 auto room transition from step frame + 1 manual capture');

      // Switch to Variables & Flags Tab
      await tester.tap(find.text('Variables & Flags'));
      await tester.pumpAndSettle();

      expect(find.text('ACTIVE FLAGS'), findsOneWidget);
      expect(find.text('%f9'), findsOneWidget);
      expect(find.text('sound_enabled'), findsOneWidget);
      expect(find.text('%v3'), findsOneWidget);
      expect(find.text('current_score'), findsOneWidget);

      // Switch to Animated Objects Tab
      await tester.tap(find.text('Animated Objects'));
      await tester.pumpAndSettle();

      expect(find.text('Ego (Object 0)'), findsOneWidget);
      expect(find.text('Pos: (80, 100)'), findsOneWidget);
      expect(find.text('Object 2'), findsOneWidget);
      expect(find.text('move.obj -> Target: (159, 145)'), findsOneWidget);
      expect(find.text('Result Flag: %f34'), findsOneWidget);

      // Switch to Logic & Stack Tab
      await tester.tap(find.text('Logic & Stack'));
      await tester.pumpAndSettle();

      expect(find.text('ENGINE & ROOM STATUS'), findsOneWidget);
      expect(find.text('Current Room: Room 3'), findsOneWidget);
    });

    testWidgets('GameScreen sidebar quick-capture button creates state snapshot without pausing game', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(engine: engine),
        ),
      );
      await tester.pumpAndSettle();

      expect(engine.checkpointHistory, isEmpty);
      expect(engine.isPaused, isFalse);

      // Find quick-capture button by tooltip
      final quickCaptureButton = find.byTooltip('Quick-Capture Checkpoint Snapshot');
      expect(quickCaptureButton, findsOneWidget);

      await tester.tap(quickCaptureButton);
      await tester.pump(); // trigger snackbar

      expect(engine.checkpointHistory.length, 1);
      expect(engine.checkpointHistory.first.roomNumber, 3);
      expect(engine.isPaused, isFalse, reason: 'Quick capture must not pause the game engine');
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('📸 Captured:'), findsOneWidget);
    });

    testWidgets('Checkpoints tab renders visual thumbnails and filters manual vs room transition checkpoints', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // 1. Setup manual snapshot and room transition snapshot
      engine.recordCheckpoint(label: 'Manual Save 1', isRoomTransition: false);
      engine.changeRoom(5);
      engine.tick(); // Post-scan triggers auto room transition snapshot

      expect(engine.checkpointHistory.length, 2);
      expect(engine.roomCheckpoints.length, 1);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => DebugInspectorDialog.show(context, engine),
                child: const Text('Open Debugger'),
              ),
            ),
          ),
        ),
      );

      // Open Dialog
      await tester.tap(find.text('Open Debugger'));
      await tester.pumpAndSettle();

      // Checkpoints tab should be open by default
      expect(find.text('All (2)'), findsOneWidget);
      expect(find.text('📸 Manual (1)'), findsOneWidget);
      expect(find.text('🚪 Room Entry (1)'), findsOneWidget);

      // Check that both badges and thumbnails are rendered
      expect(find.text('🚪 ROOM ENTRY'), findsOneWidget);
      expect(find.text('📸 SNAPSHOT'), findsOneWidget);
      expect(find.byType(SnapshotThumbnailWidget), findsWidgets);

      // Filter by Manual snapshots only
      await tester.tap(find.text('📸 Manual (1)'));
      await tester.pumpAndSettle();

      expect(find.text('📸 SNAPSHOT'), findsOneWidget);
      expect(find.text('🚪 ROOM ENTRY'), findsNothing);

      // Filter by Room Entry snapshots only
      await tester.tap(find.text('🚪 Room Entry (1)'));
      await tester.pumpAndSettle();

      expect(find.text('🚪 ROOM ENTRY'), findsOneWidget);
      expect(find.text('📸 SNAPSHOT'), findsNothing);

      // Restore room entry snapshot
      await tester.tap(find.byTooltip('Restore this state'));
      await tester.pumpAndSettle();

      expect(engine.currentRoom, 5);
    });

    testWidgets('Tab 4 Logic & Stack renders loaded logic chips and navigates to LogicBrowserScreen with Back returning to game', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Change room and load additional logic into engine
      engine.changeRoom(3);
      engine.loadLogic(104);
      expect(engine.loadedLogicNumbers, containsAll([0, 3, 104]));

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => DebugInspectorDialog.show(context, engine),
                  child: const Text('Open Debugger'),
                ),
              ),
            ),
          ),
        ),
      );

      // Open Dialog
      await tester.tap(find.text('Open Debugger'));
      await tester.pumpAndSettle();

      // Switch to Logic & Stack Tab
      await tester.tap(find.text('Logic & Stack'));
      await tester.pumpAndSettle();

      // Verify Loaded Logics Section and Chips
      expect(find.text('CURRENTLY LOADED LOGIC SCRIPTS'), findsOneWidget);
      expect(find.text('LOGIC 0 (Main Loop)'), findsOneWidget);
      expect(find.text('LOGIC 3 (Room 3)'), findsOneWidget);
      expect(find.text('LOGIC 104'), findsOneWidget);
      expect(find.text('Browse All Logics ↗'), findsOneWidget);

      // Tap Logic 3 chip to open LogicBrowserScreen
      await tester.tap(find.text('LOGIC 3 (Room 3)'));
      await tester.pumpAndSettle();

      // Verify LogicBrowserScreen is opened
      expect(find.byType(LogicBrowserScreen), findsOneWidget);
      expect(find.text('LOGIC BROWSER'), findsOneWidget);

      // Tap Back button in LogicBrowserScreen
      await tester.tap(find.byTooltip('Back to Overview'));
      await tester.pumpAndSettle();

      // Verify we returned back to DebugInspectorDialog / game workbench
      expect(find.byType(LogicBrowserScreen), findsNothing);
      expect(find.byType(DebugInspectorDialog), findsOneWidget);
      expect(find.text('AGI DEBUG WORKBENCH'), findsOneWidget);
    });
  });
}
