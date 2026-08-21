import 'dart:io';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('KQ2 Room 71 Monastery Pray', () {
    test('pray at the altar plays view 101 kneel end.of.loop animation', () async {
      final kq2Dir = Directory('reference_games/kings-quest-2');
      if (!kq2Dir.existsSync()) {
        markTestSkipped('KQ2 reference game not present');
        return;
      }

      final loader = AgiResourceLoader.fromDirectorySync(kq2Dir.path);
      final engine = AgiGameEngine(resourceLoader: loader);
      await engine.initializeGame();
      engine.changeRoom(71);

      for (var i = 0; i < 8; i++) {
        await engine.tick();
        if (engine.activeDialog != null) {
          await engine.dismissDialog();
        }
      }

      // posn(ego, 50, 81, 92, 83) is the altar box in LOGIC 71
      engine.ego.x = 70;
      engine.ego.y = 82;
      engine.ego.direction = 0;
      engine.memory.setVar(6, 0);

      engine.submitCommand('pray');
      await engine.tick();

      expect(engine.activeDialog?.message, contains('kneel'),
          reason: 'Pray at the altar should print the kneel message');
      await engine.dismissDialog();

      expect(engine.ego.view, 101, reason: 'Pray sets ego view 101');
      expect(engine.ego.cycleMode, 2, reason: 'end.of.loop(ego, f31)');
      expect(engine.ego.isCycling, isTrue,
          reason: 'Standing still must not cancel end.of.loop cycling');

      final startCel = engine.ego.cel;
      for (var i = 0; i < 6; i++) {
        await engine.tick();
      }

      expect(engine.ego.view, 101);
      expect(engine.ego.cel, greaterThan(startCel),
          reason: 'View 101 kneel loop must advance cels after pray');

      engine.dispose();
    });
  });
}
