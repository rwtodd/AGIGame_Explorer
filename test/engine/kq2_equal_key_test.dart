import 'dart:io';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group("King's Quest 2 Equal Key Binding Tests", () {
    late Directory kq2Dir;

    setUp(() {
      kq2Dir = Directory('reference_games/kings-quest-2');
    });

    test('KQ2 initializes controller binding for equal sign (=)', () async {
      if (!kq2Dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(kq2Dir.path);
      final engine = AgiGameEngine(resourceLoader: loader);

      await engine.initializeGame();

      final equalCtl = engine.controllerManager.getController(0, 61);
      expect(equalCtl, isNotNull, reason: 'KQ2 must register a controller binding for = (ascii 61)');
      expect(equalCtl, equals(22));

      engine.dispose();
    });

    test('Pressing equal sign (=) while splashing in ocean water triggers swimming in Room 15', () async {
      if (!kq2Dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(kq2Dir.path);
      final engine = AgiGameEngine(resourceLoader: loader);

      await engine.initializeGame();
      engine.changeRoom(15);

      final ego = engine.ego;
      ego.x = 90;
      ego.y = 86;

      for (var i = 0; i < 5; i++) {
        await engine.tick();
      }

      // Walk West into water until Ego splashes (view 104)
      engine.setEgoDirection(7);
      for (var i = 0; i < 20; i++) {
        await engine.tick();
        if (ego.view == 104) break;
      }

      expect(ego.view, 104);
      expect(engine.memory.getVar(95), 1); // Splashing

      // Trigger equal sign key event
      final equalCtl = engine.controllerManager.getController(0, 61);
      expect(equalCtl, isNotNull);
      engine.triggerController(equalCtl!);
      await engine.tick();

      expect(engine.activeDialog, isNull);
      expect(ego.view, 97, reason: 'Ego should be swimming (view 97)');
      expect(engine.memory.getVar(95), 2, reason: 'v95 should be 2 (swimming)');

      engine.dispose();
    });
  });
}
