import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_agigame/domain/agi_view.dart';
import 'package:flutter_agigame/domain/engine_memory.dart';
import 'package:flutter_agigame/domain/priority_buffer.dart';
import 'package:flutter_agigame/engine/motion/agi_motion_controller.dart';
import 'package:flutter_agigame/engine/motion/collision_detector.dart';
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
          rawPixels: Uint8List(width * height),
        ),
      );
    }
    loops.add(AgiViewLoop(loopNumber: l, cels: cels));
  }
  return AgiView(viewNumber: viewNumber, loops: loops);
}

void main() {
  group('AgiMotionController', () {
    late PriorityBuffer priorityBuffer;
    late CollisionDetector collisionDetector;
    late AgiMemory memory;
    late AgiMotionController controller;
    late AgiView testView4Loops;
    late AgiView testView2Loops;

    setUp(() {
      priorityBuffer = PriorityBuffer();
      collisionDetector = CollisionDetector(
        priorityBuffer: priorityBuffer,
        horizon: 36,
      );
      memory = AgiMemory();
      testView4Loops = createTestView(viewNumber: 0, numLoops: 4, celsPerLoop: 3);
      testView2Loops = createTestView(viewNumber: 1, numLoops: 2, celsPerLoop: 4);

      controller = AgiMotionController(
        priorityBuffer: priorityBuffer,
        collisionDetector: collisionDetector,
        memory: memory,
        loadedViews: {
          0: testView4Loops,
          1: testView2Loops,
        },
        randomSeed: 42,
      );
    });

    group('Direction Deltas & Normal Motion', () {
      test('direction deltas map to correct (dx, dy)', () {
        expect(AgiMotionController.directionDeltas[0], equals(const math.Point(0, 0))); // Stopped
        expect(AgiMotionController.directionDeltas[1], equals(const math.Point(0, -1))); // North
        expect(AgiMotionController.directionDeltas[2], equals(const math.Point(1, -1))); // North-East
        expect(AgiMotionController.directionDeltas[3], equals(const math.Point(1, 0))); // East
        expect(AgiMotionController.directionDeltas[4], equals(const math.Point(1, 1))); // South-East
        expect(AgiMotionController.directionDeltas[5], equals(const math.Point(0, 1))); // South
        expect(AgiMotionController.directionDeltas[6], equals(const math.Point(-1, 1))); // South-West
        expect(AgiMotionController.directionDeltas[7], equals(const math.Point(-1, 0))); // West
        expect(AgiMotionController.directionDeltas[8], equals(const math.Point(-1, -1))); // North-West
      });

      test('normal motion advances position by stepSize every stepTime ticks', () {
        final ego = controller.ego;
        ego.isAnimated = true;
        ego.isDrawn = true;
        ego.x = 50;
        ego.y = 80;
        ego.direction = 3; // East (dx = 1)
        ego.stepSize = 2;
        ego.stepTime = 2;
        ego.stepTimer = 2;

        // Tick 1: stepTimer decrements to 1 (no movement yet)
        controller.tick();
        expect(ego.x, equals(50));
        expect(ego.y, equals(80));

        // Tick 2: stepTimer expires -> moves by stepSize (2) to 52
        controller.tick();
        expect(ego.x, equals(52));
        expect(ego.y, equals(80));
      });

      test('normal motion stops when encountering obstacle and clears direction', () {
        final ego = controller.ego;
        ego.isAnimated = true;
        ego.isDrawn = true;
        ego.x = 50;
        ego.y = 80;
        ego.direction = 3; // East
        ego.stepSize = 2;
        ego.stepTime = 1;
        ego.stepTimer = 1;

        // Place obstacle at x=52..60, y=80
        for (var x = 52; x <= 60; x++) {
          priorityBuffer.setPriorityAt(x, 80, 0); // Barrier
        }

        controller.tick();

        // Should be stopped by barrier
        expect(ego.x, equals(50));
        expect(ego.direction, equals(0));
        expect(memory.getVar(6), equals(0)); // Var 6 synced
      });
    });

    group('Automatic Loop Selection', () {
      test('4-loop views map directions to proper loops', () {
        final ego = controller.ego;
        ego.isAnimated = true;
        ego.isDrawn = true;
        ego.view = 0; // 4-loop view
        ego.fixedLoop = false;
        ego.x = 50;
        ego.y = 80;
        ego.stepTime = 1;
        ego.stepTimer = 1;

        // East (3) -> Loop 0
        ego.direction = 3;
        controller.tick();
        expect(ego.loop, equals(0));

        // West (7) -> Loop 1
        ego.direction = 7;
        controller.tick();
        expect(ego.loop, equals(1));

        // South (5) -> Loop 2
        ego.direction = 5;
        controller.tick();
        expect(ego.loop, equals(2));

        // North (1) -> Loop 3
        ego.direction = 1;
        controller.tick();
        expect(ego.loop, equals(3));
      });

      test('2-loop views map East/West and retain loop on North/South', () {
        final npc = controller.objects[1];
        npc.isAnimated = true;
        npc.isDrawn = true;
        npc.view = 1; // 2-loop view
        npc.fixedLoop = false;
        npc.x = 50;
        npc.y = 80;
        npc.stepTime = 1;
        npc.stepTimer = 1;

        // East (3) -> Loop 0
        npc.direction = 3;
        controller.tick();
        expect(npc.loop, equals(0));

        // South (5) -> Retains Loop 0
        npc.direction = 5;
        controller.tick();
        expect(npc.loop, equals(0));

        // West (7) -> Loop 1
        npc.direction = 7;
        controller.tick();
        expect(npc.loop, equals(1));

        // North (1) -> Retains Loop 1
        npc.direction = 1;
        controller.tick();
        expect(npc.loop, equals(1));
      });

      test('fixedLoop retains loop regardless of movement direction', () {
        final ego = controller.ego;
        ego.isAnimated = true;
        ego.isDrawn = true;
        ego.view = 0;
        ego.loop = 2; // South
        ego.fixedLoop = true;
        ego.direction = 3; // East

        controller.tick();
        expect(ego.loop, equals(2));
      });
    });

    group('Cel Animation Cycling', () {
      test('normal cycling mode cycles forward: 0 -> 1 -> 2 -> 0', () {
        final ego = controller.ego;
        ego.isAnimated = true;
        ego.isDrawn = true;
        ego.view = 0; // 3 cels
        ego.loop = 0;
        ego.cel = 0;
        ego.cycleMode = 0; // normal
        ego.cycleTime = 1;
        ego.cycleTimer = 1;

        controller.tick();
        expect(ego.cel, equals(1));

        controller.tick();
        expect(ego.cel, equals(2));

        controller.tick();
        expect(ego.cel, equals(0));
      });

      test('reverse cycling mode cycles backward: 2 -> 1 -> 0 -> 2', () {
        final ego = controller.ego;
        ego.isAnimated = true;
        ego.isDrawn = true;
        ego.view = 0;
        ego.loop = 0;
        ego.cel = 2;
        ego.cycleMode = 1; // reverse
        ego.cycleTime = 1;
        ego.cycleTimer = 1;

        controller.tick();
        expect(ego.cel, equals(1));

        controller.tick();
        expect(ego.cel, equals(0));

        controller.tick();
        expect(ego.cel, equals(2));
      });

      test('end_of_loop cycles forward to last cel, stops cycling, and sets flag', () {
        final ego = controller.ego;
        ego.isAnimated = true;
        ego.isDrawn = true;
        ego.view = 0; // 3 cels (0, 1, 2)
        ego.loop = 0;
        ego.cel = 0;
        ego.cycleMode = 2; // end_of_loop
        ego.endOfLoopFlag = 40;
        ego.cycleTime = 1;
        ego.cycleTimer = 1;

        // Cel 0 -> 1
        controller.tick();
        expect(ego.cel, equals(1));
        expect(ego.isCycling, isTrue);
        expect(memory.getFlag(40), isFalse);

        // Cel 1 -> 2 (last cel)
        controller.tick();
        expect(ego.cel, equals(2));
        expect(ego.isCycling, isFalse);
        expect(memory.getFlag(40), isTrue);

        // Subsequent ticks should not advance cel
        controller.tick();
        expect(ego.cel, equals(2));
      });

      test('reverse_loop cycles backward to cel 0, stops cycling, and sets flag', () {
        final ego = controller.ego;
        ego.isAnimated = true;
        ego.isDrawn = true;
        ego.view = 0;
        ego.loop = 0;
        ego.cel = 2;
        ego.cycleMode = 3; // reverse_loop
        ego.endOfLoopFlag = 41;
        ego.cycleTime = 1;
        ego.cycleTimer = 1;

        // Cel 2 -> 1
        controller.tick();
        expect(ego.cel, equals(1));
        expect(ego.isCycling, isTrue);
        expect(memory.getFlag(41), isFalse);

        // Cel 1 -> 0 (first cel)
        controller.tick();
        expect(ego.cel, equals(0));
        expect(ego.isCycling, isFalse);
        expect(memory.getFlag(41), isTrue);

        // Subsequent ticks should not advance cel
        controller.tick();
        expect(ego.cel, equals(0));
      });

      test('cycleTime throttles animation cycling', () {
        final ego = controller.ego;
        ego.isAnimated = true;
        ego.isDrawn = true;
        ego.view = 0;
        ego.loop = 0;
        ego.cel = 0;
        ego.cycleMode = 0;
        ego.cycleTime = 3;
        ego.cycleTimer = 3;

        controller.tick(); // timer 2
        expect(ego.cel, equals(0));

        controller.tick(); // timer 1
        expect(ego.cel, equals(0));

        controller.tick(); // timer 0 -> resets to 3, advances cel
        expect(ego.cel, equals(1));
      });
    });

    group('moveObj Motion Mode', () {
      test('moves towards target, updates loop, snaps when reached, and sets targetFlag', () {
        final npc = controller.objects[1];
        npc.isAnimated = true;
        npc.isDrawn = true;
        npc.view = 0; // 4-loop view
        npc.x = 20;
        npc.y = 50;

        controller.moveObject(1, 26, 50, 2, 50); // Move East to (26, 50) with step 2, flag 50

        // Step 1: moves to 22, faces East (Loop 0)
        controller.tick();
        expect(npc.x, equals(22));
        expect(npc.y, equals(50));
        expect(npc.loop, equals(0));
        expect(npc.direction, equals(3));
        expect(memory.getFlag(50), isFalse);

        // Step 2: moves to 24
        controller.tick();
        expect(npc.x, equals(24));

        // Step 3: moves to 26 (reached target!)
        controller.tick();
        expect(npc.x, equals(26));
        expect(npc.y, equals(50));
        expect(npc.direction, equals(0));
        expect(npc.motionType, equals(0));
        expect(memory.getFlag(50), isTrue);
      });
    });

    group('followEgo Motion Mode', () {
      test('NPC moves towards Ego and stops with flag when reached', () {
        final ego = controller.ego;
        ego.isAnimated = true;
        ego.isDrawn = true;
        ego.x = 50;
        ego.y = 80;

        final npc = controller.objects[1];
        npc.isAnimated = true;
        npc.isDrawn = true;
        npc.view = 0;
        npc.x = 44;
        npc.y = 80;

        controller.followEgo(1, 2, 60);

        // Step 1: moves towards Ego (dx = +2) -> x=46
        controller.tick();
        expect(npc.x, equals(46));
        expect(npc.direction, equals(3)); // East
        expect(memory.getFlag(60), isFalse);

        // Step 2: moves to x=48
        controller.tick();
        expect(npc.x, equals(48));

        // Step 3: reaches Ego (dx <= step) -> stops and triggers flag 60
        controller.tick();
        expect(npc.direction, equals(0));
        expect(npc.motionType, equals(0));
        expect(memory.getFlag(60), isTrue);
      });
    });

    group('wander Motion Mode', () {
      test('NPC in wander mode picks random directions and moves', () {
        final npc = controller.objects[1];
        npc.isAnimated = true;
        npc.isDrawn = true;
        npc.view = 0;
        npc.x = 80;
        npc.y = 80;
        npc.stepSize = 1;

        controller.wander(1);

        controller.tick();
        expect(npc.direction, greaterThanOrEqualTo(0));
        expect(npc.direction, lessThanOrEqualTo(8));
      });
    });

    group('Ego Flags and Register Synchronization', () {
      test('updates Ego direction variable 6', () {
        final ego = controller.ego;
        ego.isAnimated = true;
        ego.isDrawn = true;
        ego.x = 50;
        ego.y = 80;
        controller.setDirection(0, 4); // South-East

        controller.tick();
        expect(memory.getVar(6), equals(4));
      });

      test('sets flag 0 when Ego is on water (priority 3)', () {
        final ego = controller.ego;
        ego.isAnimated = true;
        ego.isDrawn = true;
        ego.x = 50;
        ego.y = 80;

        // Not on water
        controller.tick();
        expect(memory.getFlag(0), isFalse);

        // Draw water at (50..58, 80)
        for (var x = 50; x <= 58; x++) {
          priorityBuffer.setPriorityAt(x, 80, 3);
        }

        controller.tick();
        expect(memory.getFlag(0), isTrue);
      });

      test('sets flag 3 when Ego touches signal / trigger pixel (priority 2)', () {
        final ego = controller.ego;
        ego.isAnimated = true;
        ego.isDrawn = true;
        ego.x = 50;
        ego.y = 80;

        priorityBuffer.setPriorityAt(52, 80, 2); // Trigger / Alarm pixel

        controller.tick();
        expect(memory.getFlag(3), isTrue);
      });

      test('sets flag 1 when Ego is completely obscured or not drawn', () {
        final ego = controller.ego;
        ego.isAnimated = true;
        ego.isDrawn = true;
        ego.x = 50;
        ego.y = 80;
        ego.priority = 6; // Fixed low priority (depth 6)

        // Case 1: Background has lower depth priority (e.g. 4) -> Ego is in front and visible
        for (var x = 50; x <= 58; x++) {
          priorityBuffer.setPriorityAt(x, 80, 4);
        }
        controller.tick();
        expect(memory.getFlag(1), isFalse, reason: 'Ego at priority 6 in front of depth 4 must be visible');

        // Case 2: Background has higher depth priority (e.g. 10) covering Ego's baseline -> Ego is obscured
        for (var x = 50; x <= 58; x++) {
          priorityBuffer.setPriorityAt(x, 80, 10);
        }
        controller.tick();
        expect(memory.getFlag(1), isTrue, reason: 'Ego at priority 6 behind depth 10 must be obscured (Flag 1 = true)');

        // Case 3: Ego is not drawn -> Flag 1 = true
        ego.isDrawn = false;
        controller.tick();
        expect(memory.getFlag(1), isTrue, reason: 'Undrawn Ego must be obscured (Flag 1 = true)');
      });
    });
  });
}
