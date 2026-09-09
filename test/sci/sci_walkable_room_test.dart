import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/sci/engine/sci_kernel.dart';
import 'package:flutter_agigame/sci/engine/sci_seg_manager.dart';
import 'package:flutter_agigame/sci/engine/sci_selectors.dart';
import 'package:flutter_agigame/sci/engine/sci_vm.dart';
import 'package:flutter_agigame/sci/loader/resource_type.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';

void main() {
  group('SCI Walkable Room and Animate Tests', () {
    test('Inspects PQ2 Game.play and executes until Animate', () {
      final pq2Dir = Directory('reference_games/police-quest-2');
      if (!pq2Dir.existsSync()) {
        markTestSkipped('PQ2 reference tree missing');
        return;
      }

      final volumeMgr = SciVolumeManager.fromDirectory(pq2Dir.path);
      final segMan = SciSegManager();
      final kernel = SciKernel();
      final selectors = SciSelectors();

      final vocab996Bytes = volumeMgr.getResource(SciResourceType.vocab, 996);
      segMan.loadClassTable(vocab996Bytes);

      final vocab997Bytes = volumeMgr.getResource(SciResourceType.vocab, 997);
      selectors.loadVocab997(vocab997Bytes);

      final vm = SciVM(
        segManager: segMan,
        kernel: kernel,
        selectors: selectors,
        volumeManager: volumeMgr,
      );

      final script0 = segMan.instantiateScript(0, volumeMgr);
      final gameObjOffset = script0.exports[0];
      final gameObj = script0.getObject(gameObjOffset)!;

      int animateCalls = 0;
      int drawPicCalls = 0;

      final kernelLog = <String>[];

      vm.addObserver(
        SciVmBaseObserver(
          onKernel: (id, name, argc, argv, res) {
            kernelLog.add('$name (argc=$argc, argv=$argv)');
            if (name == 'DrawPic') {
              drawPicCalls++;
            }
            if (name == 'Animate') {
              animateCalls++;
              if (animateCalls >= 5) {
                vm.abortScriptProcessing = true;
              }
            }
          },
        ),
      );

      // Execute Game.play
      vm.sendSelector(gameObj.pos, selectors.play, []);

      expect(animateCalls, greaterThanOrEqualTo(1));
      expect(drawPicCalls, greaterThanOrEqualTo(1));
      expect(kernel.currentPic, isNotNull);
      expect(kernel.currentSprites, isNotEmpty);

      // Check first sprite (Sonny Bonds)
      final sonny = kernel.currentSprites.first;
      expect(sonny.viewNumber, isNonNegative);
      expect(sonny.baselineY, greaterThan(0));
    });
  });
}
