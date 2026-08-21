import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_agigame/domain/agi_view.dart';
import 'package:flutter_agigame/domain/animated_object.dart';
import 'package:flutter_agigame/domain/logic_script.dart';
import 'package:flutter_agigame/domain/picture.dart';
import 'package:flutter_agigame/domain/priority_buffer.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/engine/motion/agi_motion.dart';
import 'package:flutter_agigame/picture/picture_slicer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Helper to create a dummy test view with [numLoops] loops and [celsPerLoop] cels each.
AgiView createTestView({
  int viewNumber = 0,
  int numLoops = 4,
  int celsPerLoop = 3,
  int width = 8,
  int height = 12,
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
  group('AgiMotion tables', () {
    test('direction deltas map to correct (dx, dy)', () {
      expect(AgiMotion.directionDeltas[0], equals(const math.Point(0, 0)));
      expect(AgiMotion.directionDeltas[1], equals(const math.Point(0, -1)));
      expect(AgiMotion.directionDeltas[2], equals(const math.Point(1, -1)));
      expect(AgiMotion.directionDeltas[3], equals(const math.Point(1, 0)));
      expect(AgiMotion.directionDeltas[4], equals(const math.Point(1, 1)));
      expect(AgiMotion.directionDeltas[5], equals(const math.Point(0, 1)));
      expect(AgiMotion.directionDeltas[6], equals(const math.Point(-1, 1)));
      expect(AgiMotion.directionDeltas[7], equals(const math.Point(-1, 0)));
      expect(AgiMotion.directionDeltas[8], equals(const math.Point(-1, -1)));
    });
  });

  group('AgiGameEngine motion', () {
    late PriorityBuffer priorityBuffer;
    late AgiGameEngine engine;
    late AgiView testView4Loops;
    late AgiView testView2Loops;

    setUp(() {
      priorityBuffer = PriorityBuffer();
      testView4Loops = createTestView(viewNumber: 0, numLoops: 4, celsPerLoop: 3);
      testView2Loops = createTestView(viewNumber: 1, numLoops: 2, celsPerLoop: 4);

      engine = AgiGameEngine(speedHz: 20, randomSeed: 42);
      engine.currentPic = AgiPic(
        visualPixels: Uint8List(160 * 168),
        priorityBuffer: priorityBuffer,
        slices: PictureSlicer.slice(
          visualPixels: Uint8List(160 * 168),
          priorityBuffer: priorityBuffer,
        ),
      );
    });

    tearDown(() {
      engine.dispose();
    });

    void bindView(AnimatedObject obj, AgiView view) {
      obj.view = view.viewNumber;
      obj.updateCachedView(view);
    }

    void face(AnimatedObject obj, int direction) {
      obj.direction = direction;
      if (obj.number == 0) {
        engine.memory.setVar(6, direction);
      }
    }

    group('Direction Deltas & Normal Motion', () {
      test('normal motion advances position by stepSize every stepTime ticks', () {
        final ego = engine.ego;
        ego.isAnimated = true;
        ego.isDrawn = true;
        ego.x = 50;
        ego.y = 80;
        ego.stepSize = 2;
        ego.stepTime = 2;
        ego.stepTimer = 2;
        face(ego, 3);

        engine.tick();
        expect(ego.x, equals(50));
        expect(ego.y, equals(80));

        engine.tick();
        expect(ego.x, equals(52));
        expect(ego.y, equals(80));
      });

      test('normal motion stops when encountering obstacle and clears direction', () {
        final ego = engine.ego;
        bindView(ego, testView4Loops);
        ego.isAnimated = true;
        ego.isDrawn = true;
        ego.x = 40;
        ego.y = 80;
        ego.stepSize = 2;
        ego.stepTime = 1;
        ego.stepTimer = 1;
        face(ego, 3);

        // Cel width 8, so x=44 occupies 44..51; x=46 would cover the wall at 52.
        for (var x = 52; x <= 60; x++) {
          priorityBuffer.setPriorityAt(x, 80, 0);
        }

        engine.tick();
        expect(ego.x, equals(42));
        engine.tick();
        expect(ego.x, equals(44));
        engine.tick();

        expect(ego.x, equals(44));
        expect(ego.direction, equals(0));
        expect(engine.memory.getVar(6), equals(0));
      });
    });

    group('Automatic Loop Selection', () {
      test('4-loop views map directions to proper loops', () {
        final ego = engine.ego;
        bindView(ego, testView4Loops);
        ego.isAnimated = true;
        ego.isDrawn = true;
        ego.fixedLoop = false;
        ego.x = 50;
        ego.y = 80;
        ego.stepTime = 1;
        ego.stepTimer = 1;

        face(ego, 3);
        engine.tick();
        expect(ego.loop, equals(0));

        face(ego, 7);
        engine.tick();
        expect(ego.loop, equals(1));

        face(ego, 5);
        engine.tick();
        expect(ego.loop, equals(2));

        face(ego, 1);
        engine.tick();
        expect(ego.loop, equals(3));
      });

      test('2-loop views map East/West and retain loop on North/South', () {
        final npc = engine.animatedObjects[1];
        bindView(npc, testView2Loops);
        npc.isAnimated = true;
        npc.isDrawn = true;
        npc.ignoreObjects = true;
        npc.fixedLoop = false;
        npc.x = 50;
        npc.y = 80;
        npc.stepTime = 1;
        npc.stepTimer = 1;

        npc.direction = 3;
        engine.tick();
        expect(npc.loop, equals(0));

        npc.direction = 5;
        engine.tick();
        expect(npc.loop, equals(0));

        npc.direction = 7;
        engine.tick();
        expect(npc.loop, equals(1));

        npc.direction = 1;
        engine.tick();
        expect(npc.loop, equals(1));
      });

      test('fixedLoop retains loop regardless of movement direction', () {
        final ego = engine.ego;
        bindView(ego, testView4Loops);
        ego.isAnimated = true;
        ego.isDrawn = true;
        ego.loop = 2;
        ego.fixedLoop = true;
        ego.x = 50;
        ego.y = 80;
        face(ego, 3);

        engine.tick();
        expect(ego.loop, equals(2));
      });
    });

    group('Cel Animation Cycling', () {
      test('normal cycling mode cycles forward: 0 -> 1 -> 2 -> 0', () {
        final ego = engine.ego;
        bindView(ego, testView4Loops);
        ego.isAnimated = true;
        ego.isDrawn = true;
        ego.loop = 0;
        ego.cel = 0;
        ego.cycleMode = 0;
        ego.cycleTime = 1;
        ego.cycleTimer = 1;
        ego.direction = 0;
        engine.memory.setVar(6, 0);

        engine.tick();
        expect(ego.cel, equals(1));

        engine.tick();
        expect(ego.cel, equals(2));

        engine.tick();
        expect(ego.cel, equals(0));
      });

      test('reverse cycling mode cycles backward: 2 -> 1 -> 0 -> 2', () {
        final ego = engine.ego;
        bindView(ego, testView4Loops);
        ego.isAnimated = true;
        ego.isDrawn = true;
        ego.loop = 0;
        ego.cel = 2;
        ego.cycleMode = 1;
        ego.cycleTime = 1;
        ego.cycleTimer = 1;
        ego.direction = 0;
        engine.memory.setVar(6, 0);

        engine.tick();
        expect(ego.cel, equals(1));

        engine.tick();
        expect(ego.cel, equals(0));

        engine.tick();
        expect(ego.cel, equals(2));
      });

      test('end_of_loop cycles forward to last cel, stops cycling, and sets flag', () {
        final ego = engine.ego;
        bindView(ego, testView4Loops);
        ego.isAnimated = true;
        ego.isDrawn = true;
        ego.loop = 0;
        ego.cel = 0;
        ego.cycleMode = 2;
        ego.endOfLoopFlag = 40;
        ego.cycleTime = 1;
        ego.cycleTimer = 1;
        ego.direction = 0;
        engine.memory.setVar(6, 0);

        engine.tick();
        expect(ego.cel, equals(1));
        expect(ego.isCycling, isTrue);
        expect(engine.memory.getFlag(40), isFalse);

        engine.tick();
        expect(ego.cel, equals(2));
        expect(ego.isCycling, isFalse);
        expect(engine.memory.getFlag(40), isTrue);

        engine.tick();
        expect(ego.cel, equals(2));
      });

      test('reverse_loop cycles backward to cel 0, stops cycling, and sets flag', () {
        final ego = engine.ego;
        bindView(ego, testView4Loops);
        ego.isAnimated = true;
        ego.isDrawn = true;
        ego.loop = 0;
        ego.cel = 2;
        ego.cycleMode = 3;
        ego.endOfLoopFlag = 41;
        ego.cycleTime = 1;
        ego.cycleTimer = 1;
        ego.direction = 0;
        engine.memory.setVar(6, 0);

        engine.tick();
        expect(ego.cel, equals(1));
        expect(ego.isCycling, isTrue);
        expect(engine.memory.getFlag(41), isFalse);

        engine.tick();
        expect(ego.cel, equals(0));
        expect(ego.isCycling, isFalse);
        expect(engine.memory.getFlag(41), isTrue);

        engine.tick();
        expect(ego.cel, equals(0));
      });

      test('cycleTime throttles animation cycling', () {
        final ego = engine.ego;
        bindView(ego, testView4Loops);
        ego.isAnimated = true;
        ego.isDrawn = true;
        ego.loop = 0;
        ego.cel = 0;
        ego.cycleMode = 0;
        ego.cycleTime = 3;
        ego.cycleTimer = 3;
        ego.direction = 0;
        engine.memory.setVar(6, 0);

        engine.tick();
        expect(ego.cel, equals(0));

        engine.tick();
        expect(ego.cel, equals(0));

        engine.tick();
        expect(ego.cel, equals(1));
      });
    });

    group('moveObj Motion Mode', () {
      test('moves towards target, updates loop, snaps when reached, and sets targetFlag', () {
        final npc = engine.animatedObjects[1];
        bindView(npc, testView4Loops);
        npc.isAnimated = true;
        npc.isDrawn = true;
        npc.ignoreObjects = true;
        npc.x = 20;
        npc.y = 50;
        npc.stepTime = 1;
        npc.stepTimer = 1;
        npc.motionType = 3;
        npc.targetX = 26;
        npc.targetY = 50;
        npc.stepSize = 2;
        npc.stepDistance = 2;
        npc.targetFlag = 50;

        engine.tick();
        expect(npc.x, equals(22));
        expect(npc.y, equals(50));
        expect(npc.loop, equals(0));
        expect(npc.direction, equals(3));
        expect(engine.memory.getFlag(50), isFalse);

        engine.tick();
        expect(npc.x, equals(24));

        engine.tick();
        expect(npc.x, equals(26));
        expect(npc.y, equals(50));
        expect(npc.direction, equals(0));
        expect(npc.motionType, equals(0));
        expect(engine.memory.getFlag(50), isTrue);
      });

      test('move.obj restores the original stepSize when the move finishes', () {
        final ego = engine.ego;
        ego.isAnimated = true;
        ego.isDrawn = true;
        ego.isUpdating = true;
        ego.ignoreObjects = true;
        ego.x = 10;
        ego.y = 80;
        ego.stepSize = 1;
        ego.stepTime = 1;
        ego.stepTimer = 1;

        // move.obj(%o0, 18, 80, 4, %f15) then return
        engine.interpreter.loadRootScript(
          AgiLogicScript(
            bytecodes: Uint8List.fromList([81, 0, 18, 80, 4, 15, 0]),
            messages: const [],
          ),
          scriptNumber: 0,
        );
        engine.interpreter.executeCycle();

        expect(ego.motionType, 3);
        expect(ego.stepSize, 4);
        expect(ego.oldStepSize, 1);
        expect(engine.isUserControl, isFalse);

        engine.interpreter.loadRootScript(
          AgiLogicScript(bytecodes: Uint8List.fromList([0]), messages: const []),
          scriptNumber: 0,
        );

        engine.tick();
        expect(ego.x, 14);
        expect(ego.stepSize, 4);

        engine.tick();
        expect(ego.x, 18);
        expect(ego.motionType, 0);
        expect(ego.stepSize, 1, reason: 'Sierra EndMoveObj restores oldStep');
        expect(engine.isUserControl, isTrue);
      });
    });

    group('followEgo Motion Mode', () {
      test('NPC moves towards Ego and stops with flag when reached', () {
        final ego = engine.ego;
        bindView(ego, testView4Loops);
        ego.isAnimated = true;
        ego.isDrawn = true;
        ego.x = 50;
        ego.y = 80;
        ego.ignoreObjects = true;

        final npc = engine.animatedObjects[1];
        bindView(npc, testView4Loops);
        npc.isAnimated = true;
        npc.isDrawn = true;
        npc.x = 44;
        npc.y = 80;
        npc.stepTime = 1;
        npc.stepTimer = 1;
        npc.motionType = 2;
        npc.stepDistance = 2;
        npc.stepSize = 2;
        npc.targetFlag = 60;

        // Width 8: centers start 6 pixels apart; Sierra arrives when |dx| < endDist.
        engine.tick();
        expect(npc.x, equals(46));
        expect(npc.direction, equals(3));
        expect(engine.memory.getFlag(60), isFalse);

        engine.tick();
        expect(npc.x, equals(48));
        expect(engine.memory.getFlag(60), isFalse);

        engine.tick();
        expect(npc.x, equals(50));
        expect(engine.memory.getFlag(60), isFalse);

        engine.tick();
        expect(npc.direction, equals(0));
        expect(npc.motionType, equals(0));
        expect(engine.memory.getFlag(60), isTrue);
      });

      test('follow.ego uses baseline centers so a wide droid to the east is not an instant catch', () {
        final ego = engine.ego;
        bindView(ego, createTestView(viewNumber: 0, numLoops: 4, celsPerLoop: 1, width: 6, height: 12));
        ego.isAnimated = true;
        ego.isDrawn = true;
        ego.x = 50;
        ego.y = 100;
        ego.ignoreObjects = true;

        final droid = engine.animatedObjects[16];
        bindView(droid, createTestView(viewNumber: 46, numLoops: 1, celsPerLoop: 1, width: 16, height: 12));
        droid.isAnimated = true;
        droid.isDrawn = true;
        droid.x = 58;
        droid.y = 100;
        droid.stepTime = 1;
        droid.stepTimer = 1;
        droid.motionType = 2;
        droid.stepDistance = 10;
        droid.stepSize = 1;
        droid.targetFlag = 235;
        engine.memory.resetFlag(235);

        // Left edges are 8 apart (would look "caught" with endDist 10),
        // but centers are 13 apart (Sierra: not caught).
        engine.tick();
        expect(engine.memory.getFlag(235), isFalse);
        expect(droid.motionType, 2);
      });

      test('follow.ego does not complete just because the NPC is past the right screen edge', () {
        // SQ1 spider droid: spawned near the east edge, FindPosn left it at
        // x=164 (fully off-screen). Sierra MOVEOBJS.C only EndMoveObj for
        // move.obj on a border — follow.ego must keep chasing.
        final ego = engine.ego;
        bindView(ego, createTestView(viewNumber: 0, numLoops: 4, celsPerLoop: 1, width: 7, height: 32));
        ego.isAnimated = true;
        ego.isDrawn = true;
        ego.x = 81;
        ego.y = 144;
        ego.ignoreObjects = true;

        final droid = engine.animatedObjects[16];
        bindView(droid, createTestView(viewNumber: 46, numLoops: 1, celsPerLoop: 1, width: 20, height: 24));
        droid.isAnimated = true;
        droid.isDrawn = true;
        droid.ignoreObjects = true;
        droid.x = 164;
        droid.y = 139;
        droid.stepTime = 1;
        droid.stepTimer = 1;
        droid.motionType = 2;
        droid.stepDistance = 10;
        droid.stepSize = 1;
        droid.targetFlag = 235;
        engine.memory.resetFlag(235);

        engine.tick();
        expect(engine.memory.getFlag(235), isFalse);
        expect(droid.motionType, 2);
        expect(droid.x + droid.getCelWidth(), lessThanOrEqualTo(160));
        expect(droid.x, greaterThanOrEqualTo(0));
      });
    });

    group('wander Motion Mode', () {
      test('NPC in wander mode picks random directions and moves', () {
        final npc = engine.animatedObjects[1];
        bindView(npc, testView4Loops);
        npc.isAnimated = true;
        npc.isDrawn = true;
        npc.ignoreObjects = true;
        npc.x = 80;
        npc.y = 80;
        npc.stepSize = 1;
        npc.stepTime = 1;
        npc.stepTimer = 1;
        npc.motionType = 1;

        engine.tick();
        expect(npc.direction, greaterThanOrEqualTo(0));
        expect(npc.direction, lessThanOrEqualTo(8));
      });
    });

    group('Ego Flags and Register Synchronization', () {
      test('updates Ego direction variable 6', () {
        final ego = engine.ego;
        ego.isAnimated = true;
        ego.isDrawn = true;
        ego.x = 50;
        ego.y = 80;
        engine.isUserControl = false;
        ego.direction = 4;

        engine.tick();
        expect(engine.memory.getVar(6), equals(4));
      });

      test('sets flag 0 when Ego is on water (priority 3)', () {
        final ego = engine.ego;
        bindView(ego, testView4Loops);
        ego.isAnimated = true;
        ego.isDrawn = true;
        ego.x = 50;
        ego.y = 80;

        engine.tick();
        expect(engine.memory.getFlag(0), isFalse);

        for (var x = 50; x <= 58; x++) {
          priorityBuffer.setPriorityAt(x, 80, 3);
        }

        engine.tick();
        expect(engine.memory.getFlag(0), isTrue);
      });

      test('sets flag 3 when Ego touches signal / trigger pixel (priority 2)', () {
        final ego = engine.ego;
        bindView(ego, testView4Loops);
        ego.isAnimated = true;
        ego.isDrawn = true;
        ego.x = 50;
        ego.y = 80;

        priorityBuffer.setPriorityAt(52, 80, 2);

        engine.tick();
        expect(engine.memory.getFlag(3), isTrue);
      });

      test('sets flag 1 when Ego is completely obscured or not drawn', () {
        final ego = engine.ego;
        bindView(ego, testView4Loops);
        ego.isAnimated = true;
        ego.isDrawn = true;
        ego.x = 50;
        ego.y = 80;
        ego.priority = 6;
        ego.fixedPriority = true;

        for (var x = 50; x <= 58; x++) {
          priorityBuffer.setPriorityAt(x, 80, 4);
        }
        engine.tick();
        expect(engine.memory.getFlag(1), isFalse, reason: 'Ego at priority 6 in front of depth 4 must be visible');

        for (var y = 68; y <= 80; y++) {
          for (var x = 50; x <= 58; x++) {
            priorityBuffer.setPriorityAt(x, y, 10);
          }
        }
        engine.tick();
        expect(engine.memory.getFlag(1), isTrue, reason: 'Ego at priority 6 behind depth 10 must be obscured (Flag 1 = true)');

        ego.isDrawn = false;
        engine.tick();
        expect(engine.memory.getFlag(1), isTrue, reason: 'Undrawn Ego must be obscured (Flag 1 = true)');
      });
    });
  });
}
