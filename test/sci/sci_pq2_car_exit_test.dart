import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/sci/engine/sci_game_engine.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';
import 'package:flutter_agigame/sci/picture/sci_pic.dart';

void main() {
  group('PQ2 Car Exit Transition', () {
    test('exiting car in room 33 transitions to room 1 and positions ego at (272, 142)', () {
      final pq2Dir = Directory('reference_games/police-quest-2');
      if (!pq2Dir.existsSync()) {
        markTestSkipped('Police Quest 2 reference game not found');
        return;
      }

      final engine = SciGameEngine(
        volumeManager: SciVolumeManager.fromDirectory(pq2Dir.path),
      );
      engine.initializeGame();
      engine.restartGame();

      // Advance until car interior (room 33) is reached
      for (var t = 0; t < 100; t++) {
        engine.tick();
        if (engine.segManager.globals[11].toUint16() == 33) {
          break;
        }
      }
      expect(engine.segManager.globals[11].toUint16(), equals(33));
      expect(engine.currentPic?.picNumber, equals(33));

      // Tick 20 more times in room 33
      for (var t = 0; t < 20; t++) {
        engine.tick();
      }

      // Verify that after room 33 addToPic execution, priority clipping protected
      // the car interior (priority 13) and Sonny (priority 12) from being overwritten
      // by lower-priority views (e.g. street at priority 1).
      final pic33 = engine.currentPic! as SciPic;
      // The right seat / headrest at (235, 100) must remain intact with priority 13 and brown color 6
      expect(pic33.priorityPixels[100 * 320 + 235], equals(13),
          reason: 'Headrest priority 13 must not be overwritten by street priority 1');
      expect(pic33.visualPixels[100 * 320 + 235], equals(6),
          reason: 'Headrest visual color 6 must not be overwritten by street');

      // Verify active slices for the 16-layer compositor
      expect(pic33.slices[0]?.hasVisiblePixels, isTrue, reason: 'Sky is in Slice 0');
      expect(pic33.slices[1]?.hasVisiblePixels, isTrue, reason: 'Street is in Slice 1');
      expect(pic33.slices[12]?.hasVisiblePixels, isTrue, reason: 'Sonny and mirror are in Slice 12');
      expect(pic33.slices[13]?.hasVisiblePixels, isTrue, reason: 'Car interior is in Slice 13');

      // Type "exit car\r"
      for (final ch in 'exit car\r'.codeUnits) {
        engine.handleKeyPress(ch, ascii: ch == 13 ? 13 : ch);
        for (var t = 0; t < 5; t++) {
          engine.tick();
        }
      }

      // Press Enter to dismiss "OK." dialog
      engine.handleKeyPress(13, ascii: 13);
      for (var t = 0; t < 5; t++) {
        engine.tick();
      }

      // Tick forward until room 1 is entered and the car exit script completes
      var reachedRoom1 = false;
      for (var t = 0; t < 50; t++) {
        engine.tick();
        final curRoom = engine.segManager.globals[11].toUint16();
        final prevRoom = engine.segManager.globals[12].toUint16();
        if (curRoom == 1 && prevRoom == 33) {
          reachedRoom1 = true;
          final ego = engine.segManager.getObject(engine.segManager.globals[0]);
          final ex = ego?.getProp(engine.segManager, engine.selectors.findSelector('x')!).toSint16();
          final ey = ego?.getProp(engine.segManager, engine.selectors.findSelector('y')!).toSint16();
          if (ex == 272 && ey == 142) {
            break;
          }
        }
      }

      expect(reachedRoom1, isTrue, reason: 'Failed to transition to room 1 from room 33');

      // Verify curRoom and prevRoom
      expect(engine.segManager.globals[11].toUint16(), equals(1));
      expect(engine.segManager.globals[12].toUint16(), equals(33));

      // Verify ourCar is deleted from cast
      final seg1 = engine.segManager.scriptToSegment[1];
      expect(seg1, isNotNull);
      final s1 = engine.segManager.loadedScripts[seg1!];
      final ourCar = s1?.objects[0x18a];
      expect(ourCar, isNotNull);

      final castObj = engine.segManager.getObject(engine.segManager.globals[5]);
      final castElementsReg = castObj?.getProp(engine.segManager, engine.selectors.findSelector('elements')!);
      final castList = castElementsReg != null ? engine.segManager.lookupList(castElementsReg) : null;
      final castElements = castList != null ? engine.segManager.listElements(castList) : [];
      expect(castElements.contains(ourCar!.pos), isFalse, reason: 'ourCar should be deleted from cast');

      // Verify Sonny (Ego) stepped out of the car at (272, 142)
      final ego = engine.segManager.getObject(engine.segManager.globals[0]);
      expect(ego, isNotNull);
      final egoX = ego!.getProp(engine.segManager, engine.selectors.findSelector('x')!).toSint16();
      final egoY = ego.getProp(engine.segManager, engine.selectors.findSelector('y')!).toSint16();
      expect(egoX, equals(272), reason: 'Ego should not be stuck at 0 on x-axis');
      expect(egoY, equals(142), reason: 'Ego should not be stuck at 0 on y-axis');
    });
  });
}
