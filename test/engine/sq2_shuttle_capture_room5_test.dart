import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';

void main() {
  group('Space Quest 2 - Room 5 Accosted in Shuttle & Black Screen Sequence', () {
    late Directory sq2Dir;

    setUp(() {
      sq2Dir = Directory('reference_games/space-quest-2');
    });

    for (final speed in [20.0, 60.0]) {
      test('Room 5 accosted in shuttle at ${speed}Hz displays all dialogs and shake.screen', () async {
        if (!sq2Dir.existsSync()) return;

        final loader = AgiResourceLoader.fromDirectorySync(sq2Dir.path);
        final engine = AgiGameEngine(resourceLoader: loader, speedHz: speed);
        await engine.initializeGame();
        engine.changeRoom(5);

        // Run 1 tick for Room 5 initialization
        await engine.tick();

        // Walk Ego up the ramp (set f31) and into the shuttle doorway
        engine.memory.setFlag(31);
        engine.ego.ignoreBlocks = true;
        engine.ego.x = 75;
        engine.ego.y = 109;
        engine.ego.direction = 0;

        final modalDialogsSeen = <String>[];
        final nonModalDialogsSeen = <String>[];
        bool sawScreenShake = false;

        for (int i = 0; i < 2000; i++) {
          if (engine.shakeOffsetX != 0.0 || engine.shakeOffsetY != 0.0 || engine.shakeCount > 0) {
            sawScreenShake = true;
          }

          if (engine.activeDialog != null) {
            final msg = engine.activeDialog!.message;
            if (engine.activeDialog!.isModal) {
              modalDialogsSeen.add(msg);
              await engine.dismissDialog();
            } else {
              if (nonModalDialogsSeen.isEmpty || nonModalDialogsSeen.last != msg) {
                nonModalDialogsSeen.add(msg);
              }
            }
          }

          await engine.tick();

          if (engine.currentRoom != 5) {
            break;
          }
        }

        // 1. Verify screen shaking opcode was triggered during beatdown
        expect(sawScreenShake, isTrue, reason: 'shake.screen must trigger screen shake');

        // 2. Verify non-modal sound hit messages (POW, THWACK, etc.)
        expect(nonModalDialogsSeen.any((d) => d.contains("POW!!") || d.contains("THWACK!!") || d.contains("BINCK!!") || d.contains("THUD!!!")), isTrue);

        // 3. Verify modal dialogue sequence before beatdown
        expect(modalDialogsSeen.any((d) => d.contains("You enter the shuttle and start sniffing")), isTrue);
        expect(modalDialogsSeen.any((d) => d.contains("You are surprised to find that the shuttle is not empty")), isTrue);
        expect(modalDialogsSeen.any((d) => d.contains("Hey! What the")), isTrue);

        // 4. Verify post-beatdown dialog
        expect(modalDialogsSeen.any((d) => d.contains("Your protest is cut short as two interstellar ruffians")), isTrue);

        // 5. Verify Black Screen "Time Passes..." sequence
        expect(modalDialogsSeen.any((d) => d.contains("Time Passes...")), isTrue, reason: '"Time Passes..." must be displayed');
        expect(modalDialogsSeen.any((d) => d.contains("More Time Passes...")), isTrue, reason: '"More Time Passes..." must be displayed');
        expect(modalDialogsSeen.any((d) => d.contains("A strange dream turns into the realization")), isTrue);
        expect(modalDialogsSeen.any((d) => d.contains("Upon awakening from your forced rest")), isTrue);
        expect(modalDialogsSeen.any((d) => d.contains("As you try to struggle free")), isTrue);

        // 6. Verify transition to Room 6 (Vohaul)
        expect(engine.currentRoom, 6, reason: 'Sequence must transition to Room 6 (Vohaul)');
        engine.dispose();
      });
    }

    test('Room 5 handles async dismissDialog from UI events without dropping Logic 5 state', () async {
      if (!sq2Dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(sq2Dir.path);
      final engine = AgiGameEngine(resourceLoader: loader, speedHz: 60.0);
      await engine.initializeGame();
      engine.changeRoom(5);
      await engine.tick();

      // Set up beatdown state right before print(%m8)
      engine.memory.setFlag(33);
      engine.memory.resetFlag(31);
      engine.memory.setVar(34, 8);
      engine.memory.setVar(33, 2);

      // Tick to trigger print(%m8)
      await engine.tick();
      expect(engine.activeDialog, isNotNull);
      expect(engine.activeDialog!.message.contains('Your protest is cut short'), isTrue);

      // Dismiss dialog asynchronously (simulating user key press outside of tick loop)
      final dismissFuture = engine.dismissDialog();

      // Immediately attempt ticks (simulating 60Hz loop timer firing)
      await engine.tick();
      if (dismissFuture is Future) {
        await dismissFuture;
      }

      // Verify that unanimate.all and assignn(%v32, 27) was NOT stomped
      expect(engine.memory.getVar(32), greaterThan(0), reason: '%v32 must be initialized to 27 or decremented to 26');
      expect(engine.memory.getFlag(129), isTrue, reason: 'Flag 129 must be set');

      // Now run ticks until transition to Room 6
      for (int i = 0; i < 500; i++) {
        if (engine.activeDialog != null && engine.activeDialog!.isModal) {
          await engine.dismissDialog();
        }
        await engine.tick();
        if (engine.currentRoom == 6) break;
      }

      expect(engine.currentRoom, 6, reason: 'Must successfully reach Room 6');
      engine.dispose();
    });
  });
}
