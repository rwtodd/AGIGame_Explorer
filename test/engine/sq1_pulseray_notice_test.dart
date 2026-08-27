import 'dart:io';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Space Quest 1 Pulseray Notice', () {
    test('persists and is correctly redrawn across room transitions (Room 51 -> 50 -> 49 -> 50)', () async {
      final path = Directory('reference_games/space-quest-1').existsSync()
          ? 'reference_games/space-quest-1'
          : '/Users/rtodd/src/flutter_agigame/reference_games/space-quest-1';
      if (!Directory(path).existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(path);
      final engine = AgiGameEngine(resourceLoader: loader);
      await engine.initializeGame();

      // Enter Room 51 (Armory)
      engine.onNewRoom(51);
      await engine.tick();

      // Ego receives the Pulseray rifle (inventory item 14)
      engine.memory.itemRooms[14] = 255;
      engine.onDisplay(24, 10, 'F6 to fire Pulseray');
      expect(
        engine.displayedTexts.any((t) => t.message.contains('F6 to fire Pulseray')),
        isTrue,
        reason: 'Room 51 should display F6 to fire Pulseray notice on row 24',
      );

      // Transition from Room 51 -> Room 50 (Star Generator room)
      engine.onNewRoom(50);
      await engine.tick();

      expect(
        engine.displayedTexts.any((t) => t.message.contains('F6 to fire Pulseray')),
        isTrue,
        reason: 'Room 50 should retain F6 to fire Pulseray notice drawn during room init (Logic 119)',
      );
      final row24 = List.generate(40, (c) => engine.textScreenBuffer.getCell(24, c).char).join('');
      expect(row24.contains('F6 to fire Pulseray'), isTrue);

      // Next tick (cycle 2) in Room 50
      await engine.tick();
      expect(
        engine.displayedTexts.any((t) => t.message.contains('F6 to fire Pulseray')),
        isTrue,
        reason: 'Notice should persist across subsequent cycles in Room 50',
      );

      // Transition from Room 50 -> Room 49
      engine.onNewRoom(49);
      await engine.tick();
      expect(
        engine.displayedTexts.any((t) => t.message.contains('F6 to fire Pulseray')),
        isTrue,
        reason: 'Notice should persist when transitioning to Room 49',
      );

      // Transition back from Room 49 -> Room 50
      engine.onNewRoom(50);
      await engine.tick();
      expect(
        engine.displayedTexts.any((t) => t.message.contains('F6 to fire Pulseray')),
        isTrue,
        reason: 'Notice should persist when returning to Room 50',
      );
    });
  });
}
