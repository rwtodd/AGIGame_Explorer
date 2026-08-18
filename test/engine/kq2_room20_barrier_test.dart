import 'dart:io';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('KQ2 Room 19 -> Room 20 Transition and Barrier Collision', () {
    test('Ego observes conditional barrier in Room 20 after entering from Room 19', () async {
      final kq2Dir = Directory('reference_games/kings-quest-2');
      if (!kq2Dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(kq2Dir.path);
      final engine = AgiGameEngine(resourceLoader: loader);

      await engine.initializeGame();

      // Enter Room 19
      engine.changeRoom(19);
      for (var i = 0; i < 5; i++) {
        await engine.tick();
      }

      final ego = engine.ego;
      expect(engine.memory.getVar(0), 19);
      // Room 19 script sets ignore.blocks(0)
      expect(ego.ignoreBlocks, isTrue, reason: 'Room 19 should have enabled ignoreBlocks');

      // Now move across right border into Room 20
      engine.memory.setVar(2, 2); // Crossed right border
      engine.changeRoom(20);
      for (var i = 0; i < 5; i++) {
        await engine.tick();
      }

      expect(engine.memory.getVar(0), 20);
      expect(ego.ignoreBlocks, isFalse, reason: 'Ego ignoreBlocks must be reset to false in new room');

      // Place Ego near the antique shop wall in Picture 20 (x=68, y=120)
      ego.x = 65;
      ego.y = 120;
      engine.setEgoDirection(3); // Move East towards wall at x=74

      for (var i = 0; i < 15; i++) {
        await engine.tick();
      }

      // Ego should be stopped before penetrating the wall (x=74)
      // With cel width 6, right edge cannot reach 74, so x <= 68.
      expect(ego.x, lessThanOrEqualTo(68), reason: 'Ego must be blocked by conditional barrier in Room 20');
      expect(ego.direction, equals(0), reason: 'Ego direction should be stopped upon hitting barrier');
      engine.dispose();
    });
  });
}
