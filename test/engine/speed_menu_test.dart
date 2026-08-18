import 'dart:io';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AGI Menu Speed Options Integration', () {
    test('KQ3 speed menu items trigger controllers and update Variable 10 and engine speed', () async {
      final path = Directory('reference_games/kings-quest-3').existsSync()
          ? 'reference_games/kings-quest-3'
          : '/Users/rtodd/src/flutter_agigame/reference_games/kings-quest-3';
      final dir = Directory(path);
      if (!dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(path);
      final engine = AgiGameEngine(resourceLoader: loader);
      await engine.initializeGame();

      // 1. Select "Fastest" (Controller 34)
      engine.controllerManager.triggerController(34, engine.memory);
      await engine.tick();

      expect(engine.memory.getVar(10), 0, reason: 'Fastest should set Var 10 to 0');
      expect(engine.speedHz, 60.0, reason: 'Engine speed should be 60 Hz on Fastest');

      // 2. Select "Normal" (Controller 32)
      engine.controllerManager.triggerController(32, engine.memory);
      await engine.tick();

      expect(engine.memory.getVar(10), 2, reason: 'Normal should set Var 10 to 2');
      expect(engine.speedHz, 20.0, reason: 'Engine speed should be 20 Hz on Normal');

      // 3. Select "Slow" (Controller 31)
      engine.controllerManager.triggerController(31, engine.memory);
      await engine.tick();

      expect(engine.memory.getVar(10), 3, reason: 'Slow should set Var 10 to 3');
      expect(engine.speedHz, 10.0, reason: 'Engine speed should be 10 Hz on Slow');

      // 4. Select "Fast" (Controller 33)
      engine.controllerManager.triggerController(33, engine.memory);
      await engine.tick();

      expect(engine.memory.getVar(10), 1, reason: 'Fast should set Var 10 to 1');
      expect(engine.speedHz, 30.0, reason: 'Engine speed should be 30 Hz on Fast');

      // 5. Trigger "Change <F10>" (Controller 4) - cycles speed (1 -> 2)
      engine.controllerManager.triggerController(4, engine.memory);
      await engine.tick();

      expect(engine.memory.getVar(10), 2, reason: 'F10 Change should cycle Var 10 from 1 to 2');
      expect(engine.speedHz, 20.0);

      engine.dispose();
    });

    test('UI setSpeedHz updates Variable 10 to maintain two-way synchronization', () async {
      final engine = AgiGameEngine();
      await engine.initializeGame();

      expect(engine.memory.getVar(10), 2, reason: 'Default speed is Normal (v10=2)');
      expect(engine.speedHz, 20.0);

      engine.setSpeedHz(60.0);
      expect(engine.memory.getVar(10), 0, reason: '60 Hz maps to Fastest (v10=0)');

      engine.setSpeedHz(30.0);
      expect(engine.memory.getVar(10), 1, reason: '30 Hz maps to Fast (v10=1)');

      engine.setSpeedHz(20.0);
      expect(engine.memory.getVar(10), 2, reason: '20 Hz maps to Normal (v10=2)');

      engine.setSpeedHz(10.0);
      expect(engine.memory.getVar(10), 3, reason: '10 Hz maps to Slow (v10=3)');

      engine.dispose();
    });

    test('Selecting speed from menu via selectMenuItem activates speed controller', () async {
      final path = Directory('reference_games/kings-quest-3').existsSync()
          ? 'reference_games/kings-quest-3'
          : '/Users/rtodd/src/flutter_agigame/reference_games/kings-quest-3';
      final dir = Directory(path);
      if (!dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(path);
      final engine = AgiGameEngine(resourceLoader: loader);
      await engine.initializeGame();
      // Enable menu system
      engine.memory.setFlag(14);

      // Open menu
      engine.openMenu();
      expect(engine.isMenuOpen, isTrue);

      // Find "Speed" menu and select "Fastest" (Controller 34)
      engine.selectMenuItem(controllerSlot: 34);
      expect(engine.isMenuOpen, isFalse);

      await engine.tick();
      expect(engine.memory.getVar(10), 0);
      expect(engine.speedHz, 60.0);

      engine.dispose();
    });
  });
}
