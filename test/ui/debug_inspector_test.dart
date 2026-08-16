import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/domain/picture.dart';
import 'package:flutter_agigame/domain/priority_buffer.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/picture/picture_slicer.dart';
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
      engine.memory.setFlag(0);
      engine.ego.x = 80;
      engine.ego.y = 100;
    });

    tearDown(() {
      engine.dispose();
    });

    testWidgets('renders tabs, captures snapshot, and displays live variables', (tester) async {
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

      expect(find.text('AGI DEBUG INSPECTOR & STATE CHECKPOINTS'), findsOneWidget);
      expect(find.text('Checkpoints & Diff'), findsOneWidget);
      expect(find.text('Variables & Flags'), findsOneWidget);
      expect(find.text('Animated Objects'), findsOneWidget);
      expect(find.text('Logic & Stack'), findsOneWidget);

      // Capture Snapshot
      await tester.tap(find.text('Capture'));
      await tester.pumpAndSettle();

      expect(engine.checkpointHistory.length, 1);
      expect(find.text('Room 3 | Cycle 0 | Score 10/0'), findsOneWidget);

      // Switch to Variables & Flags Tab
      await tester.tap(find.text('Variables & Flags'));
      await tester.pumpAndSettle();

      expect(find.text('ACTIVE FLAGS'), findsOneWidget);
      expect(find.text('%f0'), findsOneWidget);
      expect(find.text('ego_on_water'), findsOneWidget);
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
  });
}
