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
  });
}
