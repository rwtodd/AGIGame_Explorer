import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/sci/engine/sci_kernel.dart';
import 'package:flutter_agigame/sci/engine/sci_seg_manager.dart';
import 'package:flutter_agigame/sci/engine/sci_selectors.dart';
import 'package:flutter_agigame/sci/engine/sci_types.dart';
import 'package:flutter_agigame/sci/engine/sci_vm.dart';
import 'package:flutter_agigame/sci/script/sci_object.dart';

void main() {
  group('SciKernel Tests', () {
    late SciSegManager segMan;
    late SciKernel kernel;
    late SciSelectors selectors;
    late SciVM vm;

    setUp(() {
      segMan = SciSegManager();
      kernel = SciKernel();
      selectors = SciSelectors();
      vm = SciVM(segManager: segMan, kernel: kernel, selectors: selectors);
    });

    test('Doubly-linked list kernel operations', () {
      // 1. NewList
      final list = kernel.call(vm, 0x32, 0, []);
      expect(list.isPointer, isTrue);
      expect(kernel.call(vm, 0x35, 1, [list]), SciReg.nullReg); // FirstNode is null

      // 2. NewNode & AddToFront
      final node1 = kernel.call(vm, 0x34, 2, [const SciReg.fromInt(100), const SciReg.fromInt(1)]);
      kernel.call(vm, 0x3C, 2, [list, node1]); // AddToFront
      expect(kernel.call(vm, 0x35, 1, [list]), node1); // FirstNode == node1
      expect(kernel.call(vm, 0x3A, 1, [node1]).toSint16(), 100); // NodeValue == 100

      // 3. AddToEnd
      final node2 = kernel.call(vm, 0x34, 2, [const SciReg.fromInt(200), const SciReg.fromInt(2)]);
      kernel.call(vm, 0x3D, 2, [list, node2]); // AddToEnd
      expect(kernel.call(vm, 0x36, 1, [list]), node2); // LastNode == node2

      // 4. NextNode / PrevNode navigation
      final next = kernel.call(vm, 0x38, 1, [node1]); // NextNode(node1)
      expect(next, node2);
      final prev = kernel.call(vm, 0x39, 1, [node2]); // PrevNode(node2)
      expect(prev, node1);

      // 5. FindKey & DeleteKey
      final found = kernel.call(vm, 0x3E, 2, [list, const SciReg.fromInt(2)]); // FindKey(2)
      expect(found, node2);
      kernel.call(vm, 0x3F, 2, [list, const SciReg.fromInt(2)]); // DeleteKey(2)
      expect(kernel.call(vm, 0x3E, 2, [list, const SciReg.fromInt(2)]), SciReg.nullReg);

      // 6. DisposeList
      kernel.call(vm, 0x33, 1, [list]);
    });

    test('Math kernel functions', () {
      // Abs
      expect(kernel.call(vm, 0x41, 1, [const SciReg.fromInt(-42)]).toSint16(), 42);
      expect(kernel.call(vm, 0x41, 1, [const SciReg.fromInt(42)]).toSint16(), 42);

      // Sqrt
      expect(kernel.call(vm, 0x42, 1, [const SciReg.fromInt(144)]).toSint16(), 12);

      // GetDistance (3-4-5 triangle)
      final dist = kernel.call(vm, 0x44, 4, [
        const SciReg.fromInt(0),
        const SciReg.fromInt(0),
        const SciReg.fromInt(3),
        const SciReg.fromInt(4),
      ]);
      expect(dist.toSint16(), 5);

      // GetAngle
      // East (dx > 0, dy = 0) -> 90 degrees
      final angleEast = kernel.call(vm, 0x43, 4, [
        const SciReg.fromInt(0),
        const SciReg.fromInt(0),
        const SciReg.fromInt(10),
        const SciReg.fromInt(0),
      ]);
      expect(angleEast.toSint16(), 90);

      // South (dx = 0, dy > 0) -> 180 degrees
      final angleSouth = kernel.call(vm, 0x43, 4, [
        const SciReg.fromInt(0),
        const SciReg.fromInt(0),
        const SciReg.fromInt(0),
        const SciReg.fromInt(10),
      ]);
      expect(angleSouth.toSint16(), 180);
    });

    test('Object inspection kernels', () {
      final obj = SciObject(
        pos: const SciReg.pointer(1, 0x10),
        variables: [const SciReg.fromInt(1), const SciReg.fromInt(0), const SciReg.fromInt(0)],
        methods: {87: 0},
      );
      segMan.clones[0x10] = obj;
      final objAddr = const SciReg.pointer(SciSegManager.cloneSegmentId, 0x10);

      // IsObject
      expect(kernel.call(vm, 0x06, 1, [objAddr]).toSint16(), 1);
      expect(kernel.call(vm, 0x06, 1, [const SciReg.fromInt(123)]).toSint16(), 0);

      // RespondsTo (selector 87)
      expect(kernel.call(vm, 0x07, 2, [objAddr, const SciReg.fromInt(87)]).toSint16(), 1);
      expect(kernel.call(vm, 0x07, 2, [objAddr, const SciReg.fromInt(99)]).toSint16(), 0);
    });

    test('Graphics stubs trigger registered callbacks', () {
      int? drawnPic;
      int? drawnStyle;
      SciReg? animatedCast;

      kernel.onDrawPic = (pic, style) {
        drawnPic = pic;
        drawnStyle = style;
      };

      kernel.onAnimate = (cast) {
        animatedCast = cast;
      };

      kernel.call(vm, 0x08, 2, [const SciReg.fromInt(15), const SciReg.fromInt(100)]);
      expect(drawnPic, 15);
      expect(drawnStyle, 100);

      final castList = const SciReg.pointer(SciSegManager.listSegmentId, 1);
      kernel.call(vm, 0x0B, 1, [castList]);
      expect(animatedCast, castList);
    });
  });
}
