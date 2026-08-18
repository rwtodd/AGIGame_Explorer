import 'dart:io';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';
import 'package:test/test.dart';

void main() {
  group("King's Quest 3 Room 4 - Drop/Hide All Possessions Under Bed", () {
    final kq3Dir = Directory('reference_games/kings-quest-3');

    test('drop all in bedroom matches said(56, 68, 9999) and hides possessions under bed', () async {
      if (!kq3Dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync('reference_games/kings-quest-3');
      final engine = AgiGameEngine(resourceLoader: loader);
      await engine.initializeGame();

      // Skip title/intro to game room
      engine.handleKeyPress(13);
      await engine.tick();

      // Give Ego some items (set room to 255 in memory)
      engine.memory.itemRooms[6] = 255; // Thimble
      engine.memory.itemRooms[10] = 255; // Fly Wings
      engine.memory.itemRooms[37] = 255; // Magic Wand
      expect(engine.getCarriedItems().length, greaterThanOrEqualTo(3));

      // Warp directly to room 4 (Gwydion's bedroom)
      engine.changeRoom(4);
      engine.ego.x = 111;
      engine.ego.y = 133;
      engine.memory.setVar(40, 111);
      engine.memory.setVar(41, 133);

      // Run 5 cycles to stabilize room 4
      for (var i = 0; i < 5; i++) {
        await engine.tick();
      }

      final messages = <String>[];

      // Submit "drop all"
      engine.submitCommand('drop all');
      expect(engine.memory.getFlag(2), isTrue); // have.input
      expect(engine.parsedWordIds, equals([56, 68])); // drop, all

      // Advance through the kneeling cutscene (approx 80 cycles)
      for (var i = 0; i < 80; i++) {
        await engine.tick();
        if (engine.activeDialog != null) {
          messages.add(engine.activeDialog!.message);
          await engine.dismissDialog();
        }
      }

      // Verify "You might need it." was NEVER printed
      expect(messages.any((m) => m.contains('You might need it')), isFalse);

      // Verify room 4's success message was printed
      expect(
        messages.any((m) => m.contains('shove all your possessions under the bed')),
        isTrue,
        reason: 'Expected bed hiding message to be displayed, got: $messages',
      );

      // Verify items were moved from inventory (room 255) to room 4 (under bed)
      expect(engine.memory.itemRooms[6], equals(4));
      expect(engine.memory.itemRooms[10], equals(4));
      expect(engine.memory.itemRooms[37], equals(4));
      expect(engine.memory.getFlag(118), isTrue); // f118 = items under bed

      // Now test "get all" / "take all" to retrieve possessions from under bed
      messages.clear();
      engine.submitCommand('get all');

      for (var i = 0; i < 80; i++) {
        await engine.tick();
        if (engine.activeDialog != null) {
          messages.add(engine.activeDialog!.message);
          await engine.dismissDialog();
        }
      }

      // Verify retrieval message
      expect(
        messages.any((m) => m.contains('retrieve all of your possessions')),
        isTrue,
        reason: 'Expected bed retrieval message to be displayed, got: $messages',
      );

      // Verify items returned to inventory (room 255)
      expect(engine.memory.itemRooms[6], equals(255));
      expect(engine.memory.itemRooms[10], equals(255));
      expect(engine.memory.itemRooms[37], equals(255));
      expect(engine.memory.getFlag(118), isFalse); // f118 reset

      engine.dispose();
    });

    test('drop all in hallway outside bedroom warns player with message 31', () async {
      if (!kq3Dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync('reference_games/kings-quest-3');
      final engine = AgiGameEngine(resourceLoader: loader);
      await engine.initializeGame();

      engine.handleKeyPress(13);
      await engine.tick();

      // Give Ego an item
      engine.memory.itemRooms[6] = 255;

      engine.changeRoom(4);

      for (var i = 0; i < 5; i++) {
        await engine.tick();
      }

      // Position in hallway (X <= 77)
      engine.ego.x = 40;
      engine.ego.y = 140;
      engine.memory.setVar(40, 40);
      engine.memory.setVar(41, 140);

      final messages = <String>[];

      engine.submitCommand('drop all');
      for (var i = 0; i < 10; i++) {
        await engine.tick();
        if (engine.activeDialog != null) {
          messages.add(engine.activeDialog!.message);
          await engine.dismissDialog();
        }
      }

      // Message 31: "You might try that over there in your bedroom, but not here in the hall."
      expect(
        messages.any((m) => m.contains('bedroom, but not here in the hall')),
        isTrue,
        reason: 'Expected hallway warning message, got: $messages',
      );
      expect(messages.any((m) => m.contains('You might need it')), isFalse);

      engine.dispose();
    });
  });
}
