import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/sci/engine/sci_kernel.dart';
import 'package:flutter_agigame/sci/engine/sci_seg_manager.dart';
import 'package:flutter_agigame/sci/engine/sci_selectors.dart';
import 'package:flutter_agigame/sci/engine/sci_types.dart';
import 'package:flutter_agigame/sci/engine/sci_vm.dart';
import 'package:flutter_agigame/sci/script/sci_object.dart';
import 'package:flutter_agigame/sci/script/sci_script.dart';
import 'package:flutter_agigame/sci/view/sci_view.dart';

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

    test('EmptyList is a predicate and does not wipe the list', () {
      final list = kernel.call(vm, 0x32, 0, []);
      expect(kernel.call(vm, 0x37, 1, [list]).toSint16(), 1);
      final node = kernel.call(vm, 0x34, 2, [const SciReg.fromInt(1), const SciReg.fromInt(1)]);
      kernel.call(vm, 0x3D, 2, [list, node]);
      expect(kernel.call(vm, 0x37, 1, [list]).toSint16(), 0);
      expect(kernel.call(vm, 0x35, 1, [list]), node);
    });

    test('AddAfter uses Sierra order (list, existing, new)', () {
      final list = kernel.call(vm, 0x32, 0, []);
      final a = kernel.call(vm, 0x34, 2, [const SciReg.fromInt(1), const SciReg.fromInt(1)]);
      final b = kernel.call(vm, 0x34, 2, [const SciReg.fromInt(2), const SciReg.fromInt(2)]);
      final c = kernel.call(vm, 0x34, 2, [const SciReg.fromInt(3), const SciReg.fromInt(3)]);
      kernel.call(vm, 0x3D, 2, [list, a]);
      kernel.call(vm, 0x3B, 3, [list, a, b]);
      kernel.call(vm, 0x3B, 3, [list, b, c]);
      expect(kernel.call(vm, 0x35, 1, [list]), a);
      expect(kernel.call(vm, 0x38, 1, [a]), b);
      expect(kernel.call(vm, 0x38, 1, [b]), c);
      expect(kernel.call(vm, 0x36, 1, [list]), c);
    });

    test('NumLoops and NumCels read view/loop from the object', () {
      final view = SciView(
        viewNumber: 5,
        loops: [
          const SciViewLoop(loopNumber: 0, cels: [
            SciViewCel(width: 8, height: 8, transparentColor: 0, rawPixels: null),
            SciViewCel(width: 8, height: 8, transparentColor: 0, rawPixels: null),
          ]),
          const SciViewLoop(loopNumber: 1, cels: [
            SciViewCel(width: 8, height: 8, transparentColor: 0, rawPixels: null),
          ]),
        ],
      );
      kernel.registerView(5, view);
      selectors.view = 6;
      selectors.loop = 7;
      final obj = SciObject(
        pos: const SciReg.pointer(SciSegManager.cloneSegmentId, 0x20),
        variables: List<SciReg>.generate(10, (i) => SciReg.nullReg),
        baseVars: List<int>.generate(10, (i) => i),
      );
      obj.variables[6] = const SciReg.fromInt(5);
      obj.variables[7] = const SciReg.fromInt(0);
      segMan.clones[0x20] = obj;
      final objAddr = obj.pos;
      expect(kernel.call(vm, 0x0D, 1, [objAddr]).toSint16(), 2);
      expect(kernel.call(vm, 0x0E, 1, [objAddr]).toSint16(), 2);
    });

    test('MemoryInfo reports a non-zero heap', () {
      expect(kernel.call(vm, 0x5C, 1, [const SciReg.fromInt(1)]).toUint16(), 0x7fea);
      expect(kernel.call(vm, 0x5C, 1, [const SciReg.fromInt(0)]).toUint16(), 0x7fea - 2);
    });

    test('string kernels read and write script bytes', () {
      final bytes = Uint8List.fromList([65, 66, 0, 88, 89, 0]);
      segMan.loadedScripts[1] = SciScript(scriptNumber: 1, segmentId: 1, bytes: bytes);
      final ab = const SciReg.pointer(1, 0);
      final xy = const SciReg.pointer(1, 3);
      expect(kernel.call(vm, 0x4A, 1, [ab]).toSint16(), 2);
      expect(kernel.call(vm, 0x49, 2, [ab, xy]).toSint16(), isNot(0));
      kernel.call(vm, 0x4B, 2, [ab, xy]);
      expect(kernel.call(vm, 0x4A, 1, [ab]).toSint16(), 2);
      expect(bytes[0], 88);
      expect(kernel.call(vm, 0x66, 2, [ab, const SciReg.fromInt(0)]).toSint16(), 88);
    });

    test('BaseSetter uses cel width not uninitialized nsLeft/nsRight', () {
      final view = SciView(
        viewNumber: 292,
        loops: [
          const SciViewLoop(loopNumber: 0, cels: [
            SciViewCel(width: 40, height: 20, transparentColor: 0, rawPixels: null),
          ]),
        ],
      );
      kernel.registerView(292, view);
      selectors.y = 4;
      selectors.x = 5;
      selectors.view = 6;
      selectors.loop = 7;
      selectors.cel = 8;
      selectors.nsLeft = 11;
      selectors.nsRight = 13;
      selectors.brTop = 20;
      selectors.brLeft = 21;
      selectors.brBottom = 22;
      selectors.brRight = 23;
      selectors.yStep = 24;
      final obj = SciObject(
        pos: const SciReg.pointer(SciSegManager.cloneSegmentId, 0x30),
        variables: List<SciReg>.generate(30, (i) => const SciReg.fromInt(0)),
        baseVars: List<int>.generate(30, (i) => i),
      );
      obj.variables[4] = const SciReg.fromInt(50); // y
      obj.variables[5] = const SciReg.fromInt(100); // x
      obj.variables[6] = const SciReg.fromInt(292);
      obj.variables[24] = const SciReg.fromInt(3); // yStep
      segMan.clones[0x30] = obj;

      kernel.call(vm, 0x4F, 1, [obj.pos]);
      expect(obj.variables[21].toSint16(), 80); // brLeft = 100 - 40/2
      expect(obj.variables[23].toSint16(), 120); // brRight
      expect(obj.variables[22].toSint16(), 51); // brBottom = y+1
      expect(obj.variables[20].toSint16(), 48); // brTop = 51-3
    });

    test('Wait records requested ticks and returns a delta', () {
      kernel.call(vm, 0x45, 1, [const SciReg.fromInt(0)]);
      expect(kernel.lastWaitTicks, 0);
      kernel.call(vm, 0x45, 1, [const SciReg.fromInt(6)]);
      expect(kernel.lastWaitTicks, 6);
    });

    test('keyboard events are posted as key-down not mouse-press', () {
      kernel.postKeyEvent(13);
      expect(kernel.eventQueue.single.type, SciEventType.keyDown);
      expect(kernel.eventQueue.single.message, 13);
      kernel.postDirectionEvent(1);
      expect(kernel.eventQueue.last.type, SciEventType.direction);
    });

    test('SetPort 6-arg updates the picture port origin', () {
      expect(kernel.picPortTop, 10);
      expect(kernel.picPortLeft, 0);
      kernel.call(vm, 0x15, 1, [const SciReg.fromInt(3)]);
      expect(kernel.currentPort, 3);
      expect(kernel.picPortTop, 10);
      kernel.call(vm, 0x15, 6, [
        const SciReg.fromInt(0),
        const SciReg.fromInt(0),
        const SciReg.fromInt(200),
        const SciReg.fromInt(320),
        const SciReg.fromInt(0),
        const SciReg.fromInt(0),
      ]);
      expect(kernel.picPortTop, 0);
      expect(kernel.picPortLeft, 0);
      kernel.call(vm, 0x15, 6, [
        const SciReg.fromInt(10),
        const SciReg.fromInt(0),
        const SciReg.fromInt(200),
        const SciReg.fromInt(320),
        const SciReg.fromInt(10),
        const SciReg.fromInt(0),
      ]);
      expect(kernel.picPortTop, 10);
    });

    test('Animate sprite y includes the picture port origin', () {
      final view = SciView(
        viewNumber: 1,
        loops: [
          const SciViewLoop(loopNumber: 0, cels: [
            SciViewCel(width: 16, height: 16, transparentColor: 0, rawPixels: null),
          ]),
        ],
      );
      kernel.registerView(1, view);
      final obj = SciObject(
        pos: const SciReg.pointer(SciSegManager.cloneSegmentId, 0x40),
        variables: List<SciReg>.generate(25, (i) => const SciReg.fromInt(0)),
        baseVars: List<int>.generate(25, (i) => i),
      );
      obj.variables[4] = const SciReg.fromInt(100); // y
      obj.variables[5] = const SciReg.fromInt(160); // x
      obj.variables[6] = const SciReg.fromInt(1); // view
      segMan.clones[0x40] = obj;

      final list = kernel.call(vm, 0x32, 0, []);
      final node = kernel.call(vm, 0x34, 2, [obj.pos, const SciReg.fromInt(1)]);
      kernel.call(vm, 0x3D, 2, [list, node]);

      // Gameplay port: actor y is port-local, sprite is in screen space.
      kernel.call(vm, 0x0B, 2, [list, const SciReg.fromInt(0)]);
      expect(kernel.currentSprites, isNotEmpty);
      expect(kernel.currentSprites.single.position.dy, 100 + 10 - 16 + 1);
      expect(kernel.currentSprites.single.position.dx, 160 - 8);
      expect(kernel.currentSprites.single.baselineY, 100);

      // Intro / hide-menu: SetPort 6-arg drops the 10px origin.
      kernel.call(vm, 0x15, 6, [
        const SciReg.fromInt(0),
        const SciReg.fromInt(0),
        const SciReg.fromInt(200),
        const SciReg.fromInt(320),
        const SciReg.fromInt(0),
        const SciReg.fromInt(0),
      ]);
      kernel.call(vm, 0x0B, 2, [list, const SciReg.fromInt(0)]);
      expect(kernel.currentSprites.single.position.dy, 100 - 16 + 1);
    });
  });
}
