import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';

void main() {
  group('Space Quest 2 Room 98 Name Prompt Tests', () {
    late Directory sq2Dir;

    setUp(() {
      sq2Dir = Directory('reference_games/space-quest-2');
    });

    test('Entering a custom name "Richard" sets %s1 to "Richard" without leaking command to Room 2', () async {
      if (!sq2Dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(sq2Dir.path);
      final engine = AgiGameEngine(resourceLoader: loader);
      await engine.initializeGame(startingRoom: 98);

      // Cycle 1: Room 98 should prompt for name
      await engine.tick();
      expect(engine.currentRoom, equals(98));
      expect(engine.activeInputPrompt, isNotNull);
      expect(engine.activeInputPrompt!.type, equals(AgiInputPromptType.string));

      // Submit "Richard"
      engine.submitInputPrompt('Richard');

      // %s1 must be "Richard"
      expect(engine.memory.getString(1), equals('Richard'));

      // Ticking next cycle in Room 2: command must NOT leak to Room 2
      await engine.tick();
      expect(engine.currentRoom, equals(2));
      expect(engine.memory.getFlag(2), isFalse, reason: 'have_input (%f2) must be false in Room 2');
      expect(engine.memory.getVar(9), equals(0), reason: 'unknown_word (%v9) must be 0 in Room 2');
      expect(engine.activeDialog, isNull, reason: 'No "I don\'t understand" dialog should pop up');

      engine.dispose();
    });

    test('Entering an empty name defaults to "Roger Wilco" in %s1 and enters Room 2 cleanly', () async {
      if (!sq2Dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(sq2Dir.path);
      final engine = AgiGameEngine(resourceLoader: loader);
      await engine.initializeGame(startingRoom: 98);

      await engine.tick();
      expect(engine.currentRoom, equals(98));
      expect(engine.activeInputPrompt, isNotNull);

      // Submit empty string
      engine.submitInputPrompt('');

      // Logic 98 defaults %s1 to "Roger Wilco" when NOT isset(%f2)
      expect(engine.memory.getString(1), equals('Roger Wilco'));

      await engine.tick();
      expect(engine.currentRoom, equals(2));
      expect(engine.memory.getFlag(2), isFalse);
      expect(engine.memory.getVar(9), equals(0));
      expect(engine.activeDialog, isNull);

      engine.dispose();
    });
  });
}
