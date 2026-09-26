import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';
import 'package:flutter_agigame/sci/loader/resource_type.dart';
import 'package:flutter_agigame/sci/engine/sci_seg_manager.dart';
import 'package:flutter_agigame/sci/engine/sci_selectors.dart';
import 'package:flutter_agigame/sci/engine/sci_kernel.dart';
import 'package:flutter_agigame/sci/engine/sci_vm.dart';
import 'package:flutter_agigame/sci/engine/sci_game_engine.dart';
import 'package:flutter_agigame/sci/engine/sci_types.dart';

void main() {
  group('Class script dispose/reload (PQ2 station door)', () {
    final pq2Dir = Directory('reference_games/police-quest-2');

    SciVM buildVm(SciSegManager segManager, SciSelectors selectors,
        SciKernel kernel, SciVolumeManager volumeMgr) {
      return SciVM(
        segManager: segManager,
        kernel: kernel,
        selectors: selectors,
        volumeManager: volumeMgr,
      );
    }

    test('getClassAddress reloads a disposed class script instead of '
        'returning a dangling pointer', () {
      if (!pq2Dir.existsSync()) {
        markTestSkipped('PQ2 reference tree missing');
        return;
      }
      final volumeMgr = SciVolumeManager.fromDirectory(pq2Dir.path);
      final segManager = SciSegManager();
      final selectors = SciSelectors();
      final kernel = SciKernel();
      kernel.volumeManager = volumeMgr;
      kernel.selectors = selectors;
      segManager.volumeManager = volumeMgr;

      segManager
          .loadClassTable(volumeMgr.getResource(SciResourceType.vocab, 996));
      selectors
          .loadVocab997(volumeMgr.getResource(SciResourceType.vocab, 997));
      segManager.instantiateScript(0, volumeMgr);

      // Class 56 is the Door class (script 301), used by PQ2 room 1's
      // station door via `(Class_56 new:)`.
      expect(segManager.classScripts.length, greaterThan(56));
      final doorScriptNr = segManager.classScripts[56];
      var addr = segManager.getClassAddress(56, volumeManager: volumeMgr);
      expect(addr.isNull, isFalse);
      expect(segManager.getObject(addr), isNotNull);
      final firstSeg = addr.segment;

      // Game code disposes class scripts on room exit; the purge then frees
      // the segment when nothing references it.
      segManager.disposeScript(doorScriptNr);
      segManager.purgeUnmappedScripts();
      expect(segManager.getObject(addr), isNull,
          reason: 'disposed script segment must actually be freed');

      // The cached class address is now stale: it must be dropped and the
      // script reloaded on demand, never handed out dangling.
      addr = segManager.getClassAddress(56, volumeManager: volumeMgr);
      expect(addr.isNull, isFalse);
      expect(addr.segment, isNot(firstSeg));
      final doorClass = segManager.getObject(addr);
      expect(doorClass, isNotNull);
      expect(doorClass!.nameString, 'AutoDoor');

      // A repeated lookup while the script stays loaded returns the same
      // live address (cache still works when valid).
      final addrAgain =
          segManager.getClassAddress(56, volumeManager: volumeMgr);
      expect(addrAgain, addr);
    });

    test('PQ2 room 1 arrival builds a live station door', () {
      if (!pq2Dir.existsSync()) {
        markTestSkipped('PQ2 reference tree missing');
        return;
      }
      final engine = SciGameEngine(
        volumeManager: SciVolumeManager.fromDirectory(pq2Dir.path),
      );
      engine.initializeGame();
      try {
        engine.restartGame();
        for (var t = 0; t < 100; t++) {
          engine.tick();
          if (engine.segManager.globals[SciGlobals.roomNumber].toUint16() ==
              33) {
            break;
          }
        }
        engine.vm.sendSelector(
          engine.segManager.globals[SciGlobals.game],
          engine.selectors.findSelector('newRoom')!,
          [const SciReg.fromInt(1)],
        );
        for (var t = 0; t < 400; t++) {
          engine.tick();
          if (engine.segManager.globals[SciGlobals.roomNumber].toUint16() ==
              1) {
            break;
          }
        }
        expect(engine.segManager.globals[SciGlobals.roomNumber].toUint16(), 1);
        // Room init's `(Class_56 new:)` must resolve to the live AutoDoor
        // class (reloading script 301 if game code disposed it), not to a
        // freed segment. A stale pointer here means no door view on screen
        // and station entry is impossible.
        final seg = engine.segManager;
        final s1 = seg.loadedScripts[seg.scriptToSegment[1]!]!;
        final door = seg.getObject(s1.locals[1]);
        expect(door, isNotNull, reason: 'station door instance exists');
        expect(door!.nameString, contains('AutoDoor'));
        expect(door.getProp(seg, engine.selectors.findSelector('view')!), isNotNull);
      } finally {
        engine.dispose();
      }
    });

    test('new: on a reloaded class creates a live clone', () {
      if (!pq2Dir.existsSync()) {
        markTestSkipped('PQ2 reference tree missing');
        return;
      }
      final volumeMgr = SciVolumeManager.fromDirectory(pq2Dir.path);
      final segManager = SciSegManager();
      final selectors = SciSelectors();
      final kernel = SciKernel();
      kernel.volumeManager = volumeMgr;
      kernel.selectors = selectors;
      segManager.volumeManager = volumeMgr;

      segManager
          .loadClassTable(volumeMgr.getResource(SciResourceType.vocab, 996));
      selectors
          .loadVocab997(volumeMgr.getResource(SciResourceType.vocab, 997));
      segManager.instantiateScript(0, volumeMgr);
      final vm = buildVm(segManager, selectors, kernel, volumeMgr);

      final doorScriptNr = segManager.classScripts[56];
      segManager.getClassAddress(56, volumeManager: volumeMgr);
      segManager.disposeScript(doorScriptNr);
      segManager.purgeUnmappedScripts();

      // This mirrors room 1 init's `(= local1 (Class_56 new:))`: the class
      // opcode must reload the script, then `new` must produce an instance,
      // not echo back a dangling class pointer.
      final addr = segManager.getClassAddress(56, volumeManager: volumeMgr);
      final newSel = selectors.findSelector('new')!;
      vm.sendSelector(addr, newSel, []);
      final instance = segManager.getObject(vm.acc);
      expect(instance, isNotNull);
      expect(instance!.isClone, isTrue);
      expect(vm.acc, isNot(addr));
    });
  });
}
