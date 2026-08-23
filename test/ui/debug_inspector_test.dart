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

      await tester.enterText(find.byKey(const Key('debug-watch-spec')), 'f99=0');
      await tester.tap(find.byKey(const Key('debug-watch-pin')));
      await tester.pumpAndSettle();
      expect(find.text('%f99'), findsOneWidget);
      expect(engine.memory.isFlagPinned(99), isTrue);
      expect(engine.memory.getFlag(99), isFalse);

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

    testWidgets('Variables & Flags tab can SET or PIN undisplayed and zero values', (tester) async {
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

      await tester.tap(find.text('Open Debugger'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Variables & Flags'));
      await tester.pumpAndSettle();

      expect(find.text('%f99'), findsNothing);
      expect(find.text('%v200'), findsNothing);

      // SET an unseen flag to 0: it appears, but LOGIC/ticks may change it.
      await tester.enterText(find.byKey(const Key('debug-watch-spec')), 'f99=0');
      await tester.tap(find.byKey(const Key('debug-watch-set')));
      await tester.pumpAndSettle();
      expect(find.text('%f99'), findsOneWidget);
      expect(engine.memory.isFlagPinned(99), isFalse);
      expect(engine.memory.getFlag(99), isFalse);
      expect(engine.memory.watchedFlags.contains(99), isTrue);

      // PIN an unseen variable to 0: it stays visible so it can be unpinned.
      await tester.enterText(find.byKey(const Key('debug-watch-spec')), 'v200=0');
      await tester.tap(find.byKey(const Key('debug-watch-pin')));
      await tester.pumpAndSettle();
      expect(find.text('%v200'), findsOneWidget);
      expect(engine.memory.isVarPinned(200), isTrue);
      expect(engine.memory.getVar(200), 0);

      engine.memory.setVar(200, 77);
      await tester.tap(find.text('Step Frame'));
      await tester.pumpAndSettle();
      expect(engine.memory.getVar(200), 0);
      expect(find.text('%v200'), findsOneWidget);

      // PIN f2 ON so post-scan cannot clear the "have input" transient.
      await tester.enterText(find.byKey(const Key('debug-watch-spec')), 'f2=1');
      await tester.tap(find.byKey(const Key('debug-watch-pin')));
      await tester.pumpAndSettle();
      expect(engine.memory.isFlagPinned(2), isTrue);
      await tester.tap(find.text('Step Frame'));
      await tester.pumpAndSettle();
      expect(engine.memory.getFlag(2), isTrue);
      expect(find.text('%f2'), findsOneWidget);
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

      // Check that Load JSON is removed, and Copy State JSON is available
      expect(find.text('Load JSON'), findsNothing);
      expect(find.text('Copy State JSON'), findsOneWidget);

      // Copy State JSON
      await tester.tap(find.text('Copy State JSON'));
      await tester.pumpAndSettle();
      expect(find.text('📋 Current State JSON (no thumbnail) copied to clipboard!'), findsOneWidget);

      // Filter by Manual snapshots only
      await tester.tap(find.text('📸 Manual (1)'));
      await tester.pumpAndSettle();

      expect(find.text('📸 SNAPSHOT'), findsOneWidget);
      expect(find.text('🚪 ROOM ENTRY'), findsNothing);

      // Copy individual checkpoint JSON
      await tester.tap(find.byTooltip('Copy JSON for this snapshot (no thumbnail)'));
      await tester.pumpAndSettle();
      expect(find.text('Snapshot JSON (no thumbnail) copied!'), findsOneWidget);

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

    testWidgets('Header Teleport button opens teleport dialog and warps to target room', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      engine.changeRoom(2);
      expect(engine.currentRoom, 2);

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

      // Click Teleport button in Header
      await tester.tap(find.widgetWithText(OutlinedButton, 'Teleport'));
      await tester.pumpAndSettle();

      // Check Teleport dialog opened
      expect(find.text('TELEPORT TO ROOM'), findsOneWidget);
      expect(find.text('Room # (0–255)'), findsOneWidget);

      // Enter room 65 and tap Teleport (Inspect)
      await tester.enterText(find.widgetWithText(TextField, 'Room # (0–255)'), '65');
      await tester.tap(find.text('Teleport (Inspect)'));
      await tester.pumpAndSettle();

      // Verify engine room changed to 65
      expect(engine.currentRoom, 65);
      expect(find.text('Room Number:'), findsOneWidget);
      expect(find.text('65 (prev: 2)'), findsOneWidget);
    });

    testWidgets('Tab 4 Teleport section warps to room via quick chips and custom input', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      engine.changeRoom(1);
      engine.loadLogic(14);
      engine.loadLogic(75);

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

      // Switch to Tab 4
      await tester.tap(find.text('Logic & Stack'));
      await tester.pumpAndSettle();

      // Verify Teleport section
      expect(find.text('TELEPORT / ROOM SELECTOR'), findsOneWidget);
      expect(find.text('Current: Room 1'), findsOneWidget);

      // Enter room 75 and click Teleport (Inspect)
      await tester.enterText(find.widgetWithText(TextField, 'Room # (0–255)'), '75');
      await tester.ensureVisible(find.widgetWithText(OutlinedButton, 'Teleport (Inspect)'));
      await tester.tap(find.widgetWithText(OutlinedButton, 'Teleport (Inspect)'));
      await tester.pumpAndSettle();

      expect(engine.currentRoom, 75);
      expect(find.text('Current: Room 75'), findsOneWidget);
    });
  });
}
