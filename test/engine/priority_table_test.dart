import 'package:flutter_agigame/domain/animated_object.dart';
import 'package:flutter_agigame/domain/engine_memory.dart';
import 'package:flutter_agigame/domain/game_state_snapshot.dart';
import 'package:flutter_agigame/domain/logic_script.dart';
import 'package:flutter_agigame/domain/priority_table.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/engine/motion/collision_detector.dart';
import 'package:flutter_agigame/loader/game_metadata.dart';
import 'package:flutter_agigame/logic/disassembler/instruction_decoder.dart';
import 'package:flutter_agigame/logic/disassembler/logic_instruction.dart';
import 'package:flutter_agigame/logic/interpreter/agi_interpreter.dart';
import 'package:flutter_agigame/logic/interpreter/agi_interpreter_delegate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:typed_data';

class MockDelegate extends AgiInterpreterDelegate {
  int? setPriBaseVal;

  @override
  void onSetPriBase(int priorityBase) {
    setPriBaseVal = priorityBase;
  }
}

class FakeMetaData extends GameMetaData {
  @override
  final double version;
  @override
  final String versionString;
  @override
  final String gamePath = '';
  @override
  final String? prefix = null;
  @override
  final List<int> decryptionKey = const [];

  FakeMetaData(this.version, this.versionString);
}

void main() {
  group('AgiPriorityTable Tests', () {
    test('Default priority table matches classic 12-pixel bands starting at Y=48', () {
      final table = AgiPriorityTable();
      expect(table.isModified, isFalse);
      expect(table.priorityBase, isNull);

      // Y < 48 is priority 4
      for (int y = 0; y < 48; y++) {
        expect(table.priorityFromY(y), 4, reason: 'y=$y should be Pri 4');
      }

      // 48..59 -> 5, 60..71 -> 6, ..., 156..167 -> 14
      for (int p = 5; p <= 14; p++) {
        final startY = 48 + (p - 5) * 12;
        for (int y = startY; y < startY + 12; y++) {
          expect(table.priorityFromY(y), p, reason: 'y=$y should be Pri $p');
        }
      }
    });

    test('set.pri.base(73) calculates authentic AGI v3 priority bands', () {
      final table = AgiPriorityTable();
      table.setPriorityBase(73);

      expect(table.isModified, isTrue);
      expect(table.priorityBase, 73);

      // Y < 73 is Priority 4
      for (int y = 0; y < 73; y++) {
        expect(table.priorityFromY(y), 4, reason: 'y=$y should be Pri 4');
      }

      // Expected transitions with base 73:
      // y=73..82 -> 5
      expect(table.priorityFromY(73), 5);
      expect(table.priorityFromY(82), 5);

      // y=83..91 -> 6
      expect(table.priorityFromY(83), 6);
      expect(table.priorityFromY(91), 6);

      // y=92..101 -> 7
      expect(table.priorityFromY(92), 7);
      expect(table.priorityFromY(101), 7);

      // y=102..110 -> 8
      expect(table.priorityFromY(102), 8);
      expect(table.priorityFromY(108), 8); // Rosella in Room 29 pine tree
      expect(table.priorityFromY(105), 8); // Rosella in Room 21 bridge
      expect(table.priorityFromY(110), 8);

      // y=111..120 -> 9
      expect(table.priorityFromY(111), 9);
      expect(table.priorityFromY(120), 9);

      // y=121..129 -> 10
      expect(table.priorityFromY(121), 10);
      expect(table.priorityFromY(129), 10);
    });

    test('priorityToY maps fixed priorities back to top-of-band Y', () {
      final table = AgiPriorityTable();
      expect(table.priorityToY(4), 0);
      expect(table.priorityToY(5), 48);
      expect(table.priorityToY(10), 108);

      table.setPriorityBase(73);
      // For base 73, Pri 5 begins at 73, so highest Y where Pri < 5 is 72
      expect(table.priorityToY(5), 72);
      // Pri 8 begins at 102, so highest Y where Pri < 8 is 101
      expect(table.priorityToY(8), 101);
    });
  });

  group('Opcode 174 Disassembly & Interpreter Execution', () {
    test('InstructionDecoder decodes opcode 174 as set.pri.base(n)', () {
      final decoder = InstructionDecoder();
      final bytes = Uint8List.fromList([174, 73, 0x00]);
      final ast = decoder.decode(bytes);

      expect(ast.instructions.length, 2);
      final instr = ast.instructions[0] as BasicInstruction;
      expect(instr.name, 'set.pri.base');
      expect(instr.length, 2);
      expect(instr.args.length, 1);
      expect(instr.args[0], 73);
    });

    test('AgiLogicInterpreter executes opcode 174 and notifies delegate', () {
      final memory = AgiMemory();
      final mock = MockDelegate();
      final interpreter = AgiLogicInterpreter(
        memory: memory,
        animatedObjects: List.generate(16, (i) => AnimatedObject(number: i)),
        delegate: mock,
      );

      // Bytecode for set.pri.base(73) followed by return (0x00)
      final script = AgiLogicScript(
        bytecodes: Uint8List.fromList([174, 73, 0x00]),
        messages: const [],
      );
      interpreter.pushScript(script);
      interpreter.executeCycle();

      expect(mock.setPriBaseVal, 73);
    });
  });

  group('AnimatedObject & Engine Dynamic Priority Integration', () {
    test('AnimatedObject reflects engine priorityTable dynamic changes', () {
      final engine = AgiGameEngine();
      final ego = engine.ego;
      ego.y = 108;

      // With default table (base 48), Y=108 is priority 10
      CollisionDetector.syncAutoPriority(ego, ego.y);
      expect(ego.effectivePriority, 10);
      expect(ego.priority, 10);

      // Now set base 73 (KQ4 outdoor global logic)
      engine.onSetPriBase(73);

      expect(ego.effectivePriority, 8);
      expect(ego.priority, 8);
    });

    test('Save state serializer round-trips priorityBase accurately', () {
      final engine = AgiGameEngine();
      engine.setPriorityBase(73);

      final snapshot = engine.createSnapshot();
      expect(snapshot.priorityBase, 73);

      final json = snapshot.toJson();
      expect(json['priorityBase'], 73);

      final restoredSnap = AgiGameStateSnapshot.fromJson(json);
      expect(restoredSnap.priorityBase, 73);

      final newEngine = AgiGameEngine();
      expect(newEngine.priorityTable.isModified, isFalse);

      newEngine.restoreSnapshot(restoredSnap);
      expect(newEngine.priorityTable.isModified, isTrue);
      expect(newEngine.priorityTable.priorityBase, 73);
    });
  });
}
