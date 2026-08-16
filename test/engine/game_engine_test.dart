import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/domain/logic_script.dart';
import 'package:flutter_agigame/domain/picture.dart';
import 'package:flutter_agigame/domain/priority_buffer.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';
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

    test('toggles motion to stop (0) when pressing the current active direction', () {
      expect(engine.ego.direction, 0);

      // Start moving East (3)
      engine.setEgoDirection(3);
      expect(engine.ego.direction, 3);
      expect(engine.memory.getVar(6), 3);

      // Press East (3) again -> stops (0)
      engine.setEgoDirection(3);
      expect(engine.ego.direction, 0);
      expect(engine.memory.getVar(6), 0);

      // Start moving North (1)
      engine.setEgoDirection(1);
      expect(engine.ego.direction, 1);
      expect(engine.memory.getVar(6), 1);

      // Change direction to South (5) -> changes to South (5)
      engine.setEgoDirection(5);
      expect(engine.ego.direction, 5);
      expect(engine.memory.getVar(6), 5);

      // Press South (5) again -> stops (0)
      engine.setEgoDirection(5);
      expect(engine.ego.direction, 0);
      expect(engine.memory.getVar(6), 0);
    });

    test('clamps Ego to screen boundaries and sets border variables', () {
      // Move Left past boundary 0
      engine.ego.x = 1;
      engine.setEgoDirection(7); // West (dx = -1)

      engine.tick();

      expect(engine.ego.x, 0);
      expect(engine.memory.getVar(2), 4); // Left edge (%v2 = 4)
    });

    test('stops motion on PriorityBuffer barrier collision (priority 0)', () {
      final priBuf = PriorityBuffer();
      // Place unconditional barrier (priority 0) at x=82, y=100
      priBuf.setPriorityAt(82, 100, 0);

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

    test('sets flag 3 on trigger line (priority 2) without blocking motion', () {
      final priBuf = PriorityBuffer();
      // Place trigger line (priority 2) at x=82, y=100
      priBuf.setPriorityAt(82, 100, 2);

      engine.currentPic = AgiPic(
        visualPixels: Uint8List(160 * 168),
        priorityBuffer: priBuf,
        slices: PictureSlicer.slice(
          visualPixels: Uint8List(160 * 168),
          priorityBuffer: priBuf,
        ),
      );

      engine.ego.x = 80;
      engine.ego.y = 100;
      engine.ego.stepSize = 2;
      engine.setEgoDirection(3); // East across trigger line
      engine.tick();

      // Ego should NOT be blocked and move to x=82 (stepSize 2)
      expect(engine.ego.x, 82);
      expect(engine.memory.getFlag(3), isTrue);
    });

    test('sets flag 0 when Ego is on water (priority 3)', () {
      final priBuf = PriorityBuffer();
      // Draw water under Ego's position (x=80..84, y=100)
      for (int x = 80; x <= 84; x++) {
        priBuf.setPriorityAt(x, 100, 3);
      }

      engine.currentPic = AgiPic(
        visualPixels: Uint8List(160 * 168),
        priorityBuffer: priBuf,
        slices: PictureSlicer.slice(
          visualPixels: Uint8List(160 * 168),
          priorityBuffer: priBuf,
        ),
      );

      engine.tick();

      expect(engine.memory.getFlag(0), isTrue);
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

      // Subsequent said() in same cycle fails because Flag 4 is already true
      expect(engine.checkSaid([100, 200]), isFalse);
      expect(engine.checkSaid([100, 300]), isFalse);
    });

    test('checkSaid supports ANYWORD wildcard (9999) and ROL wildcard (9998)', () {
      // Input: [100 (look), 200 (at), 300 (magic), 400 (tree)]
      engine.setParsedWordIdsForTesting([100, 200, 300, 400]);

      // ANYWORD (9999) matches any token
      expect(engine.checkSaid([100, 9999, 300, 400]), isTrue);
      engine.memory.resetFlag(4);
      expect(engine.checkSaid([9999, 9999, 9999, 9999]), isTrue);
      engine.memory.resetFlag(4);
      expect(engine.checkSaid([9999, 9999, 9999]), isFalse); // too short

      // ROL (9998) matches rest of line
      engine.memory.resetFlag(4);
      expect(engine.checkSaid([100, 9998]), isTrue);
      engine.memory.resetFlag(4);
      expect(engine.checkSaid([100, 200, 9998]), isTrue);
      engine.memory.resetFlag(4);
      expect(engine.checkSaid([500, 9998]), isFalse);
    });

    test('tick post-scan clears Flag 2, Flag 4, and parsed input tokens preventing repeated triggers', () {
      engine.setParsedWordIdsForTesting([100, 200]);
      expect(engine.memory.getFlag(2), isTrue);
      expect(engine.parsedWordIds, isNotEmpty);

      // Cycle 1: checkSaid matches
      expect(engine.checkSaid([100, 200]), isTrue);
      expect(engine.memory.getFlag(4), isTrue);

      // End of cycle 1: tick cleans up
      engine.tick();
      expect(engine.memory.getFlag(2), isFalse);
      expect(engine.memory.getFlag(4), isFalse);
      expect(engine.parsedWordIds, isEmpty);

      // Cycle 2: checkSaid must return false without new user input
      expect(engine.checkSaid([100, 200]), isFalse);
    });

    test('submitCommand with unknown word sets variable 9 and flag 2 without throwing on tick', () {
      // Submit a command without a loaded dictionary (all words unknown)
      engine.submitCommand('xyzzy bar');

      expect(engine.memory.getFlag(2), isTrue, reason: 'have.input must be set');
      expect(engine.memory.getVar(9), 1, reason: '%v9 must record 1-based index of first unknown word');
      expect(engine.inputWords, equals(['xyzzy', 'bar']));

      // Calling tick() must clear the list and reset flags cleanly without throwing UnsupportedOperation
      expect(() => engine.tick(), returnsNormally);
      expect(engine.memory.getFlag(2), isFalse);
      expect(engine.parsedWordIds, isEmpty);
    });

    test('formatMessage expands %w, %v, and %s placeholders correctly', () {
      engine.memory.setVar(0, 9);
      engine.memory.setString(0, 'Graham');
      engine.submitCommand('take xyzzy');

      final formatted = engine.formatMessage('Room %v0: %s0 says "I don\'t understand %w2".');
      expect(formatted, equals('Room 9: Graham says "I don\'t understand xyzzy".'));
    });

    test('KQ2 greedy phrase parsing: "look little red riding hood" matches multi-word phrase', () {
      final loader = AgiResourceLoader.fromDirectorySync('reference_games/kings-quest-2');
      final kq2Engine = AgiGameEngine(resourceLoader: loader);

      kq2Engine.submitCommand('look little red riding hood');

      expect(kq2Engine.memory.getFlag(2), isTrue);
      expect(kq2Engine.memory.getVar(9), 0, reason: 'All words should be recognized as a multi-word phrase');
      expect(kq2Engine.parsedWordIds, isNotEmpty);
      expect(kq2Engine.inputWords, equals(['look', 'little red riding hood']));

      kq2Engine.dispose();
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

    test('changeRoom restores isUserControl to true', () {
      engine.onUserControl(false);
      expect(engine.isUserControl, isFalse);

      engine.changeRoom(25);
      expect(engine.isUserControl, isTrue);
    });

    test('onSetHorizon updates room horizon and clamps motion and border triggers', () {
      engine.ego.isAnimated = true;
      engine.ego.isDrawn = true;
      engine.ego.isUpdating = true;
      engine.onSetHorizon(71);
      expect(engine.horizon, 71);

      engine.ego.x = 80;
      engine.ego.y = 75;
      engine.ego.stepSize = 5;
      engine.setEgoDirection(1); // North towards horizon 71
      engine.tick();

      // Ego cannot cross y=71
      expect(engine.ego.y, 71);
      // Top border (%v2 = 1) is triggered at horizon
      expect(engine.memory.getVar(2), 1);
    });

    test('repositions Ego at horizon + 1 when entering from bottom border', () {
      engine.onSetHorizon(71);
      engine.memory.setVar(0, 3); // from room 3
      engine.memory.setVar(2, 3); // crossed bottom border (%v2 = 3)

      engine.changeRoom(8);
      // In new room 8, Ego is placed at defaultHorizon (36) + 1 before room init sets horizon
      expect(engine.ego.y, 37);

      // When room 8 executes set.horizon(71), horizon becomes 71
      engine.onSetHorizon(71);
      expect(engine.horizon, 71);
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

    test('onSound sets completion flag immediately when sound player is null', () {
      engine.memory.setFlag(12);
      engine.onSound(1, 12);
      expect(engine.memory.getFlag(12), isTrue);
    });

    test('onStopSound fulfills active sound completion flag', () {
      engine.memory.resetFlag(200);
      // Simulate an active sound playing with flag 200
      engine.onSound(1, 200);
      expect(engine.memory.getFlag(200), isTrue);

      engine.memory.resetFlag(200);
      engine.onStopSound();
      // onStopSound without active sound leaves flag as-is
      expect(engine.memory.getFlag(200), isFalse);
    });

    test('onQuit stops engine execution', () {
      engine.start();
      expect(engine.isRunning, isTrue);

      engine.onQuit();
      expect(engine.isRunning, isFalse);
    });
  });
}
