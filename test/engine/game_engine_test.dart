import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/domain/logic_script.dart';
import 'package:flutter_agigame/domain/picture.dart';
import 'package:flutter_agigame/domain/priority_buffer.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/picture/picture_slicer.dart';

void main() {
  group('AgiGameEngine Core Cycle & State Machine', () {
    late AgiGameEngine engine;

    setUp(() {
      engine = AgiGameEngine(speedHz: 20.0, randomSeed: 12345);
    });

    tearDown(() {
      engine.dispose();
    });

    test('initializes default registers correctly', () {
      expect(engine.isRunning, isFalse);
      expect(engine.isPaused, isFalse);
      expect(engine.speedHz, 20.0);
      expect(engine.cycleCount, 0);
      expect(engine.memory.getFlag(9), isTrue); // Sound ON by default
      expect(engine.memory.getVar(3), 0); // Score
      expect(engine.memory.getVar(6), 0); // Ego direction
      expect(engine.ego.number, 0);
    });

    test('supports configurable speed in Hertz', () {
      engine.setSpeedHz(40.0);
      expect(engine.speedHz, 40.0);

      engine.setSpeedHz(10.0);
      expect(engine.speedHz, 10.0);
    });

    test('starts, pauses, resumes, and stops loop', () {
      engine.start();
      expect(engine.isRunning, isTrue);
      expect(engine.isPaused, isFalse);

      engine.pause();
      expect(engine.isPaused, isTrue);

      engine.resume();
      expect(engine.isPaused, isFalse);

      engine.stop();
      expect(engine.isRunning, isFalse);
    });

    test('tick increments cycle count and resets transient cycle flags', () {
      // Set transient flags before tick
      engine.memory.setFlag(1); // obscured
      engine.memory.setFlag(2); // have.input
      engine.memory.setFlag(4); // said.accepted
      engine.memory.setController(0, true);

      engine.tick();

      expect(engine.cycleCount, 1);
      expect(engine.memory.getFlag(1), isFalse);
      expect(engine.memory.getFlag(2), isFalse);
      expect(engine.memory.getFlag(4), isFalse);
      expect(engine.memory.getController(0), isFalse);
    });

    test('executes logic script scan cycle during tick', () {
      // Script: assignn(%v3, 25), set(%f10), return
      final script = AgiLogicScript(
        bytecodes: Uint8List.fromList([
          0x03, 0x03, 0x19, // assignn(%v3, 25)
          0x0C, 0x0A,       // set(%f10)
          0x00,             // return
        ]),
        messages: const [],
      );

      engine.interpreter.loadRootScript(script);
      engine.tick();

      expect(engine.memory.getVar(3), 25);
      expect(engine.memory.getFlag(10), isTrue);
    });
  });

  group('AgiGameEngine Motion & Physics', () {
    late AgiGameEngine engine;

    setUp(() {
      engine = AgiGameEngine(speedHz: 20.0, randomSeed: 42);
      engine.ego.isAnimated = true;
      engine.ego.isDrawn = true;
      engine.ego.isUpdating = true;
      engine.ego.x = 80;
      engine.ego.y = 100;
      engine.ego.stepSize = 2;
      engine.ego.stepTime = 1;
      engine.ego.stepTimer = 1;
    });

    tearDown(() {
      engine.dispose();
    });

    test('moves Ego in motion direction and updates var 6', () {
      engine.setEgoDirection(3); // East (dx = +1, dy = 0)
      expect(engine.memory.getVar(6), 3);

      engine.tick();

      // stepSize = 2, so x: 80 -> 82
      expect(engine.ego.x, 82);
      expect(engine.ego.y, 100);
      expect(engine.ego.prevX, 80);
      expect(engine.ego.prevY, 100);
    });

    test('clamps Ego to screen boundaries and sets border variables', () {
      // Move Left past boundary 0
      engine.ego.x = 1;
      engine.setEgoDirection(7); // West (dx = -1)

      engine.tick();

      expect(engine.ego.x, 0);
      expect(engine.memory.getVar(2), 4); // Left edge (%v2 = 4)
    });

    test('stops motion on PriorityBuffer barrier collision', () {
      final priBuf = PriorityBuffer();
      // Place unconditional barrier (priority 2) at x=82, y=100
      priBuf.setPriorityAt(82, 100, 2);

      engine.currentPic = AgiPic(
        visualPixels: Uint8List(160 * 168),
        priorityBuffer: priBuf,
        slices: PictureSlicer.slice(
          visualPixels: Uint8List(160 * 168),
          priorityBuffer: priBuf,
        ),
      );

      engine.setEgoDirection(3); // East towards barrier
      engine.tick();

      // Ego should be blocked at x=80
      expect(engine.ego.x, 80);
    });

    test('moveObj moves towards target and sets targetFlag on arrival', () {
      final npc = engine.animatedObjects[1];
      npc.isAnimated = true;
      npc.isDrawn = true;
      npc.isUpdating = true;
      npc.x = 10;
      npc.y = 50;
      npc.stepSize = 5;
      npc.stepTime = 1;
      npc.stepTimer = 1;
      npc.motionType = 3; // move_to
      npc.targetX = 20;
      npc.targetY = 50;
      npc.targetFlag = 15;

      engine.tick(); // moves by 5 -> x=15
      expect(npc.x, 15);
      expect(engine.memory.getFlag(15), isFalse);

      engine.tick(); // moves by 5 -> x=20 (arrived)
      expect(npc.x, 20);
      expect(npc.motionType, 0);
      expect(npc.direction, 0);
      expect(engine.memory.getFlag(15), isTrue);
    });
  });

  group('AgiGameEngine Text Parser & said() Matcher', () {
    late AgiGameEngine engine;

    setUp(() {
      engine = AgiGameEngine(speedHz: 20.0);
    });

    tearDown(() {
      engine.dispose();
    });

    test('checkSaid matches exact word sequences and raises flag 4', () {
      engine.setParsedWordIdsForTesting([100, 200]);
      expect(engine.memory.getFlag(2), isTrue); // have.input = 1
      expect(engine.memory.getFlag(4), isFalse); // said.accepted = 0

      expect(engine.checkSaid([100, 200]), isTrue);
      expect(engine.memory.getFlag(4), isTrue); // said.accepted = 1

      expect(engine.checkSaid([100, 300]), isFalse);
    });

    test('checkSaid supports ANYWORD wildcard (9999) and ROL wildcard (9998)', () {
      // Input: [100 (look), 200 (at), 300 (magic), 400 (tree)]
      engine.setParsedWordIdsForTesting([100, 200, 300, 400]);

      // ANYWORD (9999) matches any token
      expect(engine.checkSaid([100, 9999, 300, 400]), isTrue);
      expect(engine.checkSaid([9999, 9999, 9999, 9999]), isTrue);
      expect(engine.checkSaid([9999, 9999, 9999]), isFalse); // too short

      // ROL (9998) matches rest of line
      expect(engine.checkSaid([100, 9998]), isTrue);
      expect(engine.checkSaid([100, 200, 9998]), isTrue);
      expect(engine.checkSaid([500, 9998]), isFalse);
    });
  });

  group('AgiGameEngine Room Transitions', () {
    late AgiGameEngine engine;

    setUp(() {
      engine = AgiGameEngine(speedHz: 20.0);
    });

    tearDown(() {
      engine.dispose();
    });

    test('changeRoom updates room registers and sets flag 5', () {
      engine.memory.setVar(0, 1); // room 1
      engine.memory.setVar(2, 2); // crossed right border (%v2 = 2)

      engine.changeRoom(2);

      expect(engine.memory.getVar(1), 1); // %v1 = previous room (1)
      expect(engine.memory.getVar(0), 2); // %v0 = current room (2)
      expect(engine.memory.getFlag(5), isTrue); // %f5 = new room
      expect(engine.memory.getVar(2), 0); // border reset
      expect(engine.ego.x, 0); // Ego placed at left edge on right border entry
    });

    test('changeRoom resets non-Ego animated objects', () {
      final npc = engine.animatedObjects[1];
      npc.isAnimated = true;
      npc.isDrawn = true;
      npc.x = 50;
      npc.y = 80;

      engine.changeRoom(5);

      expect(npc.isAnimated, isFalse);
      expect(npc.isDrawn, isFalse);
      expect(npc.x, 0);
      expect(npc.y, 0);
    });
  });

  group('AgiGameEngine Interpreter Delegate Actions', () {
    late AgiGameEngine engine;

    setUp(() {
      engine = AgiGameEngine(speedHz: 20.0);
    });

    tearDown(() {
      engine.dispose();
    });

    test('onPrint sets active dialog and dismissDialog clears it', () {
      expect(engine.activeDialog, isNull);

      engine.onPrint('Welcome to the Magic Kingdom!');
      expect(engine.activeDialog, isNotNull);
      expect(engine.activeDialog!.message, 'Welcome to the Magic Kingdom!');
      expect(engine.activeDialog!.isModal, isTrue);

      engine.dismissDialog();
      expect(engine.activeDialog, isNull);
    });

    test('onSound sets completion flag', () {
      engine.memory.resetFlag(12);
      engine.onSound(1, 12);
      expect(engine.memory.getFlag(12), isTrue);
    });

    test('onQuit stops engine execution', () {
      engine.start();
      expect(engine.isRunning, isTrue);

      engine.onQuit();
      expect(engine.isRunning, isFalse);
    });
  });
}
