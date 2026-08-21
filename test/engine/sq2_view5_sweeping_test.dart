import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/engine/motion/agi_motion.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';

void main() {
  group('3-Loop View and SQ2 Sweeping Roger Tests', () {
    late Directory sq2Dir;

    setUp(() {
      sq2Dir = Directory('reference_games/space-quest-2');
    });

    test('selectLoopForDirection with 3-loop view never selects loop 2 for South (5) or North (1)', () {
      // For a 3-loop view (loopCount = 3), only Loop 0 (East) and Loop 1 (West) are movement loops.
      // Loop 2 is auxiliary art (e.g. broom).

      // Starting facing East (loop 0)
      expect(AgiMotion.selectLoopForDirection(3, 3, 0), equals(0)); // East -> Loop 0
      expect(AgiMotion.selectLoopForDirection(5, 3, 0), equals(0)); // South -> Keeps Loop 0
      expect(AgiMotion.selectLoopForDirection(1, 3, 0), equals(0)); // North -> Keeps Loop 0

      // Starting facing West (loop 1)
      expect(AgiMotion.selectLoopForDirection(7, 3, 1), equals(1)); // West -> Loop 1
      expect(AgiMotion.selectLoopForDirection(5, 3, 1), equals(1)); // South -> Keeps Loop 1
      expect(AgiMotion.selectLoopForDirection(1, 3, 1), equals(1)); // North -> Keeps Loop 1

      // If currentLoop was out-of-range (e.g. 2), it should normalize to 0
      expect(AgiMotion.selectLoopForDirection(5, 3, 2), equals(0));
      expect(AgiMotion.selectLoopForDirection(1, 3, 2), equals(0));
    });

    test('Space Quest 2 Room 2: Roger sweeping with View 5 remains in loop 0 or 1 while wandering', () async {
      if (!sq2Dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(sq2Dir.path);
      final engine = AgiGameEngine(resourceLoader: loader);
      await engine.initializeGame(startingRoom: 2);

      // Ego starts in Room 2 sweeping with View 5
      expect(engine.ego.view, equals(5));
      expect(engine.ego.loop, isIn([0, 1]));

      // Run multiple ticks while Ego wanders in Room 2
      for (int i = 0; i < 60; i++) {
        await engine.tick();
        // Ego's loop must NEVER be 2 (which is just the broom sprite)
        expect(
          engine.ego.loop,
          isIn([0, 1]),
          reason: 'Cycle $i: Ego (View 5) loop must be 0 or 1 (sweeping animation), never 2 (broom only)',
        );
      }

      engine.dispose();
    });
  });
}
