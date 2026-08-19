import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';

void main() {
  group('Space Quest 2 Room 39 Crawling and Standing Tests', () {
    late Directory sq2Dir;

    setUp(() {
      sq2Dir = Directory('reference_games/space-quest-2');
    });

    test('Entering Room 39 from Room 37 keeps Ego crawling in View 87 without immediately standing up', () async {
      if (!sq2Dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(sq2Dir.path);
      final engine = AgiGameEngine(resourceLoader: loader);

      // Start in Room 37
      await engine.initializeGame(startingRoom: 37);

      // Move Ego East into the tunnel towards Room 39
      final ego = engine.ego;
      ego.x = 133;
      ego.y = 148;
      engine.setEgoDirection(3); // East

      // Tick to trigger new.room(39)
      await engine.tick();
      expect(engine.currentRoom, equals(39), reason: 'Ego should have entered Room 39');

      // Now we are in Room 39: Ego should be at (1, 129), with View 87, and Flag 30 (crawling) SET
      expect(ego.x, equals(1));
      expect(ego.y, equals(129));
      expect(ego.view, equals(87), reason: 'Ego must be crawling (view 87)');
      expect(engine.memory.getFlag(30), isTrue, reason: '%f30 (crawling) must be ON');
      expect(engine.memory.getFlag(3), isTrue, reason: '%f3 (signal line) must be ON since baseline spans to x=17 touching signal line at x=8..9');
      expect(engine.memory.getVar(69), isZero, reason: '%v69 should not be set to 1 ("You stand up")');

      // Tick 5 times in place while crawling: Ego must remain in View 87 and not stand up
      for (int i = 0; i < 5; i++) {
        await engine.tick();
        expect(ego.view, equals(87), reason: 'Ego should stay crawling (view 87)');
        expect(engine.memory.getFlag(30), isTrue, reason: '%f30 should stay ON');
        expect(engine.memory.getVar(69), isZero, reason: '%v69 should not trigger standing up message');
      }

      for (int i = 0; i < 20; i++) {
        engine.setEgoDirection(3); // East
        await engine.tick();
        if (ego.x >= 15) break;
      }

      // Now that Ego walked out past x=10, Ego leaves the signal line: Ego stands up (view 0)
      expect(ego.view, equals(0), reason: 'Ego should stand up upon exiting the tunnel');
      expect(engine.memory.getFlag(30), isFalse, reason: '%f30 should be OFF');

      engine.dispose();
    });
  });
}
