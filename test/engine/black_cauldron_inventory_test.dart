import 'dart:io';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('The Black Cauldron F3/F4 Item Selection & Usage', () {
    test('F3 New Object opens inventory with f13=true, selecting item sets v25/v42, F4 uses object', () async {
      final dir = Directory('reference_games/black-cauldron');
      if (!dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(dir.path);
      final engine = AgiGameEngine(resourceLoader: loader);
      await engine.initializeGame();

      // Skip title / intro to game room 2
      engine.changeRoom(2);
      await engine.tick();

      // Ensure player is carrying knapsack (item 1)
      engine.memory.itemRooms[1] = 255;

      // 1. Player triggers Controller 11 (F3 / "New Object")
      engine.controllerManager.triggerController(11, engine.memory);
      await engine.tick();

      // Inventory should be open, f13 should be true, and interpreter yielded
      expect(engine.isInventoryOpen, isTrue, reason: 'F3 should open inventory dialog');
      expect(engine.memory.getFlag(13), isTrue, reason: 'f13 (selection mode) should be enabled');
      expect(engine.interpreter.hasPendingInput, isTrue, reason: 'Interpreter should yield at status() opcode');

      // 2. Player selects Knapsack (item 1) and closes dialog
      await engine.closeInventory(1);

      // Verify v25 and v42 updated and f13 reset
      expect(engine.memory.getVar(25), 1, reason: 'v25 must receive selected item number');
      expect(engine.memory.getVar(42), 1, reason: 'v42 must store selected item number for F4 Use Object');
      expect(engine.memory.getFlag(13), isFalse, reason: 'f13 should be reset after selection');

      // 3. Now player triggers Controller 26 (F4 / "Use Object")
      engine.controllerManager.triggerController(26, engine.memory);
      await engine.tick();

      // Verify knapsack usage dialog appeared ("Your roomy knapsack can hold many things.")
      expect(engine.activeDialog?.message, contains('knapsack'));

      engine.dispose();
    });

    test('F3 New Object selecting Magic Sword (item 12) allows swinging sword with F4', () async {
      final dir = Directory('reference_games/black-cauldron');
      if (!dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(dir.path);
      final engine = AgiGameEngine(resourceLoader: loader);
      await engine.initializeGame();
      engine.changeRoom(2);
      await engine.tick();

      // Give magic sword (item 12)
      engine.memory.itemRooms[12] = 255;

      // Select Magic Sword via F3
      engine.controllerManager.triggerController(11, engine.memory);
      await engine.tick();
      expect(engine.isInventoryOpen, isTrue);

      await engine.closeInventory(12);
      expect(engine.memory.getVar(42), 12);

      // Press F4 (Use Object)
      engine.controllerManager.triggerController(26, engine.memory);
      await engine.tick();

      // Verify sword swinging view (view 5) is loaded and set on Ego
      expect(engine.ego.view, 5, reason: 'Ego view should be set to 5 (sword swinging)');
      expect(engine.memory.getFlag(133), isTrue, reason: 'Cycling flag f133 should be set');

      engine.dispose();
    });

    test('Controller 24 (See Object) opens inventory and then shows object inspection view', () async {
      final dir = Directory('reference_games/black-cauldron');
      if (!dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(dir.path);
      final engine = AgiGameEngine(resourceLoader: loader);
      await engine.initializeGame();
      engine.changeRoom(2);
      await engine.tick();

      // Give magic sword (item 12)
      engine.memory.itemRooms[12] = 255;

      // Trigger Controller 24 (See Object)
      engine.controllerManager.triggerController(24, engine.memory);
      await engine.tick();

      expect(engine.isInventoryOpen, isTrue);
      expect(engine.memory.getFlag(13), isTrue);

      // Select magic sword (item 12)
      await engine.closeInventory(12);

      // In BC Logic 0: show.obj.v(12 + 149 = 161)
      expect(engine.inspectingObjectNumber, 161, reason: 'Object inspection modal should open for view 161');

      // Dismiss inspection modal
      await engine.closeObjectInspection();
      expect(engine.inspectingObjectNumber, isNull);
      expect(engine.interpreter.hasPendingInput, isFalse);

      engine.dispose();
    });
  });
}
