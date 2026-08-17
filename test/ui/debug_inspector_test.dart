import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/domain/picture.dart';
import 'package:flutter_agigame/domain/priority_buffer.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/picture/picture_slicer.dart';
import 'package:flutter_agigame/ui/screens/game/game_screen.dart';
import 'package:flutter_agigame/ui/widgets/debug_inspector_dialog.dart';

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

      expect(engine.isPaused, isFalse);

      // Open Dialog (must pause engine automatically)
      await tester.tap(find.text('Open Debugger'));
      await tester.pumpAndSettle();

      expect(engine.isPaused, isTrue, reason: 'Opening debugger must pause the engine');
      expect(find.text('AGI DEBUG WORKBENCH'), findsOneWidget);
      expect(find.text('LIVE 1X VIEWPORT'), findsOneWidget);
      expect(find.text('PAUSED'), findsWidgets);
      expect(find.text('Resume'), findsOneWidget);
      expect(find.text('Step Frame'), findsOneWidget);

      // Step Frame (advances 1 cycle)
      final cycleBefore = engine.cycleCount;
      await tester.tap(find.text('Step Frame'));
      await tester.pumpAndSettle();

      expect(engine.cycleCount, cycleBefore + 1, reason: 'Step Frame must increment engine cycle count');

      // Resume Engine via Dialog button
      await tester.tap(find.text('Resume'));
      await tester.pumpAndSettle();

      expect(engine.isPaused, isFalse, reason: 'Resume button must unpause engine');
      expect(find.text('Pause'), findsOneWidget);
      expect(find.text('RUNNING'), findsOneWidget);

      // Pause Engine via Dialog button
      await tester.tap(find.text('Pause'));
      await tester.pumpAndSettle();

      expect(engine.isPaused, isTrue, reason: 'Pause button must pause engine');
      expect(find.text('Resume'), findsOneWidget);

      // Capture Snapshot in tab
      await tester.tap(find.text('Capture'));
      await tester.pumpAndSettle();

      expect(engine.checkpointHistory.length, 1);

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
  });
}
