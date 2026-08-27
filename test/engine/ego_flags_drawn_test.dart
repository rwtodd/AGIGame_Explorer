import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';

void main() {
  group('Ego Flags Update (isDrawn & isAnimated check)', () {
    test('Flag 0 and Flag 3 are not raised when Ego is erased/not drawn', () async {
      final path = Directory('reference_games/kings-quest-4-agi').existsSync()
          ? 'reference_games/kings-quest-4-agi'
          : '/Users/rtodd/src/flutter_agigame/reference_games/kings-quest-4-agi';
      if (!Directory(path).existsSync()) return;

      final loader = await AgiResourceLoader.fromDirectory(path);
      final engine = AgiGameEngine(resourceLoader: loader, speedHz: 20.0);
      await engine.initializeGame();

      engine.changeRoom(95);
      await engine.tick();

      // Walk Ego towards pier signal line
      engine.ego.x = 135;
      engine.ego.y = 129;
      engine.ego.direction = 5;
      engine.memory.setVar(6, 5);

      // Step until Ego steps on signal line and is replaced by falling actor o12
      var fallingTriggered = false;
      for (int i = 0; i < 25; i++) {
        await engine.tick();
        if (engine.animatedObjects[12].isDrawn && !engine.ego.isDrawn) {
          fallingTriggered = true;
          // While Ego is erased, Flag 3 (signal) must NOT be continuously re-raised
          expect(engine.memory.getFlag(3), isFalse);
        }
      }

      expect(fallingTriggered, isTrue);

      // After sequence finishes, Ego should be swimming (view 5) in water at y=163
      expect(engine.ego.isDrawn, isTrue);
      expect(engine.ego.view, 5);
      expect(engine.ego.y, 163);
      expect(engine.animatedObjects[12].isDrawn, isFalse);

      engine.dispose();
    });
  });
}
