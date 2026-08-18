import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';

void main() {
  group('King\'s Quest 2 Magic Carpet Flight', () {
    test('riding carpet in Room 2 ascends past priority 0 barrier to Room 105', () async {
      const kq2Path = 'reference_games/kings-quest-2';
      if (!Directory(kq2Path).existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(kq2Path);
      final engine = AgiGameEngine(resourceLoader: loader);
      await engine.initializeGame(startingRoom: 2);

      // Carry carpet (inventory item 76)
      engine.memory.itemRooms[76] = 255;
      engine.memory.setFlag(55); // flag 55: can fly carpet outdoors
      engine.ego.x = 114;
      engine.ego.y = 139;

      // Submit command "ride carpet"
      engine.submitCommand('ride carpet');
      await engine.tick();

      // Verify immediate state change after command
      expect(engine.ego.view, 98); // Carpet view
      expect(engine.ego.priority, 15); // Fixed priority 15
      expect(engine.memory.getFlag(148), isTrue);

      // Advance ticks and verify flight continues past y=112 barrier all the way to room 105
      var reachedRoom105 = false;
      for (int i = 0; i < 100; i++) {
        await engine.tick();
        if (engine.memory.getVar(0) == 105) {
          reachedRoom105 = true;
          break;
        }
      }

      expect(reachedRoom105, isTrue, reason: 'Carpet ascent should transition to Room 105');
      engine.dispose();
    });
  });
}
