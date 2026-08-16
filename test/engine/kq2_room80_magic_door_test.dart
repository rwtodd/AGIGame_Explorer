import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';

void main() {
  group("King's Quest 2 Room 80 Magic Door Entry Tests", () {
    late Directory kq2Dir;

    setUp(() {
      kq2Dir = Directory('reference_games/kings-quest-2');
    });

    test('Entering Room 80 from Room 42 synchronizes %v6=1 and moves Ego North (Up)', () {
      if (!kq2Dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(kq2Dir.path);
      final engine = AgiGameEngine(resourceLoader: loader);

      engine.initializeGame();
      engine.changeRoom(42);

      for (int i = 0; i < 5; i++) {
        engine.tick();
      }

      // Unlock 3rd door in Room 42
      engine.memory.setFlag(85);
      engine.memory.setFlag(86);
      engine.memory.setFlag(175); // door 3 opened

      // Trigger room transition
      engine.tick();

      expect(engine.currentRoom, 80, reason: 'Should transition to Room 80');
      expect(engine.memory.getVar(0), 80);
      expect(engine.memory.getVar(1), 42);
      expect(engine.memory.getVar(6), 1, reason: '%v6 should be set to 1 (North)');
      expect(engine.ego.direction, 1, reason: 'Ego direction should be synchronized to 1 (North)');
      expect(engine.ego.loop, 3, reason: 'Ego loop should be 3 (facing North)');

      // Advance several ticks: Ego should safely walk North (decreasing Y)
      final startY = engine.ego.y;
      for (int i = 0; i < 5; i++) {
        engine.tick();
      }

      expect(engine.ego.y, lessThan(startY), reason: 'Ego should walk North towards upper screen');
      expect(engine.ego.x, 80, reason: 'Ego X should remain centered in the safe path');
    });
  });
}
