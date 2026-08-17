import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';

void main() {
  group('Police Quest 1 Ego Animation & Movement Tests', () {
    test('Ego starts stationary in Room 6 without cycling animation cels', () {
      final gameDir = Directory('reference_games/police-quest-1');
      if (!gameDir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync('reference_games/police-quest-1');
      final engine = AgiGameEngine(resourceLoader: loader);
      addTearDown(engine.dispose);

      engine.initializeGame();

      // Skip title/intro screens by pressing Enter (13) on initial ticks
      for (int t = 1; t <= 120; t++) {
        if (t == 5 || t == 30 || t == 60) {
          engine.handleKeyPress(13); // Enter key
        }
        engine.tick();
        if (engine.memory.getVar(0) == 6 && engine.cycleCount >= 78) {
          break;
        }
      }

      // Verify we have entered Room 6
      expect(engine.memory.getVar(0), equals(6), reason: 'Engine should be in Room 6');
      expect(engine.ego.direction, equals(0), reason: 'Ego direction should be 0 (stopped)');
      expect(engine.ego.isCycling, isFalse, reason: 'Ego isCycling must be false when stationary');

      final initialCel = engine.ego.cel;

      // Pump 10 additional ticks without player input
      for (int i = 0; i < 10; i++) {
        engine.tick();
        expect(engine.ego.cel, equals(initialCel), reason: 'Ego cel should not advance while stationary');
        expect(engine.ego.isCycling, isFalse);
      }

      // Now start moving Ego East (direction 3)
      engine.setEgoDirection(3);
      expect(engine.ego.direction, equals(3));
      expect(engine.ego.isCycling, isTrue);

      engine.tick();
      expect(engine.ego.isCycling, isTrue, reason: 'Ego should cycle while moving');

      // Stop Ego (direction 0)
      engine.setEgoDirection(0);
      expect(engine.ego.direction, equals(0));

      engine.tick();
      expect(engine.ego.isCycling, isFalse, reason: 'Ego should stop cycling when stopped');
      final stoppedCel = engine.ego.cel;

      // Pump more ticks, cel should remain unchanged
      for (int i = 0; i < 5; i++) {
        engine.tick();
        expect(engine.ego.cel, equals(stoppedCel));
      }
    });
  });
}
