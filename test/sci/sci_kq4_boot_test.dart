import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/sci/engine/sci_game_engine.dart';
import 'package:flutter_agigame/sci/engine/sci_seg_manager.dart';
import 'package:flutter_agigame/sci/loader/resource_type.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';
import 'package:flutter_agigame/sci/script/sci_script_parser.dart';

void main() {
  group('King\'s Quest IV (Early SCI0) Boot Test', () {
    final kq4Dir = Directory('reference_games/kings-quest-4-sci');

    test('detects early SCI0 script header format', () {
      if (!kq4Dir.existsSync()) {
        markTestSkipped('KQ4 reference tree missing');
        return;
      }

      final volumeMgr = SciVolumeManager.fromDirectory(kq4Dir.path);
      expect(volumeMgr.isEarlySci0, isTrue);

      final script0Bytes = volumeMgr.getResource(SciResourceType.script, 0);
      expect(SciScriptParser.hasOldScriptHeader(script0Bytes), isTrue);

      // Verify PQ2 is recognized as standard (late) SCI0, not early SCI0
      final pq2Dir = Directory('reference_games/police-quest-2');
      if (pq2Dir.existsSync()) {
        final pq2VolumeMgr = SciVolumeManager.fromDirectory(pq2Dir.path);
        expect(pq2VolumeMgr.isEarlySci0, isFalse);
        final pq2Script0Bytes = pq2VolumeMgr.getResource(SciResourceType.script, 0);
        expect(SciScriptParser.hasOldScriptHeader(pq2Script0Bytes), isFalse);
      }
    });

    test('instantiates KQ4 Script 0 and parses exports and KQ4 game object', () {
      if (!kq4Dir.existsSync()) {
        markTestSkipped('KQ4 reference tree missing');
        return;
      }

      final volumeMgr = SciVolumeManager.fromDirectory(kq4Dir.path);
      final segMan = SciSegManager();
      final script0 = segMan.instantiateScript(0, volumeMgr);

      expect(script0.exports.isNotEmpty, isTrue);
      expect(script0.exports.length, 24);

      final gameObjOffset = script0.exports[0];
      final gameObj = script0.getObject(gameObjOffset);
      expect(gameObj, isNotNull);
      expect(gameObj!.nameString, 'KQ4');
      expect(gameObj.methodCount, 9);
      expect(script0.locals.length, greaterThan(0));
    });

    test('boots KQ4 through SciGameEngine without throwing RangeError', () {
      if (!kq4Dir.existsSync()) {
        markTestSkipped('KQ4 reference tree missing');
        return;
      }

      final volumeMgr = SciVolumeManager.fromDirectory(kq4Dir.path);
      final engine = SciGameEngine(volumeManager: volumeMgr);

      expect(() => engine.initializeGame(), returnsNormally);
      expect(engine.statusLine, 'KQ4');
      expect(engine.isPaused, isFalse);
      expect(engine.isRunning, isFalse);

      expect(engine.selectors.isEarlySci0, isTrue);
      expect(engine.segManager.isEarlySci0, isTrue);
      expect(engine.selectors.play, 84);
      expect(engine.selectors.init, 170);
      expect(engine.selectors.doit, 120);
      expect(engine.selectors.species, 0);
      expect(engine.selectors.superClass, 2);
      expect(engine.selectors.info, 4);
      expect(engine.selectors.name, 46);
      expect(engine.selectors.getSelectorName(84), 'play');
      expect(engine.selectors.getSelectorName(85), 'play');

      final script0 = engine.segManager.loadedScripts[1];
      final gObj = script0?.getObject(script0.exports[0]);
      expect(gObj, isNotNull);
      expect(gObj!.methods.containsKey(170), isTrue); // init:
      expect(gObj.methods.containsKey(120), isTrue); // doit:

      // (KQ4 play:) is inherited from Game
      final playMethod = gObj.lookupMethod(engine.segManager, 84);
      expect(playMethod, isNotNull);

      engine.start();
      expect(engine.isRunning, isTrue);
      expect(engine.vm.stepCounter, greaterThan(0));
      engine.dispose();
    });
  });
}
