import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';

void main() {
  group('Space Quest 2 - Room 23 Tumbling Entrance', () {
    late Directory sq2Dir;

    setUp(() {
      sq2Dir = Directory('reference_games/space-quest-2');
    });

    test('Room 23 tumbling entrance from room 25 completes and places Ego', () async {
      if (!sq2Dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(sq2Dir.path);
      final engine = AgiGameEngine(resourceLoader: loader);

      await engine.initializeGame();
      engine.memory.setVar(1, 25); // Previous room: 25
      engine.memory.setVar(87, 2); // Step size
      engine.changeRoom(23);

      final o10 = engine.animatedObjects[10];
      final ego = engine.ego;

      bool sawTumblingObj = false;
      bool egoPlacedAndDrawn = false;

      for (int i = 0; i < 150; i++) {
        if (engine.activeDialog != null) {
          await engine.dismissDialog();
        }

        await engine.tick();

        if (o10.isDrawn && o10.view == 82) {
          sawTumblingObj = true;
        }

        if (ego.isDrawn && ego.view == 0 && ego.x > 30) {
          egoPlacedAndDrawn = true;
          break;
        }
      }

      expect(sawTumblingObj, isTrue, reason: 'Object 10 should animate tumbling into room 23');
      expect(egoPlacedAndDrawn, isTrue, reason: 'Ego should be drawn and placed after tumbling finishes');
      expect(ego.x, equals(41));
      expect(ego.y, equals(136));
    });
  });
}
