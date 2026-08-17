import 'dart:io';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('KQ2 Status Line & Help Screen Lifecycle', () {
    test('KQ2 title screen has status line disabled, gameplay enables it, and preserves it across room transitions', () {
      final dir = Directory('reference_games/kings-quest-2');
      if (!dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(dir.path);
      final engine = AgiGameEngine(resourceLoader: loader);
      engine.initializeGame();

      // Title screen (room 97)
      expect(engine.memory.getVar(0), 97);
      expect(engine.isStatusLineEnabled, isFalse, reason: 'Status line should not appear on title screen');

      // Start gameplay (transitions to room 1)
      engine.handleKeyPress(13);
      engine.tick();

      expect(engine.memory.getVar(0), 1);
      expect(engine.isStatusLineEnabled, isTrue, reason: 'Status line should appear in gameplay room 1');

      // Walk / transition to Room 2
      engine.changeRoom(2);
      engine.tick();

      expect(engine.memory.getVar(0), 2);
      expect(engine.isStatusLineEnabled, isTrue, reason: 'Status line must remain visible across room transitions');

      // Walk to Room 3
      engine.changeRoom(3);
      engine.tick();

      expect(engine.memory.getVar(0), 3);
      expect(engine.isStatusLineEnabled, isTrue, reason: 'Status line must remain visible in Room 3');

      engine.dispose();
    });

    test('KQ2 Help menu item displays text screen and dismisses cleanly on key press without freezing', () {
      final dir = Directory('reference_games/kings-quest-2');
      if (!dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(dir.path);
      final engine = AgiGameEngine(resourceLoader: loader);
      engine.initializeGame();

      // Start gameplay in Room 1
      engine.handleKeyPress(13);
      engine.tick();

      expect(engine.menuManager.isSubmitted, isTrue);

      // Open menu and select Help (menu 0, item 1, ctl 1)
      engine.openMenu(menuIndex: 0);
      engine.menuManager.setSelectedItemIndex(1);
      engine.selectMenuItem();

      // Tick executes Logic 0 -> call(95) -> Help screen
      engine.tick();

      // Verify we are on the text screen
      expect(engine.isTextScreen, isTrue, reason: 'Help screen should switch to text mode');
      expect(engine.lastError, isNull);

      // Verify help text content in textScreenBuffer
      final row2Text = StringBuffer();
      for (int c = 0; c < 40; c++) {
        row2Text.write(engine.textScreenBuffer.getCell(2, c).char);
      }
      expect(row2Text.toString(), contains("KING'S QUEST II"));

      // Multiple idle ticks should yield smoothly without locking up
      for (int i = 0; i < 10; i++) {
        engine.tick();
      }
      expect(engine.isTextScreen, isTrue);

      // Now press a key (e.g. Space / Enter / 13) to dismiss Help
      engine.handleKeyPress(13);
      engine.tick();

      // Verify text screen dismissed and back in graphics mode
      expect(engine.isTextScreen, isFalse, reason: 'Pressing a key should exit Help text screen');
      expect(engine.isStatusLineEnabled, isTrue, reason: 'Status line should be restored after exiting Help');

      engine.dispose();
    });
  });
}
