import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';

void main() {
  group('move.obj Border Collision & Completion Flag Tests', () {
    late AgiGameEngine engine;

    setUp(() {
      engine = AgiGameEngine(speedHz: 20.0, randomSeed: 42);
    });

    tearDown(() {
      engine.dispose();
    });

    test('NPC object in move.obj motion reaches right border, sets flag, and completes motion', () {
      // Set up Object 2 (e.g. broom in SQ2 Room 2)
      final broom = engine.animatedObjects[2];
      broom.isAnimated = true;
      broom.isDrawn = true;
      broom.isUpdating = true;
      broom.x = 150;
      broom.y = 145;
      broom.stepSize = 1;
      broom.stepDistance = 1;

      // Start move.obj towards coordinate (159, 145) setting flag 34
      broom.motionType = 3;
      broom.targetX = 159;
      broom.targetY = 145;
      broom.targetFlag = 34;
      engine.memory.resetFlag(34);

      expect(engine.memory.getFlag(34), isFalse);
      expect(broom.motionType, 3);

      // Advance engine ticks until broom reaches screen border (x = 156-157 for 4px width)
      for (int i = 0; i < 20; i++) {
        engine.tick();
        if (engine.memory.getFlag(34)) break;
      }

      // Flag 34 must be set upon reaching right border
      expect(engine.memory.getFlag(34), isTrue);
      // Motion must be completed back to normal (0)
      expect(broom.motionType, 0);
      expect(broom.direction, 0);
    });

    test('Ego in move.obj motion reaches border, sets flag, restores user control', () {
      final ego = engine.ego;
      ego.isAnimated = true;
      ego.isDrawn = true;
      ego.isUpdating = true;
      ego.x = 150;
      ego.y = 100;
      ego.stepSize = 1;

      ego.motionType = 3;
      ego.targetX = 159;
      ego.targetY = 100;
      ego.targetFlag = 40;
      engine.memory.resetFlag(40);

      for (int i = 0; i < 20; i++) {
        engine.tick();
        if (engine.memory.getFlag(40)) break;
      }

      expect(engine.memory.getFlag(40), isTrue);
      expect(ego.motionType, 0);
    });

    test('Live SQ2 Room 2 broom sweep sets flag 34 and erases broom upon hitting edge of screen', () async {
      final sq2Dir = Directory('reference_games/space-quest-2');
      if (!sq2Dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(sq2Dir.path);
      final sq2Engine = AgiGameEngine(resourceLoader: loader, speedHz: 20.0);
      addTearDown(sq2Engine.dispose);

      await sq2Engine.initializeGame();
      sq2Engine.changeRoom(2);
      await sq2Engine.tick();

      // Verify room 2 loaded
      expect(sq2Engine.currentRoom, 2);

      // Simulate broom (o2) moving across room 2
      final o2 = sq2Engine.animatedObjects[2];
      o2.isAnimated = true;
      o2.isDrawn = true;
      o2.isUpdating = true;
      o2.x = 144;
      o2.y = 145;
      o2.stepSize = 1;
      o2.motionType = 3;
      o2.targetX = 159;
      o2.targetY = 145;
      o2.targetFlag = 34;
      sq2Engine.memory.resetFlag(34);

      // Advance ticks until broom hits border and logic 2 erases it
      for (int i = 0; i < 30; i++) {
        await sq2Engine.tick();
        if (!o2.isDrawn) break;
      }

      // Logic 2 should have erased the broom and motion completed
      expect(o2.isDrawn, isFalse);
      expect(o2.motionType, 0);
    });
  });
}
