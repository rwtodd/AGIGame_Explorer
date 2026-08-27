import 'dart:typed_data';
import 'package:flutter_agigame/domain/agi_view.dart';
import 'package:flutter_agigame/domain/animated_object.dart';
import 'package:flutter_agigame/domain/logic_script.dart';
import 'package:flutter_agigame/domain/picture.dart';
import 'package:flutter_agigame/domain/priority_buffer.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/logic/interpreter/agi_interpreter_delegate.dart';
import 'package:flutter_agigame/picture/picture_slicer.dart';
import 'package:flutter_test/flutter_test.dart';

AgiView testView({
  int viewNumber = 1,
  int width = 20,
  int height = 24,
  int numLoops = 1,
  int celsPerLoop = 2,
}) {
  final loops = <AgiViewLoop>[];
  for (var l = 0; l < numLoops; l++) {
    final cels = <AgiViewCel>[];
    for (var c = 0; c < celsPerLoop; c++) {
      cels.add(
        AgiViewCel.forward(
          width: width,
          height: height,
          transparentColor: 0,
          rawPixels: Uint8List(width * height)..fillRange(0, width * height, 15),
        ),
      );
    }
    loops.add(AgiViewLoop(loopNumber: l, cels: cels));
  }
  return AgiView(viewNumber: viewNumber, loops: loops);
}

void main() {
  group('Sierra SetCel border clip', () {
    test('clamps x when the new cel hangs off the right edge', () {
      final obj = AnimatedObject(number: 16);
      obj.updateCachedView(testView(width: 20, height: 24));
      obj.x = 153;
      obj.y = 144;

      obj.clipCelToScreen();

      expect(obj.x, 140, reason: '160 - 20, matching VIEW.C SetCel');
      expect(obj.y, 144);
      expect(obj.reposThisCycle, isTrue);
    });

    test('does not move an already on-screen cel', () {
      final obj = AnimatedObject(number: 0);
      obj.updateCachedView(testView(width: 7, height: 32));
      obj.x = 81;
      obj.y = 144;

      obj.clipCelToScreen();

      expect(obj.x, 81);
      expect(obj.y, 144);
      expect(obj.reposThisCycle, isFalse);
    });

    test('clamps y when the new cel hangs off the top, then honors horizon', () {
      final obj = AnimatedObject(number: 1);
      obj.updateCachedView(testView(width: 8, height: 40));
      obj.x = 10;
      obj.y = 5;

      obj.clipCelToScreen(horizon: 36);

      // y - height = 5-40 = -35 < -1 → y = 39, then 39 > horizon so stay 39.
      expect(obj.y, 39);
      expect(obj.reposThisCycle, isTrue);
    });

    test('nested horizon bump when height-1 is still at or above the horizon', () {
      final obj = AnimatedObject(number: 1);
      obj.updateCachedView(testView(width: 8, height: 10));
      obj.x = 10;
      obj.y = 5;

      obj.clipCelToScreen(horizon: 36);

      // y - height = -5 < -1 → y = 9, then 9 <= 36 → y = 37.
      expect(obj.y, 37);
      expect(obj.reposThisCycle, isTrue);
    });

    test('ignoreHorizon skips the nested horizon bump', () {
      final obj = AnimatedObject(number: 1);
      obj.updateCachedView(testView(width: 8, height: 10));
      obj.ignoreHorizon = true;
      obj.x = 10;
      obj.y = 5;

      obj.clipCelToScreen(horizon: 36);

      expect(obj.y, 9);
    });

    test('does nothing without a bound view', () {
      final obj = AnimatedObject(number: 0);
      obj.x = 153;
      obj.y = 144;

      obj.clipCelToScreen();

      expect(obj.x, 153);
      expect(obj.reposThisCycle, isFalse);
    });
  });

  group('SetCel clip through opcodes and cycling', () {
    late AgiGameEngine engine;

    setUp(() {
      engine = AgiGameEngine(speedHz: 20, randomSeed: 42);
      final priBuf = PriorityBuffer();
      engine.currentPic = AgiPic(
        visualPixels: Uint8List(160 * 168),
        priorityBuffer: priBuf,
        slices: PictureSlicer.slice(
          visualPixels: Uint8List(160 * 168),
          priorityBuffer: priBuf,
        ),
      );
    });

    tearDown(() {
      engine.dispose();
    });

    test('set.cel opcode clamps a 20px cel parked at x=153', () {
      final droid = engine.animatedObjects[16];
      droid.updateCachedView(testView(viewNumber: 46, width: 20, height: 24));
      droid.view = 46;
      droid.x = 153;
      droid.y = 144;

      engine.interpreter.loadRootScript(
        AgiLogicScript(
          bytecodes: Uint8List.fromList([
            0x2F, 16, 0, // set.cel(o16, 0)
            0x00,
          ]),
          messages: const [],
        ),
      );
      engine.interpreter.executeCycle();

      expect(droid.x, 140);
      expect(droid.reposThisCycle, isTrue);
    });

    test('set.view opcode clamps when switching to a wider view', () {
      final obj = engine.animatedObjects[1];
      obj.updateCachedView(testView(viewNumber: 1, width: 6, height: 12));
      obj.view = 1;
      obj.x = 155;
      obj.y = 100;

      // Delegate getView must return the wide view for set.view to bind it.
      final wide = testView(viewNumber: 46, width: 20, height: 24);
      engine.interpreter.delegate = _ViewDelegate(engine.interpreter.delegate, {46: wide});

      engine.interpreter.loadRootScript(
        AgiLogicScript(
          bytecodes: Uint8List.fromList([
            0x29, 1, 46, // set.view(o1, 46)
            0x00,
          ]),
          messages: const [],
        ),
      );
      engine.interpreter.executeCycle();

      expect(obj.view, 46);
      expect(obj.x, 140);
      expect(obj.reposThisCycle, isTrue);
    });

    test('cel cycling SetCel-clamps an off-screen droid and REPOS skips the next step', () {
      final droid = engine.animatedObjects[16];
      droid.updateCachedView(testView(viewNumber: 46, width: 20, height: 24, celsPerLoop: 2));
      droid.view = 46;
      droid.isAnimated = true;
      droid.isDrawn = true;
      droid.isUpdating = true;
      droid.isCycling = true;
      droid.ignoreObjects = true;
      droid.x = 164;
      droid.y = 139;
      droid.direction = 7; // west
      droid.stepSize = 1;
      droid.stepTime = 1;
      droid.stepTimer = 1;
      droid.cycleTime = 1;
      droid.cycleTimer = 1;
      droid.motionType = 0;

      engine.tick();
      expect(droid.x, 140, reason: 'AdvanceCel → SetCel clamps 164 to 160-20 and REPOS skips west step');

      engine.tick();
      expect(droid.x, 139, reason: 'next cycle walks west from the clamped cel');
    });
  });
}

class _ViewDelegate extends DefaultAgiInterpreterDelegate {
  _ViewDelegate(this._inner, this._views);

  final AgiInterpreterDelegate _inner;
  final Map<int, AgiView> _views;

  @override
  AgiView? getView(int viewNumber) => _views[viewNumber] ?? _inner.getView(viewNumber);

  @override
  int get horizon => _inner.horizon;
}
