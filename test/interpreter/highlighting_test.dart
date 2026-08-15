import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/domain/engine_memory.dart';
import 'package:flutter_agigame/domain/logic_script.dart';
import 'package:flutter_agigame/logic/disassembler/disassembly_formatter.dart';
import 'package:flutter_agigame/logic/disassembler/disassembly_highlighter.dart';
import 'package:flutter_agigame/logic/disassembler/instruction_decoder.dart';

void main() {
  group('DisassemblyHighlighter', () {
    test('tokenizes basic instruction with variables and flags', () {
      // assignn(%v0, 100), set(%f5), return
      final code = Uint8List.fromList([0x03, 0x00, 0x64, 0x0C, 0x05, 0x00]);
      final decoder = InstructionDecoder();
      final ast = decoder.decode(code);

      final tokens = DisassemblyHighlighter.tokenize(ast);

      final types = tokens.map((t) => t.type).toSet();
      expect(types, contains(DisassemblyTokenType.address));
      expect(types, contains(DisassemblyTokenType.opcode));
      expect(types, contains(DisassemblyTokenType.variable));
      expect(types, contains(DisassemblyTokenType.flag));
      expect(types, contains(DisassemblyTokenType.number));
      expect(types, contains(DisassemblyTokenType.punctuation));
    });

    test('tokenizes structured IF-THEN block with keywords', () {
      // IF (equaln(%v0, 10)) { set(%f1) }
      final code = Uint8List.fromList([
        0xFF,
        0x01, 0x00, 0x0A,
        0xFF,
        0x02, 0x00,
        0x0C, 0x01,
      ]);

      final decoder = InstructionDecoder();
      final ast = decoder.decode(code);

      final tokens = DisassemblyHighlighter.tokenize(ast);
      final keywords = tokens
          .where((t) => t.type == DisassemblyTokenType.keyword)
          .map((t) => t.text)
          .toList();

      expect(keywords, contains('IF-AND'));
    });

    test('produces ANSI escape colored string', () {
      final code = Uint8List.fromList([0x0C, 0x05, 0x00]); // set(%f5), return
      final decoder = InstructionDecoder();
      final ast = decoder.decode(code);

      final tokens = DisassemblyHighlighter.tokenize(ast);
      final ansi = DisassemblyHighlighter.toAnsiString(tokens);

      expect(ansi, contains('\x1B[')); // Contains ANSI color escape
      expect(ansi, contains('set'));
      expect(ansi, contains('%f5'));
    });

    test('produces Flutter TextSpans with custom colors', () {
      final script = AgiLogicScript(
        bytecodes: Uint8List.fromList([0x65, 0x01]), // print(%m1)
        messages: ['Hello Sierra!'],
      );

      final decoder = InstructionDecoder();
      final ast = decoder.decode(script.bytecodes);

      final memory = AgiMemory();
      final tokens = DisassemblyHighlighter.tokenize(
        ast,
        context: DisassemblyContext(script: script, memory: memory),
      );

      final textSpans = DisassemblyHighlighter.toTextSpans(tokens);

      expect(textSpans.isNotEmpty, isTrue);
      expect(textSpans.any((span) => span.text?.contains('print') ?? false), isTrue);
      expect(textSpans.any((span) => span.text?.contains('%m1') ?? false), isTrue);
      expect(textSpans.any((span) => span.text?.contains('Hello Sierra!') ?? false), isTrue);
    });
  });
}
