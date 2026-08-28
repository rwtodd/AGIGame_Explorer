import 'dart:io';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group("King's Quest 1 Swimming & Room Transitions", () {
    late Directory kq1Dir;

    setUp(() {
      kq1Dir = Directory('reference_games/kings-quest-1-agi');
    });

    test('Swimming North from Room 37 (swamp) into Room 44 (woodcutter) transitions to walking View 0', () async {
      if (!kq1Dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(kq1Dir.path);
      final engine = AgiGameEngine(resourceLoader: loader);
      await engine.initializeGame();

      // Start in Room 37 (swamp)
      engine.changeRoom(37);
      await engine.tick();

      // Put Graham in the water swimming in View 70
      engine.ego.x = 80;
      engine.ego.y = 60;
      engine.ego.view = 70; // View 70 is swimming in KQ1
      engine.memory.setFlag(0); // in water
      engine.memory.setFlag(98); // swimming flag in KQ1
      engine.memory.setVar(94, 2); // swimming mode in KQ1

      // Swim North into Room 44
      for (int i = 0; i < 20; i++) {
        engine.memory.setVar(6, 1); // North
        await engine.tick();
        if (engine.memory.getVar(0) == 44) {
          break;
        }
      }

      expect(engine.memory.getVar(0), 44, reason: 'Ego should have entered Room 44');
      expect(engine.ego.view, 0, reason: 'Ego should have transitioned back to walking view 0 in Room 44');
      expect(engine.memory.getFlag(98), isFalse, reason: 'Flag 98 (swimming) should be reset in Room 44');
      expect(engine.memory.getVar(94), 0, reason: 'Var 94 should be 0 (walking) in Room 44');
      expect(engine.memory.getFlag(0), isFalse, reason: 'Flag 0 should be false on dry land in Room 44');

      engine.dispose();
    });
  });
}
