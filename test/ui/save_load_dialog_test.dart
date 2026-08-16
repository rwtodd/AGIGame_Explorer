import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/engine/state/game_state_serializer.dart';
import 'package:flutter_agigame/ui/widgets/save_load_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SaveLoadDialog & RestartConfirmationDialog Widget Tests', () {
    late Directory tempDir;
    late AgiGameEngine engine;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('save_load_widget_test_');
      engine = AgiGameEngine();
      engine.saveDirectory = tempDir;
      engine.memory.setVar(0, 5); // room 5
      engine.memory.setVar(3, 30); // score 30
      engine.memory.setVar(7, 100); // max score 100
    });

    tearDown(() async {
      engine.dispose();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    testWidgets('renders Save modal, allows entering description, and saves slot to disk', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1024, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => SaveLoadDialog.showSave(context, engine, directory: tempDir),
                child: const Text('Open Save Dialog'),
              ),
            ),
          ),
        ),
      );

      expect(engine.isPaused, isFalse);

      // Open Save Dialog
      await tester.tap(find.text('Open Save Dialog'));
      await tester.pumpAndSettle();

      expect(engine.isPaused, isTrue);
      expect(find.text('SAVE GAME STATE'), findsOneWidget);
      expect(find.text('SAVE DESCRIPTION:'), findsOneWidget);
      expect(find.text('Save Game'), findsOneWidget);

      // Enter save description
      final descField = find.byType(TextField);
      expect(descField, findsOneWidget);
      await tester.enterText(descField, 'Before the Ogre');
      await tester.pump();

      // Click Save Game
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save Game'));
      await tester.pumpAndSettle();

      // Dialog closed and engine resumed
      expect(find.text('SAVE GAME STATE'), findsNothing);
      expect(engine.isPaused, isFalse);

      // Verify file written to tempDir
      final file = File('${tempDir.path}/slot_1.sav');
      expect(file.existsSync(), isTrue);

      final info = GameStateSerializer.getSlotInfoSync(1, directory: tempDir);
      expect(info, isNotNull);
      expect(info!.description, equals('Before the Ogre'));
      expect(info.roomNumber, equals(5));
      expect(info.score, equals(30));
    });

    testWidgets('renders Restore modal and restores populated save slot', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1024, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Create a save file in slot 2
      engine.memory.setVar(0, 15);
      engine.memory.setVar(3, 75);
      GameStateSerializer.saveToSlotSync(
        engine,
        2,
        description: 'Magic Tree',
        directory: tempDir,
      );

      // Mutate engine state
      engine.memory.setVar(0, 1);
      engine.memory.setVar(3, 0);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => SaveLoadDialog.showRestore(context, engine, directory: tempDir),
                child: const Text('Open Restore Dialog'),
              ),
            ),
          ),
        ),
      );

      // Open Restore Dialog
      await tester.tap(find.text('Open Restore Dialog'));
      await tester.pumpAndSettle();

      expect(engine.isPaused, isTrue);
      expect(find.text('RESTORE GAME STATE'), findsOneWidget);
      expect(find.text('Restore Game'), findsOneWidget);
      expect(find.text('Magic Tree'), findsOneWidget);

      // Tap slot 2
      await tester.tap(find.text('Magic Tree'));
      await tester.pumpAndSettle();

      // Tap Restore Game button
      await tester.tap(find.widgetWithText(ElevatedButton, 'Restore Game'));
      await tester.pumpAndSettle();

      // Dialog should be dismissed and engine resumed
      expect(find.text('RESTORE GAME STATE'), findsNothing);
      expect(engine.isPaused, isFalse);

      // Engine state restored
      expect(engine.memory.getVar(0), equals(15));
      expect(engine.memory.getVar(3), equals(75));
      expect(engine.memory.getFlag(5), isTrue);
      expect(engine.memory.getFlag(12), isTrue);
    });

    testWidgets('RestartConfirmationDialog confirms restart and resets state', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1024, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      engine.memory.setVar(0, 20);
      engine.memory.setVar(3, 100);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => SaveLoadDialog.showRestartConfirmation(context, engine),
                child: const Text('Open Restart Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Restart Dialog'));
      await tester.pumpAndSettle();

      expect(engine.isPaused, isTrue);
      expect(find.text('RESTART GAME CONFIRMATION'), findsOneWidget);
      expect(find.textContaining('Are you sure you want to restart'), findsOneWidget);

      // Click Restart
      await tester.tap(find.text('Restart [Y]'));
      await tester.pumpAndSettle();

      expect(find.text('RESTART GAME CONFIRMATION'), findsNothing);
      expect(engine.isPaused, isFalse);
      expect(engine.memory.getVar(0), equals(0));
      expect(engine.memory.getVar(3), equals(0));
      expect(engine.memory.getFlag(11), isTrue);
    });

    testWidgets('RestartConfirmationDialog cancels restart and sets Flag 16', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1024, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      expect(engine.memory.getFlag(16), isFalse);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => SaveLoadDialog.showRestartConfirmation(context, engine),
                child: const Text('Open Restart Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Restart Dialog'));
      await tester.pumpAndSettle();

      expect(engine.isPaused, isTrue);

      // Click Cancel
      await tester.tap(find.text('Cancel [N]'));
      await tester.pumpAndSettle();

      expect(find.text('RESTART GAME CONFIRMATION'), findsNothing);
      expect(engine.isPaused, isFalse);
      expect(engine.memory.getFlag(16), isTrue);
    });
  });
}
