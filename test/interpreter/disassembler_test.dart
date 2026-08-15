import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/domain/dictionary.dart';
import 'package:flutter_agigame/domain/engine_memory.dart';
import 'package:flutter_agigame/domain/inventory_object.dart';
import 'package:flutter_agigame/domain/logic_script.dart';
import 'package:flutter_agigame/logic/disassembler/disassembly_formatter.dart';
import 'package:flutter_agigame/logic/disassembler/instruction_decoder.dart';
import 'package:flutter_agigame/logic/disassembler/logic_instruction.dart';

void main() {
  group('InstructionDecoder & DisassemblyFormatter', () {
    test('decodes and formats basic action instructions', () {
      // 0x03 assignn(%v0, 15) -> 03 00 0F
      // 0x0C set(%f5)         -> 0C 05
      // 0x00 return           -> 00
      final code = Uint8List.fromList([0x03, 0x00, 0x0F, 0x0C, 0x05, 0x00]);
      final decoder = InstructionDecoder();
      final ast = decoder.decode(code);

      expect(ast.instructions.length, 3);
      expect((ast.instructions[0] as BasicInstruction).name, 'assignn');
      expect((ast.instructions[1] as BasicInstruction).name, 'set');
      expect((ast.instructions[2] as BasicInstruction).name, 'return');

      final formatter = const DisassemblyFormatter();
      final sb = StringBuffer();
      formatter.formatInstruction(ast, sb, 0, '');
      final text = sb.toString();

      expect(text, contains('0000: assignn(%v0, 15)'));
      expect(text, contains('0003: set(%f5)'));
      expect(text, contains('0005: return'));
    });

    test('decodes and annotates said() test instruction with dictionary words', () {
      // 0xFF (IF)
      // 0x0E (said), count=2, word 15 (0x0F 0x00), word 120 (0x78 0x00)
      // 0xFF (closing IF)
      // 0x02 0x00 (jump 2 bytes over THEN)
      // 0x00 (return)
      final code = Uint8List.fromList([
        0xFF,
        0x0E, 0x02, 0x0F, 0x00, 0x78, 0x00,
        0xFF,
        0x02, 0x00,
        0x00, // return
      ]);

      final dict = AgiDictionary();
      dict.addWord('look', 15);
      dict.addWord('examine', 15);
      dict.addWord('tree', 120);

      final decoder = InstructionDecoder();
      final ast = decoder.decode(code);

      final formatter = DisassemblyFormatter(
        context: DisassemblyContext(dictionary: dict),
      );
      final sb = StringBuffer();
      formatter.formatInstruction(ast, sb, 0, '');
      final text = sb.toString();

      expect(text, contains('said(%w15, %w120)'));
      expect(text, contains('[ WORD %w15: <look> <examine>'));
      expect(text, contains('[ WORD %w120: <tree>'));
    });

    test('decodes structured IF-THEN-ELSE blocks', () {
      // IF (equaln(%v0, 10)) { set(%f1) } else { reset(%f1) }
      // 0xFF
      // 0x01 (equaln) 0x00 0x0A
      // 0xFF
      // THEN jump = 5 bytes: 2 bytes (set(%f1)) + 3 bytes (GOTO 0xFE 0x02 0x00)
      // 0x05 0x00
      // THEN body: 0x0C 0x01 (set(%f1))
      // GOTO: 0xFE 0x02 0x00 (jump 2 bytes to skip ELSE)
      // ELSE body: 0x0D 0x01 (reset(%f1))
      final code = Uint8List.fromList([
        0xFF,
        0x01, 0x00, 0x0A,
        0xFF,
        0x05, 0x00,
        0x0C, 0x01,
        0xFE, 0x02, 0x00,
        0x0D, 0x01,
      ]);

      final decoder = InstructionDecoder();
      final ast = decoder.decode(code);
      expect(ast.instructions.length, 1);
      final ifIns = ast.instructions[0] as IfInstruction;

      expect(ifIns.elseBlock, isNotNull);

      final formatter = const DisassemblyFormatter();
      final sb = StringBuffer();
      formatter.formatInstruction(ast, sb, 0, '');
      final text = sb.toString();

      expect(text, contains('IF-AND ('));
      expect(text, contains('equaln(%v0, 10)'));
      expect(text, contains('set(%f1)'));
      expect(text, contains('} else {'));
      expect(text, contains('reset(%f1)'));
    });

    test('decodes OR and NOT conditions', () {
      // IF (OR(isset(%f1), NOT isset(%f2))) { return }
      // 0xFF
      // 0xFC (OR start)
      // 0x07 0x01 (isset(%f1))
      // 0xFD 0x07 0x02 (NOT isset(%f2))
      // 0xFC (OR end)
      // 0xFF
      // 0x01 0x00 (jump 1 byte)
      // 0x00 (return)
      final code = Uint8List.fromList([
        0xFF,
        0xFC,
        0x07, 0x01,
        0xFD, 0x07, 0x02,
        0xFC,
        0xFF,
        0x01, 0x00,
        0x00,
      ]);

      final decoder = InstructionDecoder();
      final ast = decoder.decode(code);

      final formatter = const DisassemblyFormatter();
      final sb = StringBuffer();
      formatter.formatInstruction(ast, sb, 0, '');
      final text = sb.toString();

      expect(text, contains('OR ('));
      expect(text, contains('isset(%f1)'));
      expect(text, contains('NOT isset(%f2)'));
    });

    test('formats script with message section and annotations', () {
      final script = AgiLogicScript(
        bytecodes: Uint8List.fromList([0x65, 0x01, 0x00]), // print(%m1), return
        messages: ['Welcome to the kingdom!'],
        logicNumber: 1,
      );

      final memory = AgiMemory();
      final objects = [AgiObject(name: 'Magic Wand', startingRoom: 1)];

      final formatter = DisassemblyFormatter(
        context: DisassemblyContext(memory: memory, objects: objects),
      );
      final formattedWithMessages = formatter.formatScript(script, includeMessages: true);

      expect(formattedWithMessages, contains('[ MESSAGES:'));
      expect(formattedWithMessages, contains('%m1: "Welcome to the kingdom!"'));
      expect(formattedWithMessages, contains('[ SCRIPT:'));
      expect(formattedWithMessages, contains('print(%m1)'));
      expect(formattedWithMessages, contains('[ MSG %m1: "Welcome to the kingdom!"'));

      final formattedWithoutMessages = formatter.formatScript(script, includeMessages: false);
      expect(formattedWithoutMessages, isNot(contains('[ MESSAGES:')));
      expect(formattedWithoutMessages, contains('[ SCRIPT:'));
      expect(formattedWithoutMessages, contains('print(%m1)'));
      expect(formattedWithoutMessages, contains('[ MSG %m1: "Welcome to the kingdom!"'));
    });
  });
}
