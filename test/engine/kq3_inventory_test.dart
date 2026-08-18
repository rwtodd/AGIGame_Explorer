import 'dart:io';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('King\'s Quest III Inventory & See Object Mechanics', () {
    test('TAB / Controller 10 opens inventory in view mode (f13=false)', () async {
      final path = Directory('reference_games/kings-quest-3').existsSync()
          ? 'reference_games/kings-quest-3'
          : '/Users/rtodd/src/flutter_agigame/reference_games/kings-quest-3';
      final dir = Directory(path);
      if (!dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(path);
      final engine = AgiGameEngine(resourceLoader: loader);
      await engine.initializeGame();

      // Give player item 1 (magic wand) and item 2 (magic dough)
      engine.memory.itemRooms[1] = 255;
      engine.memory.itemRooms[2] = 255;

      // Trigger Controller 10 (Inventory / TAB)
      engine.controllerManager.triggerController(10, engine.memory);
      await engine.tick();

      expect(engine.isInventoryOpen, isTrue);
      expect(engine.memory.getFlag(13), isFalse, reason: 'f13 should remain false during standard TAB inventory');

      // Close inventory
      await engine.closeInventory();
      expect(engine.isInventoryOpen, isFalse);

      engine.dispose();
    });

    test('F4 / Controller 26 (See Object) opens selection mode (f13=true) and Logic 0 calls show.obj.v(item + 100)', () async {
      final path = Directory('reference_games/kings-quest-3').existsSync()
          ? 'reference_games/kings-quest-3'
          : '/Users/rtodd/src/flutter_agigame/reference_games/kings-quest-3';
      final dir = Directory(path);
      if (!dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(path);
      final engine = AgiGameEngine(resourceLoader: loader);
      await engine.initializeGame();

      // Give player item 1 (*magic wand)
      engine.memory.itemRooms[1] = 255;

      // Trigger Controller 26 (See Object / F4)
      engine.controllerManager.triggerController(26, engine.memory);
      await engine.tick();

      expect(engine.isInventoryOpen, isTrue);
      expect(engine.memory.getFlag(13), isTrue, reason: 'f13 should be set to true by KQ3 Logic 0 for See Object');

      // Select item 1 (*magic wand)
      await engine.closeInventory(1);

      // Verify KQ3 Logic 0 calculated v36 = v25 + 100 = 101, and executed show.obj.v(101)
      expect(engine.memory.getVar(25), 1);
      expect(engine.memory.getVar(36), 101);
      expect(engine.inspectingObjectNumber, 101, reason: 'Engine should open inspection modal for View 101');

      // Dismiss inspection modal
      await engine.closeObjectInspection();
      expect(engine.inspectingObjectNumber, isNull);
      expect(engine.memory.getFlag(13), isFalse, reason: 'f13 should be reset after inspection');

      engine.dispose();
    });
  });
}
