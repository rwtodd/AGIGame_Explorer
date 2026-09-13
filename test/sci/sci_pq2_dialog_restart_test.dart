import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/sci/engine/sci_game_engine.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';
import 'package:flutter_agigame/ui/models/sci_window_overlay.dart';

void main() {
  group('PQ2 Room 33 Dialog & Restart Regression Tests', () {
    test('PQ2 Room 33 "hi" dialog closes on Enter key and restart works afterwards', () {
      final pq2Dir = Directory('reference_games/police-quest-2');
      if (!pq2Dir.existsSync()) {
        markTestSkipped('PQ2 reference tree missing');
        return;
      }
      final engine = SciGameEngine(
        volumeManager: SciVolumeManager.fromDirectory(pq2Dir.path),
      );
      engine.initializeGame();

      // First run: restart to skip intro and drive up to room 33
      engine.restartGame();

      for (var t = 0; t < 100; t++) {
        engine.tick();
        if (engine.segManager.globals[11].toUint16() == 33) break;
      }
      expect(engine.segManager.globals[11].toUint16(), 33, reason: 'Must reach room 33');

      // Type 'h', 'i', and Enter to talk to Keith
      engine.handleKeyPress(104, ascii: 104);
      for (var t = 0; t < 5; t++) {
        engine.tick();
      }

      engine.handleKeyPress(105, ascii: 105);
      for (var t = 0; t < 5; t++) {
        engine.tick();
      }

      engine.handleKeyPress(13, ascii: 13);
      for (var t = 0; t < 10; t++) {
        engine.tick();
      }

      // Keith's response dialog is displayed
      final keithText = engine.kernel.windowManager.windowStack
          .expand((w) => w.controls)
          .whereType<SciTextControl>()
          .map((c) => c.text)
          .join(' ');
      expect(keithText, contains('Hi.'), reason: 'Keith dialog should appear');

      // Press Enter to dismiss Keith's dialog
      engine.handleKeyPress(13, ascii: 13);
      for (var t = 0; t < 2; t++) {
        engine.tick();
      }

      // Dialog must close promptly without requiring mouse movements or multi-second timeouts
      expect(engine.kernel.windowManager.windowStack.isEmpty, isTrue,
          reason: 'Keith dialog should close immediately on Enter');

      // Restart game a second time; verify that typing in script 996 did not corrupt script bytecode or classes
      engine.restartGame();

      for (var t = 0; t < 50; t++) {
        engine.tick();
        if (engine.segManager.globals[11].toUint16() == 33) break;
      }

      // Car should drive smoothly to room 33 without triggering bogus off-screen warnings or hanging
      expect(engine.segManager.globals[11].toUint16(), 33,
          reason: 'Second restart must reach room 33 without freezing');

      engine.dispose();
    });
  });
}
