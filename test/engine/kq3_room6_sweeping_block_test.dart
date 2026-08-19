import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/engine/motion/collision_detector.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';

void main() {
  group('KQ3 Room 6 Sweeping and Script Block Tests', () {
    late Directory kq3Dir;

    setUp(() {
      kq3Dir = Directory('reference_games/kings-quest-3');
    });

    test('AgiBlockArea boundary crossing semantics', () {
      const block = AgiBlockArea(x1: 36, y1: 120, x2: 121, y2: 154);

      // (62, 123) is inside block
      expect(block.contains(62, 123), isTrue);

      // Moving within block (inside -> inside) is NOT blocked
      expect(block.crossesBoundary(62, 123, 64, 125), isFalse);
      expect(block.crossesBoundary(62, 123, 62, 124), isFalse);

      // Moving from inside to outside crosses boundary (BLOCKED)
      expect(block.crossesBoundary(62, 123, 62, 119), isTrue);
      expect(block.crossesBoundary(62, 123, 35, 123), isTrue);
      expect(block.crossesBoundary(62, 123, 122, 123), isTrue);
      expect(block.crossesBoundary(62, 123, 62, 155), isTrue);

      // Moving outside block (outside -> outside) is NOT blocked
      expect(block.crossesBoundary(10, 10, 12, 10), isFalse);

      // Moving from outside into block crosses boundary (BLOCKED)
      expect(block.crossesBoundary(10, 123, 40, 123), isTrue);
    });

    test('King\'s Quest 3 Room 6 sweeping: Ego wanders freely inside block area without getting stuck', () async {
      if (!kq3Dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(kq3Dir.path);
      final engine = AgiGameEngine(resourceLoader: loader);
      await engine.initializeGame(startingRoom: 6);

      // Restore user snapshot state or simulate getting broom in Room 6
      // Set block active
      engine.onBlock(36, 120, 121, 154);
      engine.ego.x = 62;
      engine.ego.y = 123;
      engine.ego.prevX = 62;
      engine.ego.prevY = 123;
      engine.ego.view = 10;
      engine.ego.motionType = 1; // wander
      engine.ego.direction = 4;
      engine.ego.isAnimated = true;
      engine.ego.isDrawn = true;
      engine.ego.isUpdating = true;
      engine.ego.isCycling = true;
      engine.ego.ignoreBlocks = false;

      // Track positions visited across 50 cycles
      final visitedPositions = <String>{};

      for (int i = 0; i < 60; i++) {
        await engine.tick();
        visitedPositions.add('${engine.ego.x},${engine.ego.y}');

        // Ego must remain inside the kitchen block area
        expect(
          engine.activeBlock!.contains(engine.ego.x, engine.ego.y),
          isTrue,
          reason: 'Ego should stay bounded within the kitchen block area (36, 120, 121, 154)',
        );
      }

      // Ego must have moved to multiple different positions rather than staying stuck at (62, 123)
      expect(
        visitedPositions.length,
        greaterThan(5),
        reason: 'Ego should wander around multiple positions in the kitchen',
      );

      engine.dispose();
    });
  });
}
