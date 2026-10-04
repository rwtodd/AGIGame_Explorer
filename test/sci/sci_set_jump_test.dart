import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/sci/engine/sci_game_engine.dart';
import 'package:flutter_agigame/sci/engine/sci_kernel.dart';
import 'package:flutter_agigame/sci/engine/sci_seg_manager.dart';
import 'package:flutter_agigame/sci/engine/sci_selectors.dart';
import 'package:flutter_agigame/sci/engine/sci_types.dart';
import 'package:flutter_agigame/sci/engine/sci_vm.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';
import 'package:flutter_agigame/sci/script/sci_object.dart';

void main() {
  group('SetJump Kernel and JumpTo Tests', () {
    late SciKernel kernel;
    late SciSegManager segMan;
    late SciSelectors selectors;
    late SciVM vm;

    setUp(() {
      kernel = SciKernel();
      segMan = SciSegManager();
      selectors = SciSelectors();
      vm = SciVM(segManager: segMan, kernel: kernel, selectors: selectors);
    });

    test('SetJump is registered and not marked as stub', () {
      expect(kernel.isStubKernel(0x56), isFalse, reason: 'SetJump should be implemented');
      expect(kernel.getKernelName(0x56), 'SetJump');
    });

    test('stub calls are traced in recentCallLogs with [STUB] and recorded in stubHits', () {
      kernel.call(vm, 0x57, 0, []); // SetDebug (stub)
      kernel.call(vm, 0x57, 0, []);

      expect(kernel.recentCallLogs.any((l) => l.contains('SetDebug') && l.contains('[STUB]')), isTrue);
      expect(kernel.stubHitTotal, 2);
      expect(kernel.stubHitCounts[0x57], 2);
    });

    test('SetJump calculates discrete parabolic velocities and sets xStep and yStep properties', () {
      selectors.xStep = 10;
      selectors.yStep = 11;

      // Create a mock mover object with selectors.xStep and selectors.yStep
      final moverRef = const SciReg.pointer(SciSegManager.cloneSegmentId, 1);
      final moverObj = SciObject(
        pos: moverRef,
        variables: [
          const SciReg.fromInt(0),
          const SciReg.fromInt(0),
          const SciReg.fromInt(0),
          const SciReg.fromInt(0),
        ],
        baseVars: [0, 1, selectors.xStep, selectors.yStep],
      );
      segMan.clones[1] = moverObj;

      // Test 1: dx = 44, dy = 1, gy = 3
      kernel.call(vm, 0x56, 4, [
        moverRef,
        const SciReg.fromInt(44),
        const SciReg.fromInt(1),
        const SciReg.fromInt(3),
      ]);

      final vx1 = moverObj.getProp(segMan, selectors.xStep).toSint16();
      final vy1 = moverObj.getProp(segMan, selectors.yStep).toSint16();
      expect(vx1, equals(8));
      expect(vy1, equals(-8));

      // Test 2: dx = -44, dy = -1, gy = 3 (leftward)
      kernel.call(vm, 0x56, 4, [
        moverRef,
        const SciReg.fromInt(-44),
        const SciReg.fromInt(-1),
        const SciReg.fromInt(3),
      ]);

      final vx2 = moverObj.getProp(segMan, selectors.xStep).toSint16();
      final vy2 = moverObj.getProp(segMan, selectors.yStep).toSint16();
      expect(vx2, equals(-8));
      expect(vy2, equals(-8));

      // Test 3: dx = 40, dy = 90, gy = 3 (ocean spike jump)
      kernel.call(vm, 0x56, 4, [
        moverRef,
        const SciReg.fromInt(40),
        const SciReg.fromInt(90),
        const SciReg.fromInt(3),
      ]);

      final vx3 = moverObj.getProp(segMan, selectors.xStep).toSint16();
      final vy3 = moverObj.getProp(segMan, selectors.yStep).toSint16();
      expect(vx3, equals(4));
      expect(vy3, equals(-4));
    });

    test('Codename Iceman Room 3: Volleyball maintains bounded motion without runaway divergence', () {
      final dir = Directory('reference_games/codename-iceman');
      if (!dir.existsSync()) {
        markTestSkipped('Codename: Iceman reference directory missing');
        return;
      }

      final engine = SciGameEngine(
        volumeManager: SciVolumeManager.fromDirectory(dir.path),
      );
      engine.initializeGame();
      engine.start();

      for (var t = 0; t < 50; t++) {
        engine.tick();
      }
      if (engine.kernel.windowManager.windowStack.isNotEmpty) {
        engine.handleKeyPress(13, ascii: 13);
        for (var t = 0; t < 10; t++) {
          engine.tick();
        }
      }

      // Transition to room 3
      final newRoomSel = engine.selectors.findSelector('newRoom')!;
      final curRoomRef = engine.segManager.globals[1];
      engine.vm.sendSelector(curRoomRef, newRoomSel, [const SciReg.fromInt(3)]);

      for (var t = 0; t < 50; t++) {
        engine.tick();
      }

      // Run 150 cycles and verify Ball actor stays bounded on the court (y between 65 and 100)
      for (var cycle = 0; cycle < 150; cycle++) {
        engine.tick();
        for (final a in engine.actors) {
          if (a.viewNumber == 3 && a.loopNumber == 7) {
            expect(a.position.dy, lessThan(150),
                reason: 'Ball should not experience runaway divergence past y=150 on court');
            expect(a.position.dy, greaterThan(60),
                reason: 'Ball should remain within court playing area');
          }
        }
      }
    });
  });
}
