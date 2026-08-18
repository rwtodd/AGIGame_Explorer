import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';

void main() {
  group('Space Quest 2 - Room 29 Say The Word Sequence', () {
    late Directory sq2Dir;

    setUp(() {
      sq2Dir = Directory('reference_games/space-quest-2');
    });

    test('say the word causes pink creatures to move the boulder and reveal ladder', () async {
      if (!sq2Dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(sq2Dir.path);
      final engine = AgiGameEngine(resourceLoader: loader);

      await engine.initializeGame();
      engine.memory.setVar(1, 23);
      engine.memory.setVar(87, 1);
      engine.memory.setVar(91, 1);
      engine.changeRoom(29);

      final o1 = engine.animatedObjects[1];
      final o2 = engine.animatedObjects[2];
      final o3 = engine.animatedObjects[3];

      // Mark chief speech complete
      engine.memory.setFlag(98);

      engine.submitCommand('say the word');

      bool boulderMoved = false;

      for (int i = 1; i <= 60; i++) {
        await engine.tick();
        if (engine.memory.getFlag(94)) {
          boulderMoved = true;
          break;
        }
      }

      expect(boulderMoved, isTrue, reason: 'Flag 94 should be set when creatures finish pushing boulder');
      expect(o1.x, equals(97));
      expect(o2.x, equals(104));
      expect(o3.x, greaterThanOrEqualTo(88));
      expect(engine.memory.getFlag(198), isTrue);
    });
  });
}
