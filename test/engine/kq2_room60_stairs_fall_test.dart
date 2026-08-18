import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';

void main() {
  group("King's Quest 2 Room 60 Tower Stairs Falling Tests", () {
    late Directory kq2Dir;

    setUp(() {
      kq2Dir = Directory('reference_games/kings-quest-2');
    });

    test('Walking off lower tower stairs falls to floor at (52, 148) and plays dazed animation', () async {
      if (!kq2Dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(kq2Dir.path);
      final engine = AgiGameEngine(resourceLoader: loader);

      await engine.initializeGame();
      engine.changeRoom(60);

      // Initial ticks
      for (int i = 0; i < 5; i++) {
        await engine.tick();
      }

      // Place Ego on the ramp where user stepped off: pos (59, 96)
      final ego = engine.ego;
      ego.x = 59;
      ego.y = 96;
      ego.prevX = 59;
      ego.prevY = 96;

      // Walk North into signal priority 2 to step off the stairs
      engine.setEgoDirection(1); // North
      for (int i = 0; i < 10; i++) {
        await engine.tick();
        if (engine.memory.getVar(34) > 0) break;
      }

      expect(engine.memory.getVar(30), 4, reason: 'Falling mode 4 should be triggered');
      expect(ego.view, 8, reason: 'Falling view 8 should be set during descent');

      // Run ticks to let the fall complete
      for (int i = 0; i < 30; i++) {
        await engine.tick();
      }

      expect(ego.x, 52, reason: 'Ego should have landed on floor at x=52');
      expect(ego.y, 148, reason: 'Ego should have landed on floor at y=148');
      expect(ego.view, 109, reason: 'Ego should be in dazed view 109 on the floor');
      engine.dispose();
    });

    test('Walking off high tower stairs falls to floor and results in death', () async {
      if (!kq2Dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(kq2Dir.path);
      final engine = AgiGameEngine(resourceLoader: loader);

      await engine.initializeGame();
      engine.changeRoom(60);

      for (int i = 0; i < 5; i++) {
        await engine.tick();
      }

      // Ego starts at (118, 32). Move down ramp towards (80, 74)
      final ego = engine.ego;
      ego.x = 80;
      ego.y = 74;
      ego.prevX = 80;
      ego.prevY = 74;

      // Step South into trigger at (80, 75)
      engine.setEgoDirection(5); // South
      for (int i = 0; i < 10; i++) {
        await engine.tick();
        if (engine.memory.getVar(34) > 0) break;
      }

      expect(engine.memory.getVar(30), 2, reason: 'High fall mode 2 should be triggered');

      // Run ticks to complete fall
      for (int i = 0; i < 60; i++) {
        await engine.tick();
      }

      expect(ego.x, 88);
      expect(ego.y, 166);
      expect(ego.view, 91, reason: 'Ego should be dead view 91');
      expect(engine.activeDialog, isNotNull);
      engine.dispose();
    });
  });
}
