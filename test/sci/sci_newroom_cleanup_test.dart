import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';
import 'package:flutter_agigame/sci/loader/resource_type.dart';
import 'package:flutter_agigame/sci/engine/sci_seg_manager.dart';
import 'package:flutter_agigame/sci/engine/sci_selectors.dart';
import 'package:flutter_agigame/sci/engine/sci_kernel.dart';
import 'package:flutter_agigame/sci/engine/sci_vm.dart';
import 'package:flutter_agigame/sci/engine/sci_types.dart';

void main() {
  group('SCI0 Room Change Cleanup Tests', () {
    final lsl2Dir = Directory('reference_games/lsl-2');

    test('actors from disposed scripts (e.g. AutoDoor in script 3) are cleanly deleted from cast on newRoom', () {
      if (!lsl2Dir.existsSync()) {
        markTestSkipped('LSL2 reference tree missing');
        return;
      }

      final volumeMgr = SciVolumeManager.fromDirectory(lsl2Dir.path);
      final segManager = SciSegManager();
      final selectors = SciSelectors();
      final kernel = SciKernel();
      kernel.volumeManager = volumeMgr;
      kernel.selectors = selectors;
      segManager.volumeManager = volumeMgr;

      final v996 = volumeMgr.getResource(SciResourceType.vocab, 996);
      segManager.loadClassTable(v996);
      final v997 = volumeMgr.getResource(SciResourceType.vocab, 997);
      selectors.loadVocab997(v997);

      final vm = SciVM(
        segManager: segManager,
        kernel: kernel,
        selectors: selectors,
        volumeManager: volumeMgr,
      );

      // Instantiate system scripts and script 3 (DOORS)
      segManager.instantiateScript(0, volumeMgr);
      final s994 = segManager.instantiateScript(994, volumeMgr);
      segManager.instantiateScript(998, volumeMgr);
      segManager.instantiateScript(999, volumeMgr);
      final s3 = segManager.instantiateScript(3, volumeMgr);

      // Set up cast from script 994
      final castObj = s994.getObject(0x0c)!;
      segManager.globals[5] = castObj.pos;
      final selAdd = selectors.findSelector('add')!;
      final selElements = selectors.findSelector('elements')!;
      final selEachElementDo = selectors.findSelector('eachElementDo')!;
      final selDispose = selectors.findSelector('dispose')!;
      final selDelete = selectors.findSelector('delete')!;

      // Initialize cast elements list
      vm.sendSelector(castObj.pos, selAdd, []);

      // Create AutoDoor clone (as in room 16, 18, 25)
      final autoDoorClass = s3.objects.values.firstWhere((o) => o.nameString == 'AutoDoor');
      final doorClone = segManager.cloneObject(autoDoorClass);

      // Add doorClone to cast
      vm.sendSelector(castObj.pos, selAdd, [doorClone.pos]);

      final elementsReg = castObj.getProp(segManager, selElements);
      final castList = segManager.lookupList(elementsReg)!;
      expect(segManager.listElements(castList), hasLength(1));

      // 1. Simulate RM000.SC calling (DisposeScript DOORS) before (super newRoom: n)
      segManager.disposeScript(3);

      // 2. Simulate Game::newRoom:
      // (cast eachElementDo: #dispose)
      vm.sendSelector(castObj.pos, selEachElementDo, [SciReg.fromInt(selDispose)]);
      // (cast eachElementDo: #delete)
      vm.sendSelector(castObj.pos, selEachElementDo, [SciReg.fromInt(selDelete)]);

      // The door actor must be completely removed from cast, preventing graphical ghosting
      expect(segManager.listElements(castList), isEmpty);
    });

    test('purgeUnmappedScripts drops a disposed script with no live pointers', () {
      if (!lsl2Dir.existsSync()) {
        markTestSkipped('LSL2 reference tree missing');
        return;
      }
      final volumeMgr = SciVolumeManager.fromDirectory(lsl2Dir.path);
      final segManager = SciSegManager();
      segManager.volumeManager = volumeMgr;
      segManager.loadClassTable(volumeMgr.getResource(SciResourceType.vocab, 996));
      final script = segManager.instantiateScript(3, volumeMgr);
      expect(segManager.loadedScripts.containsKey(script.segmentId), isTrue);

      segManager.disposeScript(3);
      expect(segManager.scriptToSegment.containsKey(3), isFalse);
      expect(segManager.loadedScripts.containsKey(script.segmentId), isTrue);

      expect(segManager.purgeUnmappedScripts(), 1);
      expect(segManager.loadedScripts.containsKey(script.segmentId), isFalse);
    });

    test('purge is lazy: no heap scan without a dispose, pending flag drains on sweep', () {
      if (!lsl2Dir.existsSync()) {
        markTestSkipped('LSL2 reference tree missing');
        return;
      }
      final volumeMgr = SciVolumeManager.fromDirectory(lsl2Dir.path);
      final segManager = SciSegManager();
      segManager.volumeManager = volumeMgr;
      segManager.loadClassTable(volumeMgr.getResource(SciResourceType.vocab, 996));
      final script = segManager.instantiateScript(3, volumeMgr);

      // Steady state: no dispose means no work, without scanning.
      expect(segManager.hasPendingPurge, isFalse);
      expect(segManager.purgeUnmappedScripts(), 0);

      segManager.disposeScript(3);
      expect(segManager.hasPendingPurge, isTrue);

      expect(segManager.purgeUnmappedScripts(), 1);
      expect(segManager.loadedScripts.containsKey(script.segmentId), isFalse);
      expect(segManager.hasPendingPurge, isFalse);

      // Drained flag means later sweeps stay cheap no-ops.
      expect(segManager.purgeUnmappedScripts(), 0);
    });
  });
}
