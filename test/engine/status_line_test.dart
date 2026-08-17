import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AgiGameEngine Status Line & Text Buffer Synchronization', () {
    late AgiGameEngine engine;

    setUp(() {
      engine = AgiGameEngine();
      engine.initializeGame();
      engine.onStatusLine(true);
    });

    tearDown(() {
      engine.dispose();
    });

    test('initializes with authentic status line on row 0', () {
      expect(engine.isStatusLineEnabled, isTrue);
      expect(engine.statusRow, 0);

      // Verify row 0 cells have white background (15)
      for (int c = 0; c < 40; c++) {
        expect(engine.textScreenBuffer.getCell(0, c).bg, 15);
      }

      // Check Score text at column 1
      final scoreCell = engine.textScreenBuffer.getCell(0, 1);
      expect(scoreCell.char, 'S');
      expect(scoreCell.fg, 0); // Black text

      // Check Sound text at column 30
      final soundCell = engine.textScreenBuffer.getCell(0, 30);
      expect(soundCell.char, 'S');
      expect(soundCell.fg, 0);
    });

    test('updates status line when score changes', () {
      engine.memory.setVar(3, 42); // Score = 42
      engine.memory.setVar(7, 210); // Max score = 210
      engine.tick();

      // Read characters from column 1..18
      final bufferText = StringBuffer();
      for (int c = 1; c < 20; c++) {
        bufferText.write(engine.textScreenBuffer.getCell(0, c).char);
      }

      expect(bufferText.toString(), startsWith('Score: 42 of 210'));
    });

    test('updates sound on/off indicator when sound mode changes', () {
      engine.setSoundMode(AgiSoundMode.off);
      engine.tick();

      final soundOffText = StringBuffer();
      for (int c = 30; c < 40; c++) {
        soundOffText.write(engine.textScreenBuffer.getCell(0, c).char);
      }
      expect(soundOffText.toString(), startsWith('Sound:off'));

      engine.setSoundMode(AgiSoundMode.pcJr);
      engine.tick();

      final soundOnText = StringBuffer();
      for (int c = 30; c < 40; c++) {
        soundOnText.write(engine.textScreenBuffer.getCell(0, c).char);
      }
      expect(soundOnText.toString(), startsWith('Sound:on'));
    });

    test('status.line.off and status.line.on toggles status line visibility', () {
      engine.onStatusLine(false);
      expect(engine.isStatusLineEnabled, isFalse);

      // Verify row 0 is cleared to black
      for (int c = 0; c < 40; c++) {
        expect(engine.textScreenBuffer.getCell(0, c).bg, 0);
      }

      engine.onStatusLine(true);
      expect(engine.isStatusLineEnabled, isTrue);

      // Verify row 0 is restored to white
      for (int c = 0; c < 40; c++) {
        expect(engine.textScreenBuffer.getCell(0, c).bg, 15);
      }
    });

    test('preserves KQ3 clock and custom display text on row 0 across idle ticks', () {
      // KQ3 displays clock text at row 0, column 18
      engine.onDisplay(0, 18, '12:34 AM');

      // Verify text was written
      final clockText = StringBuffer();
      for (int c = 18; c < 26; c++) {
        clockText.write(engine.textScreenBuffer.getCell(0, c).char);
      }
      expect(clockText.toString(), '12:34 AM');

      // Run multiple idle cycles (where score and sound haven't changed)
      for (int i = 0; i < 20; i++) {
        engine.tick();
      }

      // Verify clock on row 0 was NOT wiped or overwritten
      final clockAfterTicks = StringBuffer();
      for (int c = 18; c < 26; c++) {
        clockAfterTicks.write(engine.textScreenBuffer.getCell(0, c).char);
      }
      expect(clockAfterTicks.toString(), '12:34 AM');
    });
  });
}
