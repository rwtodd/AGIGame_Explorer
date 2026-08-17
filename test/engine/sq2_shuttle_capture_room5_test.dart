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

    test('Room 5 accosted in shuttle displays all dialogs and shake.screen', () {
      if (!sq2Dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(sq2Dir.path);
      final engine = AgiGameEngine(resourceLoader: loader);
      engine.initializeGame();
      engine.changeRoom(5);

      // Run 1 tick for Room 5 initialization
      engine.tick();

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
            engine.dismissDialog();
          } else {
            if (nonModalDialogsSeen.isEmpty || nonModalDialogsSeen.last != msg) {
              nonModalDialogsSeen.add(msg);
            }
          }
        }

        engine.tick();

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
    });
  });
}
