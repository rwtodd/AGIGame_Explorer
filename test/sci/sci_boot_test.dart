import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/sci/engine/sci_kernel.dart';
import 'package:flutter_agigame/sci/engine/sci_seg_manager.dart';
import 'package:flutter_agigame/sci/engine/sci_selectors.dart';
import 'package:flutter_agigame/sci/engine/sci_vm.dart';
import 'package:flutter_agigame/sci/loader/resource_type.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';

void main() {
  group('Police Quest 2 End-to-End Boot Test', () {
    test('Boots PQ2 and executes Game.play', () {
      final pq2Dir = Directory('reference_games/police-quest-2');
      if (!pq2Dir.existsSync()) {
        return; // Skip if reference game is not present
      }

      final volumeMgr = SciVolumeManager.fromDirectory(pq2Dir.path);
      final segMan = SciSegManager();
      final kernel = SciKernel();
      final selectors = SciSelectors();

      // Load Vocab 996 (class table)
      final vocab996Bytes = volumeMgr.getResource(SciResourceType.vocab, 996);
      segMan.loadClassTable(vocab996Bytes);

      // Load Vocab 997 (selectors)
      final vocab997Bytes = volumeMgr.getResource(SciResourceType.vocab, 997);
      selectors.loadVocab997(vocab997Bytes);

      final vm = SciVM(
        segManager: segMan,
        kernel: kernel,
        selectors: selectors,
        volumeManager: volumeMgr,
      );

      // Instantiate Script 0
      final script0 = segMan.instantiateScript(0, volumeMgr);
      expect(script0.exports.isNotEmpty, isTrue);

      final gameObjOffset = script0.exports[0];
      final gameObj = script0.getObject(gameObjOffset);
      expect(gameObj, isNotNull);
      expect(gameObj!.nameString, 'PQ');

      // Track pic drawn
      int? picDrawn;
      kernel.onDrawPic = (picNum, style) {
        picDrawn = picNum;
        vm.abortScriptProcessing = true;
      };

      // Track kernel calls
      final calledKernels = <String>{};

      vm.addObserver(
        SciVmBaseObserver(
          onKernel: (kernelId, name, argc, argv, result) {
            calledKernels.add(name);
          },
          onInstruction: (vm, frame, instr) {
            if (vm.stepCounter >= 100000) {
              vm.abortScriptProcessing = true;
            }
          },
        ),
      );

      // Call (PQ play:)
      expect(selectors.play, isNonNegative);
      vm.sendSelector(gameObj.pos, selectors.play, []);

      // Verify VM ran instructions and made progress
      expect(vm.stepCounter, greaterThan(1000));
      expect(segMan.loadedScripts.length, greaterThanOrEqualTo(5));
      expect(calledKernels, contains('NewList'));
      expect(calledKernels, contains('AddToEnd'));
      expect(calledKernels, contains('Animate'));
      expect(calledKernels, contains('GetEvent'));
      if (picDrawn != null) {
        expect(picDrawn, isNonNegative);
      }
    });
  });
}
