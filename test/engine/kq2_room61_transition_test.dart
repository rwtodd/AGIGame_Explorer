import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';

void main() {
  group("King's Quest 2 Castle Hallway Transitions (Room 61 <-> Room 64)", () {
    late Directory kq2Dir;

    setUp(() {
      kq2Dir = Directory('reference_games/kings-quest-2');
    });

    test('Walking right through east archway in Room 61 enters dining room (Room 64) at (25, 119)', () {
      if (!kq2Dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(kq2Dir.path);
      final engine = AgiGameEngine(resourceLoader: loader);

      engine.initializeGame();
      engine.changeRoom(61);

      for (int i = 0; i < 5; i++) {
        engine.tick();
      }

      final ego = engine.ego;
      ego.x = 125;
      ego.y = 123;
      ego.prevX = 125;
      ego.prevY = 123;

      // Walk East into right archway control line
      engine.setEgoDirection(3);

      for (int i = 0; i < 20; i++) {
        engine.tick();
        if (engine.currentRoom == 64) break;
      }

      expect(engine.currentRoom, 64, reason: 'Engine should transition to dining room 64');
      expect(engine.memory.getVar(1), 61, reason: 'Previous room should be 61');
      expect(ego.x, 25, reason: 'Ego should be positioned at x=25 entering Room 64');
      expect(ego.y, 119, reason: 'Ego should be positioned at y=119 entering Room 64');
    });

    test('Walking left through west archway in Room 64 returns to hallway (Room 61) at (125, 123)', () {
      if (!kq2Dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(kq2Dir.path);
      final engine = AgiGameEngine(resourceLoader: loader);

      engine.initializeGame();
      engine.changeRoom(64);

      for (int i = 0; i < 5; i++) {
        engine.tick();
      }

      final ego = engine.ego;
      ego.x = 25;
      ego.y = 119;
      ego.prevX = 25;
      ego.prevY = 119;

      // Walk West into left exit signal line
      engine.setEgoDirection(7);

      for (int i = 0; i < 20; i++) {
        engine.tick();
        if (engine.currentRoom == 61) break;
      }

      expect(engine.currentRoom, 61, reason: 'Engine should return to hallway 61');
      expect(engine.memory.getVar(1), 64, reason: 'Previous room should be 64');
      expect(ego.x, 125, reason: 'Ego should be positioned at x=125 in Room 61');
      expect(ego.y, 123, reason: 'Ego should be positioned at y=123 in Room 61');
    });
  });
}
