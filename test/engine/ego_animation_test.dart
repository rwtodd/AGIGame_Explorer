import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/domain/logic_script.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/logic/interpreter/agi_interpreter.dart';

void main() {
  group('Ego Animation Cycling Tests', () {
    late AgiGameEngine engine;

    setUp(() {
      engine = AgiGameEngine();
      engine.ego.isAnimated = true;
      engine.ego.isDrawn = true;
      engine.ego.view = 0;
      engine.ego.loop = 0;
      engine.ego.cel = 0;
      engine.ego.isCycling = true;
    });

    test('Ego does not cycle cels when stationary (direction == 0)', () {
      engine.setEgoDirection(0);
      final initialCel = engine.ego.cel;

      // Execute several ticks
      engine.tick();
      engine.tick();
      engine.tick();

      expect(engine.ego.cel, equals(initialCel));
    });

    test('player.control opcode restores Ego cycling and animation flags', () {
      engine.ego.isCycling = false;
      engine.ego.isAnimated = false;
      engine.ego.motionType = 1;

      final interpreter = AgiLogicInterpreter(
        memory: engine.memory,
        animatedObjects: engine.animatedObjects,
        delegate: engine,
      );

      // Bytecode for player.control (opcode 132 = 0x84) followed by return (opcode 0)
      final code = Uint8List.fromList([0x84, 0x00]);
      final script = AgiLogicScript(bytecodes: code, messages: [], logicNumber: 0);
      interpreter.loadRootScript(script, scriptNumber: 0);
      interpreter.executeCycle();

      expect(engine.ego.isCycling, isTrue);
      expect(engine.ego.isAnimated, isTrue);
      expect(engine.ego.isUpdating, isTrue);
      expect(engine.ego.motionType, equals(0));
    });

    test('Ego cycles animation cels when stationary if script enables isCycling (e.g. drowning)', () {
      engine.setEgoDirection(0);
      expect(engine.ego.isCycling, isFalse);

      final interpreter = AgiLogicInterpreter(
        memory: engine.memory,
        animatedObjects: engine.animatedObjects,
        delegate: engine,
      );

      // Script: start.cycling(ego) [opcode 71, 0x00] -> return [opcode 0]
      final code = Uint8List.fromList([71, 0, 0]);
      final script = AgiLogicScript(bytecodes: code, messages: [], logicNumber: 0);
      interpreter.loadRootScript(script, scriptNumber: 0);
      interpreter.executeCycle();

      expect(engine.ego.isCycling, isTrue);
      expect(engine.ego.direction, equals(0));

      final initialCel = engine.ego.cel;
      engine.tick();
      // Even though direction is 0, isCycling is true so cel advances
      expect(engine.ego.cel, equals(initialCel + 1));
    });

    test('program.control disables player movement and player.control restores it', () {
      expect(engine.isUserControl, isTrue);

      final interpreter = AgiLogicInterpreter(
        memory: engine.memory,
        animatedObjects: engine.animatedObjects,
        delegate: engine,
      );

      // Script: program.control() [opcode 131 = 0x83] -> return [opcode 0]
      final progCode = Uint8List.fromList([131, 0]);
      final progScript = AgiLogicScript(bytecodes: progCode, messages: [], logicNumber: 0);
      interpreter.loadRootScript(progScript, scriptNumber: 0);
      interpreter.executeCycle();

      expect(engine.isUserControl, isFalse);

      // Attempting to move Ego under program control should be ignored
      engine.ego.direction = 0;
      engine.setEgoDirection(1); // Try to move North
      expect(engine.ego.direction, equals(0), reason: 'Player cannot steer Ego under program.control()');

      // Script: player.control() [opcode 132 = 0x84] -> return [opcode 0]
      final playCode = Uint8List.fromList([132, 0]);
      final playScript = AgiLogicScript(bytecodes: playCode, messages: [], logicNumber: 0);
      interpreter.loadRootScript(playScript, scriptNumber: 0);
      interpreter.executeCycle();

      expect(engine.isUserControl, isTrue);

      // Player can steer Ego again
      engine.setEgoDirection(1);
      expect(engine.ego.direction, equals(1));
    });

    test('stop.motion(ego) disables player movement and start.motion(ego) restores it', () {
      expect(engine.isUserControl, isTrue);

      final interpreter = AgiLogicInterpreter(
        memory: engine.memory,
        animatedObjects: engine.animatedObjects,
        delegate: engine,
      );

      // Script: stop.motion(ego) [opcode 77, 0] -> return [opcode 0]
      final stopCode = Uint8List.fromList([77, 0, 0]);
      final stopScript = AgiLogicScript(bytecodes: stopCode, messages: [], logicNumber: 0);
      interpreter.loadRootScript(stopScript, scriptNumber: 0);
      interpreter.executeCycle();

      expect(engine.isUserControl, isFalse, reason: 'stop.motion(ego) must set isUserControl to false');
      expect(engine.memory.getVar(6), equals(0));

      // Moving Ego while stopped by script is ignored
      engine.setEgoDirection(3); // East
      expect(engine.ego.direction, equals(0));

      // Script: start.motion(ego) [opcode 78, 0] -> return [opcode 0]
      final startCode = Uint8List.fromList([78, 0, 0]);
      final startScript = AgiLogicScript(bytecodes: startCode, messages: [], logicNumber: 0);
      interpreter.loadRootScript(startScript, scriptNumber: 0);
      interpreter.executeCycle();

      expect(engine.isUserControl, isTrue, reason: 'start.motion(ego) must restore isUserControl to true');

      // Player can move Ego again
      engine.setEgoDirection(3);
      expect(engine.ego.direction, equals(3));
    });

    test('KQ2 swim sequence: start.motion followed by move.obj.v to current pos retains player control', () {
      final interpreter = AgiLogicInterpreter(
        memory: engine.memory,
        animatedObjects: engine.animatedObjects,
        delegate: engine,
      );

      engine.ego.x = 22;
      engine.ego.y = 79;

      // 1. Ego enters water -> stop.motion(%o0)
      final stopCode = Uint8List.fromList([77, 0, 0]);
      interpreter.loadRootScript(AgiLogicScript(bytecodes: stopCode, messages: [], logicNumber: 0), scriptNumber: 0);
      interpreter.executeCycle();

      expect(engine.isUserControl, isFalse);

      // 2. Player enters "swim" -> Logic 101 runs:
      // start.motion(%o0) [78, 0]
      // get.posn(%o0, %v67, %v68) [39, 0, 67, 68]
      // assignn(%v82, 0) [3, 82, 0]
      // move.obj.v(%o0, %v67, %v68, %v82, %f169) [82, 0, 67, 68, 82, 169]
      // return [0]
      final swimCode = Uint8List.fromList([
        78, 0,
        39, 0, 67, 68,
        3, 82, 0,
        82, 0, 67, 68, 82, 169,
        0,
      ]);
      interpreter.loadRootScript(AgiLogicScript(bytecodes: swimCode, messages: [], logicNumber: 0), scriptNumber: 0);
      interpreter.executeCycle();

      // move.obj.v to current position should immediately set target flag and enable user control
      expect(engine.isUserControl, isTrue, reason: 'Ego must have user control after swimming');
      expect(engine.memory.getFlag(169), isTrue, reason: 'Target flag 169 must be set upon reaching position');

      // Player can swim
      engine.setEgoDirection(2);
      expect(engine.ego.direction, equals(2));
    });
  });
}
