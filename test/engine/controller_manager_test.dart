import 'package:flutter/services.dart';
import 'package:flutter_agigame/domain/animated_object.dart';
import 'package:flutter_agigame/domain/engine_memory.dart';
import 'package:flutter_agigame/domain/logic_script.dart';
import 'package:flutter_agigame/engine/controllers/agi_controller_manager.dart';
import 'package:flutter_agigame/logic/interpreter/agi_interpreter.dart';
import 'package:flutter_agigame/logic/interpreter/agi_interpreter_delegate.dart';
import 'package:test/test.dart';

void main() {
  group('AgiControllerManager Unit Tests', () {
    late AgiControllerManager controllerManager;
    late AgiMemory memory;

    setUp(() {
      controllerManager = AgiControllerManager();
      memory = AgiMemory();
    });

    test('registers and retrieves key bindings for function keys and special keys', () {
      // F1 -> Controller 1 (0x3B, 0)
      controllerManager.setKey(0x3B, 0, 1);
      // F5 -> Controller 5 (0x3F, 0)
      controllerManager.setKey(0x3F, 0, 5);
      // TAB -> Controller 10 (0x0F, 9)
      controllerManager.setKey(0x0F, 9, 10);
      // ESC -> Controller 20 (0x01, 27)
      controllerManager.setKey(0x01, 27, 20);

      expect(controllerManager.getController(0x3B, 0), equals(1));
      expect(controllerManager.getController(0x3F, 0), equals(5));
      expect(controllerManager.getController(0x0F, 9), equals(10));
      expect(controllerManager.getController(0x01, 27), equals(20));
      expect(controllerManager.getController(0x40, 0), isNull);
    });

    test('supports ASCII fallback and scan code fallback matching', () {
      // Register mapping with scancode only (e.g. F2 = 0x3C, 0)
      controllerManager.setKey(0x3C, 0, 2);
      // Register mapping with ASCII only (e.g. TAB = 0, 9)
      controllerManager.setKey(0, 9, 10);

      // Match by scancode (requires ascii == 0 for extended keys)
      expect(controllerManager.getController(0x3C, 0), equals(2));
      expect(controllerManager.getController(0x3C, 99), isNull); // Normal char 'c' must not trigger F2

      // Match by ASCII (matches regardless of scancode)
      expect(controllerManager.getController(0, 9), equals(10));
      expect(controllerManager.getController(99, 9), equals(10));
    });

    test('overwrites existing binding for the same (scancode, ascii) pair', () {
      controllerManager.setKey(0x3B, 0, 1);
      expect(controllerManager.getController(0x3B, 0), equals(1));

      controllerManager.setKey(0x3B, 0, 99);
      expect(controllerManager.getController(0x3B, 0), equals(99));
      expect(controllerManager.bindings.length, equals(1));
    });

    test('triggerKey sets controller flag in AgiMemory', () {
      controllerManager.setKey(0x3F, 0, 5); // F5 -> ctl 5

      expect(memory.getController(5), isFalse);
      final triggered = controllerManager.triggerKey(0x3F, 0, memory);
      expect(triggered, isTrue);
      expect(memory.getController(5), isTrue);

      final notTriggered = controllerManager.triggerKey(0x40, 0, memory);
      expect(notTriggered, isFalse);
    });

    test('triggerController sets controller flag directly', () {
      expect(memory.getController(12), isFalse);
      controllerManager.triggerController(12, memory);
      expect(memory.getController(12), isTrue);
    });

    test('clear and reset remove all bindings', () {
      controllerManager.setKey(0x3B, 0, 1);
      controllerManager.setKey(0x3C, 0, 2);
      expect(controllerManager.bindings.length, equals(2));

      controllerManager.clear();
      expect(controllerManager.bindings, isEmpty);
      expect(controllerManager.getController(0x3B, 0), isNull);
    });

    test('loadStandardSierraBindings loads standard Sierra F1-F10, TAB, ESC shortcuts', () {
      controllerManager.loadStandardSierraBindings();

      // F1: Help (1)
      expect(controllerManager.getController(0x3B, 0), equals(1));
      // F2: Sound (2)
      expect(controllerManager.getController(0x3C, 0), equals(2));
      // F3: Retype (3)
      expect(controllerManager.getController(0x3D, 0), equals(3));
      // F5: Save (5)
      expect(controllerManager.getController(0x3F, 0), equals(5));
      // F7: Restore (7)
      expect(controllerManager.getController(0x41, 0), equals(7));
      // F9: Restart (9)
      expect(controllerManager.getController(0x43, 0), equals(9));
      // TAB: Inventory / Status (10)
      expect(controllerManager.getController(0x0F, 9), equals(10));
      // F10: Inventory / Status (10)
      expect(controllerManager.getController(0x44, 0), equals(10));
      // ESC: Menu (20)
      expect(controllerManager.getController(0x01, 27), equals(20));
    });

    test('mapLogicalKey correctly maps function keys F1-F10', () {
      expect(AgiControllerManager.mapLogicalKey(LogicalKeyboardKey.f1), equals((0x3B, 0)));
      expect(AgiControllerManager.mapLogicalKey(LogicalKeyboardKey.f2), equals((0x3C, 0)));
      expect(AgiControllerManager.mapLogicalKey(LogicalKeyboardKey.f3), equals((0x3D, 0)));
      expect(AgiControllerManager.mapLogicalKey(LogicalKeyboardKey.f4), equals((0x3E, 0)));
      expect(AgiControllerManager.mapLogicalKey(LogicalKeyboardKey.f5), equals((0x3F, 0)));
      expect(AgiControllerManager.mapLogicalKey(LogicalKeyboardKey.f6), equals((0x40, 0)));
      expect(AgiControllerManager.mapLogicalKey(LogicalKeyboardKey.f7), equals((0x41, 0)));
      expect(AgiControllerManager.mapLogicalKey(LogicalKeyboardKey.f8), equals((0x42, 0)));
      expect(AgiControllerManager.mapLogicalKey(LogicalKeyboardKey.f9), equals((0x43, 0)));
      expect(AgiControllerManager.mapLogicalKey(LogicalKeyboardKey.f10), equals((0x44, 0)));
    });

    test('mapLogicalKey correctly maps Control and Alt key combinations', () {
      // Ctrl+C -> ASCII 3
      expect(
        AgiControllerManager.mapLogicalKey(LogicalKeyboardKey.keyC, isControl: true),
        equals((0x2E, 3)),
      );
      // Ctrl+S -> ASCII 19
      expect(
        AgiControllerManager.mapLogicalKey(LogicalKeyboardKey.keyS, isControl: true),
        equals((0x1F, 19)),
      );
      // Alt+Z -> Scan code 0x2C, ASCII 0
      expect(
        AgiControllerManager.mapLogicalKey(LogicalKeyboardKey.keyZ, isAlt: true),
        equals((0x2C, 0)),
      );
    });

    test('mapLogicalKey correctly maps TAB, ESC, Enter, Space', () {
      expect(AgiControllerManager.mapLogicalKey(LogicalKeyboardKey.tab), equals((0x0F, 9)));
      expect(AgiControllerManager.mapLogicalKey(LogicalKeyboardKey.escape), equals((0x01, 27)));
      expect(AgiControllerManager.mapLogicalKey(LogicalKeyboardKey.enter), equals((0x1C, 13)));
      expect(AgiControllerManager.mapLogicalKey(LogicalKeyboardKey.space), equals((0x39, 32)));
    });

    test('mapLogicalKey correctly maps character keys like =, +, -', () {
      // With character provided
      expect(
        AgiControllerManager.mapLogicalKey(LogicalKeyboardKey.equal, character: '='),
        equals((0, 61)),
      );
      expect(
        AgiControllerManager.mapLogicalKey(LogicalKeyboardKey.add, character: '+'),
        equals((0, 43)),
      );
      expect(
        AgiControllerManager.mapLogicalKey(LogicalKeyboardKey.minus, character: '-'),
        equals((0, 45)),
      );

      // Without character string (fallback to keyId)
      expect(
        AgiControllerManager.mapLogicalKey(LogicalKeyboardKey.equal),
        equals((0, 61)),
      );
      expect(
        AgiControllerManager.mapLogicalKey(LogicalKeyboardKey.minus),
        equals((0, 45)),
      );
      expect(
        AgiControllerManager.mapLogicalKey(LogicalKeyboardKey.numpadEqual),
        equals((0, 61)),
      );
    });

    test('registers and triggers controller for equal sign (=) like in King\'s Quest 2', () {
      // Register = (ascii 61) -> Controller 22 (Swim in KQ2)
      controllerManager.setKey(0, 61, 22);

      expect(controllerManager.getController(0, 61), equals(22));
      expect(memory.getController(22), isFalse);

      final triggered = controllerManager.triggerKey(0, 61, memory);
      expect(triggered, isTrue);
      expect(memory.getController(22), isTrue);
    });
  });

  group('AgiLogicInterpreter set.key and controller(c) Integration Tests', () {
    late AgiMemory memory;
    late List<AnimatedObject> objects;
    late AgiControllerManager controllerManager;
    late AgiLogicInterpreter interpreter;

    setUp(() {
      memory = AgiMemory();
      objects = List.generate(16, (i) => AnimatedObject(number: i));
      controllerManager = AgiControllerManager();

      final delegate = _TestInterpreterDelegate(controllerManager);
      interpreter = AgiLogicInterpreter(
        memory: memory,
        animatedObjects: objects,
        delegate: delegate,
      );
    });

    test('Opcode 121 set.key delegates to AgiControllerManager', () {
      // Bytecode for: set.key(0x3F, 0, 5) -> Opcode 121 (0x79), 0x3F, 0x00, 0x05, return (0x00)
      final bytecode = Uint8List.fromList([
        121, 0x00, 0x3F, 0x05, // set.key(ascii: 0, scancode: 0x3F (F5), ctl: 5)
        0,                      // return
      ]);

      final script = AgiLogicScript(
        bytecodes: bytecode,
        messages: const [],
        logicNumber: 0,
      );
      interpreter.loadRootScript(script, scriptNumber: 0);
      interpreter.executeCycle();

      expect(controllerManager.getController(0x3F, 0), equals(5));
    });

    test('Test Opcode 12 controller(c) branches when controller flag is active', () {
      // Bytecode for:
      // if (controller(c5)) {
      //   set(f20);
      // }
      // return();
      //
      // Opcode 0xFF (if condition), 0x0C (controller), 5 (controller 5), 0xFF (end conditions),
      // 2-byte branch skip length = 2 bytes (0x02, 0x00)
      // Action: 0x0C (set flag 20) -> opcode 12 (set), 20 (f20)
      // 0 (return)
      final bytecode = Uint8List.fromList([
        0xFF,       // if
        0x0C, 5,    // controller(5)
        0xFF,       // end condition
        2, 0,       // branch skip 2 bytes if false
        12, 20,     // set(f20)
        0,          // return
      ]);

      final script = AgiLogicScript(
        bytecodes: bytecode,
        messages: const [],
        logicNumber: 0,
      );

      // 1. Controller 5 is FALSE -> Flag 20 should NOT be set
      interpreter.loadRootScript(script, scriptNumber: 0);
      interpreter.executeCycle();
      expect(memory.getFlag(20), isFalse);

      // 2. Trigger Controller 5 -> Flag 20 SHOULD be set
      memory.setController(5, true);
      interpreter.loadRootScript(script, scriptNumber: 0);
      interpreter.executeCycle();
      expect(memory.getFlag(20), isTrue);
    });

    test('memory.resetControllers clears all controller flags at end of cycle', () {
      memory.setController(1, true);
      memory.setController(5, true);
      memory.setController(10, true);

      expect(memory.getController(1), isTrue);
      expect(memory.getController(5), isTrue);
      expect(memory.getController(10), isTrue);

      memory.resetControllers();

      expect(memory.getController(1), isFalse);
      expect(memory.getController(5), isFalse);
      expect(memory.getController(10), isFalse);
    });
  });
}

class _TestInterpreterDelegate extends AgiInterpreterDelegate {
  final AgiControllerManager controllerManager;

  _TestInterpreterDelegate(this.controllerManager);

  @override
  void onSetKey(int scancode, int ascii, int controllerCode) {
    controllerManager.setKey(scancode, ascii, controllerCode);
  }
}
