import 'dart:io';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Space Quest 2 Room 46 Shuttle Cockpit Monitor', () {
    test('clears playfield monitor text when draw.pic redraws cockpit view', () async {
      final path = Directory('reference_games/space-quest-2').existsSync()
          ? 'reference_games/space-quest-2'
          : '/Users/rtodd/src/flutter_agigame/reference_games/space-quest-2';
      if (!Directory(path).existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(path);
      final engine = AgiGameEngine(resourceLoader: loader);
      await engine.initializeGame();

      // Enter Room 46 (cockpit)
      engine.onNewRoom(46);
      await engine.tick();

      // Simulate looking at the monitor: Logic 46 displays text on rows 6..21
      engine.onDisplay(6, 7, "MINIMUM ALTITUDE");
      engine.onDisplay(8, 10, "Not Ready");
      engine.onDisplay(11, 7, "ATTITUDE SYSTEM");
      engine.onDisplay(13, 7, "Vertical Control");
      engine.onDisplay(15, 6, "1 Descend");
      engine.onDisplay(16, 8, "2 Ascend");
      engine.onDisplay(21, 8, "(Press a Key)");

      expect(engine.textScreenBuffer.getCell(6, 7).char, 'M');
      expect(engine.textScreenBuffer.getCell(11, 7).char, 'A');
      expect(engine.textScreenBuffer.getCell(21, 8).char, '(');

      // Simulate player pressing a key: Logic 46 executes draw.pic(46) and show.pic
      engine.onDrawPic(46);
      engine.onShowPic();

      // Verify all playfield rows 1..21 are completely cleared of the monitor text
      for (int r = 1; r <= 21; r++) {
        final rowText = List.generate(40, (c) => engine.textScreenBuffer.getCell(r, c).char).join('').trim();
        expect(rowText, isEmpty, reason: 'Playfield Row $r must be clean after draw.pic');
      }
    });
  });
}
